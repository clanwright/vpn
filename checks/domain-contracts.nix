{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
let
  lib = inputs.nixpkgs.lib;
  nativeClanDependencyResults = import ./lib/native-clan-dependencies.nix { inherit inputs root; };
  nativeClanDependencies = builtins.all (value: value) (
    builtins.attrValues nativeClanDependencyResults
  );
  fixture = import ./fixtures/example-clan.nix;
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  vpnExports = import ../modules/contracts/vpn-exports.nix { inherit lib; };
  publisherCompiler = import ../clanServices/vpn-client-profiles/publisher.nix { inherit lib; };
  compilePublisher =
    settings: exports:
    publisherCompiler.compile {
      inherit pkgs settings exports;
      instanceName = "vpn-client-profiles";
      selectExports = inputs.clan-core.lib.selectExports;
    };
  awgValidation = import ../clanServices/amneziawg/validation.nix { inherit lib; };
  serviceSpecs = {
    vpn-mihomo-vless-xhttp.role = "gateway";
    vpn-mieru.role = "gateway";
    vpn-anytls.role = "gateway";
    vpn-trusttunnel.role = "gateway";
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
    vpn-mieru = {
      role = "gateway";
      protocol = "mieru";
    };
    vpn-anytls = {
      role = "gateway";
      protocol = "anytls";
    };
    vpn-trusttunnel = {
      role = "gateway";
      protocol = "trusttunnel";
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
    vpnExports.selectVpnProvider {
      providerInstanceId = name;
      providerMachine = "vpn-fixture";
      # Exercise the selector against real native identity metadata.
      consumerInstanceId = "version-contract-check";
      selectExports =
        predicate: exports:
        if
          predicate {
            serviceName = "@clanwright/${name}";
            roleName = spec.role;
            machineName = "vpn-fixture";
            instanceName = name;
          }
        then
          exports
        else
          { };
      exports.only.vpnProvider = raw;
    };
  providerVersionResults = lib.mapAttrs (name: raw: {
    currentAccepted = raw.schemaVersion == 3 && builtins.deepSeq (selectProvider name raw) true;
    legacyRejected =
      !(builtins.tryEval (builtins.deepSeq (selectProvider name (raw // { schemaVersion = 2; })) true))
      .success;
    missingRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectProvider name (builtins.removeAttrs raw [ "schemaVersion" ])) true
      )).success;
  }) providerExports;
  providerVersionsContract = builtins.all (
    result: builtins.all (value: value) (builtins.attrValues result)
  ) (builtins.attrValues providerVersionResults);
  awgInstance = services.vpn-amneziawg.roles.gateway.perInstance {
    settings = settingsFor "vpn-amneziawg" "gateway";
    instanceName = "vpn-amneziawg";
    machine.name = "vpn-fixture";
    mkExports = value: value;
  };
  awgProvider = awgInstance.exports.vpnProvider;
  selectAwgProvider = raw: selectProvider "vpn-amneziawg" raw;
  awgPayload = awgProvider.connection.amneziawg;
  awgTransportContract =
    awgProvider.schemaVersion == 3
    && builtins.deepSeq (selectAwgProvider awgProvider) true
    && awgPayload.endpoint.port == 443
    && !(builtins.tryEval (
      builtins.deepSeq (selectAwgProvider (
        lib.recursiveUpdate awgProvider { connection.amneziawg.endpoint.transport = "tcp"; }
      )) true
    )).success;
  mieruProvider = providerExports.vpn-mieru;
  mieruPayload = mieruProvider.connection.mieru;
  selectMieruProvider = raw: selectProvider "vpn-mieru" raw;
  rejectsMieru = raw: !(builtins.tryEval (builtins.deepSeq (selectMieruProvider raw) true)).success;
  mieruEndpointContract =
    builtins.attrNames mieruPayload.endpoint == [
      "ipv4"
      "port"
    ]
    && mieruPayload.endpoint.ipv4 == "192.0.2.13"
    && mieruPayload.endpoint.port == 8443
    && builtins.deepSeq (selectMieruProvider mieruProvider) true
    && rejectsMieru (
      lib.recursiveUpdate mieruProvider { connection.mieru.endpoint.hostname = "mieru.example.invalid"; }
    )
    && rejectsMieru (
      mieruProvider
      // {
        connection.mieru = mieruPayload // {
          endpoint = builtins.removeAttrs mieruPayload.endpoint [ "ipv4" ];
        };
      }
    )
    && rejectsMieru (lib.recursiveUpdate mieruProvider { connection.mieru.endpoint.unexpected = true; })
    && rejectsMieru (
      lib.recursiveUpdate mieruProvider { connection.mieru.endpoint.ipv4 = "192.0.2.999"; }
    )
    && !(builtins.tryEval (
      builtins.deepSeq (selectProvider "vpn-mihomo-vless-xhttp" (
        lib.recursiveUpdate providerExports.vpn-mihomo-vless-xhttp {
          connection.vless-xhttp.endpoint.hostname = null;
        }
      )) true
    )).success;
  trustTunnelProvider = providerExports.vpn-trusttunnel;
  trustTunnelPayload = trustTunnelProvider.connection.trusttunnel;
  trustTunnelEndpointContract =
    trustTunnelPayload.endpoint == {
      hostname = "trusttunnel.example.invalid";
      ipv4 = "192.0.2.15";
      port = 10443;
    }
    && trustTunnelPayload.clients.cHJvYmU.passwordSecret == "fixture-trusttunnel-password"
    && builtins.deepSeq (selectProvider "vpn-trusttunnel" trustTunnelProvider) true;
  naiveProvider = providerExports.vpn-naiveproxy;
  selectNaiveProvider = raw: selectProvider "vpn-naiveproxy" raw;
  rejectsNaive = raw: !(builtins.tryEval (builtins.deepSeq (selectNaiveProvider raw) true)).success;
  naiveProviderResults = {
    actual =
      naiveProvider.schemaVersion == 3 && builtins.deepSeq (selectNaiveProvider naiveProvider) true;
    legacyVersionRejected = rejectsNaive (naiveProvider // { schemaVersion = 2; });
    missingVersionRejected = rejectsNaive (builtins.removeAttrs naiveProvider [ "schemaVersion" ]);
    unsafeAccountRejected = rejectsNaive (
      lib.recursiveUpdate naiveProvider {
        connection.naiveproxy.clients."../account".passwordSecret = "fixture-invalid";
      }
    );
    missingPasswordRejected = rejectsNaive (
      naiveProvider
      // {
        connection.naiveproxy = naiveProvider.connection.naiveproxy // {
          clients.cHJvYmU = { };
        };
      }
    );
    nullPasswordRejected = rejectsNaive (
      lib.recursiveUpdate naiveProvider { connection.naiveproxy.clients.cHJvYmU.passwordSecret = null; }
    );
    unknownClientFieldRejected = rejectsNaive (
      lib.recursiveUpdate naiveProvider {
        connection.naiveproxy.clients.cHJvYmU.username = "unlisted-user";
      }
    );
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
    (schemaResult "vpn-anytls" ((settingsFor "vpn-anytls" "gateway") // { port = "9443"; }))
    (schemaResult "vpn-trusttunnel" ((settingsFor "vpn-trusttunnel" "gateway") // { port = "10443"; }))
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
  removedSurfacesResults = {
    libraryHelpers = builtins.attrNames self.lib == [ "exportInterfaces" ];
    exportInterfaces = builtins.attrNames self.clan.exportInterfaces == [ "vpnProvider" ];
    exportInterfaceConstructor =
      builtins.attrNames (self.lib.exportInterfaces { inherit lib; }) == [ "vpnProvider" ];
    publisherExportsNothing =
      (evaluatedServices.vpn-client-profiles.manifest.exports.out or [ ]) == [ ];
    excludedProfileNamesRejected =
      !(schemaResult "vpn-client-profiles" (
        settingsFor "vpn-client-profiles" "publisher" // { excludedProfileNames = [ ]; }
      )).success;
    publisherProbeKindRejected =
      !(schemaResult "vpn-client-profiles" (
        let
          settings = settingsFor "vpn-client-profiles" "publisher";
        in
        settings // { profiles = map (profile: profile // { kind = "probe"; }) settings.profiles; }
      )).success;
    publisherSecretPrefixRejected =
      !(schemaResult "vpn-client-profiles" (
        settingsFor "vpn-client-profiles" "publisher" // { secretPrefix = "fixture"; }
      )).success;
    profileLinkPathTokenSecretNameRejected =
      !(schemaResult "vpn-client-profiles" (
        let
          settings = settingsFor "vpn-client-profiles" "publisher";
        in
        settings
        // {
          profileLinks = map (
            link: link // { pathTokenSecretName = "fixture-link-path-token"; }
          ) settings.profileLinks;
        }
      )).success;
    profilePathTokenSecretNameRequired =
      !(schemaResult "vpn-client-profiles" (
        let
          settings = settingsFor "vpn-client-profiles" "publisher";
        in
        settings
        // {
          profiles = map (profile: builtins.removeAttrs profile [ "pathTokenSecretName" ]) settings.profiles;
        }
      )).success;
    vlessProbeKindRejected =
      !(schemaResult "vpn-mihomo-vless-xhttp" (
        let
          settings = settingsFor "vpn-mihomo-vless-xhttp" "gateway";
        in
        settings // { profiles = map (profile: profile // { kind = "probe"; }) settings.profiles; }
      )).success;
    naiveProbeUserNameRejected =
      !(schemaResult "vpn-naiveproxy" (
        settingsFor "vpn-naiveproxy" "addon" // { probeUserName = "probe"; }
      )).success;
  };
  removedSurfaces = builtins.all (value: value) (builtins.attrValues removedSurfacesResults);
  placementBehavior =
    name: machine:
    {
      vpn-mihomo-vless-xhttp =
        machine.services.xray.enable
        && machine.systemd.services ? xray
        && !((machine.networkCore.mihomo or { }) ? vlessXhttp);
      vpn-mieru = machine.systemd.services ? mita && machine.sops.templates ? "mita.json";
      vpn-anytls = machine.services.sing-box.enable && machine.systemd.services ? sing-box;
      vpn-trusttunnel =
        machine.systemd.services ? trusttunnel && machine.sops.templates ? "trusttunnel.toml";
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
      extraModule =
        lib.optionalAttrs
          (builtins.elem name [
            "vpn-anytls"
            "vpn-trusttunnel"
          ])
          {
            security.acme = {
              acceptTerms = true;
              defaults.email = "operator@example.invalid";
              certs.fixture.webroot = "/var/lib/acme/acme-challenge";
            };
          };
      supportNames = lib.optionals includeNetwork [
        "network-caddy"
        "network-certificates"
      ];
      consumer = consume {
        instanceNames = [ name ];
        inherit extraModule includeNetwork;
      };
      caddySites = consumer.machine.services.caddy.virtualHosts;
    in
    builtins.attrNames consumer.config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ [ name ])
    &&
      builtins.length (builtins.attrNames consumer.config._services.allServices)
      == builtins.length supportNames + 1
    && (!includeNetwork || ((caddySites ? "adguard.example.invalid") == (name == "dns-adguardhome")))
    && (!includeNetwork || ((caddySites ? "dns.example.invalid") == (name == "dns-adguardhome")))
    && (!includeNetwork || !(caddySites ? "profiles.example.invalid"))
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
    providerRefs = builtins.filter (
      ref: ref.instanceId == "vpn-mihomo-vless-xhttp"
    ) publisherSettings.providerRefs;
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
      let
        inherit (compilePublisher minimalPublisherSettings minimalPublisher.config.exports) manifest;
      in
      minimalPublisherIntegration.publicationUnit == "vpn-client-profiles-publish-fixture.service"
      && minimalPublisherIntegration.refreshUnit == "vpn-client-profiles-public-assets-fixture.service"
      && map (profile: profile.name) manifest.profiles == [ "cHJvYmU" ]
      &&
        map (artifact: artifact.outputName) (builtins.head manifest.profiles).artifacts == [ "mihomo.yaml" ]
      && builtins.all (
        profile:
        builtins.all (
          artifact:
          lib.hasInfix (builtins.unsafeDiscardStringContext (toString artifact.templatePath)) minimalPublisherUnits.vpn-client-profiles-publish-fixture.script
        ) profile.artifacts
      ) manifest.profiles;
    minimalProviderPresent =
      minimalPublisher.machine.services.xray.enable && minimalPublisherUnits ? xray;
    minimalHasNoUnrelatedServices =
      !(minimalPublisherUnits ? mita)
      && !(minimalPublisherUnits ? trusttunnel)
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
    extraModule = {
      systemd.services.adguardhome.wants = [ "unbound.service" ];
      # Disabled native imports must not force the uncached application package.
      services.data-mesher.package = throw "Disabled DataMesher forced its package";
    };
  };
  inherit (combined) machine;
  combinedClanFixture = import ./combined-clan-fixture.nix {
    inherit combined fixture lib;
    dataMesherSource = inputs.clan-core.inputs.data-mesher.outPath;
    publisherManifest = (compilePublisher publisherSettings combined.config.exports).manifest;
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
  stockPkgs = inputs.nixpkgs.legacyPackages.${system};
  awgUnit = machine.systemd.services.wireguard-awg-fixture;
  awgToolCommands = [
    "set awg-fixture"
    "show interfaces"
    "show awg-fixture listen-port"
    "show awg-fixture peers"
    "show awg-fixture allowed-ips"
  ];
  awgRuntimeUsesStock =
    evaluatedMachine:
    let
      unit = evaluatedMachine.systemd.services.wireguard-awg-fixture;
    in
    unit.serviceConfig.ExecStart == "${stockPkgs.amneziawg-go}/bin/amneziawg-go -f awg-fixture"
    && builtins.all (
      command:
      lib.hasInfix (builtins.unsafeDiscardStringContext "${stockPkgs.amneziawg-tools}/bin/awg ${command}") unit.postStart
    ) awgToolCommands
    && builtins.elem stockPkgs.amneziawg-go evaluatedMachine.environment.systemPackages
    && builtins.elem stockPkgs.amneziawg-tools evaluatedMachine.environment.systemPackages;
  foreignHostAliases = consume {
    instanceNames = [ "vpn-amneziawg" ];
    fixtureName = "vpn-consumer-awg-foreign-host-aliases-fixture";
    extraModule.nixpkgs.overlays = [
      (_final: _prev: {
        amneziawg-go = pkgs.hello;
        amneziawg-tools = pkgs.hello;
      })
    ];
  };
  foreignHostPkgs = foreignHostAliases.config.nixosConfigurations.vpn-fixture.pkgs;
  foreignAwgUnit = foreignHostAliases.machine.systemd.services.wireguard-awg-fixture;
  servicePackageAuthorityResults = {
    adguard = machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    dnsproxy = machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    unbound = machine.services.unbound.package == self.packages.${system}.unbound;
    awgStockVersions =
      stockPkgs.amneziawg-go.version == "3.1.20260828"
      && stockPkgs.amneziawg-tools.version == "3.1.20260812";
    awgStockOutputs =
      self.packages.${system}.amneziawg-go == stockPkgs.amneziawg-go
      && self.packages.${system}.amneziawg-tools == stockPkgs.amneziawg-tools;
    awgActualRuntime = awgRuntimeUsesStock machine;
    awgForeignHostAliasesPreserveRuntime =
      foreignHostPkgs.amneziawg-go == pkgs.hello
      && foreignHostPkgs.amneziawg-tools == pkgs.hello
      && awgRuntimeUsesStock foreignHostAliases.machine
      && foreignAwgUnit.serviceConfig.ExecStart == awgUnit.serviceConfig.ExecStart
      && foreignAwgUnit.postStart == awgUnit.postStart;
    awgFamily = awgValidation.packageFamiliesValid {
      inherit (self.packages.${system}) amneziawg-go amneziawg-tools;
    };
    adguardOverride =
      overrideAttempt.machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    dnsproxyOverride =
      overrideAttempt.machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    unboundOverride =
      overrideAttempt.machine.services.unbound.package == self.packages.${system}.unbound;
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
    && removedSurfaces
    && providerVersionsContract
    && independentPlacements
    && publisherFixtures
    && nativeClanDependencies
    && combinedClanFixture.contract
    && awgTransportContract
    && mieruEndpointContract
    && trustTunnelEndpointContract
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
        trustTunnelEndpointContract
        naiveProviderContract
        naiveProviderResults
        dnsStatePreserved
        dnsStateResults
        independentPlacementResults
        independentPlacements
        publisherFixtureResults
        publisherFixtures
        combinedClanFixture
        nativeClanDependencies
        nativeClanDependencyResults
        invalidFieldTypes
        missingAwgClientPrivateKeyBindingRejected
        invalidNestedFields
        packageAuthority
        packageAuthorityResults
        providerVersionResults
        providerVersionsContract
        registeredSchemas
        validSchemaResults
        validSchemas
        publicHelperRemoved
        removedSurfaces
        removedSurfacesResults
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
      trustTunnelEndpointContract
      naiveProviderContract
      naiveProviderResults
      dnsStatePreserved
      combinedClanFixture
      nativeClanDependencies
      nativeClanDependencyResults
      independentPlacements
      publisherFixtureResults
      publisherFixtures
      invalidFieldTypes
      missingAwgClientPrivateKeyBindingRejected
      invalidNestedFields
      packageAuthority
      providerVersionsContract
      registeredSchemas
      validSchemas
      publicHelperRemoved
      removedSurfaces
      removedSurfacesResults
      ;
  }
