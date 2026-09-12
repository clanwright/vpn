{ config, lib, ... }:
let
  integrationType = lib.types.submodule {
    options = {
      schemaVersion = lib.mkOption { type = lib.types.enum [ 1 ]; };
      uiBackend = lib.mkOption {
        type = lib.types.submodule {
          options = {
            host = lib.mkOption { type = lib.types.str; };
            port = lib.mkOption { type = lib.types.port; };
          };
        };
      };
      dohBackend = lib.mkOption {
        type = lib.types.submodule {
          options = {
            host = lib.mkOption { type = lib.types.str; };
            port = lib.mkOption { type = lib.types.port; };
            serverName = lib.mkOption { type = lib.types.str; };
          };
        };
      };
      reloadUnits = lib.mkOption { type = lib.types.listOf lib.types.str; };
    };
  };
in
{
  options.clanwright.dns.adguardhome = {
    activeInstances = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Active AdGuard instances claiming the native AdGuard Home and dnsproxy runtimes.";
    };
    integrationClaims = lib.mkOption {
      type = lib.types.listOf integrationType;
      default = [ ];
      internal = true;
      description = "Active AdGuard integration outputs before singleton selection.";
    };
    integration = lib.mkOption {
      type = lib.types.nullOr integrationType;
      default =
        if config.clanwright.dns.adguardhome.integrationClaims == [ ] then
          null
        else
          builtins.head config.clanwright.dns.adguardhome.integrationClaims;
      readOnly = true;
      description = "Read-only AdGuard backend data for consumer-owned integration.";
    };
  };
}
