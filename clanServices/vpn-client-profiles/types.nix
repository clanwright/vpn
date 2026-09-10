{ lib }:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  inherit (identities)
    optionalSafeIdentityType
    safeIdentityType
    safeSecretNameType
    ;
  linksPageDefaults = {
    enable = true;
    path = "/config-links/";
    title = "VPN client profiles";
  };
  providerNamespace =
    provider:
    "${toString (builtins.stringLength provider.machine)}-${provider.machine}-${toString (builtins.stringLength provider.instanceId)}-${provider.instanceId}";
  profileType = lib.types.submodule (_: {
    options = {
      name = lib.mkOption { type = safeIdentityType; };
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
  });

  providerRefType = lib.types.submodule (_: {
    options = {
      instanceId = lib.mkOption {
        type = safeIdentityType;
        description = "Explicit provider instance selected by this publisher.";
      };
      machine = lib.mkOption {
        type = safeIdentityType;
        description = "Machine hosting the selected provider.";
      };
      protocol = lib.mkOption {
        type = lib.types.enum [
          "naiveproxy"
          "vless-xhttp"
          "hysteria2"
          "amneziawg"
        ];
      };
      profileNames = lib.mkOption {
        type = lib.types.listOf safeIdentityType;
        default = [ ];
        description = "Profiles allowed to use the selected provider.";
      };
    };
  });

  linksPageType = lib.types.submodule (_: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = linksPageDefaults.enable;
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = linksPageDefaults.path;
      };
      title = lib.mkOption {
        type = lib.types.str;
        default = linksPageDefaults.title;
      };
    };
  });

  profileLinkType = lib.types.submodule (_: {
    options = {
      name = lib.mkOption { type = safeIdentityType; };
      label = lib.mkOption { type = lib.types.str; };
      accountDomain = lib.mkOption { type = lib.types.str; };
      pathTokenSecretName = lib.mkOption {
        type = safeSecretNameType;
        description = "SOPS secret name containing the token for this published profile path.";
      };
    };
  });
in
{
  inherit
    safeIdentityType
    optionalSafeIdentityType
    safeSecretNameType
    linksPageDefaults
    providerNamespace
    profileType
    providerRefType
    profileLinkType
    linksPageType
    ;
}
