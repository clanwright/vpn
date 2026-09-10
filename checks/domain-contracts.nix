{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  serviceSpecs = {
    vpn-mihomo-vless-xhttp.role = "gateway";
    vpn-mihomo-hysteria2.role = "gateway";
    vpn-amneziawg.role = "gateway";
    vpn-naiveproxy.role = "addon";
    vpn-client-profiles.role = "publisher";
    dns-adguardhome.role = "resolver";
    dns-unbound.role = "recursive-backend";
  };
  serviceNames = builtins.attrNames serviceSpecs;
  evaluatedServices = lib.mapAttrs' (
    publicName: module:
    let
      evaluated = inputs.clan-core.lib.evalService {
        modules = [ module ];
        prefix = [ ];
      };
    in
    lib.nameValuePair (lib.removePrefix "@clanwright/" publicName) evaluated.config
  ) self.clan.modules;
  services = lib.mapAttrs' (
    publicName: module:
    lib.nameValuePair (lib.removePrefix "@clanwright/" publicName) (builtins.head module.imports)
  ) self.clan.modules;
  settingsFor = name: role: fixture.instances.${name}.roles.${role}.machines.vpn-fixture.settings;
  providerSpecs = {
    vpn-mihomo-vless-xhttp = {
      role = "gateway";
      protocol = "vless-xhttp";
    };
    vpn-mihomo-hysteria2 = {
      role = "gateway";
      protocol = "hysteria2";
    };
    vpn-amneziawg = {
      role = "gateway";
      protocol = "amneziawg";
    };
    vpn-naiveproxy = {
      role = "addon";
      protocol = "naiveproxy";
    };
  };
  providerExports = lib.mapAttrs (
    name: spec:
    let
      service = services.${name};
      settings =
        (lib.evalModules {
          modules = [
            (service.roles.${spec.role}.interface { inherit lib; })
            { config = settingsFor name spec.role; }
          ];
        }).config;
    in
    (service.roles.${spec.role}.perInstance {
      inherit settings;
      instanceName = name;
      machine.name = "vpn-fixture";
      mkExports = value: value;
    }).exports.vpnProvider
  ) providerSpecs;
  selectProvider =
    name: raw:
    let
      spec = providerSpecs.${name};
    in
    (self.lib.vpnExports { inherit lib; }).selectVpnProvider {
      providerInstanceId = name;
      providerMachine = "vpn-fixture";
      inherit (spec) protocol;
      consumerInstanceId = "version-contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnProvider = raw;
    };
  providerVersionResults = lib.mapAttrs (name: raw: {
    currentAccepted = raw.schemaVersion == 2 && builtins.deepSeq (selectProvider name raw) true;
    legacyRejected =
      !(builtins.tryEval (builtins.deepSeq (selectProvider name (raw // { schemaVersion = 1; })) true))
      .success;
    missingRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectProvider name (builtins.removeAttrs raw [ "schemaVersion" ])) true
      )).success;
  }) providerExports;
  providerVersionsContract = builtins.all (
    result: builtins.all (value: value) (builtins.attrValues result)
  ) (builtins.attrValues providerVersionResults);
  publisherExport = {
    schemaVersion = 1;
    instanceId = "vpn-client-profiles";
    machine = "fixture";
    role = "publisher";
    enabled = true;
    accountDomain = "profiles.example.invalid";
    pagePath = "/config-links/";
    profileLinks = [
      {
        name = "cHJvYmU";
        label = "Fixture profile";
        accountDomain = "profiles.example.invalid";
      }
    ];
  };
  selectPublisher =
    raw:
    (self.lib.vpnExports { inherit lib; }).selectVpnPublisher {
      publisherInstanceId = "vpn-client-profiles";
      publisherMachine = "fixture";
      consumerInstanceId = "publisher-version-contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnPublisher = raw;
    };
  publisherVersionResults = {
    currentAccepted = builtins.deepSeq (selectPublisher publisherExport) true;
    wrongVersionRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectPublisher (publisherExport // { schemaVersion = 2; })) true
      )).success;
    missingVersionRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectPublisher (builtins.removeAttrs publisherExport [ "schemaVersion" ])) true
      )).success;
  };
  publisherVersionContract = builtins.all (value: value) (
    builtins.attrValues publisherVersionResults
  );
  awgInstance = services.vpn-amneziawg.roles.gateway.perInstance {
    settings = settingsFor "vpn-amneziawg" "gateway";
    instanceName = "vpn-amneziawg";
    machine.name = "vpn-fixture";
    mkExports = value: value;
  };
  awgProvider = awgInstance.exports.vpnProvider;
  selectAwgProvider =
    raw:
    (self.lib.vpnExports { inherit lib; }).selectVpnProvider {
      providerInstanceId = "vpn-amneziawg";
      providerMachine = "vpn-fixture";
      protocol = "amneziawg";
      consumerInstanceId = "contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnProvider = raw;
    };
  awgTransportContract =
    awgProvider.schemaVersion == 2
    && builtins.deepSeq (selectAwgProvider awgProvider) true
    && !(builtins.tryEval (
      builtins.deepSeq (selectAwgProvider (awgProvider // { schemaVersion = 1; })) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectAwgProvider (builtins.removeAttrs awgProvider [ "schemaVersion" ])) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectAwgProvider (
        lib.recursiveUpdate awgProvider { endpoint.transport = "tcp"; }
      )) true
    )).success;
  naiveSettings =
    (lib.evalModules {
      modules = [
        (services.vpn-naiveproxy.roles.addon.interface { inherit lib; })
        { config = settingsFor "vpn-naiveproxy" "addon"; }
      ];
    }).config;
  naiveInstance = services.vpn-naiveproxy.roles.addon.perInstance {
    settings = naiveSettings;
    instanceName = "vpn-naiveproxy";
    machine.name = "vpn-fixture";
    mkExports = value: value;
  };
  naiveProvider = naiveInstance.exports.vpnProvider;
  selectNaiveProvider =
    raw:
    (self.lib.vpnExports { inherit lib; }).selectVpnProvider {
      providerInstanceId = "vpn-naiveproxy";
      providerMachine = "vpn-fixture";
      protocol = "naiveproxy";
      consumerInstanceId = "contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnProvider = raw;
    };
  naiveProviderResults = {
    actual =
      naiveProvider.schemaVersion == 2 && builtins.deepSeq (selectNaiveProvider naiveProvider) true;
    legacyVersionRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (naiveProvider // { schemaVersion = 1; })) true
      )).success;
    missingVersionRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (builtins.removeAttrs naiveProvider [ "schemaVersion" ])) true
      )).success;
    unknownProfileRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          naiveProvider
          // {
            profileNames = naiveProvider.profileNames ++ [ "unknown-profile" ];
          }
        )) true
      )).success;
    missingPasswordRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          naiveProvider
          // {
            secretNames = naiveProvider.secretNames // {
              password = builtins.removeAttrs naiveProvider.secretNames.password [ "probe" ];
            };
          }
        )) true
      )).success;
    extraPasswordRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          lib.recursiveUpdate naiveProvider {
            secretNames.password.unexpected = "fixture-unexpected-secret";
          }
        )) true
      )).success;
  };
  naiveProviderContract = builtins.all (value: value) (builtins.attrValues naiveProviderResults);
  schemaResult =
    name: value:
    let
      role = serviceSpecs.${name}.role;
      service = services.${name};
    in
    builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            (service.roles.${role}.interface { inherit lib; })
            { config = value; }
          ];
        }).config
        true
    );
  validSchemaResults = lib.genAttrs serviceNames (
    name:
    let
      role = serviceSpecs.${name}.role;
    in
    (schemaResult name (settingsFor name role)).success
  );
  validSchemas = builtins.all (value: value) (builtins.attrValues validSchemaResults);
  registeredSchemas = builtins.all (
    name: builtins.deepSeq evaluatedServices.${name}.result.api.schema true
  ) serviceNames;
  closedSchemas = builtins.all (
    name:
    let
      role = serviceSpecs.${name}.role;
    in
    !(schemaResult name ((settingsFor name role) // { unexpected = true; })).success
  ) serviceNames;
  invalidNestedFields =
    !(schemaResult "vpn-mihomo-vless-xhttp" (
      (settingsFor "vpn-mihomo-vless-xhttp" "gateway")
      // {
        reality = (settingsFor "vpn-mihomo-vless-xhttp" "gateway").reality // {
          privateKey = "must-not-cross-contract";
        };
      }
    )).success
    && !(schemaResult "dns-adguardhome" (
      (settingsFor "dns-adguardhome" "resolver")
      // {
        ui = (settingsFor "dns-adguardhome" "resolver").ui // {
          unexpected = 1;
        };
      }
    )).success;
  invalidFieldTypes = builtins.all (result: !result.success) [
    (schemaResult "vpn-mihomo-vless-xhttp" (
      (settingsFor "vpn-mihomo-vless-xhttp" "gateway") // { port = "443"; }
    ))
    (schemaResult "vpn-amneziawg" ((settingsFor "vpn-amneziawg" "gateway") // { peers = "fixture"; }))
    (schemaResult "dns-unbound" (
      (settingsFor "dns-unbound" "recursive-backend")
      // {
        listen = (settingsFor "dns-unbound" "recursive-backend").listen // {
          port = "5335";
        };
      }
    ))
  ];
  missingAwgClientPrivateKeyBindingRejected =
    let
      settings = settingsFor "vpn-amneziawg" "gateway";
    in
    !(schemaResult "vpn-amneziawg" (
      settings
      // {
        peers = map (peer: builtins.removeAttrs peer [ "clientPrivateKeySecretName" ]) settings.peers;
      }
    )).success;
  publicHelperRemoved = !(self.lib ? clientProfiles);
  placementBehavior =
    name: machine:
    {
      vpn-mihomo-vless-xhttp =
        machine.services.xray.enable
        && machine.systemd.services ? xray
        && !((machine.networkCore.mihomo or { }) ? vlessXhttp);
      vpn-mihomo-hysteria2 =
        machine.systemd.services ? mihomo-hysteria2
        && machine.sops.templates ? "mihomo-hysteria2.json"
        && !((machine.networkCore.mihomo or { }) ? hysteria2);
      vpn-amneziawg =
        machine.systemd.services ? wireguard-awg-fixture
        && !(machine.networking.wireguard.interfaces ? awg-fixture);
      vpn-naiveproxy = machine.sops.templates ? "naiveproxy-vpn-fixture.caddy";
      vpn-client-profiles = !(machine.systemd.services ? mihomo-client-caddy-fixture);
      dns-adguardhome = machine.services.adguardhome.enable;
      dns-unbound = machine.services.unbound.enable;
    }
    .${name};
  independentPlacementResults = lib.genAttrs serviceNames (
    name:
    let
      includeNetwork = builtins.elem name [
        "dns-adguardhome"
        "vpn-client-profiles"
        "vpn-naiveproxy"
      ];
      extraModule = lib.optionalAttrs (name == "vpn-mihomo-hysteria2") {
        security.acme = {
          acceptTerms = true;
          defaults.email = "operator@example.invalid";
          certs.fixture.webroot = "/var/lib/acme/acme-challenge";
        };
      };
      supportNames = lib.optionals includeNetwork [
        "edge-wildcard-certificate"
        "network-caddy"
        "network-certificates"
      ];
      consumer = consume {
        instanceNames = [ name ];
        inherit extraModule includeNetwork;
      };
      caddyFragments = lib.attrByPath [ "networkCore" "caddy" "effectiveFragments" ] { } consumer.machine;
    in
    builtins.attrNames consumer.config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ [ name ])
    &&
      builtins.length (builtins.attrNames consumer.config._services.allServices)
      == builtins.length supportNames + 1
    && (!includeNetwork || ((caddyFragments ? dns-adguardhome-ui) == (name == "dns-adguardhome")))
    && (!includeNetwork || ((caddyFragments ? dns-adguardhome-doh) == (name == "dns-adguardhome")))
    && (!includeNetwork || !(caddyFragments ? vpn-client-profiles))
    && placementBehavior name consumer.machine
  );
  independentPlacements = builtins.all (value: value) (
    builtins.attrValues independentPlacementResults
  );
  combined = consume {
    instanceNames = serviceNames;
    includeNetwork = true;
    extraModule.systemd.services.adguardhome.wants = [ "unbound.service" ];
  };
  inherit (combined) machine;
  combinedClanFixture = import ./combined-clan-fixture.nix {
    inherit combined fixture lib;
  };
  overrideAttempt = consume {
    instanceNames = [
      "dns-adguardhome"
      "dns-unbound"
    ];
    includeNetwork = true;
    extraModule = {
      services = {
        adguardhome.package = pkgs.hello;
        dnsproxy.package = pkgs.hello;
        unbound.package = pkgs.hello;
      };
    };
  };
  awgOverrideRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (consume {
          instanceNames = [ "vpn-amneziawg" ];
          extraModule.nixpkgs.overlays = [
            (_final: _prev: {
              amneziawg-go = pkgs.hello;
              amneziawg-tools = pkgs.hello;
            })
          ];
        }).machine.system.build.toplevel.drvPath
        true
    )).success;
  awgOverlays = builtins.filter (
    overlay:
    let
      result = overlay pkgs pkgs;
    in
    result ? amneziawg-go && result ? amneziawg-tools
  ) machine.nixpkgs.overlays;
  awgOverlay = builtins.head awgOverlays;
  servicePackageAuthorityResults = {
    adguard = machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    dnsproxy = machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    unbound = machine.services.unbound.package == self.packages.${system}.unbound;
    awgOverlayPresent = awgOverlays != [ ];
    awgGo = (awgOverlay pkgs pkgs).amneziawg-go == self.packages.${system}.amneziawg-go;
    awgTools = (awgOverlay pkgs pkgs).amneziawg-tools == self.packages.${system}.amneziawg-tools;
    awgFamily = (self.lib.awgValidation { inherit lib; }).packageFamiliesValid {
      inherit (self.packages.${system}) amneziawg-go amneziawg-tools;
    };
    adguardOverride =
      overrideAttempt.machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    dnsproxyOverride =
      overrideAttempt.machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    unboundOverride =
      overrideAttempt.machine.services.unbound.package == self.packages.${system}.unbound;
    inherit awgOverrideRejected;
  };
  packageAuthorityResults = servicePackageAuthorityResults;
  packageAuthority = builtins.all (value: value) (builtins.attrValues packageAuthorityResults);
  dnsStateResults = {
    immutable = !machine.services.adguardhome.mutableSettings;
    adguardState = builtins.elem "AdGuardHome" (
      lib.toList machine.systemd.services.adguardhome.serviceConfig.StateDirectory
    );
    unboundState = builtins.elem "unbound" (
      lib.toList machine.systemd.services.unbound.serviceConfig.StateDirectory
    );
  };
  dnsStatePreserved = builtins.all (value: value) (builtins.attrValues dnsStateResults);
  contract =
    builtins.attrNames self.clan.modules == map (name: "@clanwright/${name}") serviceNames
    && validSchemas
    && registeredSchemas
    && closedSchemas
    && invalidNestedFields
    && invalidFieldTypes
    && missingAwgClientPrivateKeyBindingRejected
    && publicHelperRemoved
    && providerVersionsContract
    && publisherVersionContract
    && independentPlacements
    && combinedClanFixture.contract
    && awgTransportContract
    && naiveProviderContract
    && packageAuthority
    && dnsStatePreserved;
in
if !contract then
  throw "VPN domain contract failed: ${
    builtins.toJSON {
      inherit
        closedSchemas
        awgTransportContract
        naiveProviderContract
        naiveProviderResults
        awgOverrideRejected
        dnsStatePreserved
        dnsStateResults
        independentPlacementResults
        independentPlacements
        combinedClanFixture
        invalidFieldTypes
        missingAwgClientPrivateKeyBindingRejected
        invalidNestedFields
        packageAuthority
        packageAuthorityResults
        providerVersionResults
        providerVersionsContract
        publisherVersionContract
        publisherVersionResults
        registeredSchemas
        validSchemaResults
        validSchemas
        publicHelperRemoved
        ;
    }
  }"
else
  {
    all = true;
    inherit
      closedSchemas
      awgTransportContract
      naiveProviderContract
      naiveProviderResults
      dnsStatePreserved
      combinedClanFixture
      independentPlacements
      invalidFieldTypes
      missingAwgClientPrivateKeyBindingRejected
      invalidNestedFields
      packageAuthority
      providerVersionsContract
      publisherVersionContract
      registeredSchemas
      validSchemas
      publicHelperRemoved
      ;
  }
