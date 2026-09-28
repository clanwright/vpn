{
  inputs,
  root,
  self,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  service = builtins.head self.clan.modules."@clanwright/vpn-client-profiles".imports;
  evalSettings =
    settings:
    (lib.evalModules {
      modules = [
        (service.roles.publisher.interface { inherit lib; })
        { config = settings; }
      ];
    }).config;
  accepts = settings: (builtins.tryEval (builtins.deepSeq (evalSettings settings) true)).success;
  source = {
    urlSecretName = "fixture/subscription-url";
    profileNames = [ "cHJvYmU" ];
  };
  withSource = value: { externalSubscriptions.fixture = value; };
  defaults = (evalSettings (withSource source)).externalSubscriptions.fixture;
  overrides =
    (evalSettings (
      withSource (
        source
        // {
          format = "xray-json";
          auto = false;
          refreshIntervalSeconds = 7200;
          retryIntervalSeconds = 60;
          maxStaleSeconds = 14400;
        }
      )
    )).externalSubscriptions.fixture;
  fixture = import ./fixtures/example-clan.nix;
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  instanceNames = builtins.filter (
    name: !(lib.hasPrefix "network-" name) && name != "edge-wildcard-certificate"
  ) (builtins.attrNames fixture.instances);
  consumer = consume {
    inherit instanceNames;
    includeNetwork = true;
    fixtureName = "vpn-external-subscriptions-fixture";
    instanceOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.externalSubscriptions.fixture =
      source;
  };
  inherit (consumer) machine;
  unitName = "vpn-client-profiles-publish-fixture";
  unit = machine.systemd.services.${unitName};
  excludedConsumer = consume {
    inherit instanceNames;
    includeNetwork = true;
    fixtureName = "vpn-external-subscriptions-excluded-fixture";
    instanceOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings = {
      externalSubscriptions.fixture = source;
      excludedProfileNames = [ "cHJvYmU" ];
    };
  };
  manifest = machine.clanwright.vpn.publisherManifests.vpn-client-profiles;
  invalidSourceCases = {
    missingSecret = builtins.removeAttrs source [ "urlSecretName" ];
    rawUrl = source // {
      url = "https://synthetic.example.invalid/fixture";
    };
    unknownField = source // {
      tlsVerify = false;
    };
    unsupportedFormat = source // {
      format = "clash-yaml";
    };
    emptyProfiles = source // {
      profileNames = [ ];
    };
    duplicateProfiles = source // {
      profileNames = [
        "cHJvYmU"
        "cHJvYmU"
      ];
    };
    unsafeProfile = source // {
      profileNames = [ "../profile" ];
    };
    unsafeSecret = source // {
      urlSecretName = "../url-secret";
    };
    nonBooleanAuto = source // {
      auto = "false";
    };
    zeroRefresh = source // {
      refreshIntervalSeconds = 0;
    };
    negativeRetry = source // {
      retryIntervalSeconds = -1;
    };
    fractionalTtl = source // {
      maxStaleSeconds = 1.5;
    };
  };
in
{
  defaultEmpty = (evalSettings { }).externalSubscriptions == { };
  typedDefaults =
    defaults.format == "xray-json"
    && defaults.auto
    && defaults.refreshIntervalSeconds == 3600
    && defaults.retryIntervalSeconds == 300
    && defaults.maxStaleSeconds == 86400;
  typedOverrides =
    !overrides.auto
    && overrides.refreshIntervalSeconds == 7200
    && overrides.retryIntervalSeconds == 60
    && overrides.maxStaleSeconds == 14400;
  invalidSources = lib.mapAttrs (_: value: !(accepts (withSource value))) invalidSourceCases;
  unsafeSourceIdentity = !(accepts { externalSubscriptions."../fixture" = source; });
  runtimeSecret =
    machine.sops.secrets."fixture/subscription-url".owner == "root"
    && machine.sops.secrets."fixture/subscription-url".mode == "0400"
    && builtins.elem "${unitName}.service" machine.sops.secrets."fixture/subscription-url".restartUnits;
  serializedLifecycle =
    unit.serviceConfig.Type == "simple"
    && unit.serviceConfig.Restart == "on-failure"
    && unit.serviceConfig.RestartSec == "60s";
  runtimeDependencies =
    builtins.any (package: lib.hasPrefix "bash" (package.pname or package.name)) unit.path
    && builtins.elem "diffutils" (map (package: package.pname or package.name) unit.path);
  excludedSourceInactive =
    !(excludedConsumer.machine.sops.secrets ? "fixture/subscription-url")
    && excludedConsumer.machine.systemd.services.${unitName}.serviceConfig.Type == "oneshot"
    && excludedConsumer.machine.clanwright.vpn.publisherManifests.vpn-client-profiles.profiles == [ ];
  profileComposition = builtins.all (
    profile:
    profile.name == "cHJvYmU"
    && builtins.all (
      artifact:
      artifact.runtimeComposition.kind == "external-subscriptions"
      && artifact.runtimeComposition.profileName == profile.name
      && artifact.runtimeComposition.format == artifact.format
    ) profile.artifacts
  ) manifest.profiles;
  noPublicSourceCredentials =
    !(lib.hasInfix "subscription-url" (
      builtins.toJSON machine.clanwright.vpn.publishers.vpn-client-profiles
    ));
}
