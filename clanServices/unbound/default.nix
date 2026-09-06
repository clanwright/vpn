{
  unboundPackageFor ? (_system: throw "unbound requires an explicit unboundPackageFor dependency"),
}:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/dns-unbound";
    description = "Local recursive DNS backend for AdGuard";
    readme = builtins.readFile ./README.md;
  };

  roles.recursive-backend = {
    description = "Local recursive DNS backend";
    interface =
      { lib, ... }:
      {
        options = {
          listen.hosts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "127.0.0.1"
              "::1"
            ];
          };
          listen.port = lib.mkOption {
            type = lib.types.int;
            default = 5335;
          };
          privacy = {
            prefetch = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            hideIdentity = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            hideVersion = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            qnameMinimisation = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
          adguardIntegrationProvider = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "dns-adguardhome" ]);
            default = "dns-adguardhome";
            description = ''
              Optional explicit AdGuard role integrated with this recursive backend.
              Null keeps Unbound independently selectable without an AdGuard ordering edge.
            '';
          };
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            unboundPackage = unboundPackageFor pkgs.system;
          in
          {
            assertions = [
              {
                assertion = config.services.unbound.package == unboundPackage;
                message = "unbound: the runtime package must come from the VPN domain platform pin.";
              }
            ];

            services.unbound = {
              enable = true;
              package = lib.mkForce unboundPackage;
              resolveLocalQueries = false;
              settings.server = {
                inherit (settings.listen) port;
                inherit (settings.privacy) prefetch;
                interface = settings.listen.hosts;
                hide-identity = settings.privacy.hideIdentity;
                hide-version = settings.privacy.hideVersion;
                qname-minimisation = settings.privacy.qnameMinimisation;
              };
            };

          }
          // lib.optionalAttrs (settings.adguardIntegrationProvider != null) {
            systemd.services.adguardhome = {
              after = [ "unbound.service" ];
              requires = [ "unbound.service" ];
            };
          };
      };
  };
}
