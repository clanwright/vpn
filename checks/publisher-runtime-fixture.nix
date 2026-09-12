let
  repository = builtins.getFlake (toString ../.);
  pkgs = repository.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;
  testRoot = builtins.getEnv "VPN_PUBLISHER_TEST_ROOT";
  secretPath = builtins.getEnv "VPN_PUBLISHER_TEST_SECRET";
  tokenPath = builtins.getEnv "VPN_PUBLISHER_TEST_TOKEN";
  runtimeBase = "${testRoot}/runtime";
  profileRoot = "${runtimeBase}/published/current";
  publicationService = "vpn-client-profiles-publish-runtime-fixture";
  runtimeModuleOverride = builtins.getEnv "VPN_PUBLISHER_TEST_RUNTIME_MODULE";
  runtimeModule =
    if runtimeModuleOverride == "" then
      ../clanServices/vpn-client-profiles/runtime-publication.nix
    else
      runtimeModuleOverride;
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  template = {
    credential = "__FIXTURE_SECRET__";
    marker = "publisher-runtime-fixture";
  };
  manifest = {
    schemaVersion = 1;
    assetCatalog = { };
    profiles = [
      {
        name = "fixture";
        pathTokenBinding = {
          secretName = "fixture-token";
          decoding = "path-token";
        };
        artifacts = [
          {
            id = "fixture-json";
            outputName = "profile.json";
            format = "json";
            inherit template;
            templatePath = builtins.toFile "publisher-runtime-fixture.json" (builtins.toJSON template);
            assetRefs = [ ];
            bindings = [
              {
                secretName = "fixture-secret";
                decoding = "literal";
                targetPath = [ "credential" ];
                placeholder = "__FIXTURE_SECRET__";
              }
            ];
          }
        ];
      }
    ];
    publicationPhases = manifestLib.expectedPublicationPhases;
  };
  publication = import runtimeModule {
    config.sops.secrets = {
      fixture-secret.path = secretPath;
      fixture-token.path = tokenPath;
    };
    inherit
      lib
      manifest
      pkgs
      profileRoot
      publicationService
      runtimeBase
      ;
    mihomoPackage = pkgs.coreutils;
    renderedProfiles = [ ];
    settings = {
      localMachineName = "runtime-fixture";
      linksPage = {
        enable = false;
        title = "Fixture";
      };
      profileLinks = [ ];
    };
    readerGroup = "runtime-fixture";
    refreshUnit = "runtime-fixture-refresh.service";
    requiredAssetPaths = [ ];
    localAssetSyncScript = ":";
  };
in
publication.systemd.services.${publicationService}.script
