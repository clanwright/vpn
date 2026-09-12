{
  lib,
  mieruPackageFor ? (_system: throw "mieru requires an explicit mieruPackageFor dependency"),
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
  validIngressIPv4 = value: validIPv4 value && value != "0.0.0.0";
in
{
  _class = "clan.service";

  manifest = {
    name = "@clanwright/vpn-mieru";
    description = "Standalone native Mieru TCP gateway with guarded process egress";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public native Mieru TCP gateway";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run the native Mieru gateway.";
          };

          ingressIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str validIngressIPv4;
            description = "Consumer-owned public IPv4 accepted by the destination-scoped ingress guard and exported to clients.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Single native Mieru TCP port.";
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

          dnsResolverIPv4s = lib.mkOption {
            type = lib.types.addCheck (lib.types.listOf (lib.types.addCheck lib.types.str validIPv4)) (
              value: value != [ ] && lib.length (lib.unique value) == lib.length value
            );
            description = "Exact nonempty system resolver IPv4 list allowed for mita TCP/UDP port 53 egress.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "mieru",
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
        };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = providerEnvelope.mkProvider {
            protocol = "mieru";
            instanceId = instanceName;
            machine = providerMachine;
            endpoint = {
              domain = null;
              ipv4 = settings.ingressIPv4;
              inherit (settings) port;
            };
            transportMetadata = {
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
            mieruPackage = mieruPackageFor system;
            serviceName = "mita";
            serviceUnit = "${serviceName}.service";
            templateName = "${serviceName}.json";
            nftTableName = "vpn_mieru_egress";
            configPath = config.sops.templates.${templateName}.path;
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            distinctUserNames = lib.length (lib.unique profileNames) == lib.length profileNames;
            distinctSecretNames = lib.length (lib.unique userSecretNames) == lib.length userSecretNames;
            activeInstances = config.clanwright.vpn.mieru.activeInstances;
            resolverSet = lib.concatStringsSep ", " settings.dnsResolverIPv4s;
            publicOnlyDenyIPv4 = [
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
            deniedIPv4Set = lib.concatStringsSep ", " publicOnlyDenyIPv4;
            expectedNftContent = ''
              chain input_guard {
                type filter hook input priority -10; policy accept;
                meta nfproto ipv6 tcp dport ${toString settings.port} drop comment "mieru deny wildcard IPv6 ingress"
                ip daddr != ${settings.ingressIPv4} tcp dport ${toString settings.port} drop comment "mieru deny wildcard IPv4 ingress"
              }

              chain output {
                type filter hook output priority filter; policy accept;
                meta skuid "mita" ct direction reply accept comment "mieru preserve replies"
                meta skuid "mita" ip daddr { ${resolverSet} } udp dport 53 accept comment "mieru exact resolver UDP"
                meta skuid "mita" ip daddr { ${resolverSet} } tcp dport 53 accept comment "mieru exact resolver TCP"
                meta skuid "mita" ip daddr { ${deniedIPv4Set} } drop comment "mieru deny non-public IPv4 egress"
                meta skuid "mita" ip6 daddr ::/0 drop comment "mieru deny IPv6 egress"
              }
            '';
            renderedConfig = builtins.toJSON {
              portBindings = [
                {
                  inherit (settings) port;
                  protocol = "TCP";
                }
              ];
              users = map (user: {
                inherit (user) name;
                password = config.sops.placeholder.${user.passwordSecretName};
                allowPrivateIP = false;
                allowLoopbackIP = false;
              }) settings.users;
              loggingLevel = "INFO";
              dns.dualStack = "ONLY_IPv4";
            };
            socketPortHex = lib.fixedWidthString 4 "0" (lib.toHexString settings.port);
            expectedTcp4Local = "00000000:${socketPortHex}";
            expectedTcp6Local = "00000000000000000000000000000000:${socketPortHex}";
            passwordValidator = pkgs.writeShellScript "mita-validate-passwords" (
              ''
                set -eu
              ''
              + lib.concatMapStringsSep "\n" (secretName: ''
                secret_path=${lib.escapeShellArg config.sops.secrets.${secretName}.path}
                byte_count="$(${pkgs.coreutils}/bin/wc -c < "$secret_path")"
                base64url_byte_count="$(LC_ALL=C ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9_-' < "$secret_path" | ${pkgs.coreutils}/bin/wc -c)"
                if [ "$byte_count" -eq 0 ] || [ "$byte_count" -gt 64 ] || [ "$byte_count" -ne "$base64url_byte_count" ]; then
                  echo "mita: a device password must be 1..64 raw unpadded base64url bytes" >&2
                  exit 1
                fi
              '') userSecretNames
            );
            bindCapabilities = lib.optional (settings.port < 1024) "CAP_NET_BIND_SERVICE";
          in
          {
            options.clanwright.vpn.mieru.activeInstances = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              internal = true;
              description = "Active Mieru instances claiming the upstream singleton mita runtime.";
            };

            config = {
              clanwright.vpn.mieru.activeInstances = lib.mkIf active [ instanceName ];

              assertions = lib.optionals active [
                {
                  assertion = system == "x86_64-linux";
                  message = "mieru: runtime support is restricted to x86_64-linux.";
                }
                {
                  assertion = lib.getVersion mieruPackage == "3.36.0";
                  message = "mieru: the injected stock package must be exactly version 3.36.0.";
                }
                {
                  assertion = pkgs.mieru == mieruPackage;
                  message = "mieru: pkgs.mieru must come from the injected VPN application pin.";
                }
                {
                  assertion = config.networking.firewall.enable;
                  message = "mieru: destination-scoped ingress requires the NixOS firewall.";
                }
                {
                  assertion = config.networking.firewall.backend == "nftables";
                  message = "mieru: ingress and process-scoped egress require the nftables firewall backend.";
                }
                {
                  assertion = config.networking.nftables.enable;
                  message = "mieru: the module-owned process egress guard requires networking.nftables.enable.";
                }
                {
                  assertion = config.networking.nameservers == settings.dnsResolverIPv4s;
                  message = "mieru: networking.nameservers must exactly equal dnsResolverIPv4s because stock mita uses the system resolver.";
                }
                {
                  assertion = lib.length activeInstances == 1;
                  message = "mieru: only one active instance may claim the upstream singleton mita runtime per machine.";
                }
                {
                  assertion = settings.users != [ ];
                  message = "mieru: at least one per-device user is required.";
                }
                {
                  assertion = distinctUserNames;
                  message = "mieru: device identities must be unique.";
                }
                {
                  assertion = distinctSecretNames;
                  message = "mieru: every device must use a distinct SOPS password secret.";
                }
                {
                  assertion =
                    config.networking.nftables.tables.${nftTableName}.family == "inet"
                    && config.networking.nftables.tables.${nftTableName}.enable
                    && config.networking.nftables.tables.${nftTableName}.content == expectedNftContent;
                  message = "mieru: the module-owned ingress and process egress guard must not be removed or weakened.";
                }
                {
                  assertion =
                    config.systemd.services.mita.serviceConfig.User == "mita"
                    && config.systemd.services.mita.serviceConfig.Group == "mita"
                    && !(config.systemd.services.mita.serviceConfig.DynamicUser or false)
                    && config.systemd.services.mita.serviceConfig.ExecStart == "${mieruPackage}/bin/mita run"
                    && config.systemd.services.mita.serviceConfig.ExecStartPre == "+${passwordValidator}"
                    &&
                      config.systemd.services.mita.serviceConfig.Environment == [
                        "MITA_CONFIG_JSON_FILE=${configPath}"
                        "MITA_UDS_PATH=/run/mita/mita.sock"
                        "MITA_LOG_NO_TIMESTAMP=true"
                      ];
                  message = "mieru: mita identity, command, credential validation, and runtime paths must remain guarded.";
                }
              ];

              nixpkgs.overlays = lib.optional active (_final: _prev: { mieru = mieruPackage; });

              users.groups = lib.optionalAttrs active { mita = { }; };
              users.users = lib.optionalAttrs active {
                mita = {
                  isSystemUser = true;
                  group = "mita";
                  description = "Mieru server daemon";
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
                  owner = "mita";
                  group = "mita";
                  mode = "0400";
                  restartUnits = [ serviceUnit ];
                };
              };

              networking = {
                firewall.extraInputRules = lib.mkIf active (
                  lib.mkAfter ''
                    ip daddr ${settings.ingressIPv4} tcp dport ${toString settings.port} accept comment "mieru destination-scoped ingress"
                  ''
                );
                nftables = {
                  # The target user exists when nftables loads the real rules.
                  # Pure build-time nft syntax checking has no target /etc/passwd.
                  preCheckRuleset = lib.mkIf active (
                    lib.mkAfter ''
                      sed 's/meta skuid "mita"/meta skuid 0/g' -i ruleset.conf
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

              systemd.services = lib.optionalAttrs active {
                mita = {
                  description = "Native Mieru proxy gateway";
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
                  restartTriggers = [ mieruPackage ];
                  postStart = ''
                    set -euo pipefail

                    expected_tcp4=${lib.escapeShellArg expectedTcp4Local}
                    expected_tcp6=${lib.escapeShellArg expectedTcp6Local}
                    for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
                      if [ -z "''${MAINPID:-}" ]; then
                        echo "mita: main process inspection unavailable during TCP listener readiness" >&2
                        exit 1
                      fi

                      for table in tcp tcp6; do
                        proc_table="$(${pkgs.coreutils}/bin/cat /proc/"$MAINPID"/net/"$table" 2>/dev/null)" || {
                          echo "mita: main process inspection unavailable during TCP listener readiness" >&2
                          exit 1
                        }
                        expected_local="$expected_tcp4"
                        expected_remote="00000000:0000"
                        if [ "$table" = tcp6 ]; then
                          expected_local="$expected_tcp6"
                          expected_remote="00000000000000000000000000000000:0000"
                        fi

                        while read -r slot local_address remote_address state queues timers retransmits uid timeout inode remainder; do
                          if [ "$local_address" != "$expected_local" ] \
                            || [ "$remote_address" != "$expected_remote" ] \
                            || [ "$state" != "0A" ]; then
                            continue
                          fi

                          for fd in /proc/"$MAINPID"/fd/*; do
                            target="$(${pkgs.coreutils}/bin/readlink "$fd" 2>/dev/null || true)"
                            if [ "$target" = "socket:[$inode]" ]; then
                              exit 0
                            fi
                          done
                        done <<< "$proc_table"
                      done

                      ${pkgs.coreutils}/bin/sleep 1
                    done

                    echo "mita: main process did not own the configured wildcard TCP listener within 15 seconds" >&2
                    exit 1
                  '';
                  serviceConfig = {
                    Type = "exec";
                    User = "mita";
                    Group = "mita";
                    ExecStartPre = "+${passwordValidator}";
                    ExecStart = "${mieruPackage}/bin/mita run";
                    Environment = [
                      "MITA_CONFIG_JSON_FILE=${configPath}"
                      "MITA_UDS_PATH=/run/mita/mita.sock"
                      "MITA_LOG_NO_TIMESTAMP=true"
                    ];
                    Restart = "on-failure";
                    RestartSec = "5s";
                    TimeoutStartSec = "20s";
                    StateDirectory = "mita";
                    StateDirectoryMode = "0750";
                    RuntimeDirectory = "mita";
                    RuntimeDirectoryMode = "0750";
                    UMask = "0077";
                    AmbientCapabilities = bindCapabilities;
                    CapabilityBoundingSet = bindCapabilities;
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
            };
          };
      };
  };
}
