{ config, lib, ... }:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  publisherIntegrationType = lib.types.submodule (_: {
    options = {
      schemaVersion = lib.mkOption {
        type = lib.types.enum [ 1 ];
        readOnly = true;
      };
      profileRoot = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      assetRoot = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      configGatewayDomain = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      linksRoot = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      routeConfig = lib.mkOption {
        type = lib.types.lines;
        readOnly = true;
      };
      publicationUnit = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      refreshUnit = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      statusPath = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      readerGroup = lib.mkOption {
        type = identities.safeIdentityType;
        readOnly = true;
      };
    };
  });
in
{
  options.clanwright.vpn = {
    publishers = lib.mkOption {
      type = lib.types.attrsOf publisherIntegrationType;
      default = { };
      description = "Publisher runtime and static-route outputs keyed by Clan instance.";
    };
    publisherRenders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.raw);
      default = { };
      internal = true;
      description = "Pure rendered profile metadata keyed by publisher instance.";
    };
  };
  config._module.args.vpnClientProfileRender = lib.concatLists (
    builtins.attrValues config.clanwright.vpn.publisherRenders
  );
}
