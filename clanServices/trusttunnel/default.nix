{
  lib,
  trustTunnelPackageFor ? (
    _system: throw "trusttunnel requires an explicit trustTunnelPackageFor dependency"
  ),
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
  deniedIPv4Networks = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.88.99.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];
in
{
  _class = "clan.service";

  manifest = {
    name = "@clanwright/vpn-trusttunnel";
    description = "Standalone TrustTunnel HTTP/2 gateway with guarded process egress";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public TrustTunnel HTTP/2 gateway";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run the TrustTunnel gateway.";
          };

          bindIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str validBindIPv4;
            description = "Consumer-owned public IPv4 used by the exact HTTP/2 listener.";
          };

          domain = lib.mkOption {
            type = lib.types.addCheck lib.types.str validDnsName;
            description = "Consumer-owned TLS endpoint hostname exported to clients.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Direct TrustTunnel HTTP/2 TCP listener port.";
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
                    description = "Consumer-owned SOPS secret containing 1..64 raw unpadded base64url bytes.";
                  };
                };
              })
            );
            default = [ ];
            description = "Separately revocable runtime credentials, one per device.";
          };

          dnsResolverIPv4s = lib.mkOption {
            type = lib.types.listOf (lib.types.addCheck lib.types.str validIPv4);
            description = "Nonempty consumer-owned numeric IPv4 list matched against networking.nameservers and permitted on TCP/UDP port 53.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "trusttunnel",
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
            machine = providerMachine;
            protocol = "trusttunnel";
            instanceId = instanceName;
            endpoint = {
              ipv4 = settings.bindIPv4;
              inherit (settings) domain port;
            };
            transportMetadata = {
              userNames = profileNames;
              tlsServerName = settings.domain;
              tlsVerify = true;
              credentialEncoding = "base64url";
              upstreamProtocol = "http2";
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
            trustTunnelPackage = trustTunnelPackageFor system;
            serviceName = "trusttunnel";
            serviceUnit = "${serviceName}.service";
            templateName = "trusttunnel.toml";
            nftTableName = "vpn_trusttunnel_egress";
            credentialsConfigPath = config.sops.templates.${templateName}.path;
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            certificateSource = "/var/lib/acme/${settings.acmeCertName}/fullchain.pem";
            privateKeySource = "/var/lib/acme/${settings.acmeCertName}/key.pem";
            credentialDirectory = "/run/credentials/${serviceUnit}";
            certificatePath = "${credentialDirectory}/certificate.pem";
            privateKeyPath = "${credentialDirectory}/private-key.pem";
            distinctUserNames = lib.length (lib.unique profileNames) == lib.length profileNames;
            distinctSecretNames = lib.length (lib.unique userSecretNames) == lib.length userSecretNames;
            distinctResolvers =
              lib.length (lib.unique settings.dnsResolverIPv4s) == lib.length settings.dnsResolverIPv4s;
            activeInstances = config.clanwright.vpn.trusttunnel.activeInstances;
            deniedIPv4Set = lib.concatStringsSep ", " deniedIPv4Networks;
            resolverSet = lib.concatStringsSep ", " settings.dnsResolverIPv4s;
            expectedIngressRule = ''
              ip daddr ${settings.bindIPv4} tcp dport ${toString settings.port} accept comment "trusttunnel destination-scoped ingress"
            '';
            expectedNftContent = ''
              chain output {
                type filter hook output priority filter; policy accept;
                meta skuid "trusttunnel" ip saddr ${settings.bindIPv4} tcp sport ${toString settings.port} ct direction reply accept comment "trusttunnel preserve listener replies"
                meta skuid "trusttunnel" ip daddr { ${resolverSet} } udp dport 53 accept comment "trusttunnel allow consumer resolver UDP"
                meta skuid "trusttunnel" ip daddr { ${resolverSet} } tcp dport 53 accept comment "trusttunnel allow consumer resolver TCP"
                meta skuid "trusttunnel" ip daddr { ${deniedIPv4Set} } drop comment "trusttunnel deny non-public IPv4 egress"
                meta skuid "trusttunnel" ip6 daddr ::/0 drop comment "trusttunnel deny IPv6 egress"
              }
            '';
            vpnConfig = ''
              listen_address = "${settings.bindIPv4}:${toString settings.port}"
              ipv6_available = false
              allow_private_network_connections = false
              tls_handshake_timeout_secs = 10
              client_listener_timeout_secs = 600
              connection_establishment_timeout_secs = 30
              tcp_connections_timeout_secs = 604800
              udp_connections_timeout_secs = 300
              credentials_file = "${credentialsConfigPath}"
              auth_failure_status_code = 404
              non_connect_auth_failure_status_code = 404

              [listen_protocols]
              [listen_protocols.http2]
              initial_connection_window_size = 8388608
              initial_stream_window_size = 131072
              max_concurrent_streams = 1000
              max_frame_size = 16384
              header_table_size = 65536

              [forward_protocol]
              direct = {}
            '';
            hostsConfig = ''
              [[main_hosts]]
              hostname = "${settings.domain}"
              cert_chain_path = "${certificatePath}"
              private_key_path = "${privateKeyPath}"
            '';
            credentialsConfig = lib.concatMapStringsSep "\n" (user: ''
              [[client]]
              username = "${user.name}"
              password = "${config.sops.placeholder.${user.passwordSecretName}}"
            '') settings.users;
            vpnConfigPath = pkgs.writeText "trusttunnel-vpn.toml" vpnConfig;
            hostsConfigPath = pkgs.writeText "trusttunnel-hosts.toml" hostsConfig;
            socketIPv4Hex = lib.concatStrings (
              lib.reverseList (
                map (octet: lib.fixedWidthString 2 "0" (lib.toHexString (builtins.fromJSON octet))) (
                  lib.splitString "." settings.bindIPv4
                )
              )
            );
            socketPortHex = lib.fixedWidthString 4 "0" (lib.toHexString settings.port);
            expectedTcpLocal = "${socketIPv4Hex}:${socketPortHex}";
            passwordValidator = pkgs.writeShellScript "trusttunnel-validate-passwords" (
              ''
                set -eu
              ''
              + lib.concatMapStringsSep "\n" (secretName: ''
                secret_path=${lib.escapeShellArg config.sops.secrets.${secretName}.path}
                byte_count="$(${pkgs.coreutils}/bin/wc -c < "$secret_path")"
                base64url_byte_count="$(LC_ALL=C ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9_-' < "$secret_path" | ${pkgs.coreutils}/bin/wc -c)"
                if [ "$byte_count" -eq 0 ] || [ "$byte_count" -gt 64 ] || [ "$byte_count" -ne "$base64url_byte_count" ]; then
                  echo "trusttunnel: a device password must be 1..64 raw unpadded base64url bytes" >&2
                  exit 1
                fi
              '') userSecretNames
            );
            bindCapabilities = lib.optional (settings.port < 1024) "CAP_NET_BIND_SERVICE";
            expectedLoadCredential = [
              "certificate.pem:${certificateSource}"
              "private-key.pem:${privateKeySource}"
            ];
            expectedExecStart = "${trustTunnelPackage}/bin/trusttunnel_endpoint --loglvl info ${vpnConfigPath} ${hostsConfigPath}";
          in
          {
            options.clanwright.vpn.trusttunnel.activeInstances = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              internal = true;
              description = "Active TrustTunnel instances claiming the singleton runtime.";
            };

            config = {
              clanwright.vpn.trusttunnel.activeInstances = lib.mkIf active [ instanceName ];

              assertions = lib.optionals active [
                {
                  assertion = system == "x86_64-linux";
                  message = "trusttunnel: runtime support is restricted to x86_64-linux.";
                }
                {
                  assertion = lib.getVersion trustTunnelPackage == "1.1.0";
                  message = "trusttunnel: the injected stock TrustTunnel endpoint package must be exactly version 1.1.0.";
                }
                {
                  assertion = pkgs.trusttunnel-endpoint == trustTunnelPackage;
                  message = "trusttunnel: pkgs.trusttunnel-endpoint must come from the injected VPN application pin.";
                }
                {
                  assertion = config.networking.firewall.enable && config.networking.firewall.backend == "nftables";
                  message = "trusttunnel: destination-scoped ingress requires the nftables firewall backend.";
                }
                {
                  assertion = config.networking.nftables.enable;
                  message = "trusttunnel: the module-owned process egress guard requires networking.nftables.enable.";
                }
                {
                  assertion = lib.length activeInstances == 1;
                  message = "trusttunnel: only one active instance may claim the singleton runtime per machine.";
                }
                {
                  assertion = settings.users != [ ] && distinctUserNames && distinctSecretNames;
                  message = "trusttunnel: users and their SOPS password secrets must be nonempty and unique.";
                }
                {
                  assertion = settings.dnsResolverIPv4s != [ ] && distinctResolvers;
                  message = "trusttunnel: consumer resolver IPv4 addresses must be nonempty and unique.";
                }
                {
                  assertion = config.networking.nameservers == settings.dnsResolverIPv4s;
                  message = "trusttunnel: networking.nameservers must exactly match dnsResolverIPv4s.";
                }
                {
                  assertion =
                    config.networking.nftables.tables.${nftTableName}.family == "inet"
                    && config.networking.nftables.tables.${nftTableName}.enable
                    && config.networking.nftables.tables.${nftTableName}.content == expectedNftContent
                    && lib.hasInfix expectedIngressRule config.networking.firewall.extraInputRules;
                  message = "trusttunnel: ingress and process egress guards must not be removed or weakened.";
                }
                {
                  assertion =
                    config.sops.templates.${templateName}.content == credentialsConfig
                    && config.sops.templates.${templateName}.owner == serviceName
                    && config.sops.templates.${templateName}.group == serviceName
                    && config.sops.templates.${templateName}.mode == "0400"
                    && builtins.elem serviceUnit config.sops.templates.${templateName}.restartUnits;
                  message = "trusttunnel: credential template, permissions, and restart binding must remain guarded.";
                }
                {
                  assertion = builtins.all (
                    secretName:
                    config.sops.secrets.${secretName}.owner == "root"
                    && config.sops.secrets.${secretName}.group == "root"
                    && config.sops.secrets.${secretName}.mode == "0400"
                    && builtins.elem serviceUnit config.sops.secrets.${secretName}.restartUnits
                  ) userSecretNames;
                  message = "trusttunnel: password secret permissions and restart bindings must remain guarded.";
                }
                {
                  assertion =
                    builtins.elem serviceUnit
                      config.security.acme.certs.${settings.acmeCertName}.reloadServices;
                  message = "trusttunnel: ACME renewal must restart the service so LoadCredential copies are refreshed.";
                }
                {
                  assertion =
                    config.systemd.services.${serviceName}.requires == [ "nftables.service" ]
                    && config.systemd.services.${serviceName}.bindsTo == [ "nftables.service" ]
                    && config.systemd.services.${serviceName}.partOf == [ "nftables.service" ]
                    && builtins.elem "nftables.service" config.systemd.services.${serviceName}.after
                    && config.systemd.services.${serviceName}.serviceConfig.User == serviceName
                    && config.systemd.services.${serviceName}.serviceConfig.Group == serviceName
                    && !(config.systemd.services.${serviceName}.serviceConfig.DynamicUser or false)
                    && config.systemd.services.${serviceName}.serviceConfig.ExecStartPre == "+${passwordValidator}"
                    && config.systemd.services.${serviceName}.serviceConfig.ExecStart == expectedExecStart
                    && (config.systemd.services.${serviceName}.serviceConfig.ExecReload or null) == null
                    && config.systemd.services.${serviceName}.serviceConfig.LoadCredential == expectedLoadCredential
                    && config.systemd.services.${serviceName}.serviceConfig.AmbientCapabilities == bindCapabilities
                    && config.systemd.services.${serviceName}.serviceConfig.CapabilityBoundingSet == bindCapabilities
                    && config.systemd.services.${serviceName}.serviceConfig.NoNewPrivileges
                    && config.systemd.services.${serviceName}.serviceConfig.ProtectSystem == "strict"
                    &&
                      config.systemd.services.${serviceName}.serviceConfig.RestrictAddressFamilies == [
                        "AF_INET"
                        "AF_UNIX"
                      ];
                  message = "trusttunnel: service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded.";
                }
              ];

              nixpkgs.overlays = lib.optional active (
                _final: _prev: {
                  trusttunnel-endpoint = trustTunnelPackage;
                }
              );

              users.groups = lib.optionalAttrs active { ${serviceName} = { }; };
              users.users = lib.optionalAttrs active {
                ${serviceName} = {
                  isSystemUser = true;
                  group = serviceName;
                  description = "TrustTunnel endpoint daemon";
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
                  content = credentialsConfig;
                  owner = serviceName;
                  group = serviceName;
                  mode = "0400";
                  restartUnits = [ serviceUnit ];
                };
              };

              networking = {
                firewall.extraInputRules = lib.mkIf active (lib.mkAfter expectedIngressRule);
                nftables = {
                  preCheckRuleset = lib.mkIf active (
                    lib.mkAfter ''
                      sed 's/meta skuid "trusttunnel"/meta skuid 0/g' -i ruleset.conf
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
                  description = "TrustTunnel HTTP/2 proxy gateway";
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
                  restartTriggers = [ trustTunnelPackage ];
                  postStart = ''
                    set -euo pipefail

                    expected_local=${lib.escapeShellArg expectedTcpLocal}
                    for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
                      if [ -z "''${MAINPID:-}" ]; then
                        echo "trusttunnel: main process inspection unavailable during TCP listener readiness" >&2
                        exit 1
                      fi
                      tcp_table="$(${pkgs.coreutils}/bin/cat /proc/"$MAINPID"/net/tcp 2>/dev/null)" || {
                        echo "trusttunnel: main process inspection unavailable during TCP listener readiness" >&2
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

                    echo "trusttunnel: main process did not own the configured IPv4 TCP listener within 15 seconds" >&2
                    exit 1
                  '';
                  serviceConfig = {
                    Type = "exec";
                    User = serviceName;
                    Group = serviceName;
                    ExecStartPre = "+${passwordValidator}";
                    ExecStart = expectedExecStart;
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
