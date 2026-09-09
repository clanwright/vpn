{ lib }:
let
  safeIdentityType = lib.types.addCheck lib.types.nonEmptyStr (
    value: builtins.match "[A-Za-z0-9][A-Za-z0-9._-]{0,63}" value != null
  );
  optionalSafeIdentityType = lib.types.addCheck lib.types.str (
    value: value == "" || builtins.match "[A-Za-z0-9][A-Za-z0-9._-]{0,63}" value != null
  );
  safeSecretNameType = lib.types.addCheck lib.types.nonEmptyStr (
    value: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.+-]*(/[A-Za-z0-9_][A-Za-z0-9_.+-]*)*" value != null
  );
  profileType = lib.types.submodule (_: {
    options = {
      name = lib.mkOption { type = safeIdentityType; };
      vlessUuidSecretName = lib.mkOption { type = safeSecretNameType; };
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
        default = true;
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/config-links/";
      };
      title = lib.mkOption {
        type = lib.types.str;
        default = "VPN client profiles";
      };
      tailnetOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
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
    profileType
    providerRefType
    profileLinkType
    linksPageType
    ;
}
