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
  validDnsDomain =
    value:
    let
      labels = lib.splitString "." value;
      validLabel =
        label:
        builtins.stringLength label >= 1
        && builtins.stringLength label <= 63
        && builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" label != null;
    in
    value == lib.toLower value
    && builtins.stringLength value <= 253
    && builtins.length labels >= 2
    && builtins.all validLabel labels
    && builtins.match "[0-9]+(\\.[0-9]+)+" value == null;
  validIPv4Octet =
    value: builtins.match "(0|[1-9][0-9]{0,2})" value != null && lib.toInt value <= 255;
  validIPv4 =
    value:
    let
      octets = lib.splitString "." value;
    in
    builtins.length octets == 4 && builtins.all validIPv4Octet octets;
  validHttpPath = value: builtins.match "/[A-Za-z0-9._~/-]*" value != null;
  validPort = value: builtins.isInt value && value >= 1 && value <= 65535;

  clientDnsEndpointType = lib.types.submodule (_: {
    options = {
      domain = lib.mkOption {
        type = lib.types.addCheck lib.types.str validDnsDomain;
        description = "Canonical lowercase ASCII FQDN of the DNS-over-HTTPS endpoint.";
      };
      ipv4 = lib.mkOption {
        type = lib.types.addCheck lib.types.str validIPv4;
        description = "Canonical numeric IPv4 bootstrap address for the endpoint.";
      };
      port = lib.mkOption {
        type = lib.types.addCheck lib.types.int validPort;
        default = 443;
      };
      path = lib.mkOption {
        type = lib.types.addCheck lib.types.str validHttpPath;
        default = "/dns-query";
      };
    };
  });
  clientDnsEndpointsType = lib.types.addCheck (lib.types.listOf clientDnsEndpointType) (
    endpoints:
    endpoints != [ ]
    && (
      let
        domains = map (endpoint: endpoint.domain) endpoints;
      in
      domains == lib.unique domains
    )
  );

  normalizeClientDnsEndpoint =
    index: endpoint:
    let
      allowedNames = [
        "domain"
        "ipv4"
        "port"
        "path"
      ];
      unknownNames =
        if builtins.isAttrs endpoint then
          lib.subtractLists allowedNames (builtins.attrNames endpoint)
        else
          [ ];
      entry = "clientDnsEndpoints entry ${toString index}";
    in
    if !builtins.isAttrs endpoint then
      throw "vpn-client-profiles: ${entry} must be an attribute set."
    else if unknownNames != [ ] then
      throw "vpn-client-profiles: ${entry} has unsupported fields: ${lib.concatStringsSep ", " unknownNames}."
    else if
      !(endpoint ? domain) || !(builtins.isString endpoint.domain) || !validDnsDomain endpoint.domain
    then
      throw "vpn-client-profiles: ${entry}.domain must be a canonical lowercase ASCII FQDN with valid labels and must not be a numeric dotted host."
    else if !(endpoint ? ipv4) || !(builtins.isString endpoint.ipv4) || !validIPv4 endpoint.ipv4 then
      throw "vpn-client-profiles: ${entry}.ipv4 must be a canonical numeric IPv4 address without leading zeroes."
    else if !validPort (endpoint.port or 443) then
      throw "vpn-client-profiles: ${entry}.port must be an integer from 1 through 65535."
    else if
      !(builtins.isString (endpoint.path or "/dns-query"))
      || !validHttpPath (endpoint.path or "/dns-query")
    then
      throw "vpn-client-profiles: ${entry}.path must be an absolute HTTP path containing only '/', ASCII letters, digits, '.', '_', '~' and '-'."
    else
      {
        inherit (endpoint) domain ipv4;
        port = endpoint.port or 443;
        path = endpoint.path or "/dns-query";
      };

  normalizeClientDnsEndpoints =
    settings:
    let
      configured = settings.clientDnsEndpoints or null;
      rawEndpoints =
        if configured == null then
          [
            {
              domain = settings.edgeDomain or null;
              ipv4 = settings.publicIPv4 or null;
            }
          ]
        else
          configured;
      endpoints =
        if !builtins.isList rawEndpoints || rawEndpoints == [ ] then
          throw "vpn-client-profiles: clientDnsEndpoints must be null or a non-empty list."
        else
          lib.imap0 normalizeClientDnsEndpoint rawEndpoints;
      domains = map (endpoint: endpoint.domain) endpoints;
    in
    if domains != lib.unique domains then
      throw "vpn-client-profiles: clientDnsEndpoints domains must be unique, including endpoints with different IPv4 addresses or ports."
    else
      endpoints;
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
          "mieru"
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
    clientDnsEndpointType
    clientDnsEndpointsType
    normalizeClientDnsEndpoints
    profileType
    providerRefType
    profileLinkType
    linksPageType
    ;
}
