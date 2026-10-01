{
  inputs,
  root,
  self,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  publisherCompiler = import ../clanServices/vpn-client-profiles/publisher.nix { inherit lib; };
  compile =
    externalSubscriptions:
    publisherCompiler.compile {
      inherit pkgs;
      instanceName = "vpn-client-profiles";
      exports = consumer.config.exports;
      selectExports = inputs.clan-core.lib.selectExports;
      settings = fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings // {
        inherit externalSubscriptions;
      };
    };
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
  instanceNames = builtins.filter (name: !(lib.hasPrefix "network-" name)) (
    builtins.attrNames fixture.instances
  );
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
  inherit (compile { fixture = source; }) manifest;
  labelCases = {
    ordinary = "Skala";
    flagAndCyrillic = "🇩🇪 Германия";
    maximumBytes = builtins.concatStringsSep "" (builtins.genList (_: "a") 64);
  };
  invalidLabelCases = {
    empty = "";
    leadingSpace = " Skala";
    trailingSpace = "Skala ";
    controlCharacter = "Sk\nala";
    tooManyBytes = builtins.concatStringsSep "" (builtins.genList (_: "a") 65);
    multibyteTooLong = builtins.concatStringsSep "" (builtins.genList (_: "я") 33);
    reservedManual = "Ручной";
    reservedAuto = "Авто";
    reservedGlobal = "GLOBAL";
    reservedDirect = "DIRECT";
    reservedReject = "EXTERNAL-REJECT";
    reservedPassRule = "PASS-RULE";
  };
  externalOf =
    sources:
    import ../clanServices/vpn-client-profiles/external-subscriptions.nix {
      inherit lib;
      settings = {
        profiles = [ { name = "cHJvYmU"; } ];
        inherit (evalSettings { externalSubscriptions = sources; }) externalSubscriptions;
      };
      config.sops.secrets."fixture/subscription-url".path = "/run/secrets/fixture";
      runtimeBase = "/var/lib/fixture";
    };
  labelled = externalOf {
    fixture = source // {
      label = "Skala";
    };
  };
  unlabelled = externalOf { fixture = source; };
  inherit (labelled) composer converter runtimeScript;
  forcesCompilation =
    candidate:
    let
      attempt = builtins.tryEval (
        builtins.deepSeq candidate.settings (manifestLib.validateManifest candidate.manifest)
      );
    in
    attempt.success && attempt.value;
  labelCollision = compile {
    fixture = source // {
      label = "A";
    };
  };
  distinctLabel = compile {
    fixture = source // {
      label = "Skala";
    };
  };
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
  labelDefaultsToSourceId = defaults.label == null;
  labelOverride =
    (evalSettings (withSource (source // { label = "Skala"; }))).externalSubscriptions.fixture.label
    == "Skala";
  validLabels = lib.mapAttrs (
    _: value: accepts (withSource (source // { label = value; }))
  ) labelCases;
  invalidLabels = lib.mapAttrs (
    _: value: !(accepts (withSource (source // { label = value; })))
  ) invalidLabelCases;
  ownLabelCollisionRejected = !(forcesCompilation labelCollision);
  distinctLabelAccepted = forcesCompilation distinctLabel;
  # Names are resolved when composing: the label is a compose-time argument
  # and the cached download stores neither name nor digest.
  composerGroups =
    lib.hasInfix "Ручной" composer
    && lib.hasInfix "Авто" composer
    && lib.hasInfix "GLOBAL" composer
    && lib.hasInfix "EXTERNAL-REJECT" composer
    && !(lib.hasInfix "SELECTIVE" composer)
    && !(lib.hasInfix "FULL" composer)
    && !(lib.hasInfix "UDP" composer)
    && !(lib.hasInfix "external-" composer);
  composeTimeLabel =
    lib.hasInfix "--arg source Skala 'map(" runtimeScript
    && lib.hasInfix "--arg source fixture 'map(" unlabelled.runtimeScript;
  cacheStoresNoNames =
    !(lib.hasInfix "digest" runtimeScript) && !(lib.hasInfix "sha256" (converter + runtimeScript));
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
  profileComposition =
    manifest.profiles != [ ]
    && builtins.all (
      profile:
      profile.name == "cHJvYmU"
      && builtins.all (
        artifact:
        artifact.runtimeComposition.kind == "external-subscriptions"
        && artifact.runtimeComposition.profileName == profile.name
        && artifact.runtimeComposition.format == artifact.format
      ) profile.artifacts
    ) manifest.profiles;
  actualPublicationUsesCompiledTemplates = builtins.all (
    profile:
    builtins.all (
      artifact:
      lib.hasInfix (builtins.unsafeDiscardStringContext (toString artifact.templatePath)) unit.script
    ) profile.artifacts
  ) manifest.profiles;
  noPublicSourceCredentials =
    !(lib.hasInfix "subscription-url" (
      builtins.toJSON machine.clanwright.vpn.publishers.vpn-client-profiles
    ));
}
