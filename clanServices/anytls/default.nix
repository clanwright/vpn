{
  lib,
  singBoxPackageFor ? (_system: throw "anytls requires an explicit singBoxPackageFor dependency"),
  ...
}:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  providerEnvelope = import ../../modules/contracts/provider-envelope.nix { inherit lib; };
  decimalPattern = "(0|[1-9][0-9]{0,2})";
  validIPv4 =
    value:
    let
      octets = lib.splitString "." value;
      validOctet =
        octet:
        builtins.match decimalPattern octet != null
        && builtins.fromJSON octet >= 0
        && builtins.fromJSON octet <= 255;
    in
    lib.length octets == 4 && builtins.all validOctet octets;
  validBindIPv4 = value: validIPv4 value && value != "0.0.0.0";
  validDnsName =
    value:
    value != ""
    && builtins.match "[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?" value != null
    && lib.hasInfix "." value;
  validDnsEndpointDomain =
    value:
    let
      labels = lib.splitString "." value;
      validLabel =
        label:
        builtins.stringLength label >= 1
        && builtins.stringLength label <= 63
        && builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" label != null;
    in
    value == lib.toLower value
    && builtins.stringLength value <= 253
    && builtins.length labels >= 2
    && builtins.all validLabel labels
    && builtins.match "[0-9]+(\\.[0-9]+)+" value == null;
  validHttpPath = value: builtins.match "/[A-Za-z0-9._~/-]*" value != null;
  ipv4ToInt =
    value:
    let
      octets = map builtins.fromJSON (lib.splitString "." value);
    in
    builtins.elemAt octets 0 * 16777216
    + builtins.elemAt octets 1 * 65536
    + builtins.elemAt octets 2 * 256
    + builtins.elemAt octets 3;
  pow2 = exponent: if exponent == 0 then 1 else 2 * pow2 (exponent - 1);
  deniedIPv4Networks = [
    {
      address = "0.0.0.0";
      prefixLength = 8;
    }
    {
      address = "10.0.0.0";
      prefixLength = 8;
    }
    {
      address = "100.64.0.0";
      prefixLength = 10;
    }
    {
      address = "127.0.0.0";
      prefixLength = 8;
    }
    {
      address = "169.254.0.0";
      prefixLength = 16;
    }
    {
      address = "172.16.0.0";
      prefixLength = 12;
    }
    {
      address = "192.0.0.0";
      prefixLength = 24;
    }
    {
      address = "192.0.2.0";
      prefixLength = 24;
    }
    {
      address = "192.88.99.0";
      prefixLength = 24;
    }
    {
      address = "192.168.0.0";
      prefixLength = 16;
    }
    {
      address = "198.18.0.0";
      prefixLength = 15;
    }
    {
      address = "198.51.100.0";
      prefixLength = 24;
    }
    {
      address = "203.0.113.0";
      prefixLength = 24;
    }
    {
      address = "224.0.0.0";
      prefixLength = 4;
    }
    {
      address = "240.0.0.0";
      prefixLength = 4;
    }
  ];
  publicOnlyDenyIPv4 = map (
    network: "${network.address}/${toString network.prefixLength}"
  ) deniedIPv4Networks;
  deniedIPv4 =
    value:
    let
      address = ipv4ToInt value;
    in
    builtins.any (
      network:
      let
        first = ipv4ToInt network.address;
        lastExclusive = first + pow2 (32 - network.prefixLength);
      in
      address >= first && address < lastExclusive
    ) deniedIPv4Networks;
  validPublicIPv4 = value: validIPv4 value && !deniedIPv4 value;
in
{
  _class = "clan.service";

  manifest = {
    name = "@clanwright/vpn-anytls";
    description = "Standalone sing-box AnyTLS TCP gateway with guarded process egress";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public sing-box AnyTLS TCP gateway";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run the AnyTLS gateway.";
          };

          bindIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str validBindIPv4;
            description = "Consumer-owned public IPv4 used by the listener and destination-scoped ingress guard.";
          };

          domain = lib.mkOption {
            type = lib.types.addCheck lib.types.str validDnsName;
            description = "Consumer-owned TLS endpoint hostname exported to clients.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Direct AnyTLS TCP listener port.";
          };

          acmeCertName = lib.mkOption {
            type = identities.safeIdentityType;
            description = "Consumer-owned ACME certificate name under /var/lib/acme.";
          };

          users = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption {
                    type = identities.safeIdentityType;
                    description = "Unique device identity exported to client profile generation.";
                  };
                  passwordSecretName = lib.mkOption {
                    type = identities.safeSecretNameType;
                    description = "Consumer-owned SOPS secret containing a nonempty unpadded base64url password.";
                  };
                };
              })
            );
            default = [ ];
            description = "Separately revocable runtime credentials, one per device.";
          };

          dnsEndpoint = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                domain = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validDnsEndpointDomain;
                  description = "Consumer-owned canonical lowercase DoH hostname used for TLS identity and HTTP authority.";
                };
                ipv4 = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validPublicIPv4;
                  description = "Consumer-owned public numeric IPv4 bootstrap address for the DoH endpoint.";
                };
                port = lib.mkOption {
                  type = lib.types.port;
                  default = 443;
                  description = "HTTPS port of the DoH endpoint.";
                };
                path = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validHttpPath;
                  default = "/dns-query";
                  description = "Absolute HTTP path of the DoH endpoint.";
                };
              };
            });
            description = "Single consumer-owned public DNS-over-HTTPS endpoint used by the AnyTLS process.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "anytls",
        machine ? {
          name = null;
        },
        mkExports ? (value: value),
        ...
      }:
      let
        active = settings.enable;
        providerMachine =
          if machine ? name && machine.name != null && machine.name != "" then
            machine.name
          else
            builtins.head (lib.splitString "--" instanceName);
        profileNames = map (user: user.name) settings.users;
        userSecretNames = map (user: user.passwordSecretName) settings.users;
        secretNames.users = lib.listToAttrs (
          map (user: {
            inherit (user) name;
            value = user.passwordSecretName;
          }) settings.users
        );
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = providerEnvelope.mkProvider {
            protocol = "anytls";
            instanceId = instanceName;
            machine = providerMachine;
            endpoint = {
              ipv4 = settings.bindIPv4;
              inherit (settings) domain port;
            };
            transportMetadata = {
              userNames = profileNames;
              tlsServerName = settings.domain;
              tlsVerify = true;
              tlsMinVersion = "1.3";
            };
            inherit profileNames secretNames;
          };
        });

        nixosModule =
          {
            config,
            pkgs,
            ...
          }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            singBoxPackage = singBoxPackageFor system;
            serviceName = "anytls";
            serviceUnit = "${serviceName}.service";
            templateName = "${serviceName}.json";
            nftTableName = "vpn_anytls_egress";
            configPath = config.sops.templates.${templateName}.path;
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            certificateSource = "/var/lib/acme/${settings.acmeCertName}/fullchain.pem";
            privateKeySource = "/var/lib/acme/${settings.acmeCertName}/key.pem";
            credentialDirectory = "/run/credentials/${serviceUnit}";
            certificatePath = "${credentialDirectory}/certificate.pem";
            privateKeyPath = "${credentialDirectory}/private-key.pem";
            distinctUserNames = lib.length (lib.unique profileNames) == lib.length profileNames;
            distinctSecretNames = lib.length (lib.unique userSecretNames) == lib.length userSecretNames;
            activeInstances = config.clanwright.vpn.anytls.activeInstances;
            deniedIPv4Set = lib.concatStringsSep ", " publicOnlyDenyIPv4;
            expectedNftContent = ''
              chain output {
                type filter hook output priority filter; policy accept;
                meta skuid "anytls" ip saddr ${settings.bindIPv4} tcp sport ${toString settings.port} ct direction reply accept comment "anytls preserve listener replies"
                meta skuid "anytls" ip daddr { ${deniedIPv4Set} } drop comment "anytls deny non-public IPv4 egress"
                meta skuid "anytls" ip6 daddr ::/0 drop comment "anytls deny IPv6 egress"
              }
            '';
            renderedConfig = builtins.toJSON {
              log.level = "info";
              dns = {
                servers = [
                  {
                    type = "https";
                    tag = "own-adguard-doh";
                    server = settings.dnsEndpoint.ipv4;
                    server_port = settings.dnsEndpoint.port;
                    path = settings.dnsEndpoint.path;
                    tls = {
                      enabled = true;
                      server_name = settings.dnsEndpoint.domain;
                    };
                  }
                ];
                final = "own-adguard-doh";
                strategy = "ipv4_only";
              };
              inbounds = [
                {
                  type = "anytls";
                  tag = "anytls-in";
                  listen = settings.bindIPv4;
                  listen_port = settings.port;
                  users = map (user: {
                    inherit (user) name;
                    password = config.sops.placeholder.${user.passwordSecretName};
                  }) settings.users;
                  tls = {
                    enabled = true;
                    server_name = settings.domain;
                    min_version = "1.3";
                    max_version = "1.3";
                    certificate_path = certificatePath;
                    key_path = privateKeyPath;
                  };
                }
              ];
              outbounds = [
                {
                  type = "direct";
                  tag = "direct";
                }
              ];
              route = {
                rules = [
                  {
                    inbound = [ "anytls-in" ];
                    action = "resolve";
                    server = "own-adguard-doh";
                    strategy = "ipv4_only";
                  }
                  {
                    inbound = [ "anytls-in" ];
                    ip_cidr = publicOnlyDenyIPv4;
                    action = "reject";
                  }
                  {
                    inbound = [ "anytls-in" ];
                    ip_is_private = true;
                    action = "reject";
                  }
                ];
                final = "direct";
                default_domain_resolver = {
                  server = "own-adguard-doh";
                  strategy = "ipv4_only";
                };
              };
            };
            socketIPv4Hex = lib.concatStrings (
              lib.reverseList (
                map (octet: lib.fixedWidthString 2 "0" (lib.toHexString (builtins.fromJSON octet))) (
                  lib.splitString "." settings.bindIPv4
                )
              )
            );
            socketPortHex = lib.fixedWidthString 4 "0" (lib.toHexString settings.port);
            expectedTcpLocal = "${socketIPv4Hex}:${socketPortHex}";
            passwordValidator = pkgs.writeShellScript "anytls-validate-passwords" (
              ''
                set -eu
              ''
              + lib.concatMapStringsSep "\n" (secretName: ''
                secret_path=${lib.escapeShellArg config.sops.secrets.${secretName}.path}
                byte_count="$(${pkgs.coreutils}/bin/wc -c < "$secret_path")"
                base64url_byte_count="$(LC_ALL=C ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9_-' < "$secret_path" | ${pkgs.coreutils}/bin/wc -c)"
                if [ "$byte_count" -eq 0 ] || [ "$byte_count" -gt 64 ] || [ "$byte_count" -ne "$base64url_byte_count" ]; then
                  echo "anytls: a device password must be 1..64 raw unpadded base64url bytes" >&2
                  exit 1
                fi
              '') userSecretNames
            );
            bindCapabilities = lib.optional (settings.port < 1024) "CAP_NET_BIND_SERVICE";
            expectedLoadCredential = [
              "certificate.pem:${certificateSource}"
              "private-key.pem:${privateKeySource}"
            ];
          in
          {
            options.clanwright.vpn.anytls.activeInstances = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              internal = true;
              description = "Active AnyTLS instances claiming the singleton runtime.";
            };

            config = {
              clanwright.vpn.anytls.activeInstances = lib.mkIf active [ instanceName ];

              assertions = lib.optionals active [
                {
                  assertion = system == "x86_64-linux";
                  message = "anytls: runtime support is restricted to x86_64-linux.";
                }
                {
                  assertion = lib.getVersion singBoxPackage == "1.14.0";
                  message = "anytls: the injected stock sing-box package must be exactly version 1.14.0.";
                }
                {
                  assertion = pkgs.sing-box == singBoxPackage;
                  message = "anytls: pkgs.sing-box must come from the injected VPN application pin.";
                }
                {
                  assertion = config.networking.firewall.enable;
                  message = "anytls: destination-scoped ingress requires the NixOS firewall.";
                }
                {
                  assertion = config.networking.firewall.backend == "nftables";
                  message = "anytls: ingress and process-scoped egress require the nftables firewall backend.";
                }
                {
                  assertion = config.networking.nftables.enable;
                  message = "anytls: the module-owned process egress guard requires networking.nftables.enable.";
                }
                {
                  assertion = lib.length activeInstances == 1;
                  message = "anytls: only one active instance may claim the singleton runtime per machine.";
                }
                {
                  assertion = settings.users != [ ];
                  message = "anytls: at least one per-device user is required.";
                }
                {
                  assertion = distinctUserNames;
                  message = "anytls: device identities must be unique.";
                }
                {
                  assertion = distinctSecretNames;
                  message = "anytls: every device must use a distinct SOPS password secret.";
                }
                {
                  assertion =
                    config.networking.nftables.tables.${nftTableName}.family == "inet"
                    && config.networking.nftables.tables.${nftTableName}.enable
                    && config.networking.nftables.tables.${nftTableName}.content == expectedNftContent;
                  message = "anytls: the module-owned ingress and process egress guard must not be removed or weakened.";
                }
                {
                  assertion =
                    config.sops.templates.${templateName}.content == renderedConfig
                    && config.sops.templates.${templateName}.owner == serviceName
                    && config.sops.templates.${templateName}.group == serviceName
                    && config.sops.templates.${templateName}.mode == "0400"
                    && builtins.elem serviceUnit config.sops.templates.${templateName}.restartUnits;
                  message = "anytls: the runtime config template, permissions, and restart binding must remain guarded.";
                }
                {
                  assertion = builtins.all (
                    secretName:
                    config.sops.secrets.${secretName}.owner == "root"
                    && config.sops.secrets.${secretName}.group == "root"
                    && config.sops.secrets.${secretName}.mode == "0400"
                    && builtins.elem serviceUnit config.sops.secrets.${secretName}.restartUnits
                  ) userSecretNames;
                  message = "anytls: password secret permissions and restart bindings must remain guarded.";
                }
                {
                  assertion =
                    builtins.elem serviceUnit
                      config.security.acme.certs.${settings.acmeCertName}.reloadServices;
                  message = "anytls: ACME renewal must reload the AnyTLS service.";
                }
                {
                  assertion =
                    config.systemd.services.${serviceName}.serviceConfig.User == serviceName
                    && config.systemd.services.${serviceName}.serviceConfig.Group == serviceName
                    && !(config.systemd.services.${serviceName}.serviceConfig.DynamicUser or false)
                    && config.systemd.services.${serviceName}.serviceConfig.ExecStartPre == "+${passwordValidator}"
                    &&
                      config.systemd.services.${serviceName}.serviceConfig.ExecStart
                      == "${lib.getExe singBoxPackage} run -c ${configPath}"
                    && config.systemd.services.${serviceName}.serviceConfig.LoadCredential == expectedLoadCredential
                    &&
                      config.systemd.services.${serviceName}.serviceConfig.RestrictAddressFamilies == [
                        "AF_INET"
                        "AF_UNIX"
                      ];
                  message = "anytls: process identity, command, credentials, and IPv4-only address families must remain guarded.";
                }
              ];

              nixpkgs.overlays = lib.optional active (_final: _prev: { sing-box = singBoxPackage; });

              users.groups = lib.optionalAttrs active { ${serviceName} = { }; };
              users.users = lib.optionalAttrs active {
                ${serviceName} = {
                  isSystemUser = true;
                  group = serviceName;
                  description = "AnyTLS sing-box server daemon";
                };
              };

              sops.secrets = lib.optionalAttrs active (
                lib.genAttrs userSecretNames (_: {
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  restartUnits = [ serviceUnit ];
                })
              );
              sops.templates = lib.optionalAttrs active {
                ${templateName} = {
                  content = renderedConfig;
                  owner = serviceName;
                  group = serviceName;
                  mode = "0400";
                  restartUnits = [ serviceUnit ];
                };
              };

              networking = {
                firewall.extraInputRules = lib.mkIf active (
                  lib.mkAfter ''
                    ip daddr ${settings.bindIPv4} tcp dport ${toString settings.port} accept comment "anytls destination-scoped ingress"
                  ''
                );
                nftables = {
                  # Pure nft syntax checks have no target user database.
                  preCheckRuleset = lib.mkIf active (
                    lib.mkAfter ''
                      sed 's/meta skuid "anytls"/meta skuid 0/g' -i ruleset.conf
                    ''
                  );
                  tables = lib.optionalAttrs active {
                    ${nftTableName} = {
                      enable = true;
                      family = "inet";
                      content = expectedNftContent;
                    };
                  };
                };
              };

              security.acme.certs = lib.optionalAttrs active {
                ${settings.acmeCertName}.reloadServices = [ serviceUnit ];
              };

              systemd.services = lib.optionalAttrs active {
                ${serviceName} = {
                  description = "sing-box AnyTLS proxy gateway";
                  wantedBy = [ "multi-user.target" ];
                  after = [
                    "network-online.target"
                    "nftables.service"
                  ]
                  ++ sopsUnits;
                  wants = [ "network-online.target" ] ++ sopsUnits;
                  requires = [ "nftables.service" ];
                  bindsTo = [ "nftables.service" ];
                  partOf = [ "nftables.service" ];
                  restartTriggers = [ singBoxPackage ];
                  postStart = ''
                    set -euo pipefail

                    expected_local=${lib.escapeShellArg expectedTcpLocal}
                    for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
                      if [ -z "''${MAINPID:-}" ]; then
                        echo "anytls: main process inspection unavailable during TCP listener readiness" >&2
                        exit 1
                      fi
                      tcp_table="$(${pkgs.coreutils}/bin/cat /proc/"$MAINPID"/net/tcp 2>/dev/null)" || {
                        echo "anytls: main process inspection unavailable during TCP listener readiness" >&2
                        exit 1
                      }

                      while read -r slot local_address remote_address state queues timers retransmits uid timeout inode remainder; do
                        if [ "$local_address" != "$expected_local" ] \
                          || [ "$remote_address" != "00000000:0000" ] \
                          || [ "$state" != "0A" ]; then
                          continue
                        fi

                        for fd in /proc/"$MAINPID"/fd/*; do
                          target="$(${pkgs.coreutils}/bin/readlink "$fd" 2>/dev/null || true)"
                          if [ "$target" = "socket:[$inode]" ]; then
                            exit 0
                          fi
                        done
                      done <<< "$tcp_table"

                      ${pkgs.coreutils}/bin/sleep 1
                    done

                    echo "anytls: main process did not own the configured IPv4 TCP listener within 15 seconds" >&2
                    exit 1
                  '';
                  serviceConfig = {
                    Type = "exec";
                    User = serviceName;
                    Group = serviceName;
                    ExecStartPre = "+${passwordValidator}";
                    ExecStart = "${lib.getExe singBoxPackage} run -c ${configPath}";
                    Restart = "on-failure";
                    RestartSec = "5s";
                    TimeoutStartSec = "20s";
                    StateDirectory = serviceName;
                    StateDirectoryMode = "0750";
                    RuntimeDirectory = serviceName;
                    RuntimeDirectoryMode = "0750";
                    UMask = "0077";
                    AmbientCapabilities = bindCapabilities;
                    CapabilityBoundingSet = bindCapabilities;
                    LoadCredential = expectedLoadCredential;
                    LockPersonality = true;
                    NoNewPrivileges = true;
                    PrivateDevices = true;
                    PrivateTmp = true;
                    ProtectClock = true;
                    ProtectControlGroups = true;
                    ProtectHome = true;
                    ProtectHostname = true;
                    ProtectKernelLogs = true;
                    ProtectKernelModules = true;
                    ProtectKernelTunables = true;
                    ProtectProc = "invisible";
                    ProtectSystem = "strict";
                    RestrictAddressFamilies = [
                      "AF_INET"
                      "AF_UNIX"
                    ];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    RestrictSUIDSGID = true;
                    SystemCallArchitectures = "native";
                  };
                };
              };
            };
          };
      };
  };
}
