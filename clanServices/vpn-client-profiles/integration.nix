{ lib, ... }:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  publisherOptions = {
    schemaVersion = lib.mkOption {
      type = lib.types.enum [ 2 ];
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
    logConfig = lib.mkOption {
      type = lib.types.lines;
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
  publisherKeys = builtins.attrNames publisherOptions;
  publisherData =
    raw: builtins.isAttrs raw && lib.subtractLists publisherKeys (builtins.attrNames raw) == [ ];
  # Native submodule reconstruction must retain the raw data boundary.
  closedPublisherType =
    nativeType:
    (lib.types.addCheck nativeType publisherData)
    // {
      substSubModules = modules: closedPublisherType (nativeType.substSubModules modules);
      typeMerge =
        other:
        let
          merged = nativeType.typeMerge other;
        in
        if merged == null then null else closedPublisherType merged;
    };
  publisherIntegrationType = closedPublisherType (
    lib.types.submodule {
      options = publisherOptions;
    }
  );
in
{
  options.clanwright.vpn = {
    publishers = lib.mkOption {
      type = lib.types.attrsOf publisherIntegrationType;
      default = { };
      description = "Publisher runtime and static-route outputs keyed by Clan instance.";
    };
  };
}
