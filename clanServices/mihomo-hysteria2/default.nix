{
  mihomoPackageFor ? (
    _system: throw "mihomo-hysteria2 requires an explicit mihomoPackageFor dependency"
  ),
  lib,
  ...
}:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-mihomo-hysteria2";
    description = "Independent Mihomo Hysteria2 gateway fragment";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public Hysteria2 UDP gateway listener";
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
          listenIPv4 = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 address for the Hysteria2 listener.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
          };
          serverName = lib.mkOption {
            type = lib.types.str;
            description = "Existing Hysteria2 endpoint hostname; ALPN is fixed to h3.";
          };
          users = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption { type = lib.types.str; };
                  passwordSecretName = lib.mkOption { type = lib.types.str; };
                };
              })
            );
            default = [ ];
          };
          masqueradeUrl = lib.mkOption { type = lib.types.str; };
          ignoreClientBandwidth = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          acmeCertName = lib.mkOption { type = lib.types.str; };
          obfsPasswordSecretName = lib.mkOption { type = lib.types.str; };
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
        active = settings.enable && (settings.lifecycle or "enabled") == "enabled";
        providerMachine =
          if machine ? name && machine.name != null && machine.name != "" then
            machine.name
          else
            builtins.head (lib.splitString "--" instanceName);
        profileNames = map (user: user.name) settings.users;
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
          vpnProvider = {
            schemaVersion = 1;
            instanceId = instanceName;
            machine = providerMachine;
            role = "gateway";
            protocol = "hysteria2";
            enabled = true;
            endpoint = {
              domain = settings.serverName;
              ipv4 = settings.listenIPv4;
              inherit (settings) port;
              transport = "udp";
            };
            transportMetadata = {
              protocol = "hysteria2";
              sni = settings.serverName;
              alpn = [ "h3" ];
              userNames = profileNames;
              obfsName = "salamander";
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
            networkCore.mihomo.hysteria2 = lib.mkIf active [
              (
                (builtins.removeAttrs settings [ "lifecycle" ])
                // {
                  alpn = [ "h3" ];
                }
              )
            ];
          };
      };
  };
}
