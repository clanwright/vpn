{
  appsPkgsFor ? (_system: throw "amneziawg requires an explicit appsPkgsFor dependency"),
  lib,
  ...
}:
let
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
          lifecycle = lib.mkOption {
            type = lib.types.enum [
              "enabled"
              "disabled-retained"
            ];
            default = "enabled";
          };

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

          mtu = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
          };

          address = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            description = "Interface address with prefix, for example 10.77.0.1/24.";
          };

          privateKeySecretName = lib.mkOption {
            type = lib.types.str;
          };

          serverPublicKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Configured public key derived from the gateway private key at runtime.";
          };

          peers = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                  };
                  publicKey = lib.mkOption {
                    type = lib.types.str;
                  };
                  allowedIPs = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                  };
                  clientPersistentKeepalive = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                  };
                  serverPersistentKeepalive = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                  };
                };
              })
            );
            default = [ ];
          };

          extraOptions = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.oneOf [
                lib.types.str
                lib.types.int
              ]
            );
            default = { };
            description = "AmneziaWG 2.0 interface options: H1-H4, I1-I5, Jc, Jmin, Jmax, and S1-S4.";
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
        active = settings.enable && (settings.lifecycle or "enabled") == "enabled";
        providerMachine =
          if machine ? name && machine.name != null && machine.name != "" then
            machine.name
          else
            builtins.head (lib.splitString "--" instanceName);
        rendererMachineName = lib.removeSuffix "-grosbeak" providerMachine;
        profileNames = map (peer: peer.name) settings.peers;
        secretNames = {
          clientPrivateKey = lib.listToAttrs (
            map (peer: {
              inherit (peer) name;
              value = "amneziawg-${rendererMachineName}-client-${peer.name}-private-key";
            }) settings.peers
          );
        };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = {
            schemaVersion = 1;
            instanceId = instanceName;
            machine = providerMachine;
            role = "gateway";
            protocol = "amneziawg";
            enabled = true;
            endpoint = {
              domain = settings.endpointDomain;
              ipv4 = settings.listenIPv4;
              port = settings.listenPort;
              transport = "udp";
            };
            transportMetadata = {
              protocol = "amneziawg";
              inherit (settings) serverPublicKey;
              inherit (settings) interfaceName;
              inherit (settings) address;
              inherit (settings) mtu;
              inherit (settings) peers;
              peerPublicKeys = lib.listToAttrs (
                map (peer: {
                  inherit (peer) name;
                  value = peer.publicKey;
                }) settings.peers
              );
              inherit (settings) extraOptions;
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
            publicKeyCheck = import ./public-key-check.nix { pkgs = appsPkgs; };
            mkPeer =
              peer:
              let
                persistentKeepalive = peer.serverPersistentKeepalive or null;
              in
              {
                inherit (peer) publicKey allowedIPs;
              }
              // lib.optionalAttrs (persistentKeepalive != null) {
                inherit persistentKeepalive;
              };

            nftNatTableName = "vpn_amneziawg_${builtins.hashString "sha256" settings.interfaceName}";
            inRange =
              value: min: max:
              value >= min && value <= max;
            peerPersistentKeepaliveIsValid =
              peer:
              let
                clientPersistentKeepalive = peer.clientPersistentKeepalive or null;
                serverPersistentKeepalive = peer.serverPersistentKeepalive or null;
                isValid = value: value == null || (builtins.isInt value && inRange value 1 65535);
              in
              isValid clientPersistentKeepalive && isValid serverPersistentKeepalive;
            interfaceExtraOptions = lib.filterAttrs (_: value: value != "") settings.extraOptions;
            optionAssertions = map (item: item // { assertion = !active || item.assertion; }) (
              validation.assertions {
                options = settings.extraOptions;
                serviceName = "amneziawg";
              }
            );
            active = settings.enable && (settings.lifecycle or "enabled") == "enabled";
          in
          {
            assertions = [
              {
                assertion = !active || settings.interfaceName != "";
                message = "amneziawg: interfaceName must not be empty.";
              }
              {
                assertion = !active || settings.listenIPv4 != null;
                message = "amneziawg: listenIPv4 must not be empty.";
              }
              {
                assertion = !active || settings.address != null;
                message = "amneziawg: address must not be empty.";
              }
              {
                assertion = !active || settings.privateKeySecretName != "";
                message = "amneziawg: privateKeySecretName must not be empty.";
              }
              {
                assertion = !active || (settings.serverPublicKey != null && settings.serverPublicKey != "");
                message = "amneziawg: serverPublicKey must not be empty.";
              }
              {
                assertion =
                  !active || settings.mtu == null || (builtins.isInt settings.mtu && inRange settings.mtu 1280 1420);
                message = "amneziawg: mtu must be null or within 1280..1420.";
              }
              {
                assertion = !active || settings.peers != [ ];
                message = "amneziawg: at least one peer is required.";
              }
              {
                assertion = !active || builtins.all peerPersistentKeepaliveIsValid settings.peers;
                message = "amneziawg: clientPersistentKeepalive and serverPersistentKeepalive must be null or within 1..65535.";
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
              {
                assertion = !active || !settings.enableNat || settings.egressIPv4 != null;
                message = "amneziawg: egressIPv4 is required when NAT is enabled.";
              }
              {
                assertion = !active || !settings.enableNat || settings.clientSubnetIPv4 != null;
                message = "amneziawg: clientSubnetIPv4 is required when NAT is enabled.";
              }
            ]
            ++ optionAssertions;

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
              # The networkd backend asserts WireGuard interfaces use type = "wireguard".
              wireguard.useNetworkd = lib.mkForce false;
              wireguard.interfaces.${settings.interfaceName} = {
                inherit (settings) listenPort mtu;
                extraOptions = interfaceExtraOptions;
                type = "amneziawg";
                ips = [ settings.address ];
                privateKeyFile = config.sops.secrets.${settings.privateKeySecretName}.path;
                peers = map mkPeer settings.peers;
                postSetup = ''
                  ${lib.getExe publicKeyCheck} \
                    ${lib.escapeShellArg settings.privateKeySecretName} \
                    ${lib.escapeShellArg config.sops.secrets.${settings.privateKeySecretName}.path} \
                    ${lib.escapeShellArg settings.serverPublicKey}
                '';
              };

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
                      ip saddr ${settings.clientSubnetIPv4} snat to ${settings.egressIPv4} comment "amneziawg source NAT"
                    }
                  '';
                };
              };
            };

          }
          // lib.optionalAttrs settings.enable {
            # Retain the declaration and restart metadata while a brick is
            # disabled-retained; the active block above owns runtime effects.
            sops.secrets.${settings.privateKeySecretName} = {
              path = "/run/secrets/${settings.privateKeySecretName}";
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ "wireguard-${settings.interfaceName}.service" ];
            };
          }
          // lib.optionalAttrs (active && settings.enableNat) {
            boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
          };
      };
  };
}
