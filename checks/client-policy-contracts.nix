{
  lib,
  pkgs,
}:
let
  providerEnvelope = import ../modules/contracts/provider-envelope.nix { inherit lib; };
  profileTypes = import ../clanServices/vpn-client-profiles/types.nix { inherit lib; };
  users = [
    "alice"
    "bob"
    "carol"
  ];
  secretMap = prefix: names: lib.genAttrs names (name: "fixture-${prefix}-${name}");
  allowedUsers =
    machine:
    if machine == "edge-a" then
      [
        "alice"
        "bob"
      ]
    else
      [
        "alice"
        "carol"
      ];
  endpointIPv4 = machine: if machine == "edge-a" then "192.0.2.21" else "192.0.2.22";
  endpointDomain = machine: protocol: "${protocol}-${machine}.example.invalid";
  displayFor =
    machine:
    if machine == "edge-a" then
      {
        label = "A";
        country = "Литва";
        countryCode = "LT";
      }
    else
      {
        label = "B";
        country = "Германия";
        countryCode = "DE";
      };
  # Literal expectations, independent of the implementation's flag and name code.
  expectedBaseName = machine: if machine == "edge-a" then "🇱🇹 Литва · A" else "🇩🇪 Германия · B";
  expectedKindLabel = {
    naiveproxy = "Naive";
    vless-xhttp = "VLESS";
    amneziawg = "AWG";
    mieru = "Mieru";
    anytls = "AnyTLS";
    trusttunnel = "TrustTunnel";
  };
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
  mkProvider =
    machine: protocol:
    let
      profileNames = allowedUsers machine;
      domain = endpointDomain machine protocol;
      common = {
        inherit protocol machine profileNames;
        instanceId = "${protocol}-${machine}";
        endpoint = {
          inherit domain;
          ipv4 = endpointIPv4 machine;
          port = if protocol == "mieru" then 8443 else 443;
        };
      };
      protocolData = {
        naiveproxy = {
          transportMetadata = {
            tlsServerName = domain;
            userNames = profileNames;
            port = 443;
          };
          secretNames.password = secretMap "naive-${machine}" profileNames;
        };
        vless-xhttp = {
          transportMetadata = {
            reality = {
              serverName = "donor.example.invalid";
              serverNames = [ "donor.example.invalid" ];
              target = "donor.example.invalid:443";
              publicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
              shortIdsByProfile = lib.genAttrs profileNames (_: "0123456789abcdef");
            };
            xhttp = {
              path = "/fixture";
              mode = "auto";
            };
            fingerprint = "firefox";
            doh = {
              domain = "dns-a.example.invalid";
              ipv4 = "192.0.2.53";
            };
          };
          secretNames = {
            realityPrivateKey = "fixture-reality-${machine}";
            vlessUuid = secretMap "vless-${machine}" profileNames;
          };
        };
        amneziawg = {
          transportMetadata = {
            serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            interfaceName = "awg-${machine}";
            address = "10.77.0.1/24";
            mtu = 1280;
            peers = lib.imap0 (index: name: {
              inherit name;
              publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
              allowedIPs = [ "10.77.0.${toString (index + 2)}/32" ];
              clientPersistentKeepalive = 25;
            }) profileNames;
          };
          secretNames = {
            clientPrivateKey = secretMap "awg-private-${machine}" profileNames;
            headerProtectionKey = "fixture-awg-header-${machine}";
          };
        };
        mieru = {
          transportMetadata.userNames = profileNames;
          secretNames.users = secretMap "mieru-${machine}" profileNames;
        };
        anytls = {
          transportMetadata = {
            tlsServerName = domain;
            userNames = profileNames;
          };
          secretNames.users = secretMap "anytls-${machine}" profileNames;
        };
        trusttunnel = {
          transportMetadata = {
            tlsServerName = domain;
            userNames = profileNames;
          };
          secretNames.users = secretMap "trusttunnel-${machine}" profileNames;
        };
      };
    in
    providerEnvelope.mkProvider (common // protocolData.${protocol})
    // {
      display = displayFor machine;
    };
  protocols = builtins.attrNames providerEnvelope.protocols;
  providers = lib.concatMap (machine: map (mkProvider machine) protocols) [
    "edge-a"
    "edge-b"
  ];
  publishers = {
    publisher-a = {
      localMachineName = "publisher-a";
      publicIPv4 = "192.0.2.31";
      edgeDomain = "edge-a.example.invalid";
      configGatewayDomain = "profiles-a.example.invalid";
    };
    publisher-b = {
      localMachineName = "publisher-b";
      publicIPv4 = "192.0.2.32";
      edgeDomain = "edge-b.example.invalid";
      configGatewayDomain = "profiles-b.example.invalid";
    };
    publisher-c = {
      localMachineName = "publisher-c";
      publicIPv4 = "192.0.2.33";
      edgeDomain = "edge-c.example.invalid";
      configGatewayDomain = "profiles-c.example.invalid";
    };
  };
  settingsFor =
    publisher: profiles:
    publisher
    // {
      clientDnsEndpoints = [
        {
          domain = "dns-a.example.invalid";
          ipv4 = "192.0.2.53";
          port = 443;
          path = "/dns-query";
        }
        {
          domain = "dns-b.example.invalid";
          ipv4 = "198.51.100.53";
          port = 443;
          path = "/dns-query";
        }
        {
          domain = "dns-c.example.invalid";
          ipv4 = "203.0.113.53";
          port = 8443;
          path = "/fixture-dns-query";
        }
      ];
      secretPrefix = publisher.localMachineName;
      excludedProfileNames = [ ];
      tailnetAdminDomains = [ "admin.example.invalid" ];
      personalProxyDomains = [ "personal.example.invalid" ];
      inherit profiles;
    };
  render =
    publisher: selectedProviders: profiles:
    import ../clanServices/vpn-client-profiles/client-profiles.nix {
      inherit lib pkgs;
      providers = selectedProviders;
      settings = settingsFor publisher profiles;
    };
  profile = name: {
    inherit name;
    kind = "mobile";
    publishProfileJson = true;
    autoProtocols = [
      "naiveproxy"
      "vless-xhttp"
      "mieru"
      "anytls"
      "trusttunnel"
    ];
  };
  matrixRenders = lib.mapAttrs (
    _: publisher: render publisher providers (map profile users)
  ) publishers;
  excludedRender = import ../clanServices/vpn-client-profiles/client-profiles.nix {
    inherit lib pkgs providers;
    settings = (settingsFor publishers.publisher-a (map profile users)) // {
      excludedProfileNames = [ "bob" ];
    };
  };
  excludedProfileResults =
    let
      baseline = matrixRenders.publisher-a;
      retained = [
        "alice"
        "carol"
      ];
      profileNames = entries: map (entry: entry.name) entries;
      artifactNames = entries: map (entry: map (artifact: artifact.outputName) entry.artifacts) entries;
    in
    {
      excludedProfileOtherwisePublishable =
        profileNames baseline.manifest.profiles == users
        && builtins.all (artifacts: artifacts != [ ]) (artifactNames baseline.manifest.profiles);
      excludedProfileAbsentFromRenderedProfiles =
        profileNames excludedRender.renderedProfiles == retained;
      excludedProfileAbsentFromGeneratedProfiles =
        profileNames excludedRender.generatedProfiles == retained;
      excludedProfileAbsentFromManifestAndLinkInputs =
        profileNames excludedRender.manifest.profiles == retained
        &&
          map (entry: entry.pathTokenBinding.secretName) excludedRender.manifest.profiles == [
            "mihomo-client-publisher-a-alice-path-token"
            "mihomo-client-publisher-a-carol-path-token"
          ];
      retainedArtifactsUnchanged =
        artifactNames excludedRender.manifest.profiles
        == artifactNames (builtins.filter (entry: entry.name != "bob") baseline.manifest.profiles);
    };
  renderedByName =
    publisherName: name:
    builtins.head (
      builtins.filter (entry: entry.name == name) matrixRenders.${publisherName}.renderedProfiles
    );
  # A profile's provider names gain the protocol kind only when several of its
  # providers share the same base name, here the providers of one machine.
  providerTag =
    user: provider:
    let
      sharingBase = builtins.filter (
        candidate: builtins.elem user candidate.profileNames && candidate.machine == provider.machine
      ) providers;
      base = expectedBaseName provider.machine;
    in
    if builtins.length sharingBase > 1 then
      "${base} · ${expectedKindLabel.${provider.protocol}}"
    else
      base;
  eligible =
    user: protocolSet:
    builtins.filter (
      provider: builtins.elem user provider.profileNames && builtins.elem provider.protocol protocolSet
    ) providers;
  sorted = lib.sort builtins.lessThan;
  mihomoTags =
    renderedProfile: sorted (map (proxy: proxy.name) renderedProfile.mihomoSelectiveTemplate.proxies);
  singBoxTags =
    renderedProfile:
    sorted (
      map (outbound: outbound.tag) (
        builtins.filter (
          outbound:
          builtins.elem outbound.type [
            "naive"
            "anytls"
          ]
        ) renderedProfile.profileJsonTemplate.outbounds
      )
    );
  tunInbound = renderedProfile: builtins.head renderedProfile.profileJsonTemplate.inbounds;
  mihomoTunResults =
    template:
    let
      inherit (template) tun rules;
      baseExclusions = [
        "10.0.0.0/8"
        "100.64.0.0/10"
        "127.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "224.0.0.0/4"
        "fc00::/7"
        "fe80::/10"
        "ff00::/8"
      ];
      pinnedExclusions = map (ip: "${ip}/32") (lib.unique (builtins.attrValues template.hosts));
      rejectIndex = indexOf (rule: rule == "IP-CIDR6,::/0,REJECT,no-resolve") rules;
      localIPv6Rules = [
        "IP-CIDR6,::1/128,DIRECT,no-resolve"
        "IP-CIDR6,fc00::/7,DIRECT,no-resolve"
        "IP-CIDR6,fe80::/10,DIRECT,no-resolve"
        "IP-CIDR6,ff00::/8,DIRECT,no-resolve"
      ];
    in
    {
      noExplicitRouteAddress = !(builtins.hasAttr "route-address" tun);
      routingFlagsPreserved =
        tun.enable && tun."auto-route" && tun."auto-detect-interface" && tun."strict-route";
      routeExclusionsPreserved = tun."route-exclude-address" == baseExclusions ++ pinnedExclusions;
      noInterfaceName =
        !(tun ? device)
        && !(builtins.hasAttr "interface-name" tun)
        && !(builtins.hasAttr "interface-name" template);
      ipv6PolicyPreserved =
        template.ipv6
        && !template.dns.ipv6
        && tun."inet6-address" == [ "fdfe:dcba:9876::1/126" ]
        && rejectIndex >= 0
        && builtins.all (
          rule:
          let
            localIndex = indexOf (candidate: candidate == rule) rules;
          in
          localIndex >= 0 && localIndex < rejectIndex
        ) localIPv6Rules;
    };
  tunRouteResults =
    renderedProfile:
    let
      inbound = tunInbound renderedProfile;
    in
    {
      noRouteAddress = !(inbound ? route_address);
      noLegacyExclusionKey = builtins.all (name: !(lib.hasPrefix "route_exclude" name)) (
        builtins.attrNames inbound
      );
      tunRoutingFlagsPreserved = inbound.auto_route && inbound.strict_route;
      routeAutoDetectionPreserved = renderedProfile.profileJsonTemplate.route.auto_detect_interface;
      noInterfacePin =
        !(inbound ? interface_name) && !(renderedProfile.profileJsonTemplate.route ? default_interface);
    };
  indexOf =
    predicate: values:
    let
      go =
        index: remaining:
        if remaining == [ ] then
          -1
        else if predicate (builtins.head remaining) then
          index
        else
          go (index + 1) (builtins.tail remaining);
    in
    go 0 values;
  newDomainTags = [
    "ai_domains"
    "github_domains"
  ];
  # Mihomo rule fields: RULE-SET,<set>,<policy>[,no-resolve].
  ruleSetOf = rule: builtins.elemAt (lib.splitString "," rule) 1;
  routesToManual =
    rule: lib.hasPrefix "RULE-SET," rule && builtins.elemAt (lib.splitString "," rule) 2 == manualGroup;
  mihomoDomainPolicy =
    template:
    let
      inherit (template) rules;
      ruIndex = indexOf (rule: rule == "DOMAIN-SUFFIX,ru,DIRECT") rules;
      matchIndex = indexOf (rule: lib.hasPrefix "MATCH," rule) rules;
      rejectIndex = indexOf (rule: rule == "IP-CIDR6,::/0,REJECT,no-resolve") rules;
      proxyRules = builtins.filter (
        rule: lib.hasPrefix "AND," rule || lib.hasPrefix "RULE-SET," rule || lib.hasPrefix "MATCH," rule
      ) rules;
    in
    {
      ruDirectAfterIpv6GuardBeforeProxyPolicies =
        ruIndex > rejectIndex
        && rejectIndex >= 0
        && builtins.all (rule: ruIndex < indexOf (candidate: candidate == rule) rules) proxyRules;
      ruExcludedFromFakeIp = builtins.elem "+.ru" template.dns."fake-ip-filter";
      domainFeedsUseClassicalText = builtins.all (
        tag:
        let
          provider = template."rule-providers".${tag};
        in
        provider.behavior == "classical"
        && provider.format == "text"
        && lib.hasSuffix ".txt" provider.url
        && lib.hasSuffix ".txt" provider.path
      ) newDomainTags;
      newDomainsHaveTcpPolicy = builtins.all (
        tag: builtins.any (rule: routesToManual rule && ruleSetOf rule == tag) rules
      ) newDomainTags;
      # Mihomo skips a matched UDP rule when the selected proxy lacks UDP, so the
      # explicit REJECT must follow the protected rule and precede MATCH,DIRECT.
      newDomainsHaveUdpPolicy = builtins.all (
        tag:
        let
          udpIndex = indexOf (rule: rule == "AND,((NETWORK,UDP),(RULE-SET,${tag})),REJECT") rules;
          tcpIndex = indexOf (rule: routesToManual rule && ruleSetOf rule == tag) rules;
        in
        udpIndex >= 0 && tcpIndex >= 0 && tcpIndex < udpIndex && udpIndex < matchIndex
      ) newDomainTags;
      protectedUdpNeverReachesDirect =
        let
          protectedTcpRules = builtins.filter routesToManual rules;
        in
        protectedTcpRules != [ ]
        && builtins.all (
          rule: builtins.elem "AND,((NETWORK,UDP),(RULE-SET,${ruleSetOf rule})),REJECT" rules
        ) protectedTcpRules
        && matchIndex == builtins.length rules - 1
        && builtins.elemAt rules matchIndex == "MATCH,DIRECT"
        && !(builtins.any (lib.hasPrefix "NETWORK,UDP,") rules);
    };
  singBoxDomainPolicy =
    template:
    let
      inherit (template.route) rules;
      ruResolveIndex = indexOf (
        rule: (rule.domain_suffix or [ ]) == [ "ru" ] && (rule.action or null) == "resolve"
      ) rules;
      ruDirectIndex = indexOf (
        rule: (rule.domain_suffix or [ ]) == [ "ru" ] && (rule.outbound or null) == "DIRECT"
      ) rules;
      rejectIndex = indexOf (
        rule: (rule.ip_version or null) == 6 && (rule.action or null) == "reject"
      ) rules;
      proxyRules = builtins.filter (
        rule: rule ? clash_mode || (rule.rule_set or [ ]) != [ ] || (rule.outbound or null) == manualGroup
      ) rules;
      fakeIpRule = builtins.head template.dns.rules;
      exclusions = lib.last fakeIpRule.rules;
    in
    {
      ruResolvedBeforeDirectAfterIpv6Guard =
        rejectIndex >= 0
        && ruResolveIndex > rejectIndex
        && ruDirectIndex == ruResolveIndex + 1
        && (builtins.elemAt rules ruResolveIndex).strategy == "ipv4_only"
        && !((builtins.elemAt rules ruResolveIndex) ? server);
      ruDirectBeforeGlobalAndProtectedPolicy =
        ruDirectIndex >= 0
        && builtins.all (rule: ruDirectIndex < indexOf (candidate: candidate == rule) rules) proxyRules;
      ruExcludedFromProtectedFakeIp =
        exclusions.invert
        && exclusions.mode == "or"
        && builtins.any (rule: builtins.elem "ru" (rule.domain_suffix or [ ])) exclusions.rules;
      newDomainsUseFakeIpAndProtectedTcpUdp = builtins.all (
        tag:
        builtins.elem tag (builtins.elemAt fakeIpRule.rules 1).rule_set
        # One network-agnostic rule covers TCP and UDP; sing-box fails UDP on an
        # outbound without UDP support instead of falling back to DIRECT.
        && builtins.any (
          rule:
          builtins.elem tag (rule.rule_set or [ ])
          && (rule.outbound or null) == manualGroup
          && !(rule ? network)
          && !(rule ? action)
        ) rules
      ) newDomainTags;
      protectedUdpNeverReachesDirect =
        let
          ruleSetRules = builtins.filter (rule: (rule.rule_set or [ ]) != [ ]) rules;
        in
        ruleSetRules != [ ]
        && builtins.all (
          rule: (rule.outbound or null) == manualGroup && !(rule ? network) && !(rule ? action)
        ) ruleSetRules
        && !(builtins.any (
          rule: (rule.network or null) == "udp" && (rule.outbound or null) == "DIRECT"
        ) rules)
        && !(builtins.any (rule: builtins.elem (rule.outbound or null) legacyGroupNames) rules);
      newDomainsUseBinaryRemoteRules = builtins.all (
        tag:
        builtins.any (
          ruleSet:
          ruleSet.tag == tag
          && ruleSet.type == "remote"
          && ruleSet.format == "binary"
          && lib.hasSuffix ".srs" ruleSet.url
        ) template.route.rule_set
      ) newDomainTags;
    };
  # Fixed group topology: Ручной lists Авто first, Авто tests only the automatic
  # candidates, and GLOBAL offers only the VPN groups so Clash Global mode never
  # starts on DIRECT. Neither client format has a full-tunnel variant.
  mihomoGroupResults =
    renderedProfile:
    let
      template = renderedProfile.mihomoSelectiveTemplate;
      groups = template."proxy-groups";
      named = name: builtins.head (builtins.filter (group: group.name == name) groups);
    in
    {
      exactGroupNames =
        map (group: group.name) groups == [
          manualGroup
          autoGroup
          "GLOBAL"
        ];
      groupTypes =
        (named manualGroup).type == "select"
        && (named autoGroup).type == "url-test"
        && (named "GLOBAL").type == "select";
      manualStartsWithAuto = builtins.head (named manualGroup).proxies == autoGroup;
      globalOffersOnlyVpnGroups =
        (named "GLOBAL").proxies == [
          manualGroup
          autoGroup
        ];
      noDirectInVpnGroups = builtins.all (group: !(builtins.elem "DIRECT" group.proxies)) groups;
      noLegacyGroupReferences =
        builtins.all (
          group: builtins.all (member: !(builtins.elem member legacyGroupNames)) group.proxies
        ) groups
        && builtins.all (
          rule: !(builtins.any (field: builtins.elem field legacyGroupNames) (lib.splitString "," rule))
        ) template.rules;
      protectedRulesUseManualGroup =
        lib.last template.rules == "MATCH,DIRECT"
        && builtins.elem "RULE-SET,secure_dns_domains,${manualGroup}" template.rules;
      noFullVariant = !(renderedProfile ? mihomoFullTemplate);
    };
  singBoxGroupResults =
    renderedProfile:
    let
      template = renderedProfile.profileJsonTemplate;
      manual = builtins.head (
        builtins.filter (outbound: (outbound.tag or null) == manualGroup) template.outbounds
      );
      auto = builtins.head (
        builtins.filter (outbound: (outbound.tag or null) == autoGroup) template.outbounds
      );
      globalIndex = indexOf (
        rule: (rule.clash_mode or null) == "Global" && (rule.outbound or null) == manualGroup
      ) template.route.rules;
    in
    {
      selectorAndUrltestOnly =
        builtins.length (builtins.filter (outbound: outbound.type == "selector") template.outbounds) == 1
        && builtins.length (builtins.filter (outbound: outbound.type == "urltest") template.outbounds) == 1;
      manualDefaultsToAuto =
        manual.type == "selector"
        && manual.default == autoGroup
        && builtins.head manual.outbounds == autoGroup;
      autoIsUrltest = auto.type == "urltest";
      noDirectInVpnGroups =
        !(builtins.elem "DIRECT" manual.outbounds) && !(builtins.elem "DIRECT" auto.outbounds);
      globalModeUsesManualGroup =
        globalIndex >= 0
        &&
          builtins.length (builtins.filter (rule: (rule.clash_mode or null) == "Global") template.route.rules)
          == 1;
      noLegacyOutboundReferences =
        builtins.all (outbound: !(builtins.elem (outbound.tag or null) legacyGroupNames)) template.outbounds
        && builtins.all (
          rule: !(builtins.elem (rule.outbound or null) legacyGroupNames)
        ) template.route.rules;
    };
  matrixResults = lib.mapAttrs (
    publisherName: publisher:
    lib.genAttrs users (
      user:
      let
        renderedProfile = renderedByName publisherName user;
      in
      {
        tunRoutes = tunRouteResults renderedProfile;
        mihomoSelectiveTun = mihomoTunResults renderedProfile.mihomoSelectiveTemplate;
        mihomoSelectiveDomains = mihomoDomainPolicy renderedProfile.mihomoSelectiveTemplate;
        singBoxDomains = singBoxDomainPolicy renderedProfile.profileJsonTemplate;
        mihomoGroups = mihomoGroupResults renderedProfile;
        singBoxGroups = singBoxGroupResults renderedProfile;
        noFullArtifact = builtins.all (
          entry: builtins.all (artifact: artifact.outputName != "mihomo-full.yaml") entry.artifacts
        ) matrixRenders.${publisherName}.manifest.profiles;
        mihomoContainsExactlyCompatibleAuthorizedProviders =
          mihomoTags renderedProfile == sorted (
            map (providerTag user) (
              eligible user [
                "vless-xhttp"
                "amneziawg"
                "mieru"
                "anytls"
                "trusttunnel"
              ]
            )
          );
        singBoxContainsExactlyCompatibleAuthorizedProviders =
          singBoxTags renderedProfile == sorted (
            map (providerTag user) (
              eligible user [
                "naiveproxy"
                "anytls"
              ]
            )
          );
        publisherIdentityAppliedToBothFormats =
          renderedProfile.mihomoSelectiveTemplate.hosts.${publisher.configGatewayDomain}
          == publisher.publicIPv4
          && builtins.all (
            ruleProvider:
            lib.hasPrefix "https://${publisher.configGatewayDomain}/assets/v1/catalog/" ruleProvider.url
          ) (builtins.attrValues renderedProfile.mihomoSelectiveTemplate."rule-providers")
          &&
            (lib.last renderedProfile.profileJsonTemplate.dns.servers)
            .predefined.${publisher.configGatewayDomain} == publisher.publicIPv4
          && builtins.all (
            ruleSet: lib.hasPrefix "https://${publisher.configGatewayDomain}/assets/v1/catalog/" ruleSet.url
          ) renderedProfile.profileJsonTemplate.route.rule_set;
        threeDnsEndpointsRenderedInBothFormats =
          builtins.length renderedProfile.mihomoSelectiveTemplate.dns.nameserver == 3
          &&
            builtins.length (
              builtins.filter (server: server.type == "https") renderedProfile.profileJsonTemplate.dns.servers
            ) == 3;
        awgIsManualOnlyAndIdle =
          let
            awgTags = map (providerTag user) (eligible user [ "amneziawg" ]);
            awgProxies = builtins.filter (
              proxy: builtins.elem proxy.name awgTags
            ) renderedProfile.mihomoSelectiveTemplate.proxies;
            groups = renderedProfile.mihomoSelectiveTemplate."proxy-groups";
            automaticGroups = builtins.filter (group: group.type == "url-test") groups;
            manualGroups = builtins.filter (group: group.name == manualGroup) groups;
          in
          builtins.all (proxy: proxy."persistent-keepalive" == 0) awgProxies
          && builtins.all (
            group: builtins.all (tag: !(builtins.elem tag group.proxies)) awgTags
          ) automaticGroups
          && builtins.all (tag: builtins.all (group: builtins.elem tag group.proxies) manualGroups) awgTags;
        ipv6CaptureRejectsPublicAfterLocalExceptions =
          let
            mihomoRules = renderedProfile.mihomoSelectiveTemplate.rules;
            singBoxRules = renderedProfile.profileJsonTemplate.route.rules;
            mihomoLocalIndex = indexOf (rule: rule == "IP-CIDR6,fc00::/7,DIRECT,no-resolve") mihomoRules;
            mihomoRejectIndex = indexOf (rule: rule == "IP-CIDR6,::/0,REJECT,no-resolve") mihomoRules;
            singBoxLocalIndex = indexOf (
              rule: builtins.elem "fc00::/7" (rule.ip_cidr or [ ]) && (rule.outbound or null) == "DIRECT"
            ) singBoxRules;
            tailnetIndex = indexOf (
              rule: (rule.domain or [ ]) == [ "admin.example.invalid" ] && (rule.outbound or null) == "DIRECT"
            ) singBoxRules;
            singBoxRejectIndex = indexOf (
              rule: (rule.ip_version or null) == 6 && (rule.action or null) == "reject"
            ) singBoxRules;
          in
          builtins.elem "fdfe:dcba:9876::1/126" (builtins.head renderedProfile.profileJsonTemplate.inbounds)
          .address
          && mihomoLocalIndex >= 0
          && mihomoLocalIndex < mihomoRejectIndex
          && singBoxLocalIndex >= 0
          && singBoxLocalIndex < singBoxRejectIndex
          && tailnetIndex >= 0
          && tailnetIndex < singBoxRejectIndex;
      }
    )
  ) publishers;
  protocolOnlyResults = lib.genAttrs protocols (
    protocol:
    let
      candidate = render publishers.publisher-a [ (mkProvider "edge-a" protocol) ] [ (profile "alice") ];
      renderedProfile = builtins.head candidate.renderedProfiles;
      inherit (builtins.head candidate.manifest.profiles) artifacts;
      outputs = map (artifact: artifact.outputName) artifacts;
    in
    {
      newAssetRefsFollowClientFormat = builtins.all (
        artifact:
        let
          ownFormat = if artifact.format == "mihomo" then "mihomo" else "sing-box";
          otherFormat = if artifact.format == "mihomo" then "sing-box" else "mihomo";
        in
        builtins.all (
          tag:
          builtins.elem "${ownFormat}-${tag}" artifact.assetRefs
          && !(builtins.elem "${otherFormat}-${tag}" artifact.assetRefs)
        ) newDomainTags
      ) artifacts;
      domainPolicy =
        if renderedProfile.profileJsonTemplate == null then
          mihomoDomainPolicy renderedProfile.mihomoSelectiveTemplate
        else if renderedProfile.mihomoSelectiveTemplate == null then
          singBoxDomainPolicy renderedProfile.profileJsonTemplate
        else
          {
            mihomo = mihomoDomainPolicy renderedProfile.mihomoSelectiveTemplate;
            singBox = singBoxDomainPolicy renderedProfile.profileJsonTemplate;
          };
      tunRoutes =
        if renderedProfile.profileJsonTemplate == null then
          { ineligibleFormatSkipped = true; }
        else
          tunRouteResults renderedProfile;
      artifactCompatibility =
        if protocol == "naiveproxy" then
          outputs == [ "profile.json" ] && renderedProfile.mihomoSelectiveTemplate == null
        else if
          builtins.elem protocol [
            "anytls"
          ]
        then
          outputs == [
            "mihomo.yaml"
            "profile.json"
          ]
        else
          outputs == [ "mihomo.yaml" ] && renderedProfile.profileJsonTemplate == null;
      trustTunnelOnlyMihomoShape =
        protocol != "trusttunnel"
        || (
          let
            proxy = builtins.head renderedProfile.mihomoSelectiveTemplate.proxies;
            groups = renderedProfile.mihomoSelectiveTemplate."proxy-groups";
            manualGroups = builtins.filter (group: group.name == manualGroup) groups;
            autoGroups = builtins.filter (group: group.type == "url-test") groups;
          in
          proxy.type == "trusttunnel"
          && proxy.server == "192.0.2.21"
          && proxy.port == 443
          && proxy.username == "alice"
          && proxy.password == "__MIHOMO_TRUSTTUNNEL_PASSWORD_6-edge-a-18-trusttunnel-edge-a_alice__"
          && proxy.sni == "trusttunnel-edge-a.example.invalid"
          && !proxy."skip-cert-verify"
          && proxy."client-fingerprint" == "chrome"
          && !proxy.quic
          && proxy.udp
          && builtins.all (
            artifact:
            artifact.bindings == [
              {
                secretName = "fixture-trusttunnel-edge-a-alice";
                decoding = "base64url";
                targetPath = [
                  "proxies"
                  0
                  "password"
                ];
                placeholder = "__MIHOMO_TRUSTTUNNEL_PASSWORD_6-edge-a-18-trusttunnel-edge-a_alice__";
              }
            ]
          ) artifacts
          && builtins.all (group: group.proxies == [ proxy.name ]) autoGroups
          && proxy.name == expectedBaseName "edge-a"
          && builtins.all (group: builtins.elem proxy.name group.proxies) manualGroups
          && renderedProfile.profileJsonTemplate == null
        );
      naiveOnlyProtectedUdpStaysOnTcpOnlyOutbound =
        protocol != "naiveproxy"
        || (
          let
            template = renderedProfile.profileJsonTemplate;
            selector = builtins.head (
              builtins.filter (outbound: (outbound.tag or null) == manualGroup) template.outbounds
            );
            protectedRules = builtins.filter (rule: (rule.rule_set or [ ]) != [ ]) template.route.rules;
            naiveTags = map (outbound: outbound.tag) (
              builtins.filter (outbound: outbound.type == "naive") template.outbounds
            );
          in
          naiveTags == [ (expectedBaseName "edge-a") ]
          && protectedRules != [ ]
          && builtins.all (
            rule: rule.outbound == manualGroup && !(rule ? network) && !(rule ? action)
          ) protectedRules
          &&
            selector.outbounds == [
              autoGroup
              (expectedBaseName "edge-a")
            ]
          && !(builtins.elem "DIRECT" selector.outbounds)
          && !(builtins.any (
            rule: (rule.network or null) == "udp" && (rule.outbound or null) == "DIRECT"
          ) template.route.rules)
        );
      anytlsOnlyProtectedUdpUsesTunnel =
        protocol != "anytls"
        || (
          let
            manualSelector = builtins.head (
              builtins.filter (
                outbound: (outbound.tag or null) == manualGroup
              ) renderedProfile.profileJsonTemplate.outbounds
            );
            protectedUdpRules = builtins.filter (
              rule: (rule.rule_set or [ ]) != [ ]
            ) renderedProfile.profileJsonTemplate.route.rules;
            anytlsTags = map (outbound: outbound.tag) (
              builtins.filter (outbound: outbound.type == "anytls") renderedProfile.profileJsonTemplate.outbounds
            );
          in
          protectedUdpRules != [ ]
          && builtins.all (
            rule: (rule.outbound or null) == manualGroup && !(rule ? network) && !(rule ? action)
          ) protectedUdpRules
          && anytlsTags == [ (expectedBaseName "edge-a") ]
          && builtins.all (tag: builtins.elem tag manualSelector.outbounds) anytlsTags
          && !(builtins.elem "DIRECT" manualSelector.outbounds)
        );
    }
  );
  noAutoRender = render publishers.publisher-a providers [
    ((profile "alice") // { autoProtocols = [ ]; })
  ];
  ruCollisionRender = import ../clanServices/vpn-client-profiles/client-profiles.nix {
    inherit lib pkgs providers;
    settings = (settingsFor publishers.publisher-a [ (profile "alice") ]) // {
      personalProxyDomains = [
        "github.fixture.ru"
        "ai.fixture.ru"
      ];
    };
  };
  ruCollisionProfile = builtins.head ruCollisionRender.renderedProfiles;
  ruCollisionResults = {
    mihomoSelective = mihomoDomainPolicy ruCollisionProfile.mihomoSelectiveTemplate;
    singBox = singBoxDomainPolicy ruCollisionProfile.profileJsonTemplate;
    competingMihomoPersonalPolicyPresent = builtins.elem "RULE-SET,personal_proxy_domains,${manualGroup}" ruCollisionProfile.mihomoSelectiveTemplate.rules;
    competingSingBoxPersonalPoliciesFollowRu =
      let
        rules = ruCollisionProfile.profileJsonTemplate.route.rules;
        ruIndex = indexOf (
          rule: (rule.domain_suffix or [ ]) == [ "ru" ] && (rule.outbound or null) == "DIRECT"
        ) rules;
        personalRules = builtins.filter (
          rule:
          (rule.domain_suffix or [ ]) == [
            "github.fixture.ru"
            "ai.fixture.ru"
          ]
        ) rules;
      in
      builtins.length personalRules == 1
      && builtins.all (rule: indexOf (candidate: candidate == rule) rules > ruIndex) personalRules;
  };
  noAutoProfile = builtins.head noAutoRender.renderedProfiles;
  noAutoMihomoGroups = noAutoProfile.mihomoSelectiveTemplate."proxy-groups";
  noAutoSingBoxOutbounds = noAutoProfile.profileJsonTemplate.outbounds;
  noAutoResults = {
    noBackgroundTestsInEitherFormat =
      builtins.filter (group: group.type == "url-test") noAutoMihomoGroups == [ ]
      && builtins.filter (outbound: outbound.type == "urltest") noAutoSingBoxOutbounds == [ ];
    mihomoManualSelectorRetainsCompatibleProviders =
      let
        expected = map (providerTag "alice") (
          eligible "alice" [
            "vless-xhttp"
            "mieru"
            "anytls"
            "trusttunnel"
            "amneziawg"
          ]
        );
        manual = builtins.head (builtins.filter (group: group.name == manualGroup) noAutoMihomoGroups);
      in
      sorted manual.proxies == sorted expected
      &&
        builtins.head manual.proxies
        == providerTag "alice" (builtins.head (eligible "alice" [ "vless-xhttp" ]));
    # Without automatic candidates only Ручной and GLOBAL exist; GLOBAL never
    # lists DIRECT, so Clash Global mode cannot bypass the tunnel.
    mihomoGroupsWithoutAuto =
      map (group: group.name) noAutoMihomoGroups == [
        manualGroup
        "GLOBAL"
      ]
      && (builtins.elemAt noAutoMihomoGroups 1).proxies == [ manualGroup ]
      && !(builtins.elem "DIRECT" (builtins.elemAt noAutoMihomoGroups 0).proxies);
    singBoxManualSelectorRetainsCompatibleProviders =
      let
        expected = map (providerTag "alice") (
          eligible "alice" [
            "naiveproxy"
            "anytls"
          ]
        );
        manual = builtins.head (
          builtins.filter (outbound: (outbound.tag or null) == manualGroup) noAutoSingBoxOutbounds
        );
      in
      sorted manual.outbounds == sorted expected
      && manual.default == builtins.head manual.outbounds
      && !(builtins.elem "DIRECT" manual.outbounds)
      && builtins.all (
        outbound: !(builtins.elem (outbound.tag or null) ([ autoGroup ] ++ legacyGroupNames))
      ) noAutoSingBoxOutbounds;
    awgIdleWhenManualOnly = builtins.all (
      proxy: proxy.type != "wireguard" || proxy."persistent-keepalive" == 0
    ) noAutoProfile.mihomoSelectiveTemplate.proxies;
  };
  evalProfile =
    value:
    (lib.evalModules {
      modules = [
        {
          options.value = lib.mkOption {
            type = profileTypes.profileType;
          };
        }
        { config.value = value; }
      ];
    }).config.value;
  profileSchemaAccepts =
    value: (builtins.tryEval (builtins.deepSeq (evalProfile value) true)).success;
  autoProtocolsResults = {
    emptyAccepted = profileSchemaAccepts {
      name = "schema-empty";
      autoProtocols = [ ];
    };
    defaultIncludesAllProtocols =
      (evalProfile { name = "schema-default"; }).autoProtocols == profileTypes.protocolValues;
    duplicateRejected =
      !(profileSchemaAccepts {
        name = "schema-duplicate";
        autoProtocols = [
          "anytls"
          "anytls"
        ];
      });
    unknownRejected =
      !(profileSchemaAccepts {
        name = "schema-unknown";
        autoProtocols = [ "unknown" ];
      });
  };
  allTrue =
    value: if builtins.isBool value then value else builtins.all allTrue (builtins.attrValues value);
  results = {
    inherit
      autoProtocolsResults
      excludedProfileResults
      matrixResults
      noAutoResults
      protocolOnlyResults
      ruCollisionResults
      ;
  };
in
if !allTrue results then
  throw "Client policy matrix contract failed: ${builtins.toJSON results}"
else
  {
    all = true;
    inherit results;
  }
