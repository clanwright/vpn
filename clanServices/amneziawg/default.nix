{
  appsPkgsFor ? (_system: throw "amneziawg requires an explicit appsPkgsFor dependency"),
  lib,
  ...
}:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  providerEnvelope = import ../../modules/contracts/provider-envelope.nix { inherit lib; };
  validation = import ./validation.nix { inherit lib; };
in
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-amneziawg";
    description = "AmneziaWG gateway with destination-IP scoped UDP ingress";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public AmneziaWG gateway";
    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };

          interfaceName = lib.mkOption {
            type = lib.types.str;
            default = "awg0";
          };

          listenIPv4 = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Public IPv4 allowed to receive AmneziaWG UDP packets.";
          };

          endpointDomain = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Public hostname used by generated AmneziaWG client profiles.";
          };

          listenPort = lib.mkOption {
            type = lib.types.port;
            default = 443;
          };

          address = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Interface address with prefix, for example 10.77.0.1/24.";
          };

          privateKeySecretName = lib.mkOption {
            type = identities.safeSecretNameType;
          };

          headerProtectionKeySecretName = lib.mkOption {
            type = identities.safeSecretNameType;
            description = "SOPS secret containing one canonical base64-encoded 32-byte AWG3 header protection key.";
          };

          serverPublicKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Declared public key corresponding to the gateway private key.";
          };

          peers = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption {
                    type = identities.safeIdentityType;
                  };
                  publicKey = lib.mkOption {
                    type = lib.types.str;
                  };
                  clientPrivateKeySecretName = lib.mkOption {
                    type = identities.safeSecretNameType;
                    description = "SOPS secret containing this peer's client private key.";
                  };
                  allowedIPs = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                  };
                  clientPersistentKeepalive = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                  };
                };
              })
            );
            default = [ ];
          };

          egressIPv4 = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Public source IPv4 used for SNAT when enableNat = true.";
          };

          clientSubnetIPv4 = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Client subnet used for forwarding and SNAT.";
          };

          enableNat = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "amneziawg",
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
        profileNames = map (peer: peer.name) settings.peers;
        secretNames = {
          headerProtectionKey = settings.headerProtectionKeySecretName;
          clientPrivateKey = lib.listToAttrs (
            map (peer: {
              inherit (peer) name;
              value = peer.clientPrivateKeySecretName;
            }) settings.peers
          );
        };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = providerEnvelope.mkProvider {
            protocol = "amneziawg";
            instanceId = instanceName;
            machine = providerMachine;
            endpoint = {
              domain = settings.endpointDomain;
              ipv4 = settings.listenIPv4;
              port = settings.listenPort;
            };
            transportMetadata = {
              inherit (settings) serverPublicKey;
              inherit (settings) interfaceName;
              inherit (settings) address;
              mtu = 1280;
              peers = map (peer: {
                inherit (peer)
                  name
                  publicKey
                  allowedIPs
                  clientPersistentKeepalive
                  ;
              }) settings.peers;
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
            appsPkgs = appsPkgsFor system;
            peerSetArguments = lib.concatMapStringsSep " " (
              peer:
              "peer ${lib.escapeShellArg peer.publicKey} allowed-ips ${
                lib.escapeShellArg (if peer.allowedIPs == [ ] then "" else builtins.head peer.allowedIPs)
              }"
            ) settings.peers;
            expectedPeers = lib.concatStringsSep "\n" (
              lib.sort builtins.lessThan (map (peer: peer.publicKey) settings.peers)
            );
            expectedPeerAllowedIPs = lib.concatStringsSep "\n" (
              lib.sort builtins.lessThan (
                map (
                  peer: "${peer.publicKey}\t${if peer.allowedIPs == [ ] then "" else builtins.head peer.allowedIPs}"
                ) settings.peers
              )
            );
            peerRouteCommands = lib.concatMapStringsSep "\n" (peer: ''
              ${pkgs.iproute2}/bin/ip route replace ${
                lib.escapeShellArg (if peer.allowedIPs == [ ] then "" else builtins.head peer.allowedIPs)
              } dev ${lib.escapeShellArg settings.interfaceName}
            '') settings.peers;
            interfaceNameArgument = lib.escapeShellArg settings.interfaceName;
            socketPath = lib.escapeShellArg "/run/amneziawg/${settings.interfaceName}.sock";

            nftNatTableName = "vpn_amneziawg_${builtins.hashString "sha256" settings.interfaceName}";
            settingsAssertions = map (item: item // { assertion = !active || item.assertion; }) (
              validation.assertions {
                inherit settings;
                serviceName = "amneziawg";
              }
            );
            active = settings.enable;
            interfaceClaims = config.clanwright.vpn.amneziawg.interfaceClaims;
            listenPortClaims = config.clanwright.vpn.amneziawg.listenPortClaims;
            requiredCapabilities = [
              "CAP_NET_ADMIN"
            ]
            ++ lib.optional (settings.listenPort < 1024) "CAP_NET_BIND_SERVICE";
          in
          {
            imports = [
              ./shared.nix
            ];
            clanwright.vpn.amneziawg = {
              interfaceClaims = lib.mkIf active [ settings.interfaceName ];
              listenPortClaims = lib.mkIf active [ settings.listenPort ];
              forwardingRequired = lib.mkIf (active && settings.enableNat) true;
            };
            assertions = settingsAssertions ++ [
              {
                assertion =
                  !active
                  || builtins.length (builtins.filter (name: name == settings.interfaceName) interfaceClaims) == 1;
                message = "amneziawg: each active interfaceName may be claimed by only one instance per machine.";
              }
              {
                assertion =
                  !active
                  || builtins.length (builtins.filter (port: port == settings.listenPort) listenPortClaims) == 1;
                message = "amneziawg: each active userspace instance must claim a unique listenPort per machine.";
              }
              {
                assertion = !active || system == "x86_64-linux";
                message = "amneziawg: runtime support is restricted to x86_64-linux.";
              }
              {
                assertion =
                  !active || (config.networking.firewall.enable && config.networking.firewall.backend == "nftables");
                message = "amneziawg: active destination-scoped ingress and NAT require the enabled NixOS nftables firewall backend.";
              }
              {
                assertion = !active || validation.packageFamiliesValid appsPkgs;
                message = "amneziawg: amneziawg-go and amneziawg-tools must both be in the 3.1.* family.";
              }
              {
                assertion = !active || pkgs.amneziawg-go == appsPkgs.amneziawg-go;
                message = "amneziawg: amneziawg-go must come from the VPN domain application pin.";
              }
              {
                assertion = !active || pkgs.amneziawg-tools == appsPkgs.amneziawg-tools;
                message = "amneziawg: amneziawg-tools must come from the VPN domain application pin.";
              }
            ];

          }
          // lib.optionalAttrs active {
            nixpkgs.overlays = [
              (_final: _prev: {
                inherit (appsPkgs) amneziawg-go amneziawg-tools;
              })
            ];

            environment.systemPackages = lib.filter (pkg: pkg != null) [
              (appsPkgs.amneziawg-tools or null)
              (appsPkgs.amneziawg-go or null)
            ];

            networking = {
              firewall = {
                extraInputRules = lib.mkAfter ''
                  ip daddr ${settings.listenIPv4} udp dport ${toString settings.listenPort} accept comment "amneziawg destination-scoped ingress"
                '';
                extraForwardRules = lib.mkAfter (
                  lib.optionalString settings.enableNat ''
                    iifname "${settings.interfaceName}" ip saddr ${settings.clientSubnetIPv4} accept comment "amneziawg client egress"
                    oifname "${settings.interfaceName}" ip daddr ${settings.clientSubnetIPv4} ct state { established, related } accept comment "amneziawg established return"
                  ''
                );
              };

              nftables.tables = lib.optionalAttrs settings.enableNat {
                ${nftNatTableName} = {
                  family = "ip";
                  content = ''
                    chain postrouting {
                      type nat hook postrouting priority srcnat - 10; policy accept;
                      ip saddr ${settings.clientSubnetIPv4} ip daddr != ${settings.clientSubnetIPv4} snat to ${settings.egressIPv4} comment "amneziawg source NAT"
                    }
                  '';
                };
              };
            };

            systemd.services."wireguard-${settings.interfaceName}" = {
              description = "AmneziaWG userspace tunnel - ${settings.interfaceName}";
              wantedBy = [ "multi-user.target" ];
              before = [ "network.target" ];
              after = [
                "network-pre.target"
              ]
              ++ lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
              wants = [
                "network.target"
              ]
              ++ lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
              serviceConfig = {
                Type = "exec";
                ExecStart = "${appsPkgs.amneziawg-go}/bin/amneziawg-go -f ${interfaceNameArgument}";
                Restart = "on-failure";
                RestartSec = "5s";
                TimeoutStartSec = "20s";
                AmbientCapabilities = requiredCapabilities;
                CapabilityBoundingSet = requiredCapabilities;
                DeviceAllow = [ "/dev/net/tun rw" ];
                DevicePolicy = "closed";
                LockPersonality = true;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_NETLINK"
                  "AF_UNIX"
                ];
                UMask = "0077";
              };
              postStart = ''
                attempts=0
                while [ ! -S ${socketPath} ] && [ "$attempts" -lt 100 ]; do
                  attempts=$((attempts + 1))
                  ${pkgs.coreutils}/bin/sleep 0.1
                done
                if [ ! -S ${socketPath} ]; then
                  echo "amneziawg: userspace interface socket did not become ready" >&2
                  exit 1
                fi

                if ! ${appsPkgs.amneziawg-tools}/bin/awg set ${interfaceNameArgument} \
                  private-key ${lib.escapeShellArg config.sops.secrets.${settings.privateKeySecretName}.path} \
                  listen-port ${lib.escapeShellArg (toString settings.listenPort)} \
                  content-padding-addition ${
                    lib.escapeShellArg validation.interfaceExtraOptions."Content-Padding-Addition"
                  } \
                  disable-cookies ${lib.escapeShellArg validation.interfaceExtraOptions."Disable-Cookies"} \
                  h1 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.H1)} \
                  h2 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.H2)} \
                  h3 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.H3)} \
                  h4 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.H4)} \
                  header-protection-key ${
                    lib.escapeShellArg config.sops.secrets.${settings.headerProtectionKeySecretName}.path
                  } \
                  random-trailers ${lib.escapeShellArg validation.interfaceExtraOptions."Random-Trailers"} \
                  s1 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.S1)} \
                  s2 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.S2)} \
                  s3 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.S3)} \
                  s4 ${lib.escapeShellArg (toString validation.interfaceExtraOptions.S4)} \
                  ${peerSetArguments} >/dev/null 2>&1; then
                  echo "amneziawg: userspace interface configuration failed" >&2
                  exit 1
                fi

                ${pkgs.iproute2}/bin/ip address add ${lib.escapeShellArg settings.address} dev ${interfaceNameArgument}
                ${pkgs.iproute2}/bin/ip link set dev ${interfaceNameArgument} mtu 1280
                ${pkgs.iproute2}/bin/ip link set up dev ${interfaceNameArgument}
                ${peerRouteCommands}

                link_state="$(${pkgs.iproute2}/bin/ip -o link show dev ${interfaceNameArgument} up 2>/dev/null)" || {
                  echo "amneziawg: interface link readiness query failed" >&2
                  exit 1
                }
                if [ -z "$link_state" ]; then
                  echo "amneziawg: expected interface link is not up" >&2
                  exit 1
                fi

                interfaces="$(${appsPkgs.amneziawg-tools}/bin/awg show interfaces 2>/dev/null)" || {
                  echo "amneziawg: interface readiness query failed" >&2
                  exit 1
                }
                interface_found=0
                for interface in $interfaces; do
                  if [ "$interface" = ${interfaceNameArgument} ]; then
                    interface_found=1
                  fi
                done
                if [ "$interface_found" -ne 1 ]; then
                  echo "amneziawg: expected interface is not ready" >&2
                  exit 1
                fi

                actual_listen_port="$(${appsPkgs.amneziawg-tools}/bin/awg show ${interfaceNameArgument} listen-port 2>/dev/null)" || {
                  echo "amneziawg: listen-port readiness query failed" >&2
                  exit 1
                }
                if [ "$actual_listen_port" != ${lib.escapeShellArg (toString settings.listenPort)} ]; then
                  echo "amneziawg: listen port readiness check failed" >&2
                  exit 1
                fi

                actual_peers_raw="$(${appsPkgs.amneziawg-tools}/bin/awg show ${interfaceNameArgument} peers 2>/dev/null)" || {
                  echo "amneziawg: peer readiness query failed" >&2
                  exit 1
                }
                actual_peers="$(${pkgs.coreutils}/bin/printf '%s\n' "$actual_peers_raw" | LC_ALL=C ${pkgs.coreutils}/bin/sort)" || {
                  echo "amneziawg: peer readiness normalization failed" >&2
                  exit 1
                }
                if [ "$actual_peers" != ${lib.escapeShellArg expectedPeers} ]; then
                  echo "amneziawg: peer readiness check failed" >&2
                  exit 1
                fi

                actual_peer_allowed_ips_raw="$(${appsPkgs.amneziawg-tools}/bin/awg show ${interfaceNameArgument} allowed-ips 2>/dev/null)" || {
                  echo "amneziawg: allowed-ips readiness query failed" >&2
                  exit 1
                }
                actual_peer_allowed_ips="$(${pkgs.coreutils}/bin/printf '%s\n' "$actual_peer_allowed_ips_raw" | LC_ALL=C ${pkgs.coreutils}/bin/sort)" || {
                  echo "amneziawg: allowed-ips readiness normalization failed" >&2
                  exit 1
                }
                if [ "$actual_peer_allowed_ips" != ${lib.escapeShellArg expectedPeerAllowedIPs} ]; then
                  echo "amneziawg: allowed-ips readiness check failed" >&2
                  exit 1
                fi
              '';
              postStop = ''
                ${pkgs.iproute2}/bin/ip link delete dev ${interfaceNameArgument} >/dev/null 2>&1 || true
                ${pkgs.coreutils}/bin/rm -f -- ${socketPath}
              '';
            };

          }
          // lib.optionalAttrs active {
            sops.secrets =
              lib.genAttrs
                (lib.unique [
                  settings.privateKeySecretName
                  settings.headerProtectionKeySecretName
                ])
                (secretName: {
                  path = "/run/secrets/${secretName}";
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  restartUnits = [ "wireguard-${settings.interfaceName}.service" ];
                });
          };
      };
  };
}
