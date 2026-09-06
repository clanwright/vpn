{
  mihomoPackageFor ? (
    _system: throw "mihomo-vless-xhttp requires an explicit mihomoPackageFor dependency"
  ),
  lib,
  ...
}:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-mihomo-vless-xhttp";
    description = "Independent Mihomo VLESS/REALITY + XHTTP gateway fragment";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public VLESS/XHTTP gateway listener";
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
          bindIPv4 = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 address for the VLESS listener.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
          };
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Public hostname represented by this VLESS fragment.";
          };
          clientFingerprint = lib.mkOption {
            type = lib.types.enum [
              "edge"
              "firefox"
            ];
            default = "edge";
            description = "TLS client fingerprint published for generated client profiles.";
          };
          doh = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                domain = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Provider-local DNS-over-HTTPS hostname for generated profiles.";
                };
                ipv4 = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Provider-local DNS-over-HTTPS IPv4 address.";
                };
              };
            });
            default = { };
          };
          reality = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                serverName = lib.mkOption { type = lib.types.str; };
                dest = lib.mkOption { type = lib.types.str; };
                shortIds = lib.mkOption { type = lib.types.listOf lib.types.str; };
                publicKey = lib.mkOption { type = lib.types.str; };
                privateKeySecretName = lib.mkOption { type = lib.types.str; };
              };
            });
          };
          xhttp = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                path = lib.mkOption { type = lib.types.str; };
                mode = lib.mkOption {
                  type = lib.types.enum [
                    "auto"
                    "stream-one"
                    "stream-up"
                    "packet-up"
                  ];
                  default = "packet-up";
                };
              };
            });
          };
          profiles = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption { type = lib.types.str; };
                  vlessUuidSecretName = lib.mkOption { type = lib.types.str; };
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
            default = [ ];
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
        active = settings.enable && (settings.lifecycle or "enabled") == "enabled";
        providerMachine =
          if machine ? name && machine.name != null && machine.name != "" then
            machine.name
          else
            builtins.head (lib.splitString "--" instanceName);
        profileNames = map (profile: profile.name) settings.profiles;
        secretNames = {
          realityPrivateKey = settings.reality.privateKeySecretName;
          vlessUuid = lib.listToAttrs (
            map (profile: {
              inherit (profile) name;
              value = profile.vlessUuidSecretName;
            }) settings.profiles
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
            protocol = "vless-xhttp";
            enabled = true;
            endpoint = {
              inherit (settings) domain;
              ipv4 = settings.bindIPv4;
              inherit (settings) port;
              transport = "tcp";
            };
            transportMetadata = {
              protocol = "vless-xhttp";
              reality = {
                inherit (settings.reality)
                  serverName
                  dest
                  shortIds
                  publicKey
                  ;
              };
              inherit (settings) xhttp;
              fingerprint = settings.clientFingerprint;
              inherit (settings) doh;
            };
            inherit profileNames secretNames;
          };
        });
        nixosModule =
          { pkgs, ... }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            mihomoPackage = mihomoPackageFor system;
            active = settings.enable && (settings.lifecycle or "enabled") == "enabled";
          in
          {
            imports = [ ../../modules/edge/mihomo-runtime.nix ];
            networkCore.mihomo.packages = lib.mkIf active (lib.mkForce [ mihomoPackage ]);
            networkCore.mihomo.vlessXhttp = lib.mkIf active [
              (builtins.removeAttrs settings [
                "lifecycle"
                "clientFingerprint"
                "doh"
              ])
            ];
          };
      };
  };
}
