{ lib }:
let
  profileType = lib.types.submodule (_: {
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
  });

  providerRefType = lib.types.submodule (_: {
    options = {
      instanceId = lib.mkOption {
        type = lib.types.str;
        description = "Explicit provider instance selected by this publisher.";
      };
      machine = lib.mkOption {
        type = lib.types.str;
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
        type = lib.types.listOf lib.types.str;
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
      name = lib.mkOption { type = lib.types.str; };
      label = lib.mkOption { type = lib.types.str; };
      accountDomain = lib.mkOption { type = lib.types.str; };
      pathTokenSecretName = lib.mkOption {
        type = lib.types.str;
        description = "SOPS secret name containing the token for this published profile path.";
      };
    };
  });
in
{
  inherit
    profileType
    providerRefType
    profileLinkType
    linksPageType
    ;
}
