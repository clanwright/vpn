{
  inputs,
  root,
  self,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
  profileTypes = import ../clanServices/vpn-client-profiles/types.nix { inherit lib; };
  clientDnsResults = import ./client-dns-contracts.nix { inherit lib profileTypes; };
  allBooleansTrue =
    value:
    if builtins.isBool value then
      value
    else if builtins.isAttrs value then
      builtins.all allBooleansTrue (builtins.attrValues value)
    else
      false;
  clientDnsContract = allBooleansTrue clientDnsResults;
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
  renderCaptureModule =
    {
      lib,
      vpnClientProfileRender,
      ...
    }:
    {
      options.clanwright.checks.vpnClientProfileRender = lib.mkOption {
        type = lib.types.raw;
        internal = true;
      };
      config.clanwright.checks.vpnClientProfileRender = vpnClientProfileRender;
    };
  consumer = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = serviceNames;
    includeNetwork = true;
    extraModule = renderCaptureModule;
  };
  zeroNaiveInstances = fixture.instances // {
    vpn-client-profiles = lib.recursiveUpdate fixture.instances.vpn-client-profiles {
      roles.publisher.machines.vpn-fixture.settings.providerRefs = builtins.filter (
        ref: ref.protocol != "naiveproxy"
      ) fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.providerRefs;
    };
  };
  zeroNaiveConsumer = inputs.clan-core.lib.clan {
    self.inputs = {
      vpn = self;
      inherit (inputs) network;
      self.clan = zeroNaiveConsumer.config;
    };
    specialArgs.clan-core = inputs.clan-core;
    directory = builtins.path {
      path = root + /checks/fixtures;
      name = "vpn-consumer-zero-naive-fixture";
    };
    imports = [
      self.clanModule
      {
        machines.${fixtureMachineName} =
          _:
          fixture.machine
          // {
            imports = (fixture.machine.imports or [ ]) ++ [
              fixture.networkIntegrationModule
              renderCaptureModule
            ];
          };
        inventory = {
          meta.name = "vpn-consumer-zero-naive-fixture";
          machines.${fixtureMachineName} = { };
          instances = zeroNaiveInstances;
        };
      }
    ];
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
    let
      candidate = inputs.clan-core.lib.clan {
        self.inputs = {
          vpn = self;
          inherit (inputs) network;
          self.clan = candidate.config;
        };
        specialArgs.clan-core = inputs.clan-core;
        directory = builtins.path {
          path = root + /checks/fixtures;
          name = "vpn-consumer-${name}-fixture";
        };
        imports = [
          self.clanModule
          {
            machines.${fixtureMachineName} =
              _:
              fixture.machine
              // {
                imports = (fixture.machine.imports or [ ]) ++ [
                  fixture.networkIntegrationModule
                  renderCaptureModule
                ];
              };
            inventory = {
              meta.name = "vpn-consumer-${name}-fixture";
              machines.${fixtureMachineName} = { };
              inherit instances;
            };
          }
        ];
      };
    in
    candidate;
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
    builtins.head
      candidate.config.nixosConfigurations.${fixtureMachineName}.config.clanwright.checks.vpnClientProfileRender;
  rejectsInstances =
    name: instances:
    let
      candidate = evaluateInstances name instances;
    in
    !(builtins.tryEval (
      builtins.deepSeq
        candidate.config.nixosConfigurations.${fixtureMachineName}.config.system.build.toplevel.drvPath
        true
    )).success;
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
  disjointPublisherMachine =
    disjointPublisherConsumer.config.nixosConfigurations.${fixtureMachineName}.config;
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
  rendered = builtins.head consumerMachine.clanwright.checks.vpnClientProfileRender;
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
  zeroNaiveRendered = builtins.head zeroNaiveMachine.clanwright.checks.vpnClientProfileRender;
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
  vless = builtins.head (
    builtins.filter (proxy: proxy.type == "vless") rendered.mihomoSelectiveTemplate.proxies
  );
  hysteria = builtins.head (
    builtins.filter (proxy: proxy.type == "hysteria2") rendered.mihomoSelectiveTemplate.proxies
  );
  awg = builtins.head (
    builtins.filter (proxy: proxy.type == "wireguard") rendered.mihomoSelectiveTemplate.proxies
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
  multicastIndex = indexOf (rule: (rule.ip_cidr or [ ]) == [ "224.0.0.0/4" ]) profile.route.rules;
  protectedUdpIndex = indexOf (
    rule:
    (rule.network or null) == "udp"
    && (rule.rule_set or [ ]) != [ ]
    && (rule.action or null) == "reject"
  ) profile.route.rules;
  protectedProxyIndex = indexOf (
    rule: (rule.rule_set or [ ]) != [ ] && (rule.outbound or null) == "SELECTIVE"
  ) profile.route.rules;
  globalUdpIndex = indexOf (
    rule:
    (rule.clash_mode or null) == "Global"
    && (rule.network or null) == "udp"
    && (rule.action or null) == "reject"
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
      headers.Host =
        if endpoint.port == 443 then endpoint.domain else "${endpoint.domain}:${toString endpoint.port}";
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
    && bootstrapHosts.path == [ "/dev/null" ]
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
    ]
    &&
      selectiveGroups == [
        "SELECTIVE"
        "SELECTIVE-AUTO"
      ]
    &&
      fullGroups == [
        "FULL"
        "FULL-AUTO"
      ]
    && rendered.mihomoSelectiveTemplate.mode == "rule"
    && rendered.mihomoFullTemplate.mode == "rule"
    && !(builtins.elem "DIRECT" selectiveManual.proxies)
    && !(builtins.elem "DIRECT" selectiveAuto.proxies)
    && !(builtins.elem "DIRECT" fullManual.proxies)
    && !(builtins.elem "DIRECT" fullAuto.proxies)
    && lib.last rendered.mihomoSelectiveTemplate.rules == "MATCH,DIRECT"
    && lib.last rendered.mihomoFullTemplate.rules == "MATCH,FULL"
    && vless.uuid == "__MIHOMO_VLESS_UUID_11-vpn-fixture-22-vpn-mihomo-vless-xhttp__"
    && vless."reality-opts"."short-id" == "0123456789abcdef"
    && hysteria."obfs-min-packet-size" == 512
    && hysteria."obfs-max-packet-size" == 1200
    && hysteria.password == "__MIHOMO_HY2_PASSWORD_11-vpn-fixture-20-vpn-mihomo-hysteria2_cHJvYmU__"
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
    && (selector "SELECTIVE" profile).default == "SELECTIVE-AUTO"
    &&
      (selector "SELECTIVE" profile).outbounds == [
        "SELECTIVE-AUTO"
        naive.tag
      ]
    && (selector "FULL" profile).default == "FULL-AUTO"
    &&
      (selector "FULL" profile).outbounds == [
        "FULL-AUTO"
        naive.tag
      ]
    && builtins.length (urlTests profile) == 2
    && !(builtins.elem "DIRECT" (selector "SELECTIVE" profile).outbounds)
    && !(builtins.elem "DIRECT" (selector "FULL" profile).outbounds)
    && builtins.all (test: test.outbounds == [ naive.tag ]) (urlTests profile)
    && builtins.all (ruleSet: ruleSet.download_detour == naive.tag) (remoteRuleSets profile);
  routeContract =
    builtins.length (udpRejects profile) >= 2
    && builtins.length resolveRules == 2
    && privateIndex < tailnetResolveIndex
    && multicastIndex < tailnetResolveIndex
    && tailnetResolveIndex < globalUdpIndex
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
    && builtins.length profile.dns.servers == builtins.length expectedSingBoxDohServers + 2
    &&
      builtins.elemAt profile.dns.servers (builtins.length expectedSingBoxDohServers) == {
        tag = "fakeip";
        type = "fakeip";
        inet4_range = "198.18.0.0/15";
      }
    && (lib.last profile.dns.servers).tag == "bootstrap-hosts"
    && (lib.last profile.dns.servers).type == "hosts"
    && (lib.last profile.dns.servers).path == [ "/dev/null" ]
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
    profileLinkSuppressed = !(lib.hasInfix "/profile.json" zeroNaivePublicationScript);
    publicationDisabled = !zeroNaiveRendered.publishProfileJson;
    templateSuppressed = zeroNaiveRendered.profileJsonTemplate == null;
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
    && clientDnsRenderVariantsContract
    && mihomoContract
    && singBoxContract
    && routeContract
    && dnsContract
    && namespaceContract
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
        dnsContract
        disjointPublisherContract
        disjointPublisherResults
        mihomoContract
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
