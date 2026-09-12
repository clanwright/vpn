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
    "edge-wildcard-certificate"
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
  zeroNaiveOverrides = {
    vpn-client-profiles = {
      roles.publisher.machines.vpn-fixture.settings.providerRefs = builtins.filter (
        ref: ref.protocol != "naiveproxy"
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
  publisherWithExactSettings =
    settings:
    let
      instance = fixture.instances.vpn-client-profiles;
      role = instance.roles.publisher;
      machine = role.machines.${fixtureMachineName};
    in
    fixture.instances
    // {
      vpn-client-profiles = instance // {
        roles.publisher = role // {
          machines.${fixtureMachineName} = machine // {
            inherit settings;
          };
        };
      };
    };
  renderedWithSettings =
    name: settings:
    let
      candidate = evaluateInstances name (publisherWithExactSettings settings);
    in
    builtins.head candidate.machine.clanwright.vpn.publisherRenders.vpn-client-profiles;
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
    localMachineName: secretPrefix: configGatewayDomain:
    publisherSettings
    // {
      inherit localMachineName secretPrefix configGatewayDomain;
      profileLinks = map (
        link:
        link
        // {
          pathTokenSecretName = "mihomo-client-${secretPrefix}-${link.name}-path-token";
          accountDomain = configGatewayDomain;
        }
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
  unknownProfileRejected = rejectsInstances "unknown-profile" (
    publisherWith (
      publisherSettings
      // {
        providerRefs = [
          ((builtins.head publisherSettings.providerRefs) // { profileNames = [ "unknown-profile" ]; })
        ];
      }
    )
  );
  duplicateProfileRejected = rejectsInstances "duplicate-profile" (
    publisherWith (
      publisherSettings // { profiles = publisherSettings.profiles ++ publisherSettings.profiles; }
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
      protocol = "mieru";
      consumerInstanceId = "vpn-client-profiles";
      exports.selected.vpnProvider = raw;
      selectExports = _predicate: exports: exports;
    };
  validMieruExport = {
    schemaVersion = 2;
    instanceId = "vpn-mieru";
    machine = fixtureMachineName;
    role = "gateway";
    protocol = "mieru";
    enabled = true;
    endpoint = {
      domain = null;
      ipv4 = "192.0.2.13";
      port = 8443;
      transport = "tcp";
    };
    transportMetadata = {
      protocol = "mieru";
      userNames = [ "cHJvYmU" ];
      credentialEncoding = "base64url";
    };
    profileNames = [ "cHJvYmU" ];
    secretNames.users.cHJvYmU = "fixture-mieru-password";
  };
  evalProviderExportType =
    raw:
    (lib.evalModules {
      modules = [
        {
          options.value = lib.mkOption {
            type = lib.types.submodule vpnExports.vpnProviderModule;
          };
          config.value = raw;
        }
      ];
    }).config.value;
  validNaiveExport = {
    schemaVersion = 2;
    instanceId = "vpn-naiveproxy";
    machine = fixtureMachineName;
    role = "addon";
    protocol = "naiveproxy";
    enabled = true;
    endpoint = {
      domain = "site.example.invalid";
      ipv4 = "192.0.2.10";
      port = 443;
      transport = "tcp";
    };
    transportMetadata = {
      protocol = "naiveproxy";
      tlsServerName = "site.example.invalid";
      userNames = [ "cHJvYmU" ];
      port = 443;
    };
    profileNames = [ "cHJvYmU" ];
    secretNames.password.cHJvYmU = "fixture-naive-password";
  };
  rejectsMieruExport =
    raw: !(builtins.tryEval (builtins.deepSeq (selectMieruExport raw) true)).success;
  mieruContractResults = {
    typeAcceptsDomainFreeMieru = (evalProviderExportType validMieruExport).endpoint.domain == null;
    typeRejectsDomainFreeExistingProtocol =
      !(builtins.tryEval (
        builtins.deepSeq (evalProviderExportType (
          lib.recursiveUpdate validNaiveExport { endpoint.domain = null; }
        )) true
      )).success;
    validDomainFreeExportAccepted =
      (selectMieruExport validMieruExport).endpoint == validMieruExport.endpoint;
    domainRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { endpoint.domain = "mieru.example.invalid"; }
    );
    invalidIpv4Rejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { endpoint.ipv4 = "192.0.2.999"; }
    );
    udpTransportRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { endpoint.transport = "udp"; }
    );
    unknownEndpointFieldRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { endpoint.serverName = "example.invalid"; }
    );
    unknownMetadataRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { transportMetadata.sni = "example.invalid"; }
    );
    unknownSecretFieldRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { secretNames.password.cHJvYmU = "unexpected-secret"; }
    );
    mismatchedUserNamesRejected = rejectsMieruExport (
      lib.recursiveUpdate validMieruExport { transportMetadata.userNames = [ "other" ]; }
    );
  };
  mieruExportContract = builtins.all (value: value) (builtins.attrValues mieruContractResults);
  conflictingDnsPinCaseRejected = rejectsInstances "conflicting-dns-pin-case" (
    publisherWith (
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
    )
  );
  consumerMachine = consumer.config.nixosConfigurations.${fixtureMachineName}.config;
  rendered = builtins.head consumerMachine.clanwright.vpn.publisherRenders.vpn-client-profiles;
  manifest = consumerMachine.clanwright.vpn.publisherManifests.vpn-client-profiles;
  manifestProfile = builtins.head manifest.profiles;
  manifestArtifacts = manifestProfile.artifacts;
  artifactByOutput =
    outputName:
    builtins.head (builtins.filter (artifact: artifact.outputName == outputName) manifestArtifacts);
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
  publicationPhaseIds = map (phase: phase.id) manifest.publicationPhases;
  phaseIndex = id: indexOf (candidate: candidate == id) publicationPhaseIds;
  allAssetRefs = lib.unique (lib.concatMap (artifact: artifact.assetRefs) manifestArtifacts);
  manifestAssets = builtins.attrValues manifest.assetCatalog;
  manifestResults = {
    schemaVersion = manifest.schemaVersion == 1;
    profileIdentity =
      map (profileEntry: profileEntry.name) manifest.profiles == [ "cHJvYmU" ]
      &&
        manifestProfile.pathTokenBinding == {
          secretName = "mihomo-client-fixture-cHJvYmU-path-token";
          decoding = "path-token";
        };
    artifactOutputs =
      map (artifact: artifact.outputName) manifestArtifacts == [
        "mihomo.yaml"
        "mihomo-full.yaml"
        "profile.json"
      ];
    actualTemplatesRetained =
      (artifactByOutput "mihomo.yaml").template == rendered.mihomoSelectiveTemplate
      && (artifactByOutput "mihomo-full.yaml").template == rendered.mihomoFullTemplate
      && (artifactByOutput "profile.json").template == rendered.profileJsonTemplate;
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
    canonicalAndLegacyAssetRoutesExposed =
      let
        routeConfig = consumerMachine.clanwright.vpn.publishers.vpn-client-profiles.routeConfig;
        publicPaths = lib.concatMap (asset: [ asset.publicPath ] ++ asset.legacyPublicPaths) manifestAssets;
      in
      publicPaths == lib.unique publicPaths
      && builtins.all (path: lib.hasInfix "handle ${path} {" routeConfig) publicPaths;
    assetCatalogClosed =
      builtins.all (
        asset:
        builtins.elem asset.validator [
          "nonempty"
          "mrs-domain"
          "mrs-ipcidr"
          "srs"
        ]
        && builtins.isList asset.legacyPublicPaths
        && asset.legacyPublicPaths == lib.unique asset.legacyPublicPaths
        && !(builtins.elem asset.publicPath asset.legacyPublicPaths)
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
        lib.concatMap (asset: [ asset.publicPath ] ++ asset.legacyPublicPaths) manifestAssets == lib.unique
          (lib.concatMap (asset: [ asset.publicPath ] ++ asset.legacyPublicPaths) manifestAssets)
      &&
        map (asset: asset.routePriority) manifestAssets
        == lib.unique (map (asset: asset.routePriority) manifestAssets);
    publishedPhasesMatchManifest =
      consumerMachine.clanwright.vpn.publisherPublicationPhases.vpn-client-profiles
      == manifest.publicationPhases;
    publicationPhasesOrdered =
      manifest.publicationPhases == [
        {
          id = "revoke-current";
          prerequisites = [ ];
        }
        {
          id = "sync-local-assets";
          prerequisites = [ "revoke-current" ];
        }
        {
          id = "check-assets";
          prerequisites = [ "sync-local-assets" ];
        }
        {
          id = "prepare-generation";
          prerequisites = [ "check-assets" ];
        }
        {
          id = "render-artifacts";
          prerequisites = [ "prepare-generation" ];
        }
        {
          id = "finalize-links";
          prerequisites = [ "render-artifacts" ];
        }
        {
          id = "seal-generation";
          prerequisites = [ "finalize-links" ];
        }
        {
          id = "expose-generation";
          prerequisites = [ "seal-generation" ];
        }
        {
          id = "retire-old-generations";
          prerequisites = [ "expose-generation" ];
        }
        {
          id = "cleanup-private-temporaries";
          prerequisites = [ "retire-old-generations" ];
        }
      ]
      && builtins.all (
        phase:
        builtins.all (prerequisite: phaseIndex prerequisite < phaseIndex phase.id) phase.prerequisites
      ) manifest.publicationPhases;
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
  zeroNaiveRendered = builtins.head zeroNaiveMachine.clanwright.vpn.publisherRenders.vpn-client-profiles;
  zeroNaiveManifest = zeroNaiveMachine.clanwright.vpn.publisherManifests.vpn-client-profiles;
  zeroNaiveArtifacts = (builtins.head zeroNaiveManifest.profiles).artifacts;
  zeroNaivePublicationScript = zeroNaiveMachine.systemd.services.${publicationUnitName}.script;
  publicationScript = consumerMachine.systemd.services.${publicationUnitName}.script;
  mihomoTypes = map (proxy: proxy.type) rendered.mihomoSelectiveTemplate.proxies;
  selectiveGroups = map (group: group.name) rendered.mihomoSelectiveTemplate."proxy-groups";
  fullGroups = map (group: group.name) rendered.mihomoFullTemplate."proxy-groups";
  selectiveManual = builtins.head (
    builtins.filter (group: group.name == "SELECTIVE") rendered.mihomoSelectiveTemplate."proxy-groups"
  );
  selectiveAuto = builtins.head (
    builtins.filter (
      group: group.name == "SELECTIVE-AUTO"
    ) rendered.mihomoSelectiveTemplate."proxy-groups"
  );
  fullManual = builtins.head (
    builtins.filter (group: group.name == "FULL") rendered.mihomoFullTemplate."proxy-groups"
  );
  fullAuto = builtins.head (
    builtins.filter (group: group.name == "FULL-AUTO") rendered.mihomoFullTemplate."proxy-groups"
  );
  profile = rendered.profileJsonTemplate;
  clientDnsEndpoints = profileTypes.normalizeClientDnsEndpoints publisherSettings;
  naiveOutbounds = builtins.filter (outbound: outbound.type == "naive") profile.outbounds;
  naive = builtins.head naiveOutbounds;
  singBoxHysteria = selector hysteria.name profile;
  singBoxAnytls = selector anytls.name profile;
  vless = builtins.head (
    builtins.filter (proxy: proxy.type == "vless") rendered.mihomoSelectiveTemplate.proxies
  );
  hysteria = builtins.head (
    builtins.filter (proxy: proxy.type == "hysteria2") rendered.mihomoSelectiveTemplate.proxies
  );
  awg = builtins.head (
    builtins.filter (proxy: proxy.type == "wireguard") rendered.mihomoSelectiveTemplate.proxies
  );
  mieru = builtins.head (
    builtins.filter (proxy: proxy.type == "mieru") rendered.mihomoSelectiveTemplate.proxies
  );
  anytls = builtins.head (
    builtins.filter (proxy: proxy.type == "anytls") rendered.mihomoSelectiveTemplate.proxies
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
    rule: (rule.action or null) == "resolve" && !(rule ? domain)
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
  protectedUdpIndex = indexOf (
    rule:
    (rule.network or null) == "udp" && (rule.rule_set or [ ]) != [ ] && (rule.outbound or null) == "UDP"
  ) profile.route.rules;
  protectedProxyIndex = indexOf (
    rule: (rule.rule_set or [ ]) != [ ] && (rule.outbound or null) == "SELECTIVE"
  ) profile.route.rules;
  globalUdpIndex = indexOf (
    rule:
    (rule.clash_mode or null) == "Global"
    && (rule.network or null) == "udp"
    && (rule.outbound or null) == "UDP"
  ) profile.route.rules;
  globalFullIndex = indexOf (
    rule: (rule.clash_mode or null) == "Global" && (rule.outbound or null) == "FULL"
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
    && builtins.any (
      rule: (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
    ) (lib.last candidateFakeIpRule.rules).rules
    &&
      builtins.tail candidateProfile.dns.rules
      == singBoxDohRulesFor endpoints ++ [ { action = "reject"; } ]
    && builtins.length candidateResolveRules == 2
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
  namespaceResults = {
    ambiguousTuplesDistinct =
      profileTypes.providerNamespace {
        machine = "a-b";
        instanceId = "c";
      } != profileTypes.providerNamespace {
        machine = "a";
        instanceId = "b-c";
      };
    canonicalTags =
      vless.name == "11-vpn-fixture-22-vpn-mihomo-vless-xhttp-cHJvYmU-vless"
      && hysteria.name == "11-vpn-fixture-20-vpn-mihomo-hysteria2-cHJvYmU-hysteria2"
      && awg.name == "11-vpn-fixture-13-vpn-amneziawg-cHJvYmU-amneziawg"
      && naive.tag == "11-vpn-fixture-14-vpn-naiveproxy-cHJvYmU-edge";
  };
  namespaceContract = builtins.all (value: value) (builtins.attrValues namespaceResults);
  mihomoContract =
    builtins.all (type: builtins.elem type mihomoTypes) [
      "vless"
      "hysteria2"
      "wireguard"
      "mieru"
      "anytls"
    ]
    &&
      selectiveGroups == [
        "SELECTIVE"
        "SELECTIVE-AUTO"
        "UDP"
        "UDP-AUTO"
      ]
    &&
      fullGroups == [
        "FULL"
        "FULL-AUTO"
        "UDP"
        "UDP-AUTO"
      ]
    && rendered.mihomoSelectiveTemplate.mode == "rule"
    && rendered.mihomoFullTemplate.mode == "rule"
    && !(builtins.elem "DIRECT" selectiveManual.proxies)
    && !(builtins.elem "DIRECT" selectiveAuto.proxies)
    && !(builtins.elem "DIRECT" fullManual.proxies)
    && !(builtins.elem "DIRECT" fullAuto.proxies)
    && builtins.all (group: builtins.elem mieru.name group.proxies) [
      selectiveManual
      selectiveAuto
      fullManual
      fullAuto
    ]
    && builtins.all (group: builtins.elem anytls.name group.proxies) [
      selectiveManual
      selectiveAuto
      fullManual
      fullAuto
    ]
    && lib.last rendered.mihomoSelectiveTemplate.rules == "MATCH,DIRECT"
    && lib.last rendered.mihomoFullTemplate.rules == "MATCH,FULL"
    && vless.uuid == "__MIHOMO_VLESS_UUID_11-vpn-fixture-22-vpn-mihomo-vless-xhttp__"
    && vless."reality-opts"."short-id" == "0123456789abcdef"
    && hysteria."obfs-min-packet-size" == 512
    && hysteria."obfs-max-packet-size" == 1200
    && hysteria.password == "__MIHOMO_HY2_PASSWORD_11-vpn-fixture-20-vpn-mihomo-hysteria2_cHJvYmU__"
    && mieru.name == "11-vpn-fixture-9-vpn-mieru-cHJvYmU-mieru"
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
    && anytls.name == "11-vpn-fixture-10-vpn-anytls-cHJvYmU-anytls"
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
    && awg."private-key" == "__MIHOMO_AMNEZIAWG_PRIVATE_KEY_11-vpn-fixture-13-vpn-amneziawg__"
    && awg."amnezia-wg-option".version == 3
    &&
      awg."amnezia-wg-option"."header-protection-key"
      == "__MIHOMO_AMNEZIAWG_HEADER_PROTECTION_KEY_11-vpn-fixture-13-vpn-amneziawg_cHJvYmU__"
    && rendered.mihomoSelectiveTemplate.dns.nameserver == expectedMihomoDohNameservers
    && rendered.mihomoSelectiveTemplate.dns."proxy-server-nameserver" == expectedMihomoDohNameservers
    && rendered.mihomoSelectiveTemplate.dns."default-nameserver" == expectedMihomoBootstrapNameservers
    && rendered.mihomoFullTemplate.dns.nameserver == expectedMihomoDohNameservers
    && rendered.mihomoFullTemplate.dns."proxy-server-nameserver" == expectedMihomoDohNameservers
    && rendered.mihomoFullTemplate.dns."default-nameserver" == expectedMihomoBootstrapNameservers
    && builtins.all (
      endpoint:
      rendered.mihomoSelectiveTemplate.hosts.${endpoint.domain} == endpoint.ipv4
      && rendered.mihomoFullTemplate.hosts.${endpoint.domain} == endpoint.ipv4
    ) clientDnsEndpoints
    && mihomoDirectIndex < mihomoProtectedIndex;
  singBoxContract =
    rendered.publishProfileJson
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
    && singBoxHysteria.type == "hysteria2"
    && singBoxHysteria.obfs.type == "gecko"
    && singBoxHysteria.obfs.min_packet_size == 512
    && singBoxHysteria.obfs.max_packet_size == 1200
    && singBoxHysteria.tls.enabled
    && !singBoxHysteria.tls.insecure
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
    && (selector "SELECTIVE" profile).default == "SELECTIVE-AUTO"
    &&
      (selector "SELECTIVE" profile).outbounds == [
        "SELECTIVE-AUTO"
        naive.tag
        hysteria.name
        anytls.name
      ]
    && (selector "FULL" profile).default == "FULL-AUTO"
    &&
      (selector "FULL" profile).outbounds == [
        "FULL-AUTO"
        naive.tag
        hysteria.name
        anytls.name
      ]
    && builtins.length (urlTests profile) == 3
    && !(builtins.elem "DIRECT" (selector "SELECTIVE" profile).outbounds)
    && !(builtins.elem "DIRECT" (selector "FULL" profile).outbounds)
    &&
      (selector "SELECTIVE-AUTO" profile).outbounds == [
        naive.tag
        hysteria.name
        anytls.name
      ]
    &&
      (selector "FULL-AUTO" profile).outbounds == [
        naive.tag
        hysteria.name
        anytls.name
      ]
    &&
      (selector "UDP" profile).outbounds == [
        "UDP-AUTO"
        hysteria.name
        anytls.name
      ]
    &&
      (selector "UDP-AUTO" profile).outbounds == [
        hysteria.name
        anytls.name
      ]
    && builtins.all (
      ruleSet:
      !(ruleSet ? download_detour)
      && !(ruleSet.http_client ? detour)
      && ruleSet.http_client.domain_resolver.server == "bootstrap-hosts"
      && ruleSet.http_client.tls.server_name == publisherSettings.configGatewayDomain
    ) (remoteRuleSets profile);
  routeContract =
    udpRejects profile == [ ]
    && builtins.length resolveRules == 2
    && privateIndex < tailnetResolveIndex
    && multicastIndex < tailnetResolveIndex
    && tailnetResolveIndex < globalUdpIndex
    && tailnetDirectIndex < ipv6RejectIndex
    && ipv6RejectIndex < globalUdpIndex
    && tailnetDirectIndex == tailnetResolveIndex + 1
    && protectedProxyIndex < fallbackResolveIndex
    && builtins.all (rule: !(rule ? server) && rule.strategy == "ipv4_only") resolveRules
    &&
      profile.route.default_domain_resolver == {
        server = "bootstrap-hosts";
        strategy = "ipv4_only";
      }
    && builtins.elemAt profile.route.rules (fallbackResolveIndex + 1) == { outbound = "DIRECT"; }
    && dnsIndex < protectedUdpIndex
    && privateIndex < protectedUdpIndex
    && multicastIndex < protectedUdpIndex
    && privateIndex < globalUdpIndex
    && globalUdpIndex < globalFullIndex
    && protectedUdpIndex < protectedProxyIndex
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
    && (builtins.head fakeIpDnsRule.rules).rule_set != [ ]
    && (lib.last fakeIpDnsRule.rules).invert
    && builtins.any (
      rule: (rule.domain or [ ]) == publisherSettings.tailnetAdminDomains
    ) (lib.last fakeIpDnsRule.rules).rules
    &&
      builtins.any (rule: (rule.domain_suffix or [ ]) == [ "ts.net" ])
        (lib.last fakeIpDnsRule.rules).rules
    && dnsRulesAfterFakeIp == expectedSingBoxDohRules ++ [ { action = "reject"; } ]
    && (builtins.elemAt profile.dns.rules ((builtins.length profile.dns.rules) - 1)).action == "reject"
    && !(profile.dns ? final);
  zeroNaiveResults = {
    publicationUnitPresent = builtins.hasAttr publicationUnitName zeroNaiveMachine.systemd.services;
    mihomoLinksRetained =
      lib.hasInfix "/mihomo.yaml" zeroNaivePublicationScript
      && lib.hasInfix "/mihomo-full.yaml" zeroNaivePublicationScript;
    hysteriaProfileLinkRetained = lib.hasInfix "/profile.json" zeroNaivePublicationScript;
    hysteriaPublicationEnabled = zeroNaiveRendered.publishProfileJson;
    hysteriaTemplateRetained = zeroNaiveRendered.profileJsonTemplate != null;
    manifestIncludesProfileJson =
      map (artifact: artifact.outputName) zeroNaiveArtifacts == [
        "mihomo.yaml"
        "mihomo-full.yaml"
        "profile.json"
      ];
  };
  zeroNaiveContract = builtins.all (value: value) (builtins.attrValues zeroNaiveResults);
  negativeResults = {
    inherit
      conflictingDnsPinCaseRejected
      deadPublisherCredentialRejected
      duplicatePublisherDomainCaseRejected
      duplicatePublisherDomainRejected
      duplicatePublisherRuntimeIdentityRejected
      duplicateProfileRejected
      duplicateProviderRefRejected
      missingCredentialRejected
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
        "anytls.service"
        "${publicationUnitName}.service"
      ]
      && lib.hasInfix consumerMachine.sops.secrets."fixture-anytls-password".path publicationScript;
    explicitAwgClientKeyBinding =
      consumerMachine.sops.secrets."fixture-awg-client-private-key".restartUnits
      == [ "${publicationUnitName}.service" ]
      &&
        lib.hasInfix consumerMachine.sops.secrets."fixture-awg-client-private-key".path
          publicationScript;
  };
  negativeContract = builtins.all (value: value) (builtins.attrValues negativeResults);
  contract =
    clientDnsContract
    && clientPolicyContract
    && clientDnsRenderVariantsContract
    && mihomoContract
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
        clientDnsContract
        clientDnsRenderVariantResults
        clientDnsRenderVariantsContract
        clientDnsResults
        clientPolicyContract
        clientPolicyResults
        dnsContract
        disjointPublisherContract
        disjointPublisherResults
        mihomoContract
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
      clientDnsContract
      clientDnsRenderVariantResults
      clientDnsRenderVariantsContract
      clientDnsResults
      dnsContract
      disjointPublisherContract
      disjointPublisherResults
      mihomoContract
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
