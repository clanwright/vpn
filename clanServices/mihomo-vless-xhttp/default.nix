{
  xrayPackageFor ? (
    _system: throw "mihomo-vless-xhttp requires an explicit xrayPackageFor dependency"
  ),
  lib,
  ...
}:
let
  identityPattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,63}";
  secretNamePattern = "[A-Za-z0-9_][A-Za-z0-9_.+-]*(/[A-Za-z0-9_][A-Za-z0-9_.+-]*)*";
  validIdentity = value: builtins.match identityPattern value != null;
  validSecretName = value: builtins.match secretNamePattern value != null;
  validHostname =
    value:
    let
      labels = lib.splitString "." value;
      validLabel = label: builtins.match "[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?" label != null;
    in
    value != "" && builtins.stringLength value <= 253 && builtins.all validLabel labels;
  parseDecimal = value: builtins.match "(0|[1-9][0-9]{0,2})" value != null;
  validIPv4 =
    value:
    let
      octets = lib.splitString "." value;
    in
    lib.length octets == 4
    && builtins.all (octet: parseDecimal octet && builtins.fromJSON octet <= 255) octets;
  validLoopbackIPv4 = value: validIPv4 value && builtins.head (lib.splitString "." value) == "127";
  validShortId = value: builtins.match "[0-9a-f]{16}" value != null;
  validPublicKey = value: builtins.match "[A-Za-z0-9_-]{43}" value != null;
  validPath = value: builtins.match "/[^[:space:]]*" value != null;
  identityType = lib.types.addCheck lib.types.str validIdentity;
  secretNameType = lib.types.addCheck lib.types.str validSecretName;
  hostnameType = lib.types.addCheck lib.types.str validHostname;
in
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-mihomo-vless-xhttp";
    description = "Independent stock Xray VLESS/REALITY + XHTTP gateway";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public VLESS/REALITY/XHTTP gateway listener";
    interface = { lib, ... }: {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        bindIPv4 = lib.mkOption {
          type = lib.types.addCheck lib.types.str validIPv4;
          description = "Public endpoint IPv4 address and direct-listener bind address.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 443;
        };
        domain = lib.mkOption {
          type = hostnameType;
          description = "Public VLESS endpoint hostname used by generated clients.";
        };
        localListener = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule (_: {
              options = {
                ipv4 = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validLoopbackIPv4;
                  default = "127.0.0.1";
                  description = "Canonical loopback IPv4 address for consumer-owned TCP passthrough.";
                };
                port = lib.mkOption {
                  type = lib.types.addCheck lib.types.port (port: port != 0);
                  description = "Required local Xray listener port for consumer-owned TCP passthrough.";
                };
              };
            })
          );
          default = null;
          description = "Optional loopback listener behind consumer-owned TCP passthrough.";
        };
        clientFingerprint = lib.mkOption {
          type = lib.types.enum [
            "edge"
            "firefox"
          ];
          default = "edge";
          description = "TLS fingerprint published for generated client profiles.";
        };
        doh = lib.mkOption {
          type = lib.types.submodule (_: {
            options = {
              domain = lib.mkOption { type = hostnameType; };
              ipv4 = lib.mkOption { type = lib.types.addCheck lib.types.str validIPv4; };
            };
          });
          description = "Client publication metadata; this service creates no DoH listener.";
        };
        reality = lib.mkOption {
          type = lib.types.submodule (_: {
            options = {
              targetHost = lib.mkOption {
                type = hostnameType;
                description = "External TLS 1.3 and HTTP/2 REALITY target; port 443 is fixed.";
              };
              serverNames = lib.mkOption {
                type = lib.types.nonEmptyListOf hostnameType;
                description = "Names covered by the selected target certificate.";
              };
              publicKey = lib.mkOption { type = lib.types.addCheck lib.types.str validPublicKey; };
              privateKeySecretName = lib.mkOption { type = secretNameType; };
            };
          });
        };
        xhttp = lib.mkOption {
          type = lib.types.submodule (_: {
            options = {
              path = lib.mkOption { type = lib.types.addCheck lib.types.str validPath; };
            };
          });
        };
        profiles = lib.mkOption {
          type = lib.types.nonEmptyListOf (
            lib.types.submodule (_: {
              options = {
                name = lib.mkOption { type = identityType; };
                vlessUuidSecretName = lib.mkOption { type = secretNameType; };
                realityShortId = lib.mkOption { type = lib.types.addCheck lib.types.str validShortId; };
                kind = lib.mkOption {
                  type = lib.types.enum [
                    "mobile"
                    "router"
                    "probe"
                  ];
                  default = "mobile";
                };
                publishProfileJson = lib.mkOption {
                  type = lib.types.nullOr lib.types.bool;
                  default = null;
                };
              };
            })
          );
        };
      };
    };

    perInstance =
      {
        settings,
        instanceName ? "mihomo-vless-xhttp",
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
        profileNames = map (profile: profile.name) settings.profiles;
        uuidSecretNames = map (profile: profile.vlessUuidSecretName) settings.profiles;
        shortIds = map (profile: profile.realityShortId) settings.profiles;
        shortIdsByProfile = lib.listToAttrs (
          map (profile: {
            inherit (profile) name;
            value = profile.realityShortId;
          }) settings.profiles
        );
        secretNames = {
          realityPrivateKey = settings.reality.privateKeySecretName;
          vlessUuid = lib.listToAttrs (
            map (profile: {
              inherit (profile) name;
              value = profile.vlessUuidSecretName;
            }) settings.profiles
          );
        };
        localListener = settings.localListener or null;
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = {
            schemaVersion = 2;
            instanceId = instanceName;
            machine = providerMachine;
            role = "gateway";
            protocol = "vless-xhttp";
            enabled = true;
            endpoint = {
              inherit (settings) domain port;
              ipv4 = settings.bindIPv4;
              transport = "tcp";
            };
            transportMetadata = {
              protocol = "vless-xhttp";
              reality = {
                serverName = settings.reality.targetHost;
                inherit (settings.reality) serverNames publicKey;
                target = "${settings.reality.targetHost}:443";
                inherit shortIdsByProfile;
              };
              xhttp = {
                inherit (settings.xhttp) path;
                mode = "auto";
              };
              fingerprint = settings.clientFingerprint;
              inherit (settings) doh;
            };
            inherit profileNames secretNames;
          };
        });

        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            xrayPackage = xrayPackageFor system;
            listenerIPv4 = if localListener == null then settings.bindIPv4 else localListener.ipv4;
            listenerPort = if localListener == null then settings.port else localListener.port;
            bindCapability = lib.optional (listenerPort < 1024) "CAP_NET_BIND_SERVICE";
            active = settings.enable;
            serviceName = "xray.service";
            templateName = "xray-vless-xhttp.json";
            configCredentialPath = config.sops.templates.${templateName}.path;
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            xraySettings = {
              log.loglevel = "warning";
              inbounds = [
                {
                  tag = "vless-xhttp-in";
                  listen = listenerIPv4;
                  port = listenerPort;
                  protocol = "vless";
                  settings = {
                    clients = map (profile: {
                      id = config.sops.placeholder.${profile.vlessUuidSecretName};
                      email = profile.name;
                    }) settings.profiles;
                    decryption = "none";
                  };
                  streamSettings = {
                    network = "xhttp";
                    security = "reality";
                    realitySettings = {
                      show = false;
                      target = "${settings.reality.targetHost}:443";
                      xver = 0;
                      inherit (settings.reality) serverNames;
                      privateKey = config.sops.placeholder.${settings.reality.privateKeySecretName};
                      inherit shortIds;
                    };
                    xhttpSettings = {
                      inherit (settings.xhttp) path;
                      mode = "auto";
                    };
                  };
                  sniffing.enabled = false;
                }
              ];
              outbounds = [
                {
                  tag = "direct";
                  protocol = "freedom";
                }
              ];
            };
            secretDeclarations =
              lib.genAttrs (lib.unique ([ settings.reality.privateKeySecretName ] ++ uuidSecretNames))
                (_name: {
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  restartUnits = [ serviceName ];
                });
          in
          {
            imports = [
              {
                options.clanwright.vpn.xrayVless.activeInstances = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  internal = true;
                  description = "Active VLESS instances claiming the stable Xray unit and template.";
                };
              }
            ];
            clanwright.vpn.xrayVless.activeInstances = lib.mkIf active [ instanceName ];
            assertions = [
              {
                assertion = !active || lib.length config.clanwright.vpn.xrayVless.activeInstances == 1;
                message = "Only one active VLESS/XHTTP instance may claim a machine.";
              }
              {
                assertion =
                  !active
                  || localListener != null
                  || (config.networking.firewall.enable && config.networking.firewall.backend == "nftables");
                message = "VLESS/XHTTP requires the consumer's enabled nftables firewall for destination-scoped ingress.";
              }
              {
                assertion = !active || settings.bindIPv4 != "0.0.0.0";
                message = "VLESS/XHTTP requires an exact non-wildcard bindIPv4 for scoped ingress.";
              }
              {
                assertion = !active || localListener == null || !validLoopbackIPv4 settings.bindIPv4;
                message = "VLESS/XHTTP local-listener mode requires a non-loopback public bindIPv4 endpoint.";
              }
              {
                assertion = !active || builtins.elem settings.reality.targetHost settings.reality.serverNames;
                message = "VLESS/XHTTP REALITY target host must be present in serverNames.";
              }
              {
                assertion = !active || lib.toLower settings.reality.targetHost != lib.toLower settings.domain;
                message = "VLESS/XHTTP REALITY target must differ from the public VPN endpoint domain.";
              }
              {
                assertion =
                  !active
                  ||
                    lib.length (lib.unique (map lib.toLower settings.reality.serverNames))
                    == lib.length settings.reality.serverNames;
                message = "VLESS/XHTTP REALITY serverNames must be unique.";
              }
              {
                assertion = !active || lib.length (lib.unique profileNames) == lib.length profileNames;
                message = "VLESS/XHTTP profile names must be unique.";
              }
              {
                assertion = !active || lib.length (lib.unique uuidSecretNames) == lib.length uuidSecretNames;
                message = "VLESS/XHTTP UUID secret names must be unique per device.";
              }
              {
                assertion = !active || !(builtins.elem settings.reality.privateKeySecretName uuidSecretNames);
                message = "VLESS/XHTTP REALITY and UUID credentials must use distinct SOPS secret names.";
              }
              {
                assertion = !active || lib.length (lib.unique shortIds) == lib.length shortIds;
                message = "VLESS/XHTTP REALITY short IDs must be unique per device.";
              }
            ];
          }
          // lib.optionalAttrs active {
            sops.secrets = secretDeclarations;
            sops.templates.${templateName} = {
              content = builtins.toJSON xraySettings;
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ serviceName ];
            };
            services.xray = {
              enable = true;
              package = lib.mkForce xrayPackage;
              settingsFile = configCredentialPath;
            };
            systemd.services.xray = {
              after = [ "network-online.target" ] ++ sopsUnits;
              wants = [ "network-online.target" ] ++ sopsUnits;
              serviceConfig = {
                AmbientCapabilities = lib.mkForce bindCapability;
                CapabilityBoundingSet = lib.mkForce bindCapability;
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                ];
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                Restart = "on-failure";
                RestartSec = "2s";
                UMask = "0077";
              };
            };
          }
          // lib.optionalAttrs (active && localListener == null) {
            networking.firewall.extraInputRules = lib.mkAfter ''
              ip daddr ${settings.bindIPv4} tcp dport ${toString settings.port} accept comment "xray vless destination-scoped ingress"
            '';
          };
      };
  };
}
