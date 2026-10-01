{
  inputs,
  root,
  self,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  vpnExports = import ../modules/contracts/vpn-exports.nix { inherit lib; };
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  publisherCompiler = import ../clanServices/vpn-client-profiles/publisher.nix { inherit lib; };
  manifestView = import ./lib/manifest-view.nix { inherit lib; };
  compilePublisher =
    settings: exports:
    publisherCompiler.compile {
      inherit pkgs settings exports;
      instanceName = "vpn-client-profiles";
      selectExports = inputs.clan-core.lib.selectExports;
    };
  compileView = settings: exports: manifestView (compilePublisher settings exports).manifest;
  profileTypes = import ../clanServices/vpn-client-profiles/types.nix { inherit lib; };
  clientDnsResults = import ./client-dns-contracts.nix { inherit lib profileTypes; };
  clientPolicyResults = import ./client-policy-contracts.nix { inherit lib pkgs; };
  allBooleansTrue =
    value:
    if builtins.isBool value then
      value
    else if builtins.isAttrs value then
      builtins.all allBooleansTrue (builtins.attrValues value)
    else
      false;
  clientDnsContract = allBooleansTrue clientDnsResults;
  clientPolicyContract = allBooleansTrue clientPolicyResults;
  fixture = import ./fixtures/example-clan.nix;
  fixtureMachineName = fixture.machineName or "vpn-fixture";
  supportNames = [
    "network-caddy"
    "network-certificates"
  ];
  serviceNames = builtins.filter (name: !(builtins.elem name supportNames)) (
    builtins.attrNames fixture.instances
  );
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  consumer = consume {
    instanceNames = serviceNames;
    includeNetwork = true;
    fixtureName = "vpn-consumer-client-render-fixture";
  };
  sameCanonicalConsumer = consume {
    instanceNames = serviceNames;
    includeNetwork = true;
    fixtureName = "vpn-consumer-same-canonical-fixture";
    instanceOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings = {
      configGatewayDomain = "site.example.invalid";
      profileLinks = [
        {
          name = "cHJvYmU";
          label = "Fixture profile";
          accountDomain = "site.example.invalid";
        }
      ];
    };
  };
  sameCanonicalPublisherSettings =
    (lib.evalModules {
      modules = [
        publisherCompiler.interface
        sameCanonicalConsumer.config.inventory.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings
      ];
    }).config;
  sameCanonicalResults = import ./lib/native-composition.nix { inherit lib; } {
    inherit (sameCanonicalConsumer) machine;
    publisherManifest =
      (compilePublisher sameCanonicalPublisherSettings sameCanonicalConsumer.config.exports).manifest;
    domain = "site.example.invalid";
    sameCanonical = true;
  };
  sameCanonicalContract = builtins.all (value: value) (builtins.attrValues sameCanonicalResults);
  zeroNaiveOverrides = {
    vpn-client-profiles = {
      roles.publisher.machines.vpn-fixture.settings.providerRefs = builtins.filter (
        ref: ref.instanceId != "vpn-naiveproxy"
      ) fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.providerRefs;
    };
  };
  zeroNaiveConsumer = consume {
    instanceNames = serviceNames;
    instanceOverrides = zeroNaiveOverrides;
    includeNetwork = true;
    fixtureName = "vpn-consumer-zero-naive-fixture";
  };
  publisherSettings =
    fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings;
  runtimeMachineName = publisherSettings.localMachineName;
  publicationUnitName = "vpn-client-profiles-publish-${runtimeMachineName}";
  publisherWith =
    settings:
    lib.recursiveUpdate fixture.instances {
      vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings = settings;
    };
  evaluateInstances =
    name: instances:
    consume {
      inherit instances;
      includeNetwork = true;
      fixtureName = "vpn-consumer-${name}-fixture";
    };
  renderedWithSettings =
    _name: settings: builtins.head (compileView settings consumer.config.exports).renderedProfiles;
  rejectsCompilation =
    settings:
    let
      compiledCandidate = compilePublisher settings consumer.config.exports;
      attempt = builtins.tryEval (
        builtins.deepSeq compiledCandidate.settings (
          manifestLib.validateManifest compiledCandidate.manifest
        )
      );
    in
    !attempt.success || !attempt.value;
  rejectsInstances =
    name: instances:
    let
      candidate = evaluateInstances name instances;
    in
    !(builtins.tryEval (builtins.deepSeq candidate.machine.system.build.toplevel.drvPath true)).success;
  secondPublisherWith =
    settings:
    lib.recursiveUpdate fixture.instances.vpn-client-profiles {
      roles.publisher.machines.vpn-fixture.settings = settings;
    };
  publisherSettingsFor =
    localMachineName: tokenPrefix: configGatewayDomain:
    publisherSettings
    // {
      inherit localMachineName configGatewayDomain;
      profiles = map (
        profile: profile // { pathTokenSecretName = "${tokenPrefix}-${profile.name}-path-token"; }
      ) publisherSettings.profiles;
      profileLinks = map (
        link: link // { accountDomain = configGatewayDomain; }
      ) publisherSettings.profileLinks;
    };
  firstPublisherSettings = publisherSettingsFor "fixture-a" "fixture-a" "profiles-a.example.invalid";
  secondPublisherSettings = publisherSettingsFor "fixture-b" "fixture-b" "profiles-b.example.invalid";
  publisherPair =
    firstSettings: secondSettings:
    builtins.removeAttrs fixture.instances [ "vpn-client-profiles" ]
    // {
      profile-a = secondPublisherWith firstSettings;
      profile_a = secondPublisherWith secondSettings;
    };
  duplicatePublisherRuntimeIdentityRejected = rejectsInstances "duplicate-publisher-runtime" (
    publisherPair firstPublisherSettings (
      secondPublisherSettings // { inherit (firstPublisherSettings) localMachineName; }
    )
  );
  duplicatePublisherDomainRejected = rejectsInstances "duplicate-publisher-domain" (
    publisherPair firstPublisherSettings (
      secondPublisherSettings // { inherit (firstPublisherSettings) configGatewayDomain; }
    )
  );
  duplicatePublisherDomainCaseRejected = rejectsInstances "duplicate-publisher-domain-case" (
    publisherPair firstPublisherSettings (
      publisherSettingsFor "fixture-b" "fixture-b" "PROFILES-A.EXAMPLE.INVALID"
    )
  );
  disjointPublisherConsumer = evaluateInstances "disjoint-publishers" (
    publisherPair firstPublisherSettings secondPublisherSettings
  );
  disjointPublisherMachine = disjointPublisherConsumer.machine;
  disjointPublisherIntegrations = disjointPublisherMachine.clanwright.vpn.publishers;
  disjointPublisherResults = {
    registryMerged =
      builtins.attrNames disjointPublisherIntegrations == [
        "profile-a"
        "profile_a"
      ];
    profileRootsDistinct =
      disjointPublisherIntegrations.profile-a.profileRoot
      == "/run/vpn-client-profiles/fixture-a/published/current"
      &&
        disjointPublisherIntegrations.profile_a.profileRoot
        == "/run/vpn-client-profiles/fixture-b/published/current";
    unitsDistinct =
      disjointPublisherIntegrations.profile-a.publicationUnit
      == "vpn-client-profiles-publish-fixture-a.service"
      &&
        disjointPublisherIntegrations.profile_a.publicationUnit
        == "vpn-client-profiles-publish-fixture-b.service"
      &&
        disjointPublisherIntegrations.profile_a.refreshUnit
        == "vpn-client-profiles-public-assets-fixture-b.service";
    stateDistinct =
      disjointPublisherIntegrations.profile_a.assetRoot == "/var/lib/vpn-client-profiles/fixture-b/assets"
      &&
        disjointPublisherIntegrations.profile_a.statusPath
        == "/var/lib/vpn-client-profiles/fixture-b/status.json";
    domainsDistinct =
      disjointPublisherIntegrations.profile-a.configGatewayDomain == "profiles-a.example.invalid"
      && disjointPublisherIntegrations.profile_a.configGatewayDomain == "profiles-b.example.invalid";
    matcherNamespacesInjective =
      disjointPublisherIntegrations.profile-a.routeConfig
      != disjointPublisherIntegrations.profile_a.routeConfig
      && lib.hasInfix "vpn_client_profile_yaml_profile_ha" disjointPublisherIntegrations.profile-a.routeConfig
      && lib.hasInfix "vpn_client_profile_yaml_profile_ua" disjointPublisherIntegrations.profile_a.routeConfig;
  };
  disjointPublisherContract = builtins.all (value: value) (
    builtins.attrValues disjointPublisherResults
  );
  unknownProfileRejected = rejectsCompilation (
    publisherSettings
    // {
      providerRefs = [
        (
          (builtins.head publisherSettings.providerRefs)
          // {
            clients = {
              unknown-profile = "cHJvYmU";
            };
          }
        )
      ];
    }
  );
  duplicateProfileRejected = rejectsInstances "duplicate-profile" (
    publisherWith (
      publisherSettings // { profiles = publisherSettings.profiles ++ publisherSettings.profiles; }
    )
  );
  pathTokenCredentialSecretRejected = rejectsInstances "path-token-credential-secret" (
    publisherWith (
      publisherSettings
      // {
        profiles = map (
          profile: profile // { pathTokenSecretName = "fixture-vless-uuid"; }
        ) publisherSettings.profiles;
      }
    )
  );
  duplicateProviderRefRejected = rejectsInstances "duplicate-provider-ref" (
    publisherWith (
      publisherSettings
      // {
        providerRefs = publisherSettings.providerRefs ++ [ (builtins.head publisherSettings.providerRefs) ];
      }
    )
  );
  deadPublisherCredentialRejected = rejectsInstances "dead-publisher-credential" (
    publisherWith (
      publisherSettings
      // {
        profiles = map (
          profile: profile // { vlessUuidSecretName = "fixture-vless-uuid"; }
        ) publisherSettings.profiles;
      }
    )
  );
  missingCredentialRejected =
    let
      instance = fixture.instances.vpn-naiveproxy;
      role = instance.roles.addon;
      machine = role.machines.vpn-fixture;
      inherit (machine) settings;
    in
    rejectsInstances "missing-credential" (
      fixture.instances
      // {
        vpn-naiveproxy = instance // {
          roles = instance.roles // {
            addon = role // {
              machines = role.machines // {
                vpn-fixture = machine // {
                  settings = settings // {
                    passwordSecretNames = builtins.removeAttrs settings.passwordSecretNames [ "cHJvYmU" ];
                  };
                };
              };
            };
          };
        };
      }
    );
  selectMieruExport =
    raw:
    vpnExports.selectVpnProvider {
      providerInstanceId = "vpn-mieru";
      providerMachine = fixtureMachineName;
      consumerInstanceId = "vpn-client-profiles";
      exports.selected.vpnProvider = raw;
      selectExports =
        predicate: exports:
        if
          predicate {
            serviceName = "@clanwright/vpn-mieru";
            roleName = "gateway";
            machineName = fixtureMachineName;
            instanceName = "vpn-mieru";
          }
        then
          exports
        else
          { };
    };
  validMieruExport = {
    schemaVersion = 3;
    connection.mieru = {
      endpoint = {
        ipv4 = "192.0.2.13";
        port = 8443;
      };
      clients.cHJvYmU.passwordSecret = "fixture-mieru-password";
    };
  };
  evalProviderExportType =
    raw:
    (lib.evalModules {
      modules = [
        {
          options.value = lib.mkOption { type = lib.types.submodule vpnExports.vpnProviderModule; };
          config.value = raw;
        }
      ];
    }).config.value;
  validNaiveExport = {
    schemaVersion = 3;
    connection.naiveproxy = {
      endpoint = {
        hostname = "site.example.invalid";
        ipv4 = "192.0.2.10";
        port = 443;
      };
      clients.cHJvYmU.passwordSecret = "fixture-naive-password";
    };
  };
  rejectsMieruExport =
    raw: !(builtins.tryEval (builtins.deepSeq (selectMieruExport raw) true)).success;
  mieruContractResults = {
    typeAcceptsDomainFreeMieru =
      builtins.attrNames (evalProviderExportType validMieruExport).connection.mieru.endpoint == [
        "ipv4"
        "port"
      ];
    typeRejectsDomainFreeExistingProtocol =
      !(builtins.tryEval (
        builtins.deepSeq (evalProviderExportType (
          lib.recursiveUpdate validNaiveExport { connection.naiveproxy.endpoint.hostname = null; }
        )) true
      )).success;
    validDomainFreeExportAccepted =
      (selectMieruExport validMieruExport).connection == validMieruExport.connection;
    hostnameRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport {
        connection.mieru.endpoint.hostname = "mieru.example.invalid";
      }
    );
    invalidIpv4Rejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { connection.mieru.endpoint.ipv4 = "192.0.2.999"; }
    );
    transportRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { connection.mieru.endpoint.transport = "udp"; }
    );
    unknownEndpointFieldRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { connection.mieru.endpoint.serverName = "example.invalid"; }
    );
    unknownPayloadFieldRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { connection.mieru.sni = "example.invalid"; }
    );
    unknownClientFieldRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { connection.mieru.clients.cHJvYmU.username = "other"; }
    );
    emptyClientsRejected = rejectsMieruExport (
      validMieruExport
      // {
        connection.mieru = validMieruExport.connection.mieru // {
          clients = { };
        };
      }
    );
  };
  mieruExportContract = builtins.all (value: value) (builtins.attrValues mieruContractResults);
  conflictingDnsPinCaseRejected = rejectsCompilation (
    publisherSettings
    // {
      edgeDomain = lib.toUpper publisherSettings.edgeDomain;
      clientDnsEndpoints = [
        {
          domain = publisherSettings.edgeDomain;
          ipv4 = "198.51.100.53";
        }
      ];
    }
  );
  # Consumer migration expands the old all-profile reference into an explicit
  # mapping. Publisher profile identities remain independent of provider accounts.
  migratedSettings = publisherSettings // {
    profiles = map (profile: profile // { name = "travel"; }) publisherSettings.profiles;
    profileLinks = map (link: link // { name = "travel"; }) publisherSettings.profileLinks;
    providerRefs = map (
      ref:
      ref
      // {
        clients = {
          travel = "cHJvYmU";
        };
      }
    ) publisherSettings.providerRefs;
  };
  migratedCompiled = compileView migratedSettings consumer.config.exports;
  migratedRendered = builtins.head migratedCompiled.renderedProfiles;
  migratedManifest = migratedCompiled.manifest;
  migratedProxy =
    type:
    builtins.head (
      builtins.filter (proxy: proxy.type == type) migratedRendered.mihomoSelectiveTemplate.proxies
    );
  migratedNaive = builtins.head (
    builtins.filter (outbound: outbound.type == "naive") migratedRendered.profileJsonTemplate.outbounds
  );
  migrationResults = {
    allRefsExplicit = builtins.all (
      ref: ref.clients == { travel = "cHJvYmU"; } && !(ref ? protocol) && !(ref ? profileNames)
    ) migratedSettings.providerRefs;
    profileIdentityPreserved =
      migratedRendered.name == "travel" && (builtins.head migratedManifest.profiles).name == "travel";
    accountsRemainProviderIdentities =
      migratedNaive.username == "cHJvYmU"
      && (migratedProxy "mieru").username == "cHJvYmU"
      && (migratedProxy "trusttunnel").username == "cHJvYmU";
    devicePayloadPreserved =
      (migratedProxy "vless")."reality-opts"."short-id" == "0123456789abcdef"
      && (migratedProxy "wireguard").ip == "10.77.0.2";
    bindingsRemainProviderSecrets =
      lib.sort builtins.lessThan (
        lib.unique (
          lib.concatMap (
            artifact: map (binding: binding.secretName) artifact.bindings
          ) (builtins.head migratedManifest.profiles).artifacts
        )
      ) == lib.sort builtins.lessThan [
        "fixture-vless-uuid"
        "fixture-awg-client-private-key"
        "fixture-awg-header-protection-key"
        "fixture-naive-published-password"
        "fixture-mieru-password"
        "fixture-anytls-password"
        "fixture-trusttunnel-password"
      ];
    outputsPreserved =
      map (artifact: artifact.outputName) (builtins.head migratedManifest.profiles).artifacts == [
        "mihomo.yaml"
        "profile.json"
      ];
  };
  migrationContract = builtins.all (value: value) (builtins.attrValues migrationResults);
  unknownAccountRejected = rejectsCompilation (
    publisherSettings
    // {
      providerRefs = [
        (
          (builtins.head publisherSettings.providerRefs)
          // {
            clients = {
              cHJvYmU = "unknown-account";
            };
          }
        )
      ];
    }
  );
  emptyMappingRejected = rejectsCompilation (
    publisherSettings
    // {
      providerRefs = [ ((builtins.head publisherSettings.providerRefs) // { clients = { }; }) ];
    }
  );
  sharedAccountRejected = rejectsCompilation (
    publisherSettings
    // {
      profiles = publisherSettings.profiles ++ [
        (
          (builtins.head publisherSettings.profiles)
          // {
            name = "travel";
            pathTokenSecretName = "fixture-travel-path-token";
          }
        )
      ];
      providerRefs = [
        (
          (builtins.head publisherSettings.providerRefs)
          // {
            clients = {
              cHJvYmU = "cHJvYmU";
              travel = "cHJvYmU";
            };
          }
        )
      ];
    }
  );
  consumerMachine = consumer.config.nixosConfigurations.${fixtureMachineName}.config;
  compiled = compileView publisherSettings consumer.config.exports;
  rendered = builtins.head compiled.renderedProfiles;
  inherit (compiled) manifest;
  manifestProfile = builtins.head manifest.profiles;
  manifestArtifacts = manifestProfile.artifacts;
  valueAtPath =
    value: path:
    if path == [ ] then
      value
    else
      let
        component = builtins.head path;
        next = if builtins.isInt component then builtins.elemAt value component else value.${component};
      in
      valueAtPath next (builtins.tail path);
  placeholdersIn =
    value:
    if builtins.isString value then
      lib.optional (builtins.match "__[A-Za-z0-9_-]+__" value != null) value
    else if builtins.isList value then
      lib.concatMap placeholdersIn value
    else if builtins.isAttrs value then
      lib.concatMap placeholdersIn (builtins.attrValues value)
    else
      [ ];
  allAssetRefs = lib.unique (lib.concatMap (artifact: artifact.assetRefs) manifestArtifacts);
  manifestAssets = builtins.attrValues manifest.assetCatalog;
  expectedCanonicalAssets = {
    mihomo-ai_domains = [
      "/assets/v1/catalog/8a6d58340125ea123ceb6af7ab8417dd.txt"
      "ai_domains.txt"
      "text/plain; charset=utf-8"
    ];
    mihomo-github_domains = [
      "/assets/v1/catalog/6c07c90dacb4128c65b1680c81794fe2.txt"
      "github_domains.txt"
      "text/plain; charset=utf-8"
    ];
    mihomo-refilter_blocked_domains = [
      "/assets/v1/catalog/bcb9e8902437561cc6a78db13fb7f133.mrs"
      "refilter_blocked_domains.mrs"
      "application/octet-stream"
    ];
    mihomo-refilter_blocked_ips = [
      "/assets/v1/catalog/8a8d4d676688e6ced1d2debd9050c9c6.mrs"
      "refilter_blocked_ips.mrs"
      "application/octet-stream"
    ];
    mihomo-ru_blocked_and_geoblocked_domains = [
      "/assets/v1/catalog/545ebc4683015b7f430e203c2d0bd4e9.mrs"
      "ru_blocked_and_geoblocked_domains.mrs"
      "application/octet-stream"
    ];
    mihomo-ru_blocked_asn_ips = [
      "/assets/v1/catalog/cf0daa490dbfd773961568099e805230.mrs"
      "ru_blocked_asn_ips.mrs"
      "application/octet-stream"
    ];
    personal-proxy-domains = [
      "/assets/v1/catalog/17c14c90710e679f2843ea2d477b433e.txt"
      "segments.txt"
      "text/plain; charset=utf-8"
    ];
    secure-dns-domains = [
      "/assets/v1/catalog/3547f64c9a6f5f9e8aa9e407979f7588.txt"
      "secure-dns.txt"
      "text/plain; charset=utf-8"
    ];
    secure-dns-filter = [
      "/assets/v1/catalog/4a2faad8247af00b19dc5c027ba0bbe9.srs"
      "filters.srs"
      "application/octet-stream"
    ];
    sing-box-ai_domains = [
      "/assets/v1/catalog/d5fb80bc38cb1d62efea8a4844083183.srs"
      "ai_domains.srs"
      "application/octet-stream"
    ];
    sing-box-github_domains = [
      "/assets/v1/catalog/b85034083613ad64795a5186b9e8e99b.srs"
      "github_domains.srs"
      "application/octet-stream"
    ];
    sing-box-refilter_blocked_domains = [
      "/assets/v1/catalog/e177dfe079f48001b49cf9215ea1147e.srs"
      "refilter_blocked_domains.srs"
      "application/octet-stream"
    ];
    sing-box-refilter_blocked_ips = [
      "/assets/v1/catalog/b07c03e0d2f99e8bf92291923e9daa3e.srs"
      "refilter_blocked_ips.srs"
      "application/octet-stream"
    ];
    sing-box-ru_blocked_and_geoblocked_domains = [
      "/assets/v1/catalog/d854f0910ec651c1ae32afcae93cd989.srs"
      "ru_blocked_and_geoblocked_domains.srs"
      "application/octet-stream"
    ];
    sing-box-ru_blocked_asn_ips = [
      "/assets/v1/catalog/ce8a692bf3a0dc8e4630e38ada50167d.srs"
      "ru_blocked_asn_ips.srs"
      "application/octet-stream"
    ];
  };
  retiredAssetPaths = [
    "/assets/v1/catalog/filters.srs"
    "/assets/v1/catalog/segments.txt"
    "/assets/v1/catalog/secure-dns.txt"
    "/assets/v1/catalog/ru_blocked_and_geoblocked_domains.srs"
    "/assets/v1/catalog/ru_blocked_and_geoblocked_domains.mrs"
    "/assets/v1/catalog/ru_blocked_asn_ips.srs"
    "/assets/v1/catalog/ru_blocked_asn_ips.mrs"
    "/assets/v1/catalog/refilter_blocked_domains.srs"
    "/assets/v1/catalog/refilter_blocked_domains.mrs"
    "/assets/v1/catalog/refilter_blocked_ips.srs"
    "/assets/v1/catalog/refilter_blocked_ips.mrs"
  ];
  manifestResults = {
    canonicalManifestAccepted = manifestLib.validateManifest manifest;
    schemaVersion = manifest.schemaVersion == 1;
    profileIdentity =
      map (profileEntry: profileEntry.name) manifest.profiles == [ "cHJvYmU" ]
      &&
        manifestProfile.pathTokenBinding == {
          secretName = "publisher-profile-path-token-cHJvYmU";
          decoding = "path-token";
        };
    artifactOutputs =
      map (artifact: artifact.outputName) manifestArtifacts == [
        "mihomo.yaml"
        "profile.json"
      ];
    noFullVariantArtifact =
      !(rendered ? mihomoFullTemplate)
      && !(builtins.any (artifact: artifact.outputName == "mihomo-full.yaml") manifestArtifacts)
      && !(builtins.any (artifact: lib.hasSuffix "-mihomo-full" artifact.id) manifestArtifacts);
    actualPublicationUsesCompiledTemplates = builtins.all (
      artifact:
      lib.hasInfix (builtins.unsafeDiscardStringContext (toString artifact.templatePath)) publicationScript
    ) manifestArtifacts;
    actualPublicationUsesCompiledBindings = builtins.all (
      artifact:
      builtins.all (
        binding: lib.hasInfix consumerMachine.sops.secrets.${binding.secretName}.path publicationScript
      ) artifact.bindings
    ) manifestArtifacts;
    closedArtifactFormats = builtins.all (
      artifact:
      builtins.elem artifact.format [
        "mihomo"
        "json"
      ]
    ) manifestArtifacts;
    bindingTargetsResolve = builtins.all (
      artifact:
      builtins.all (
        binding: valueAtPath artifact.template binding.targetPath == binding.placeholder
      ) artifact.bindings
    ) manifestArtifacts;
    placeholdersBoundExactlyOnce = builtins.all (
      artifact:
      let
        placeholders = placeholdersIn artifact.template;
        bindingPlaceholders = map (binding: binding.placeholder) artifact.bindings;
      in
      bindingPlaceholders == lib.unique bindingPlaceholders
      && lib.sort builtins.lessThan placeholders == lib.sort builtins.lessThan bindingPlaceholders
    ) manifestArtifacts;
    closedDecodingRules = builtins.all (
      artifact:
      builtins.all (
        binding:
        builtins.elem binding.decoding [
          "literal"
          "wireguard-private-key"
          "base64url"
        ]
      ) artifact.bindings
    ) manifestArtifacts;
    assetsDeclaredAndUsed =
      builtins.all (assetId: builtins.hasAttr assetId manifest.assetCatalog) allAssetRefs
      && lib.sort builtins.lessThan allAssetRefs == builtins.attrNames manifest.assetCatalog;
    newDomainAssetsHaveFormatSpecificMirrorsAndReadiness =
      builtins.all
        (
          tag:
          let
            upstreamName = if tag == "ai_domains" then "category-ai-!cn" else "github";
            mihomoAsset = manifest.assetCatalog.${"mihomo-${tag}"};
            singBoxAsset = manifest.assetCatalog.${"sing-box-${tag}"};
            provider = rendered.mihomoSelectiveTemplate."rule-providers".${tag};
            remoteRuleSet = builtins.head (
              builtins.filter (ruleSet: ruleSet.tag == tag) rendered.profileJsonTemplate.route.rule_set
            );
            refreshScript =
              consumerMachine.systemd.services.${"vpn-client-profiles-public-assets-${runtimeMachineName}"}.script;
            assetRoot = consumerMachine.clanwright.vpn.publishers.vpn-client-profiles.assetRoot;
          in
          mihomoAsset.filename == "${tag}.txt"
          && mihomoAsset.validator == "nonempty"
          &&
            mihomoAsset.source == {
              kind = "download";
              url = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/classical/${upstreamName}.list";
            }
          && singBoxAsset.filename == "${tag}.srs"
          && singBoxAsset.validator == "srs"
          &&
            singBoxAsset.source == {
              kind = "download";
              url = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/${upstreamName}.srs";
            }
          && provider.url == "https://${publisherSettings.configGatewayDomain}${mihomoAsset.publicPath}"
          && remoteRuleSet.url == "https://${publisherSettings.configGatewayDomain}${singBoxAsset.publicPath}"
          && builtins.match "\\./ruleset/[a-f0-9]{32}\\.txt" provider.path != null
          &&
            builtins.all
              (
                asset:
                builtins.match "/assets/v1/catalog/[a-f0-9]{32}\\.(txt|srs)" asset.publicPath != null
                && builtins.elem asset.id allAssetRefs
                && lib.hasInfix "refresh_download ${lib.escapeShellArg asset.validator} ${lib.escapeShellArg asset.filename} ${lib.escapeShellArg asset.source.url}" refreshScript
                && lib.hasInfix "[ ! -s ${lib.escapeShellArg "${assetRoot}/${asset.filename}"} ]" refreshScript
                && lib.hasInfix "test -s ${lib.escapeShellArg "${assetRoot}/${asset.filename}"}" publicationScript
              )
              [
                mihomoAsset
                singBoxAsset
              ]
        )
        [
          "ai_domains"
          "github_domains"
        ];
    canonicalAssetRoutesExposed =
      let
        routeConfig = consumerMachine.clanwright.vpn.publishers.vpn-client-profiles.routeConfig;
        publicPaths = map (asset: asset.publicPath) manifestAssets;
      in
      publicPaths == lib.unique publicPaths
      && builtins.all (path: lib.hasInfix "handle ${path} {" routeConfig) publicPaths;
    exactCanonicalAssetTable =
      lib.mapAttrs (_: asset: [
        asset.publicPath
        asset.filename
        asset.contentType
      ]) manifest.assetCatalog == expectedCanonicalAssets;
    retiredAssetAliasesAbsent =
      let
        nativeSite = consumerMachine.services.caddy.virtualHosts."profiles.example.invalid";
        routeConfig = consumerMachine.clanwright.vpn.publishers.vpn-client-profiles.routeConfig;
      in
      builtins.all (
        path: !(lib.hasInfix path routeConfig) && !(lib.hasInfix path nativeSite.extraConfig)
      ) retiredAssetPaths;
    # Only the single Mihomo profile is routed; the removed full variant is not.
    mihomoProfileRouteOnly =
      let
        routeConfig = consumerMachine.clanwright.vpn.publishers.vpn-client-profiles.routeConfig;
      in
      lib.hasInfix "path_regexp ^/[A-Za-z0-9_-]{32,128}/mihomo\\.yaml$" routeConfig
      && !(lib.hasInfix "mihomo(-full)?" routeConfig)
      && !(lib.hasInfix "mihomo-full" routeConfig);
    assetCatalogClosed =
      builtins.all (
        asset:
        builtins.elem asset.validator [
          "nonempty"
          "mrs-domain"
          "mrs-ipcidr"
          "srs"
        ]
        && builtins.elem asset.source.kind [
          "download"
          "adguard-to-srs"
          "local-file"
        ]
      ) manifestAssets
      &&
        map (asset: asset.filename) manifestAssets
        == lib.unique (map (asset: asset.filename) manifestAssets)
      &&
        map (asset: asset.publicPath) manifestAssets
        == lib.unique (map (asset: asset.publicPath) manifestAssets);
    manifestClosedFields =
      builtins.attrNames manifest == [
        "assetCatalog"
        "profiles"
        "schemaVersion"
      ];
    removedDiagnosticProjections =
      builtins.all (field: !(builtins.hasAttr field consumerMachine.clanwright.vpn))
        [
          "publisherPublicationPhases"
          "publisherRenders"
          "publisherManifests"
        ];
  };
  manifestContract = builtins.all (value: value) (builtins.attrValues manifestResults);
  oneDnsRendered = renderedWithSettings "one-client-dns" (
    publisherSettings
    // {
      clientDnsEndpoints = [
        {
          domain = "dns-one.example.invalid";
          ipv4 = "192.0.2.53";
        }
      ];
    }
  );
  legacyDnsRendered = renderedWithSettings "legacy-client-dns" (
    builtins.removeAttrs publisherSettings [ "clientDnsEndpoints" ]
  );
  zeroNaiveMachine = zeroNaiveConsumer.config.nixosConfigurations.${fixtureMachineName}.config;
  zeroNaiveCompiled = compileView (
    publisherSettings
    // {
      providerRefs =
        zeroNaiveOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.providerRefs;
    }
  ) zeroNaiveConsumer.config.exports;
  zeroNaiveRendered = builtins.head zeroNaiveCompiled.renderedProfiles;
  zeroNaiveManifest = zeroNaiveCompiled.manifest;
  zeroNaiveArtifacts = (builtins.head zeroNaiveManifest.profiles).artifacts;
  zeroNaivePublicationScript = zeroNaiveMachine.systemd.services.${publicationUnitName}.script;
  publicationScript = consumerMachine.systemd.services.${publicationUnitName}.script;
  mihomoTypes = map (proxy: proxy.type) rendered.mihomoSelectiveTemplate.proxies;
  manualGroup = "Ручной";
  autoGroup = "Авто";
  legacyGroupNames = [
    "SELECTIVE"
    "SELECTIVE-AUTO"
    "FULL"
    "FULL-AUTO"
    "UDP"
    "UDP-AUTO"
  ];
  selectiveGroups = map (group: group.name) rendered.mihomoSelectiveTemplate."proxy-groups";
  mihomoGroup =
    name:
    builtins.head (
      builtins.filter (group: group.name == name) rendered.mihomoSelectiveTemplate."proxy-groups"
    );
  selectiveManual = mihomoGroup manualGroup;
  selectiveAuto = mihomoGroup autoGroup;
  selectiveGlobal = mihomoGroup "GLOBAL";
  profile = rendered.profileJsonTemplate;
  expectedSingBoxCacheFile = {
    enabled = true;
    store_fakeip = true;
  };
  clientDnsEndpoints = profileTypes.normalizeClientDnsEndpoints publisherSettings;
  naiveOutbounds = builtins.filter (outbound: outbound.type == "naive") profile.outbounds;
  naive = builtins.head naiveOutbounds;
  singBoxAnytls = selector anytls.name profile;
  vless = builtins.head (
    builtins.filter (proxy: proxy.type == "vless") rendered.mihomoSelectiveTemplate.proxies
  );
  vlessPolicyRender =
    enabled:
    let
      service = builtins.head self.clan.modules."@clanwright/vpn-mihomo-vless-xhttp".imports;
      settings =
        (lib.evalModules {
          modules = [
            (service.roles.gateway.interface { inherit lib; })
            {
              config = fixture.instances.vpn-mihomo-vless-xhttp.roles.gateway.machines.vpn-fixture.settings // {
                clientFingerprint = "chrome";
                clientSupportX25519MLKEM768 = enabled;
              };
            }
          ];
        }).config;
      producer = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "vpn-mihomo-vless-xhttp";
        machine.name = fixtureMachineName;
        mkExports = value: value;
      };
      scopes = inputs.clan-core.lib.selectExports (
        scope:
        scope.serviceName == "@clanwright/vpn-mihomo-vless-xhttp"
        && scope.roleName == "gateway"
        && scope.machineName == fixtureMachineName
        && scope.instanceName == "vpn-mihomo-vless-xhttp"
      ) consumer.config.exports;
      variantExports = lib.mapAttrs (
        name: value:
        if builtins.hasAttr name scopes then
          value // { vpnProvider = producer.exports.vpnProvider; }
        else
          value
      ) consumer.config.exports;
    in
    assert builtins.length (builtins.attrNames scopes) == 1;
    builtins.head (compileView publisherSettings variantExports).renderedProfiles;
  vlessClientPolicyContract =
    vless."client-fingerprint"
    == fixture.instances.vpn-mihomo-vless-xhttp.roles.gateway.machines.vpn-fixture.settings.clientFingerprint
    && !(vless."reality-opts" ? "support-x25519mlkem768")
    &&
      builtins.all
        (
          enabled:
          let
            candidate = vlessPolicyRender enabled;
          in
          builtins.all
            (
              template:
              let
                proxy = builtins.head (builtins.filter (entry: entry.type == "vless") template.proxies);
              in
              proxy."client-fingerprint" == "chrome"
              &&
                proxy."reality-opts"
                == (vless."reality-opts" // lib.optionalAttrs enabled { "support-x25519mlkem768" = true; })
            )
            [
              candidate.mihomoSelectiveTemplate
            ]
        )
        [
          false
          true
        ];
  awg = builtins.head (
    builtins.filter (proxy: proxy.type == "wireguard") rendered.mihomoSelectiveTemplate.proxies
  );
  mieru = builtins.head (
    builtins.filter (proxy: proxy.type == "mieru") rendered.mihomoSelectiveTemplate.proxies
  );
  anytls = builtins.head (
    builtins.filter (proxy: proxy.type == "anytls") rendered.mihomoSelectiveTemplate.proxies
  );
  trustTunnel = builtins.head (
    builtins.filter (proxy: proxy.type == "trusttunnel") rendered.mihomoSelectiveTemplate.proxies
  );
  selector =
    tag: config: builtins.head (builtins.filter (outbound: outbound.tag == tag) config.outbounds);
  urlTests = config: builtins.filter (outbound: outbound.type == "urltest") config.outbounds;
  udpRejects =
    config:
    builtins.filter (
      rule: (rule.network or null) == "udp" && (rule.action or null) == "reject"
    ) config.route.rules;
  remoteRuleSets = config: builtins.filter (ruleSet: ruleSet.type == "remote") config.route.rule_set;
  indexOf =
    predicate: values:
    let
      go =
        index: remaining:
        if remaining == [ ] || predicate (builtins.head remaining) then
          index
        else
          go (index + 1) (builtins.tail remaining);
    in
    go 0 values;
  dnsIndex = indexOf (rule: (rule.action or null) == "hijack-dns") profile.route.rules;
  privateIndex = indexOf (
    rule:
    (rule.ip_cidr or [ ]) == [
      "10.0.0.0/8"
      "100.64.0.0/10"
      "127.0.0.0/8"
      "169.254.0.0/16"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "::1/128"
      "fc00::/7"
      "fe80::/10"
    ]
  ) profile.route.rules;
  tailnetResolveIndex = indexOf (
    rule:
    (rule.action or null) == "resolve" && (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
  ) profile.route.rules;
  tailnetDirectIndex = indexOf (
    rule:
    (rule.outbound or null) == "DIRECT" && (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
  ) profile.route.rules;
  fallbackResolveIndex = indexOf (
    rule: (rule.action or null) == "resolve" && !(rule ? domain) && !(rule ? domain_suffix)
  ) profile.route.rules;
  resolveRules = builtins.filter (rule: (rule.action or null) == "resolve") profile.route.rules;
  multicastIndex = indexOf (
    rule:
    (rule.ip_cidr or [ ]) == [
      "224.0.0.0/4"
      "ff00::/8"
    ]
  ) profile.route.rules;
  ipv6RejectIndex = indexOf (
    rule: (rule.ip_version or null) == 6 && (rule.action or null) == "reject"
  ) profile.route.rules;
  protectedProxyIndex = indexOf (
    rule: (rule.rule_set or [ ]) != [ ] && (rule.outbound or null) == manualGroup
  ) profile.route.rules;
  globalManualIndex = indexOf (
    rule: (rule.clash_mode or null) == "Global" && (rule.outbound or null) == manualGroup
  ) profile.route.rules;
  mihomoDirectIndex = indexOf (
    rule: lib.hasPrefix "IP-CIDR,10.0.0.0/8,DIRECT" rule
  ) rendered.mihomoSelectiveTemplate.rules;
  mihomoProtectedIndex = indexOf (
    rule: lib.hasPrefix "RULE-SET,secure_dns_domains," rule
  ) rendered.mihomoSelectiveTemplate.rules;
  mihomoDohNameserversFor =
    endpoints:
    map (
      endpoint: "https://${endpoint.domain}:${toString endpoint.port}${endpoint.path}#DIRECT"
    ) endpoints;
  mihomoBootstrapNameserversFor =
    endpoints:
    map (
      endpoint: "https://${endpoint.ipv4}:${toString endpoint.port}${endpoint.path}#DIRECT"
    ) endpoints;
  singBoxDohServersFor =
    endpoints:
    lib.imap0 (index: endpoint: {
      tag = "own-doh-${toString index}";
      type = "https";
      server = endpoint.ipv4;
      server_port = endpoint.port;
      inherit (endpoint) path;
      tls = {
        enabled = true;
        server_name = endpoint.domain;
      };
    }) endpoints;
  singBoxDohRulesFor =
    endpoints:
    lib.concatLists (
      lib.imap0 (
        index: _endpoint:
        let
          serverTag = "own-doh-${toString index}";
          responseTag = "${serverTag}-response";
        in
        [
          (
            {
              action = "evaluate";
              server = serverTag;
              tag = responseTag;
            }
            // lib.optionalAttrs (index > 0) { speculative = true; }
          )
          {
            match_response = responseTag;
            action = "respond";
            race = true;
          }
        ]
      ) endpoints
    );
  expectedMihomoDohNameservers = mihomoDohNameserversFor clientDnsEndpoints;
  expectedMihomoBootstrapNameservers = mihomoBootstrapNameserversFor clientDnsEndpoints;
  expectedSingBoxDohServers = singBoxDohServersFor clientDnsEndpoints;
  expectedSingBoxDohRules = singBoxDohRulesFor clientDnsEndpoints;
  expectedSingBoxFakeIpDomainRuleSets = [
    "secure_dns_domains"
    "ru_blocked_and_geoblocked_domains"
    "refilter_blocked_domains"
    "ai_domains"
    "github_domains"
  ];
  actualSingBoxDohServers = builtins.filter (server: server.type == "https") profile.dns.servers;
  customPortSingBoxDoh = builtins.elemAt actualSingBoxDohServers 2;
  fakeIpDnsRule = builtins.head profile.dns.rules;
  dnsRulesAfterFakeIp = builtins.tail profile.dns.rules;
  renderedDnsShapeFor =
    candidate: endpoints:
    let
      candidateProfile = candidate.profileJsonTemplate;
      httpsServers = builtins.filter (server: server.type == "https") candidateProfile.dns.servers;
      bootstrapHosts = lib.last candidateProfile.dns.servers;
      candidateFakeIpRule = builtins.head candidateProfile.dns.rules;
      candidateResolveRules = builtins.filter (
        rule: (rule.action or null) == "resolve"
      ) candidateProfile.route.rules;
    in
    candidate.mihomoSelectiveTemplate.dns.nameserver == mihomoDohNameserversFor endpoints
    &&
      candidate.mihomoSelectiveTemplate.dns."proxy-server-nameserver" == mihomoDohNameserversFor endpoints
    &&
      candidate.mihomoSelectiveTemplate.dns."default-nameserver"
      == mihomoBootstrapNameserversFor endpoints
    && httpsServers == singBoxDohServersFor endpoints
    && builtins.length candidateProfile.dns.servers == builtins.length endpoints + 2
    && (builtins.elemAt candidateProfile.dns.servers (builtins.length endpoints)).type == "fakeip"
    && bootstrapHosts.tag == "bootstrap-hosts"
    && bootstrapHosts.type == "hosts"
    && !(bootstrapHosts ? path)
    && builtins.all (endpoint: bootstrapHosts.predefined.${endpoint.domain} == endpoint.ipv4) endpoints
    && builtins.length candidateFakeIpRule.rules == 3
    &&
      builtins.head candidateFakeIpRule.rules == {
        query_type = [
          "A"
          "AAAA"
        ];
      }
    && (builtins.elemAt candidateFakeIpRule.rules 1).rule_set == expectedSingBoxFakeIpDomainRuleSets
    && builtins.any (
      rule: (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
    ) (lib.last candidateFakeIpRule.rules).rules
    &&
      builtins.tail candidateProfile.dns.rules
      == singBoxDohRulesFor endpoints ++ [ { action = "reject"; } ]
    && builtins.length candidateResolveRules == 3
    && builtins.all (rule: !(rule ? server)) candidateResolveRules
    && !(candidateProfile.dns ? final);
  oneDnsEndpoints = profileTypes.normalizeClientDnsEndpoints {
    clientDnsEndpoints = [
      {
        domain = "dns-one.example.invalid";
        ipv4 = "192.0.2.53";
      }
    ];
  };
  legacyDnsEndpoints = profileTypes.normalizeClientDnsEndpoints (
    builtins.removeAttrs publisherSettings [ "clientDnsEndpoints" ]
  );
  clientDnsRenderVariantResults = {
    oneEndpoint = renderedDnsShapeFor oneDnsRendered oneDnsEndpoints;
    omittedSettingUsesLegacyEndpoint = renderedDnsShapeFor legacyDnsRendered legacyDnsEndpoints;
  };
  clientDnsRenderVariantsContract = builtins.all (value: value) (
    builtins.attrValues clientDnsRenderVariantResults
  );
  visibleNames =
    map (proxy: proxy.name) rendered.mihomoSelectiveTemplate.proxies
    ++ map (outbound: outbound.tag) profile.outbounds
    ++ map (group: group.name) rendered.mihomoSelectiveTemplate."proxy-groups";
  namespaceResults = {
    ambiguousTuplesDistinct =
      profileTypes.providerNamespace {
        machine = "a-b";
        instanceId = "c";
      } != profileTypes.providerNamespace {
        machine = "a";
        instanceId = "b-c";
      };
    # Visible names are display names; secret placeholders keep the technical
    # machine/instance namespace.
    displayNames =
      vless.name == "🇱🇹 Литва · A · VLESS"
      && awg.name == "🇱🇹 Литва · A · AWG"
      && naive.tag == "🇱🇹 Литва · A · Naive"
      && mieru.name == "🇱🇹 Литва · A · Mieru"
      && anytls.name == "🇱🇹 Литва · A · AnyTLS"
      && trustTunnel.name == "🇱🇹 Литва · A · TrustTunnel"
      && singBoxAnytls.tag == anytls.name;
    technicalIdsAbsentFromVisibleNames = builtins.all (
      name:
      !(lib.hasInfix "vpn-fixture" name)
      && !(lib.hasInfix "cHJvYmU" name)
      && !(lib.hasInfix "vpn-mihomo" name)
      && !(lib.hasInfix "vpn-anytls" name)
      && !(lib.hasInfix "11-" name)
    ) visibleNames;
  };
  namespaceContract = builtins.all (value: value) (builtins.attrValues namespaceResults);
  mihomoContract =
    builtins.all (type: builtins.elem type mihomoTypes) [
      "vless"
      "wireguard"
      "mieru"
      "anytls"
      "trusttunnel"
    ]
    &&
      selectiveGroups == [
        manualGroup
        autoGroup
        "GLOBAL"
      ]
    && selectiveGlobal.type == "select"
    &&
      selectiveGlobal.proxies == [
        manualGroup
        autoGroup
      ]
    && rendered.mihomoSelectiveTemplate.mode == "rule"
    && !(rendered ? mihomoFullTemplate)
    && !(builtins.elem "DIRECT" selectiveManual.proxies)
    && !(builtins.elem "DIRECT" selectiveAuto.proxies)
    && !(builtins.elem "DIRECT" selectiveGlobal.proxies)
    && builtins.head selectiveManual.proxies == autoGroup
    && builtins.all (group: builtins.elem mieru.name group.proxies) [
      selectiveManual
      selectiveAuto
    ]
    && builtins.all (group: builtins.elem anytls.name group.proxies) [
      selectiveManual
      selectiveAuto
    ]
    && builtins.all (group: builtins.elem trustTunnel.name group.proxies) [
      selectiveManual
      selectiveAuto
    ]
    && builtins.elem awg.name selectiveManual.proxies
    && builtins.all (
      group: !(builtins.elem group.name legacyGroupNames)
    ) rendered.mihomoSelectiveTemplate."proxy-groups"
    && lib.last rendered.mihomoSelectiveTemplate.rules == "MATCH,DIRECT"
    && vless.uuid == "__MIHOMO_VLESS_UUID_11-vpn-fixture-22-vpn-mihomo-vless-xhttp__"
    && vless."reality-opts"."short-id" == "0123456789abcdef"
    && mieru.name == "🇱🇹 Литва · A · Mieru"
    && mieru.server == "192.0.2.13"
    && mieru.port == 8443
    && mieru.username == "cHJvYmU"
    && mieru.password == "__MIHOMO_MIERU_PASSWORD_11-vpn-fixture-9-vpn-mieru_cHJvYmU__"
    && mieru.transport == "TCP"
    && mieru.multiplexing == "MULTIPLEXING_LOW"
    && mieru."handshake-mode" == "HANDSHAKE_STANDARD"
    && mieru.udp
    && !(mieru ? "traffic-pattern")
    && !(mieru ? tls)
    && !(mieru ? sni)
    && anytls.name == "🇱🇹 Литва · A · AnyTLS"
    && anytls.server == "anytls.example.invalid"
    && anytls.port == 9443
    && anytls.password == "__MIHOMO_ANYTLS_PASSWORD_11-vpn-fixture-10-vpn-anytls_cHJvYmU__"
    && anytls.udp
    && anytls.sni == "anytls.example.invalid"
    && !anytls."skip-cert-verify"
    && !(anytls ? username)
    && !(anytls ? tls)
    && !(anytls ? "client-fingerprint")
    && !(anytls ? "client-metadata")
    && !(anytls ? "idle-session-check-interval")
    && !(anytls ? "idle-session-timeout")
    && !(anytls ? "min-idle-session")
    && trustTunnel.name == "🇱🇹 Литва · A · TrustTunnel"
    && trustTunnel.server == "192.0.2.15"
    && trustTunnel.port == 10443
    && trustTunnel.username == "cHJvYmU"
    &&
      trustTunnel.password == "__MIHOMO_TRUSTTUNNEL_PASSWORD_11-vpn-fixture-15-vpn-trusttunnel_cHJvYmU__"
    && trustTunnel.sni == "trusttunnel.example.invalid"
    && !trustTunnel."skip-cert-verify"
    && trustTunnel."client-fingerprint" == "chrome"
    && !trustTunnel.quic
    && trustTunnel.udp
    && !(trustTunnel ? alpn)
    && !(trustTunnel ? "health-check")
    && !(trustTunnel ? "max-connections")
    && !(trustTunnel ? "min-streams")
    && !(trustTunnel ? "max-streams")
    && awg."private-key" == "__MIHOMO_AMNEZIAWG_PRIVATE_KEY_11-vpn-fixture-13-vpn-amneziawg__"
    && awg."amnezia-wg-option".version == 3
    &&
      awg."amnezia-wg-option"."header-protection-key"
      == "__MIHOMO_AMNEZIAWG_HEADER_PROTECTION_KEY_11-vpn-fixture-13-vpn-amneziawg_cHJvYmU__"
    && rendered.mihomoSelectiveTemplate.dns.nameserver == expectedMihomoDohNameservers
    && rendered.mihomoSelectiveTemplate.dns."proxy-server-nameserver" == expectedMihomoDohNameservers
    && rendered.mihomoSelectiveTemplate.dns."default-nameserver" == expectedMihomoBootstrapNameservers
    && builtins.all (
      endpoint: rendered.mihomoSelectiveTemplate.hosts.${endpoint.domain} == endpoint.ipv4
    ) clientDnsEndpoints
    && mihomoDirectIndex < mihomoProtectedIndex;
  singBoxContract =
    rendered.publishProfileJson
    && profile.experimental.cache_file == expectedSingBoxCacheFile
    && profile.experimental.clash_api.default_mode == "Rule"
    && builtins.length naiveOutbounds == 1
    && naive.server == "192.0.2.10"
    && naive.server_port == 443
    && naive.username == "cHJvYmU"
    && naive.insecure_concurrency == 0
    && !naive.udp_over_tcp
    && !naive.quic
    && naive.tls.enabled
    && naive.tls.server_name == "site.example.invalid"
    && singBoxAnytls.type == "anytls"
    && singBoxAnytls.server == "192.0.2.14"
    && singBoxAnytls.server_port == 9443
    && singBoxAnytls.password == "__PROFILE_ANYTLS_PASSWORD_11-vpn-fixture-10-vpn-anytls_cHJvYmU__"
    &&
      singBoxAnytls.tls == {
        enabled = true;
        server_name = "anytls.example.invalid";
        insecure = false;
        min_version = "1.3";
        max_version = "1.3";
      }
    && !(singBoxAnytls ? username)
    && !(singBoxAnytls ? udp_over_tcp)
    && !(singBoxAnytls ? client_metadata)
    && !(singBoxAnytls ? idle_session_check_interval)
    && !(singBoxAnytls ? idle_session_timeout)
    && !(singBoxAnytls ? min_idle_session)
    && builtins.all (outbound: outbound.type != "trusttunnel") profile.outbounds
    && (selector manualGroup profile).type == "selector"
    && (selector manualGroup profile).default == autoGroup
    &&
      (selector manualGroup profile).outbounds == [
        autoGroup
        naive.tag
        anytls.name
      ]
    && (selector autoGroup profile).type == "urltest"
    && builtins.length (urlTests profile) == 1
    && !(builtins.elem "DIRECT" (selector manualGroup profile).outbounds)
    && !(builtins.elem "DIRECT" (selector autoGroup profile).outbounds)
    &&
      (selector autoGroup profile).outbounds == [
        naive.tag
        anytls.name
      ]
    # Only Ручной and Авто are client groups: no FULL, UDP or *-AUTO variants.
    && builtins.all (outbound: !(builtins.elem outbound.tag legacyGroupNames)) profile.outbounds
    &&
      lib.sort builtins.lessThan (
        map (outbound: outbound.tag) (
          builtins.filter (
            outbound:
            builtins.elem outbound.type [
              "selector"
              "urltest"
            ]
          ) profile.outbounds
        )
      ) == lib.sort builtins.lessThan [
        manualGroup
        autoGroup
      ]
    && builtins.all (
      ruleSet:
      !(ruleSet ? download_detour)
      && !(ruleSet.http_client ? detour)
      && ruleSet.http_client.domain_resolver.server == "bootstrap-hosts"
      && ruleSet.http_client.tls.server_name == publisherSettings.configGatewayDomain
    ) (remoteRuleSets profile);
  fakeIpPersistenceResults = {
    generatedCacheFileExact = profile.experimental.cache_file == expectedSingBoxCacheFile;
    stableAcrossProfileRefreshInputs =
      builtins.all
        (candidate: candidate.profileJsonTemplate.experimental.cache_file == expectedSingBoxCacheFile)
        [
          oneDnsRendered
          legacyDnsRendered
          zeroNaiveRendered
        ];
  };
  fakeIpPersistenceContract = builtins.all (value: value) (
    builtins.attrValues fakeIpPersistenceResults
  );
  routeContract =
    udpRejects profile == [ ]
    && builtins.length resolveRules == 3
    && privateIndex < tailnetResolveIndex
    && multicastIndex < tailnetResolveIndex
    && tailnetResolveIndex < globalManualIndex
    && tailnetDirectIndex < ipv6RejectIndex
    && ipv6RejectIndex < globalManualIndex
    && tailnetDirectIndex == tailnetResolveIndex + 1
    && protectedProxyIndex < fallbackResolveIndex
    && builtins.all (rule: !(rule ? server) && rule.strategy == "ipv4_only") resolveRules
    &&
      profile.route.default_domain_resolver == {
        server = "bootstrap-hosts";
        strategy = "ipv4_only";
      }
    && builtins.elemAt profile.route.rules (fallbackResolveIndex + 1) == { outbound = "DIRECT"; }
    && dnsIndex < protectedProxyIndex
    && privateIndex < protectedProxyIndex
    && multicastIndex < protectedProxyIndex
    && privateIndex < globalManualIndex
    && globalManualIndex >= 0
    && globalManualIndex < protectedProxyIndex
    # Clash Global mode selects Ручной; no UDP-specific rule can send protected
    # traffic to DIRECT.
    &&
      builtins.length (builtins.filter (rule: (rule.clash_mode or null) == "Global") profile.route.rules)
      == 1
    && !(builtins.any (rule: (rule.network or null) == "udp") profile.route.rules)
    && builtins.all (rule: !(rule ? port)) (udpRejects profile);
  dnsContract =
    actualSingBoxDohServers == expectedSingBoxDohServers
    && customPortSingBoxDoh.server == "203.0.113.53"
    && customPortSingBoxDoh.server_port == 8443
    && customPortSingBoxDoh.path == "/fixture-dns-query"
    && customPortSingBoxDoh.tls.server_name == "dns-c.example.invalid"
    && !(customPortSingBoxDoh ? headers)
    && builtins.length profile.dns.servers == builtins.length expectedSingBoxDohServers + 2
    &&
      builtins.elemAt profile.dns.servers (builtins.length expectedSingBoxDohServers) == {
        tag = "fakeip";
        type = "fakeip";
        inet4_range = "198.18.0.0/15";
      }
    && (lib.last profile.dns.servers).tag == "bootstrap-hosts"
    && (lib.last profile.dns.servers).type == "hosts"
    && !((lib.last profile.dns.servers) ? path)
    && builtins.all (
      endpoint: (lib.last profile.dns.servers).predefined.${endpoint.domain} == endpoint.ipv4
    ) clientDnsEndpoints
    && fakeIpDnsRule.type == "logical"
    && fakeIpDnsRule.mode == "and"
    && fakeIpDnsRule.action == "route"
    && fakeIpDnsRule.server == "fakeip"
    && builtins.length fakeIpDnsRule.rules == 3
    &&
      builtins.head fakeIpDnsRule.rules == {
        query_type = [
          "A"
          "AAAA"
        ];
      }
    && (builtins.elemAt fakeIpDnsRule.rules 1).rule_set == expectedSingBoxFakeIpDomainRuleSets
    && (lib.last fakeIpDnsRule.rules).invert
    && builtins.any (
      rule: (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
    ) (lib.last fakeIpDnsRule.rules).rules
    && builtins.any (
      rule:
      (rule.domain_suffix or [ ]) == [
        "ts.net"
        "ru"
      ]
    ) (lib.last fakeIpDnsRule.rules).rules
    && dnsRulesAfterFakeIp == expectedSingBoxDohRules ++ [ { action = "reject"; } ]
    && (builtins.elemAt profile.dns.rules ((builtins.length profile.dns.rules) - 1)).action == "reject"
    && !(profile.dns ? final);
  zeroNaiveResults = {
    publicationUnitPresent = builtins.hasAttr publicationUnitName zeroNaiveMachine.systemd.services;
    mihomoLinksRetained =
      lib.hasInfix "/mihomo.yaml" zeroNaivePublicationScript
      && !(lib.hasInfix "mihomo-full" zeroNaivePublicationScript);
    anytlsProfileLinkRetained = lib.hasInfix "/profile.json" zeroNaivePublicationScript;
    anytlsPublicationEnabled = zeroNaiveRendered.publishProfileJson;
    anytlsTemplateRetained = zeroNaiveRendered.profileJsonTemplate != null;
    manifestIncludesProfileJson =
      map (artifact: artifact.outputName) zeroNaiveArtifacts == [
        "mihomo.yaml"
        "profile.json"
      ];
  };
  zeroNaiveContract = builtins.all (value: value) (builtins.attrValues zeroNaiveResults);
  negativeResults = {
    inherit unknownAccountRejected emptyMappingRejected sharedAccountRejected;
    inherit
      conflictingDnsPinCaseRejected
      deadPublisherCredentialRejected
      duplicatePublisherDomainCaseRejected
      duplicatePublisherDomainRejected
      duplicatePublisherRuntimeIdentityRejected
      duplicateProfileRejected
      duplicateProviderRefRejected
      missingCredentialRejected
      pathTokenCredentialSecretRejected
      unknownProfileRejected
      ;
    tokenLengthValidationPresent = lib.hasInfix "wc -c" publicationScript;
    tokenPatternValidationPresent = lib.hasInfix "^[A-Za-z0-9_-]{32,128}$" publicationScript;
    base64urlCredentialValidationPresent = lib.hasInfix "^[A-Za-z0-9_-]+$" publicationScript;
    base64urlCredentialLengthValidationPresent = lib.hasInfix "value_count\" -gt 64" publicationScript;
    generatedTemporaryReferencesExpanded =
      lib.hasInfix ("> \"" + "$" + "{binding_") publicationScript
      && lib.hasInfix "--rawfile binding_" publicationScript
      && lib.hasInfix ("\"" + "$" + "{binding_") publicationScript
      && lib.hasInfix ("cp \"" + "$" + "{artifact_") publicationScript
      && lib.hasInfix ("yq -P -o=yaml '.' \"" + "$" + "{artifact_") publicationScript
      && !(lib.hasInfix ("$" + "$" + "{record.fileVariable}") publicationScript)
      && !(lib.hasInfix ("$" + "$" + "{record.valueVariable}") publicationScript)
      && !(lib.hasInfix ("$" + "$" + "{jsonVariable}") publicationScript)
      && !(lib.hasInfix ("$" + "$" + "{outputVariable}") publicationScript);
    explicitMieruCredentialBinding =
      lib.sort builtins.lessThan consumerMachine.sops.secrets."fixture-mieru-password".restartUnits
      == lib.sort builtins.lessThan [
        "mita.service"
        "${publicationUnitName}.service"
      ]
      && lib.hasInfix consumerMachine.sops.secrets."fixture-mieru-password".path publicationScript;
    explicitAnytlsCredentialBinding =
      lib.sort builtins.lessThan consumerMachine.sops.secrets."fixture-anytls-password".restartUnits
      == lib.sort builtins.lessThan [
        "sing-box.service"
        "${publicationUnitName}.service"
      ]
      && lib.hasInfix consumerMachine.sops.secrets."fixture-anytls-password".path publicationScript;
    explicitTrustTunnelCredentialBinding =
      lib.sort builtins.lessThan consumerMachine.sops.secrets."fixture-trusttunnel-password".restartUnits
      == lib.sort builtins.lessThan [
        "trusttunnel.service"
        "${publicationUnitName}.service"
      ]
      && lib.hasInfix consumerMachine.sops.secrets."fixture-trusttunnel-password".path publicationScript;
    explicitAwgClientKeyBinding =
      consumerMachine.sops.secrets."fixture-awg-client-private-key".restartUnits
      == [ "${publicationUnitName}.service" ]
      &&
        lib.hasInfix consumerMachine.sops.secrets."fixture-awg-client-private-key".path
          publicationScript;
  };
  negativeContract = builtins.all (value: value) (builtins.attrValues negativeResults);
  contract =
    sameCanonicalContract
    && clientDnsContract
    && migrationContract
    && clientPolicyContract
    && fakeIpPersistenceContract
    && clientDnsRenderVariantsContract
    && mihomoContract
    && vlessClientPolicyContract
    && mieruExportContract
    && singBoxContract
    && routeContract
    && dnsContract
    && namespaceContract
    && manifestContract
    && zeroNaiveContract
    && disjointPublisherContract
    && negativeContract;
in
if !contract then
  throw "Pure client renderer contract failed: ${
    builtins.toJSON {
      inherit
        sameCanonicalContract
        sameCanonicalResults
        vlessClientPolicyContract
        clientDnsContract
        clientDnsRenderVariantResults
        clientDnsRenderVariantsContract
        clientDnsResults
        clientPolicyContract
        clientPolicyResults
        dnsContract
        fakeIpPersistenceContract
        fakeIpPersistenceResults
        disjointPublisherContract
        disjointPublisherResults
        mihomoContract
        migrationContract
        migrationResults
        manifestContract
        manifestResults
        mieruContractResults
        mieruExportContract
        namespaceContract
        namespaceResults
        negativeContract
        negativeResults
        routeContract
        singBoxContract
        zeroNaiveContract
        zeroNaiveResults
        ;
    }
  }"
else
  {
    all = true;
    inherit
      sameCanonicalContract
      sameCanonicalResults
      vlessClientPolicyContract
      clientDnsContract
      clientDnsRenderVariantResults
      clientDnsRenderVariantsContract
      clientDnsResults
      dnsContract
      fakeIpPersistenceContract
      fakeIpPersistenceResults
      disjointPublisherContract
      disjointPublisherResults
      mihomoContract
      migrationContract
      migrationResults
      manifestContract
      manifestResults
      mieruContractResults
      mieruExportContract
      namespaceContract
      namespaceResults
      negativeContract
      negativeResults
      routeContract
      singBoxContract
      zeroNaiveContract
      zeroNaiveResults
      ;
  }
