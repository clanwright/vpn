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
    vpn-mieru.role = "gateway";
    vpn-amneziawg.role = "gateway";
    vpn-naiveproxy.role = "addon";
    vpn-client-profiles.role = "publisher";
    dns-adguardhome.role = "resolver";
    dns-unbound.role = "recursive-backend";
  };
  serviceNames = builtins.attrNames serviceSpecs;
  independentServiceNames = builtins.filter (name: name != "vpn-client-profiles") serviceNames;
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
    vpn-mieru = {
      role = "gateway";
      protocol = "mieru";
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
  mieruProvider = providerExports.vpn-mieru;
  selectMieruProvider = raw: selectProvider "vpn-mieru" raw;
  mieruEndpointContract =
    mieruProvider.endpoint.domain == null
    && mieruProvider.endpoint.ipv4 == "192.0.2.13"
    && mieruProvider.endpoint.port == 8443
    && mieruProvider.endpoint.transport == "tcp"
    && builtins.deepSeq (selectMieruProvider mieruProvider) true
    && !(builtins.tryEval (
      builtins.deepSeq (selectMieruProvider (
        lib.recursiveUpdate mieruProvider { endpoint.domain = "mieru.example.invalid"; }
      )) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectMieruProvider (
        mieruProvider
        // {
          endpoint = builtins.removeAttrs mieruProvider.endpoint [ "ipv4" ];
        }
      )) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectMieruProvider (
        lib.recursiveUpdate mieruProvider { endpoint.unexpected = true; }
      )) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectMieruProvider (
        lib.recursiveUpdate mieruProvider { endpoint.ipv4 = "192.0.2.999"; }
      )) true
    )).success
    && !(builtins.tryEval (
      builtins.deepSeq (selectProvider "vpn-mihomo-vless-xhttp" (
        lib.recursiveUpdate providerExports.vpn-mihomo-vless-xhttp { endpoint.domain = null; }
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
    (schemaResult "vpn-mieru" ((settingsFor "vpn-mieru" "gateway") // { port = "8443"; }))
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
      vpn-mieru = machine.systemd.services ? mita && machine.sops.templates ? "mita.json";
      vpn-amneziawg =
        machine.systemd.services ? wireguard-awg-fixture
        && !(machine.networking.wireguard.interfaces ? awg-fixture);
      vpn-naiveproxy = machine.sops.templates ? "naiveproxy-vpn-fixture.caddy";
      dns-adguardhome = machine.services.adguardhome.enable;
      dns-unbound = machine.services.unbound.enable;
    }
    .${name};
  independentPlacementResults = lib.genAttrs independentServiceNames (
    name:
    let
      includeNetwork = builtins.elem name [
        "dns-adguardhome"
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
  publisherSettings = settingsFor "vpn-client-profiles" "publisher";
  disabledPublisherOverrides = {
    vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.enable = false;
  };
  disabledPublisher = consume {
    instanceNames = [ "vpn-client-profiles" ];
    instanceOverrides = disabledPublisherOverrides;
    fixtureName = "vpn-consumer-disabled-publisher-fixture";
  };
  minimalPublisherSettings = publisherSettings // {
    providerRefs = builtins.filter (ref: ref.protocol == "vless-xhttp") publisherSettings.providerRefs;
  };
  minimalPublisher = consume {
    instanceNames = [
      "vpn-mihomo-vless-xhttp"
      "vpn-client-profiles"
    ];
    instanceOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings =
      minimalPublisherSettings;
    fixtureName = "vpn-consumer-minimal-publisher-fixture";
  };
  disabledPublisherUnits = disabledPublisher.machine.systemd.services;
  minimalPublisherUnits = minimalPublisher.machine.systemd.services;
  minimalPublisherIntegration =
    minimalPublisher.machine.clanwright.vpn.publishers.vpn-client-profiles;
  publisherFixtureResults = {
    disabledExplicit =
      disabledPublisherOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.enable
      == false;
    disabledHasNoIntegration =
      !(disabledPublisher.machine.clanwright.vpn.publishers ? vpn-client-profiles);
    disabledHasNoDeclarations =
      !(disabledPublisherUnits ? vpn-client-profiles-publish-fixture)
      && !(disabledPublisherUnits ? vpn-client-profiles-public-assets-fixture)
      && !(disabledPublisher.machine.users.groups ? vpn-client-profiles)
      && disabledPublisher.machine.sops.secrets == { };
    minimalInventoryExplicit =
      builtins.attrNames minimalPublisher.config.inventory.instances == [
        "vpn-client-profiles"
        "vpn-mihomo-vless-xhttp"
      ];
    minimalPublicationPresent =
      minimalPublisherUnits ? vpn-client-profiles-publish-fixture
      && minimalPublisherUnits ? vpn-client-profiles-public-assets-fixture;
    minimalIntegrationPresent =
      minimalPublisherIntegration.publicationUnit == "vpn-client-profiles-publish-fixture.service"
      && minimalPublisherIntegration.refreshUnit == "vpn-client-profiles-public-assets-fixture.service"
      && minimalPublisher.machine.clanwright.vpn.publisherRenders ? vpn-client-profiles;
    minimalProviderPresent =
      minimalPublisher.machine.services.xray.enable && minimalPublisherUnits ? xray;
    minimalHasNoUnrelatedServices =
      !(minimalPublisherUnits ? mihomo-hysteria2)
      && !(minimalPublisherUnits ? mita)
      && !(minimalPublisherUnits ? wireguard-awg-fixture)
      && !(minimalPublisherUnits ? caddy)
      && !minimalPublisher.machine.services.adguardhome.enable
      && !minimalPublisher.machine.services.dnsproxy.enable
      && !minimalPublisher.machine.services.unbound.enable;
  };
  publisherFixtures = builtins.all (value: value) (builtins.attrValues publisherFixtureResults);
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
    && publisherFixtures
    && combinedClanFixture.contract
    && awgTransportContract
    && mieruEndpointContract
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
        mieruEndpointContract
        naiveProviderContract
        naiveProviderResults
        awgOverrideRejected
        dnsStatePreserved
        dnsStateResults
        independentPlacementResults
        independentPlacements
        publisherFixtureResults
        publisherFixtures
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
      mieruEndpointContract
      naiveProviderContract
      naiveProviderResults
      dnsStatePreserved
      combinedClanFixture
      independentPlacements
      publisherFixtureResults
      publisherFixtures
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
