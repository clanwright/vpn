{
  mihomoPackageFor ? (
    _system: throw "mihomo-hysteria2 requires an explicit mihomoPackageFor dependency"
  ),
  lib,
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
  validListenIPv4 = value: validIPv4 value && value != "0.0.0.0";
  validDnsName =
    value:
    value != ""
    && builtins.match "[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?" value != null
    && lib.hasInfix "." value;
  validMasqueradeRoot =
    value:
    let
      segments = lib.splitString "/" value;
    in
    builtins.match "/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9._~+-]+(/[A-Za-z0-9._~+-]+)*" value
    != null
    && builtins.all (segment: segment != "." && segment != "..") segments;
in
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-mihomo-hysteria2";
    description = "Deprecated Mihomo Hysteria2 gateway retained for compatibility";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Deprecated public Hysteria2 UDP gateway retained for compatibility";
    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          listenIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str validListenIPv4;
            description = "IPv4 address for the Hysteria2 listener and destination-scoped firewall rule.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
          };
          serverName = lib.mkOption {
            type = lib.types.addCheck lib.types.str validDnsName;
            description = "Existing Hysteria2 TLS endpoint hostname; ALPN is fixed to h3.";
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
                    description = "Consumer-owned SOPS secret containing an unpadded base64url password.";
                  };
                };
              })
            );
            default = [ ];
          };
          acmeCertName = lib.mkOption {
            type = identities.safeIdentityType;
            description = "Consumer-owned ACME certificate name under /var/lib/acme.";
          };
          obfsPasswordSecretName = lib.mkOption {
            type = identities.safeSecretNameType;
            description = "Consumer-owned SOPS secret containing an unpadded base64url Gecko password.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "mihomo-hysteria2",
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
        secretNames = {
          users = lib.listToAttrs (
            map (user: {
              inherit (user) name;
              value = user.passwordSecretName;
            }) settings.users
          );
          obfsPassword = settings.obfsPasswordSecretName;
        };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = providerEnvelope.mkProvider {
            protocol = "hysteria2";
            instanceId = instanceName;
            machine = providerMachine;
            endpoint = {
              domain = settings.serverName;
              ipv4 = settings.listenIPv4;
              inherit (settings) port;
            };
            transportMetadata = {
              sni = settings.serverName;
              userNames = profileNames;
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
            mihomoPackage = mihomoPackageFor system;
            serviceName = "mihomo-hysteria2";
            serviceUnit = "${serviceName}.service";
            templateName = "${serviceName}.json";
            configPath = config.sops.templates.${templateName}.path;
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            certificateSource = "/var/lib/acme/${settings.acmeCertName}/fullchain.pem";
            privateKeySource = "/var/lib/acme/${settings.acmeCertName}/key.pem";
            credentialDirectory = "/run/credentials/${serviceUnit}";
            certificatePath = "${credentialDirectory}/certificate.pem";
            privateKeyPath = "${credentialDirectory}/private-key.pem";
            socketIPv4Hex = lib.concatStrings (
              lib.reverseList (
                map (octet: lib.fixedWidthString 2 "0" (lib.toHexString (builtins.fromJSON octet))) (
                  lib.splitString "." settings.listenIPv4
                )
              )
            );
            socketPortHex = lib.fixedWidthString 4 "0" (lib.toHexString settings.port);
            expectedUdpLocal = "${socketIPv4Hex}:${socketPortHex}";
            bindCapability = lib.optional (settings.port < 1024) "CAP_NET_BIND_SERVICE";
            users = lib.listToAttrs (
              map (user: {
                inherit (user) name;
                value = config.sops.placeholder.${user.passwordSecretName};
              }) settings.users
            );
            listener = {
              name = "hysteria2-in";
              type = "hysteria2";
              listen = settings.listenIPv4;
              inherit (settings) port;
              inherit users;
              masquerade = "file://${config.clanwright.vpn.hysteria2.masqueradeRoot}";
              "ignore-client-bandwidth" = true;
              alpn = [ "h3" ];
              certificate = certificatePath;
              "private-key" = privateKeyPath;
              obfs = "gecko";
              "obfs-password" = config.sops.placeholder.${settings.obfsPasswordSecretName};
              "obfs-min-packet-size" = 512;
              "obfs-max-packet-size" = 1200;
            };
            renderedConfig = builtins.toJSON {
              ipv6 = false;
              "log-level" = "info";
              listeners = [ listener ];
            };
            distinctUserNames = lib.length (lib.unique profileNames) == lib.length profileNames;
            distinctSecretNames =
              lib.length (lib.unique (userSecretNames ++ [ settings.obfsPasswordSecretName ]))
              == lib.length userSecretNames + 1;
            activeInstances = config.clanwright.vpn.hysteria2.activeInstances;
          in
          {
            options.clanwright.vpn.hysteria2 = {
              activeInstances = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                internal = true;
                description = "Active Hysteria2 instances claiming the stable unit and template names.";
              };
              masqueradeRoot = lib.mkOption {
                type = lib.types.addCheck lib.types.str validMasqueradeRoot;
                description = "Consumer-owned static site root in the Nix store used for Hysteria2 masquerading.";
              };
            };

            config = {
              clanwright.vpn.hysteria2.activeInstances = lib.mkIf active [ instanceName ];

              assertions = lib.optionals active [
                {
                  assertion = system == "x86_64-linux";
                  message = "Hysteria2 runtime is supported only on x86_64-linux";
                }
                {
                  assertion = config.networking.firewall.enable;
                  message = "Hysteria2 requires the NixOS firewall to be enabled";
                }
                {
                  assertion = config.networking.firewall.backend == "nftables";
                  message = "Hysteria2 destination-scoped ingress requires the nftables firewall backend";
                }
                {
                  assertion = lib.length activeInstances == 1;
                  message = "Only one active Hysteria2 instance may claim a machine";
                }
                {
                  assertion = settings.users != [ ];
                  message = "Hysteria2 requires at least one per-device user";
                }
                {
                  assertion = distinctUserNames;
                  message = "Hysteria2 device identities must be unique";
                }
                {
                  assertion = distinctSecretNames;
                  message = "Hysteria2 user and Gecko credentials must use distinct SOPS secrets";
                }
              ];

              users.groups = lib.optionalAttrs active { ${serviceName} = { }; };
              users.users = lib.optionalAttrs active {
                ${serviceName} = {
                  isSystemUser = true;
                  group = serviceName;
                };
              };

              sops.secrets = lib.optionalAttrs active (
                lib.genAttrs (userSecretNames ++ [ settings.obfsPasswordSecretName ]) (_: {
                  owner = "root";
                  group = "root";
                  mode = "0400";
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

              systemd.services = lib.optionalAttrs active {
                ${serviceName} = {
                  description = "Deprecated Mihomo Hysteria2 gateway retained for compatibility";
                  after = [ "network-online.target" ] ++ sopsUnits;
                  wants = [ "network-online.target" ] ++ sopsUnits;
                  wantedBy = [ "multi-user.target" ];
                  restartTriggers = [ mihomoPackage ];
                  postStart = ''
                    set -euo pipefail

                    expected_local=${lib.escapeShellArg expectedUdpLocal}
                    for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
                      if [ -z "''${MAINPID:-}" ]; then
                        echo "mihomo-hysteria2: main process inspection unavailable during UDP listener readiness" >&2
                        exit 1
                      fi
                      udp_table="$(${pkgs.coreutils}/bin/cat /proc/"$MAINPID"/net/udp 2>/dev/null)" || {
                        echo "mihomo-hysteria2: main process inspection unavailable during UDP listener readiness" >&2
                        exit 1
                      }

                      while read -r slot local_address remote_address state queues timers retransmits uid timeout inode remainder; do
                        if [ "$local_address" != "$expected_local" ] \
                          || [ "$remote_address" != "00000000:0000" ] \
                          || [ "$state" != "07" ]; then
                          continue
                        fi

                        for fd in /proc/"$MAINPID"/fd/*; do
                          target="$(${pkgs.coreutils}/bin/readlink "$fd" 2>/dev/null || true)"
                          if [ "$target" = "socket:[$inode]" ]; then
                            exit 0
                          fi
                        done
                      done <<< "$udp_table"

                      ${pkgs.coreutils}/bin/sleep 1
                    done

                    echo "mihomo-hysteria2: main process did not own the configured UDP listener within 15 seconds" >&2
                    exit 1
                  '';
                  serviceConfig = {
                    Type = "exec";
                    User = serviceName;
                    Group = serviceName;
                    ExecStart = "${lib.getExe mihomoPackage} -d /var/lib/${serviceName} -f ${configPath}";
                    Environment = "SAFE_PATHS=${credentialDirectory}";
                    Restart = "on-failure";
                    RestartSec = "2s";
                    TimeoutStartSec = "20s";
                    StateDirectory = serviceName;
                    StateDirectoryMode = "0750";
                    UMask = "0077";
                    AmbientCapabilities = bindCapability;
                    CapabilityBoundingSet = bindCapability;
                    LoadCredential = [
                      "certificate.pem:${certificateSource}"
                      "private-key.pem:${privateKeySource}"
                    ];
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
                      "AF_INET6"
                      "AF_UNIX"
                    ];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    RestrictSUIDSGID = true;
                    SystemCallArchitectures = "native";
                  };
                };
              };

              networking.firewall.extraInputRules = lib.mkIf active (
                lib.mkAfter ''
                  ip daddr ${settings.listenIPv4} udp dport ${toString settings.port} accept comment "mihomo hysteria2 destination-scoped ingress"
                ''
              );

              security.acme.certs = lib.optionalAttrs active {
                ${settings.acmeCertName}.reloadServices = [ serviceUnit ];
              };
            };
          };
      };
  };
}
