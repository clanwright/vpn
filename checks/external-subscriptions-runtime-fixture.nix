let
  repository = builtins.getFlake (toString ../.);
  pkgs = repository.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;
  labelEnv = builtins.getEnv "VPN_SUBSCRIPTION_TEST_LABEL";
  source = {
    urlSecretName = "fixture-url";
    # Unset selects the ordinary label; "-" selects the source-id fallback.
    label =
      if labelEnv == "" then
        "Skala"
      else if labelEnv == "-" then
        null
      else
        labelEnv;
    format = "xray-json";
    profileNames = [ "fixture" ];
    auto = builtins.getEnv "VPN_SUBSCRIPTION_TEST_MANUAL" != "1";
    maxStaleSeconds = if builtins.getEnv "VPN_SUBSCRIPTION_TEST_SHORT_TTL" == "1" then 60 else 86400;
  };
  providers = [
    {
      instanceId = "own-naive";
      machine = "own-edge";
      connection.naiveproxy = {
        endpoint = {
          hostname = "own-naive.example.invalid";
          ipv4 = "192.0.2.10";
          port = 443;
        };
        clients.fixture.passwordSecret = "fixture-own-password";
      };
      profileClients.fixture = "fixture";
    }
  ];
  settings = {
    localMachineName = "fixture";
    publicIPv4 = "192.0.2.10";
    edgeDomain = "own-edge.example.invalid";
    configGatewayDomain = "profiles.example.invalid";
    clientDnsEndpoints = [
      {
        domain = "own-dns.example.invalid";
        ipv4 = "192.0.2.53";
        port = 443;
        path = "/dns-query";
      }
    ];
    tailnetAdminDomains = [ "admin.example.invalid" ];
    personalProxyDomains = [ "personal.example.invalid" ];
    profiles = [
      {
        name = "fixture";
        pathTokenSecretName = "fixture-path-token";
        kind = "mobile";
        publishProfileJson = true;
        autoProtocols = [ "naiveproxy" ];
      }
    ];
    externalSubscriptions =
      if builtins.getEnv "VPN_SUBSCRIPTION_TEST_REMOVED" == "1" then
        { }
      else
        {
          fixture = source;
        }
        // lib.optionalAttrs (builtins.getEnv "VPN_SUBSCRIPTION_TEST_SECOND_SOURCE" == "1") {
          other = source // {
            label = "Other";
            maxStaleSeconds = 60;
          };
        };
  };
  rendered = import ../clanServices/vpn-client-profiles/client-profiles.nix {
    inherit
      lib
      pkgs
      settings
      providers
      ;
  };
  profile =
    builtins.head
      ((import ./lib/manifest-view.nix { inherit lib; }) rendered.manifest).renderedProfiles;
  external = import ../clanServices/vpn-client-profiles/external-subscriptions.nix {
    inherit lib settings;
    config.sops.secrets.fixture-url.path = builtins.getEnv "VPN_SUBSCRIPTION_TEST_URL_FILE";
    runtimeBase = builtins.getEnv "VPN_SUBSCRIPTION_TEST_ROOT";
  };
in
{
  inherit (external)
    sources
    converter
    composer
    converterPath
    composerPath
    ;
  runtimeScript =
    builtins.replaceStrings
      [ (toString external.converterPath) (toString external.composerPath) ]
      [
        (builtins.getEnv "VPN_SUBSCRIPTION_TEST_CONVERTER")
        (builtins.getEnv "VPN_SUBSCRIPTION_TEST_COMPOSER")
      ]
      external.runtimeScript;
  mihomo = profile.mihomoSelectiveTemplate;
  ownNames =
    (builtins.head (builtins.head rendered.manifest.profiles).artifacts).runtimeComposition.ownNames
      or [ ];
  singBox = profile.profileJsonTemplate;
}
