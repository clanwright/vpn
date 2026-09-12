{
  lib,
  pkgs,
  settings,
  providers,
}:
let
  profileTypes = import ./types.nix { inherit lib; };
  manifestLib = import ./artifact-manifest.nix { inherit lib; };
  inherit (settings) localMachineName;
  inherit (settings) clientDnsEndpoints;
  localPublicNetwork = {
    inherit (settings) publicIPv4;
    domains.edge = settings.edgeDomain;
    serviceDomains.configGateway = settings.configGatewayDomain;
  };
  inherit (settings) secretPrefix;
  profiles = builtins.filter (
    profile: !(builtins.elem profile.name settings.excludedProfileNames)
  ) settings.profiles;
  providersFor = protocol: builtins.filter (provider: provider.protocol == protocol) providers;
  vlessProviders = providersFor "vless-xhttp";
  amneziawgProviders = providersFor "amneziawg";
  hysteria2Providers = providersFor "hysteria2";
  naiveProviders = providersFor "naiveproxy";
  mieruProviders = providersFor "mieru";
  providerId = profileTypes.providerNamespace;
  profilePolicy = profileName: provider: builtins.elem profileName provider.profileNames;
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

  opaqueAssetStem =
    id: builtins.substring 0 32 (builtins.hashString "sha256" "vpn-client-profiles/v1/${id}");
  opaqueAssetPublicPath = id: extension: "/assets/v1/catalog/${opaqueAssetStem id}.${extension}";
  opaqueClientCachePath = id: extension: "./ruleset/${opaqueAssetStem id}.${extension}";
  secureDnsRuleSetPublicPath = opaqueAssetPublicPath "secure-dns-filter" "srs";
  personalProxyDomainsTxtPublicPath = opaqueAssetPublicPath "personal-proxy-domains" "txt";
  ruleSetMirrorPublicPath = tag: opaqueAssetPublicPath "sing-box-${tag}" "srs";
  ruleSetMirrorMrsPublicPath = tag: opaqueAssetPublicPath "mihomo-${tag}" "mrs";
  secureDnsDomainsTxtPublicPath = opaqueAssetPublicPath "secure-dns-domains" "txt";
  legacySecureDnsRuleSetPublicPath = "/assets/v1/catalog/filters.srs";
  legacyPersonalProxyDomainsTxtPublicPath = "/assets/v1/catalog/segments.txt";
  legacyRuleSetMirrorPublicPath = tag: "/assets/v1/catalog/${tag}.srs";
  legacyRuleSetMirrorMrsPublicPath = tag: "/assets/v1/catalog/${tag}.mrs";
  legacySecureDnsDomainsTxtPublicPath = "/assets/v1/catalog/secure-dns.txt";
  personalProxyDomainLines = settings.personalProxyDomains or [ ];
  personalProxyDomainRegex = "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$";
  invalidPersonalProxyDomains = builtins.filter (
    domain: builtins.match personalProxyDomainRegex domain == null
  ) personalProxyDomainLines;
  personalProxyDomains =
    if invalidPersonalProxyDomains != [ ] then
      throw "Invalid personal_proxy_domains entries: ${lib.concatStringsSep ", " invalidPersonalProxyDomains}"
    else
      personalProxyDomainLines;
  personalProxyMihomoDomains = map (domain: "+.${domain}") personalProxyDomains;
  personalProxyDomainsTxt = pkgs.writeText "personal-proxy-domains.txt" (
    lib.concatStringsSep "\n" personalProxyMihomoDomains + "\n"
  );
  configGatewayDomain = localPublicNetwork.serviceDomains.configGateway;
  probeUrl64k = "https://speed.cloudflare.com/__down?bytes=65536";

  mkMihomoDohUrl =
    endpoint: "https://${endpoint.domain}:${toString endpoint.port}${endpoint.path}#DIRECT";
  mkMihomoBootstrapDohUrl =
    endpoint: "https://${endpoint.ipv4}:${toString endpoint.port}${endpoint.path}#DIRECT";

  mkRuleProvider =
    {
      assetId,
      behavior,
      url,
      proxy,
      format ? "text",
    }:
    {
      inherit
        behavior
        url
        proxy
        format
        ;
      type = "http";
      path = opaqueClientCachePath assetId (if format == "mrs" then "mrs" else "txt");
      interval = 86400;
    };

  mkRuleProviders =
    lib.listToAttrs (
      map (
        ruleSet:
        lib.nameValuePair ruleSet.tag (mkRuleProvider {
          assetId = "mihomo-${ruleSet.tag}";
          inherit (ruleSet) behavior;
          proxy = "DIRECT";
          format = "mrs";
          url = "https://${configGatewayDomain}${ruleSetMirrorMrsPublicPath ruleSet.tag}";
        })
      ) mihomoMrsUpstream
    )
    // {
      secure_dns_domains = mkRuleProvider {
        assetId = "secure-dns-domains";
        behavior = "domain";
        proxy = "DIRECT";
        url = "https://${configGatewayDomain}${secureDnsDomainsTxtPublicPath}";
      };
    }
    // lib.optionalAttrs (personalProxyDomains != [ ]) {
      personal_proxy_domains = mkRuleProvider {
        assetId = "personal-proxy-domains";
        behavior = "domain";
        proxy = "DIRECT";
        url = "https://${configGatewayDomain}${personalProxyDomainsTxtPublicPath}";
      };
    };

  mkSingBoxRemoteRuleSet =
    {
      tag,
      url,
    }:
    {
      type = "remote";
      inherit tag url;
      format = "binary";
      update_interval = "1d";
      http_client = {
        domain_resolver = {
          server = "bootstrap-hosts";
          strategy = "ipv4_only";
        };
        tls.server_name = configGatewayDomain;
      };
    };

  upstreamRuleSets = [
    {
      tag = "ru_blocked_and_geoblocked_domains";
      url = "https://github.com/legiz-ru/sb-rule-sets/raw/main/ru-bundle.srs";
    }
    {
      tag = "ru_blocked_asn_ips";
      url = "https://github.com/legiz-ru/sb-rule-sets/raw/main/rknasnblock.srs";
    }
    {
      tag = "refilter_blocked_domains";
      url = "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ruleset-domain-refilter_domains.srs";
    }
    {
      tag = "refilter_blocked_ips";
      url = "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ruleset-ip-refilter_ipsum.srs";
    }
  ];

  # Native mihomo .mrs sources, mirrored alongside the sing-box .srs so the
  # mihomo client fetches rule sets from its own edge (DIRECT), not upstream.
  # behavior is required by mihomo rule-providers; sing-box .srs carries it
  # inside the binary so upstreamRuleSets above does not need it.
  mihomoMrsUpstream = [
    {
      tag = "ru_blocked_and_geoblocked_domains";
      behavior = "domain";
      url = "https://github.com/legiz-ru/mihomo-rule-sets/raw/main/ru-bundle/rule.mrs";
    }
    {
      tag = "ru_blocked_asn_ips";
      behavior = "ipcidr";
      url = "https://github.com/legiz-ru/mihomo-rule-sets/raw/main/ru-bundle/rknasnblock.mrs";
    }
    {
      tag = "refilter_blocked_domains";
      behavior = "domain";
      url = "https://github.com/legiz-ru/mihomo-rule-sets/raw/main/re-filter/domain-rule.mrs";
    }
    {
      tag = "refilter_blocked_ips";
      behavior = "ipcidr";
      url = "https://github.com/legiz-ru/mihomo-rule-sets/raw/main/re-filter/ip-rule.mrs";
    }
  ];

  assetCatalog = {
    secure-dns-domains = {
      id = "secure-dns-domains";
      filename = "secure-dns.txt";
      publicPath = secureDnsDomainsTxtPublicPath;
      legacyPublicPaths = [ legacySecureDnsDomainsTxtPublicPath ];
      routePriority = 30;
      contentType = "text/plain; charset=utf-8";
      validator = "nonempty";
      source = {
        kind = "download";
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/doh-onlydomains.txt";
      };
    };
    personal-proxy-domains = {
      id = "personal-proxy-domains";
      filename = "segments.txt";
      publicPath = personalProxyDomainsTxtPublicPath;
      legacyPublicPaths = [ legacyPersonalProxyDomainsTxtPublicPath ];
      routePriority = 1;
      contentType = "text/plain; charset=utf-8";
      validator = "nonempty";
      source = {
        kind = "local-file";
        path = personalProxyDomainsTxt;
      };
    };
    secure-dns-filter = {
      id = "secure-dns-filter";
      filename = "filters.srs";
      publicPath = secureDnsRuleSetPublicPath;
      legacyPublicPaths = [ legacySecureDnsRuleSetPublicPath ];
      routePriority = 0;
      contentType = "application/octet-stream";
      validator = "srs";
      source = {
        kind = "adguard-to-srs";
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh.txt";
      };
    };
  }
  // builtins.listToAttrs (
    lib.imap0 (index: ruleSet: {
      name = "sing-box-${ruleSet.tag}";
      value = {
        id = "sing-box-${ruleSet.tag}";
        filename = "${ruleSet.tag}.srs";
        publicPath = ruleSetMirrorPublicPath ruleSet.tag;
        legacyPublicPaths = [ (legacyRuleSetMirrorPublicPath ruleSet.tag) ];
        routePriority = 10 + index;
        contentType = "application/octet-stream";
        validator = "srs";
        source = {
          kind = "download";
          inherit (ruleSet) url;
        };
      };
    }) upstreamRuleSets
  )
  // builtins.listToAttrs (
    lib.imap0 (index: ruleSet: {
      name = "mihomo-${ruleSet.tag}";
      value = {
        id = "mihomo-${ruleSet.tag}";
        filename = "${ruleSet.tag}.mrs";
        publicPath = ruleSetMirrorMrsPublicPath ruleSet.tag;
        legacyPublicPaths = [ (legacyRuleSetMirrorMrsPublicPath ruleSet.tag) ];
        routePriority = 20 + index;
        contentType = "application/octet-stream";
        validator = "mrs-${ruleSet.behavior}";
        source = {
          kind = "download";
          inherit (ruleSet) url;
        };
      };
    }) mihomoMrsUpstream
  );

  # The publisher mirrors upstream .srs assets. Clients fetch them from the
  # pinned config gateway through the explicit HTTP-client resolver above.
  mkSingBoxRuleSets = map (
    ruleSet:
    mkSingBoxRemoteRuleSet {
      inherit (ruleSet) tag;
      url = "https://${configGatewayDomain}${ruleSetMirrorPublicPath ruleSet.tag}";
    }
  ) upstreamRuleSets;
  singBoxFakeIpDomainRuleSets = [
    "secure_dns_domains"
    "ru_blocked_and_geoblocked_domains"
    "refilter_blocked_domains"
  ];
  protectedRuleSets = [
    "secure_dns_domains"
    "ru_blocked_and_geoblocked_domains"
    "ru_blocked_asn_ips"
    "refilter_blocked_domains"
    "refilter_blocked_ips"
  ];
  protectedRuleSetsWithPersonal =
    protectedRuleSets ++ lib.optional (personalProxyDomains != [ ]) "personal_proxy_domains";

  localDirectRules = [
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
    "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve"
    "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve"
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve"
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve"
    "IP-CIDR,224.0.0.0/4,DIRECT,no-resolve"
    "IP-CIDR6,::1/128,DIRECT,no-resolve"
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve"
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve"
    "IP-CIDR6,ff00::/8,DIRECT,no-resolve"
  ];
  ipv6RejectRules = [
    "IP-CIDR6,::/0,REJECT,no-resolve"
  ];
  protectedRules = [
    "RULE-SET,secure_dns_domains,PROXY"
    "RULE-SET,ru_blocked_and_geoblocked_domains,PROXY"
    "RULE-SET,refilter_blocked_domains,PROXY"
    "RULE-SET,ru_blocked_asn_ips,PROXY,no-resolve"
    "RULE-SET,refilter_blocked_ips,PROXY,no-resolve"
  ]
  ++ lib.optional (personalProxyDomains != [ ]) "RULE-SET,personal_proxy_domains,PROXY";

  findAmneziawgPeer =
    profileName: provider:
    let
      matches = builtins.filter (peer: peer.name == profileName) provider.transportMetadata.peers;
    in
    if builtins.length matches != 1 then
      throw "Expected exactly one AmneziaWG peer named ${profileName} for provider ${providerId provider}"
    else
      builtins.head matches;

  firstAddress = cidr: builtins.head (lib.splitString "/" cidr);

  mkVlessCredential =
    profileName: provider:
    let
      metadata = provider.transportMetadata;
      machineName = providerId provider;
    in
    {
      inherit machineName;
      vlessUuidSecretName =
        provider.secretNames.vlessUuid.${profileName}
          or (throw "VLESS UUID secret name is required for ${machineName}/${profileName}");
      vlessTag = "${machineName}-${profileName}-vless";
      edgeDomain = provider.endpoint.domain;
      port = provider.endpoint.port;
      edgeIPv4 = provider.endpoint.ipv4;
      inherit (metadata) reality xhttp;
      dohDomain = metadata.doh.domain;
      dohIPv4 = metadata.doh.ipv4;
      clientFingerprint = metadata.fingerprint;
    };

  mkAmneziawgCredential =
    profileName: provider:
    let
      peer = findAmneziawgPeer profileName provider;
      metadata = provider.transportMetadata;
      machineName = providerId provider;
    in
    {
      inherit machineName;
      inherit (metadata) serverPublicKey;
      headerProtectionKeySecretName = provider.secretNames.headerProtectionKey;
      clientPublicKey = peer.publicKey;
      endpointDomain = provider.endpoint.domain;
      listenPort = provider.endpoint.port;
      mtu = metadata.mtu or null;
      clientPersistentKeepalive = peer.clientPersistentKeepalive or 25;
      amneziawgTag = "${machineName}-${profileName}-amneziawg";
      endpointIPv4 = provider.endpoint.ipv4;
      clientAddress = firstAddress (builtins.head peer.allowedIPs);
      clientPrivateKeySecretName =
        provider.secretNames.clientPrivateKey.${profileName}
          or (throw "AmneziaWG private-key secret name is required for ${machineName}/${profileName}");
      inherit (metadata) generation profile;
    };

  mkHysteria2Credential =
    profileName: provider:
    let
      metadata = provider.transportMetadata;
      machineName = providerId provider;
    in
    {
      inherit machineName;
      endpointDomain = provider.endpoint.domain;
      endpointIPv4 = provider.endpoint.ipv4;
      port = provider.endpoint.port;
      inherit (metadata)
        sni
        alpn
        obfsName
        obfsMinPacketSize
        obfsMaxPacketSize
        tlsVerify
        credentialEncoding
        ;
      obfsPasswordSecretName = provider.secretNames.obfsPassword;
      inherit profileName;
      tag = "${machineName}-${profileName}-hysteria2";
      passwordSecretName =
        provider.secretNames.users.${profileName}
          or (throw "Hysteria2 password secret name is required for ${machineName}/${profileName}");
    };

  mkNaiveCredential =
    profileName: provider:
    let
      machineName = providerId provider;
      passwordSecretName =
        provider.secretNames.password.${profileName}
          or (throw "NaiveProxy password secret name is required for ${machineName}/${profileName}");
    in
    {
      inherit machineName;
      domain = provider.endpoint.domain;
      endpointIPv4 = provider.endpoint.ipv4 or settings.publicIPv4;
      port = provider.transportMetadata.port or provider.endpoint.port;
      username = profileName;
      tlsServerName = provider.transportMetadata.tlsServerName or provider.endpoint.domain;
      tag = "${machineName}-${profileName}-edge";
      inherit passwordSecretName;
    };

  mkMieruCredential =
    profileName: provider:
    let
      machineName = providerId provider;
    in
    {
      inherit machineName profileName;
      endpointIPv4 = provider.endpoint.ipv4;
      port = provider.endpoint.port;
      tag = "${machineName}-${profileName}-mieru";
      passwordSecretName =
        provider.secretNames.users.${profileName}
          or (throw "Mieru password secret name is required for ${machineName}/${profileName}");
    };

  mkProfile =
    profile:
    let
      basename = "${localMachineName}-${profile.name}";
      profileKind = profile.kind or "mobile";
      autoProtocols = profile.autoProtocols or profileTypes.protocolValues;
      autoProtocolEnabled = protocol: builtins.elem protocol autoProtocols;
      isRouterProfile = profileKind == "router";
      profileJsonRequested =
        if (profile.publishProfileJson or null) != null then
          profile.publishProfileJson
        else
          !isRouterProfile;
      pathTokenSecret = "mihomo-client-${secretPrefix}-${profile.name}-path-token";
      profileVlessProviders = builtins.filter (profilePolicy profile.name) vlessProviders;
      dohNameservers = map mkMihomoDohUrl clientDnsEndpoints;
      dohBootstrapNameservers = map mkMihomoBootstrapDohUrl clientDnsEndpoints;
      profileAmneziawgProviders = builtins.filter (profilePolicy profile.name) amneziawgProviders;
      profileHysteria2Providers = builtins.filter (profilePolicy profile.name) hysteria2Providers;
      profileNaiveProviders = builtins.filter (profilePolicy profile.name) naiveProviders;
      profileMieruProviders = builtins.filter (profilePolicy profile.name) mieruProviders;
      upstreamCredentials = map (mkVlessCredential profile.name) profileVlessProviders;
      amneziawgCredentials = map (mkAmneziawgCredential profile.name) profileAmneziawgProviders;
      hysteria2Credentials = map (mkHysteria2Credential profile.name) profileHysteria2Providers;
      naiveCredentials = map (mkNaiveCredential profile.name) profileNaiveProviders;
      mieruCredentials = map (mkMieruCredential profile.name) profileMieruProviders;
      publishProfileJson =
        profileJsonRequested && (naiveCredentials != [ ] || hysteria2Credentials != [ ]);

      mkVlessProxy = cred: {
        name = cred.vlessTag;
        type = "vless";
        server = cred.edgeDomain;
        inherit (cred) port;
        uuid = "__MIHOMO_VLESS_UUID_${cred.machineName}__";
        network = "xhttp";
        udp = true;
        tls = true;
        servername = cred.reality.serverName;
        "client-fingerprint" = cred.clientFingerprint;
        "reality-opts" = {
          "public-key" = cred.reality.publicKey;
          "short-id" = cred.reality.shortIdsByProfile.${profile.name};
        };
        alpn = [ "h2" ];
        "xhttp-opts" = {
          inherit (cred.xhttp) path;
          mode = "auto";
        }
        // lib.optionalAttrs (!isRouterProfile) {
          host = cred.edgeDomain;
          "reuse-settings"."max-connections" = "2";
        };
      };

      mkAmneziawgProxy =
        cred:
        {
          name = cred.amneziawgTag;
          type = "wireguard";
          server = cred.endpointDomain;
          port = cred.listenPort;
          ip = cred.clientAddress;
          "private-key" = "__MIHOMO_AMNEZIAWG_PRIVATE_KEY_${cred.machineName}__";
          "public-key" = cred.serverPublicKey;
          "allowed-ips" = [ "0.0.0.0/0" ];
          udp = true;
          "persistent-keepalive" =
            if autoProtocolEnabled "amneziawg" then cred.clientPersistentKeepalive or 25 else 0;
          "amnezia-wg-option" = {
            version = cred.generation;
            inherit (cred.profile)
              s1
              s2
              s3
              s4
              ;
            h1 = toString cred.profile.h1;
            h2 = toString cred.profile.h2;
            h3 = toString cred.profile.h3;
            h4 = toString cred.profile.h4;
            "content-padding-addition" =
              "${toString cred.profile.contentPaddingAddition.min}-${toString cred.profile.contentPaddingAddition.max}";
            "random-trailers" = cred.profile.randomTrailers;
            "disable-cookies" = cred.profile.disableCookies;
            "header-protection-key" =
              "__MIHOMO_AMNEZIAWG_HEADER_PROTECTION_KEY_${cred.machineName}_${profile.name}__";
          };
        }
        // lib.optionalAttrs (cred.mtu != null) {
          inherit (cred) mtu;
        };

      mkHysteria2Proxy = cred: {
        name = cred.tag;
        type = "hysteria2";
        server = cred.endpointDomain;
        inherit (cred) port sni alpn;
        password = "__MIHOMO_HY2_PASSWORD_${cred.machineName}_${cred.profileName}__";
        obfs = cred.obfsName;
        "obfs-password" = "__MIHOMO_HY2_OBFS_PASSWORD_${cred.machineName}__";
        "obfs-min-packet-size" = cred.obfsMinPacketSize;
        "obfs-max-packet-size" = cred.obfsMaxPacketSize;
        "skip-cert-verify" = !cred.tlsVerify;
      };

      mkMieruProxy = cred: {
        name = cred.tag;
        type = "mieru";
        server = cred.endpointIPv4;
        inherit (cred) port;
        username = cred.profileName;
        password = "__MIHOMO_MIERU_PASSWORD_${cred.machineName}_${cred.profileName}__";
        transport = "TCP";
        multiplexing = "MULTIPLEXING_LOW";
        "handshake-mode" = "HANDSHAKE_STANDARD";
        udp = true;
      };

      unorderedProxies =
        (map mkVlessProxy upstreamCredentials)
        ++ (map mkHysteria2Proxy hysteria2Credentials)
        ++ (map mkMieruProxy mieruCredentials)
        ++ (map mkAmneziawgProxy amneziawgCredentials);

      vlessProxyNames = map (cred: cred.vlessTag) upstreamCredentials;
      hysteria2ProxyNames = map (cred: cred.tag) hysteria2Credentials;
      mieruProxyNames = map (cred: cred.tag) mieruCredentials;
      amneziawgProxyNames = map (cred: cred.amneziawgTag) amneziawgCredentials;
      autoProxyNames =
        lib.optionals (autoProtocolEnabled "vless-xhttp") vlessProxyNames
        ++ lib.optionals (autoProtocolEnabled "hysteria2") hysteria2ProxyNames
        ++ lib.optionals (autoProtocolEnabled "mieru") mieruProxyNames
        ++ lib.optionals (autoProtocolEnabled "amneziawg") amneziawgProxyNames;
      udpProxyNames = vlessProxyNames ++ hysteria2ProxyNames ++ mieruProxyNames ++ amneziawgProxyNames;
      autoUdpProxyNames =
        lib.optionals (autoProtocolEnabled "vless-xhttp") vlessProxyNames
        ++ lib.optionals (autoProtocolEnabled "hysteria2") hysteria2ProxyNames
        ++ lib.optionals (autoProtocolEnabled "mieru") mieruProxyNames
        ++ lib.optionals (autoProtocolEnabled "amneziawg") amneziawgProxyNames;
      orderedProxyNames =
        if isRouterProfile then
          hysteria2ProxyNames ++ mieruProxyNames ++ amneziawgProxyNames ++ vlessProxyNames
        else
          vlessProxyNames ++ hysteria2ProxyNames ++ mieruProxyNames ++ amneziawgProxyNames;
      proxyByName = builtins.listToAttrs (
        map (proxy: {
          inherit (proxy) name;
          value = proxy;
        }) unorderedProxies
      );
      proxies = map (name: proxyByName.${name}) orderedProxyNames;
      publishMihomo = orderedProxyNames != [ ];
      rawPinnedHostEntries = [
        {
          name = localPublicNetwork.domains.edge;
          value = localPublicNetwork.publicIPv4;
        }
        {
          name = configGatewayDomain;
          value = localPublicNetwork.publicIPv4;
        }
      ]
      ++ map (endpoint: {
        name = endpoint.domain;
        value = endpoint.ipv4;
      }) clientDnsEndpoints
      ++ lib.concatMap (
        cred:
        lib.optional (cred.endpointIPv4 != null) {
          name = cred.domain;
          value = cred.endpointIPv4;
        }
      ) naiveCredentials
      ++ lib.concatMap (
        cred:
        lib.optional (cred.edgeIPv4 != null) {
          name = cred.edgeDomain;
          value = cred.edgeIPv4;
        }
      ) upstreamCredentials
      ++ lib.concatMap (
        cred:
        lib.optional (cred.dohIPv4 != null) {
          name = cred.dohDomain;
          value = cred.dohIPv4;
        }
      ) upstreamCredentials
      ++ lib.concatMap (
        cred:
        lib.optional (cred.endpointIPv4 != null) {
          name = cred.endpointDomain;
          value = cred.endpointIPv4;
        }
      ) (hysteria2Credentials ++ amneziawgCredentials);
      pinnedHostEntries = map (entry: entry // { name = lib.toLower entry.name; }) rawPinnedHostEntries;
      pinnedHostEntriesByDomain = lib.groupBy (entry: entry.name) pinnedHostEntries;
      conflictingPinnedHostDomains = builtins.filter (
        domain:
        builtins.length (lib.unique (map (entry: entry.value) pinnedHostEntriesByDomain.${domain})) > 1
      ) (builtins.attrNames pinnedHostEntriesByDomain);
      pinnedHosts =
        if conflictingPinnedHostDomains != [ ] then
          throw "vpn-client-profiles: conflicting pinned IPv4 addresses for domains: ${lib.concatStringsSep ", " conflictingPinnedHostDomains}"
        else
          builtins.listToAttrs pinnedHostEntries;
      isIPv4Literal =
        value: builtins.isString value && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" value != null;
      pinnedEdgeRouteExcludes = map (ip: "${ip}/32") (
        lib.unique (builtins.filter isIPv4Literal (builtins.attrValues pinnedHosts))
      );

      mkMihomoTemplate = modeGroup: finalTarget: {
        profile."store-selected" = true;
        mode = "rule";
        "allow-lan" = false;
        "bind-address" = "*";
        "log-level" = "info";
        "unified-delay" = true;
        "find-process-mode" = "strict";
        ipv6 = true;
        port = 0;
        "socks-port" = 0;
        "redir-port" = 0;
        "mixed-port" = 0;
        "tproxy-port" = 0;
        # Client profile remains an off-LAN fallback. Android apps can detect
        # VpnService/TUN/route/DNS-hijack state; the external LAN gateway is the
        # preferred low-detect path for devices that need app-side checks.
        tun = {
          enable = true;
          stack = "system";
          "auto-route" = true;
          "auto-detect-interface" = true;
          "strict-route" = true;
          "inet6-address" = [ "fdfe:dcba:9876::1/126" ];
          "route-address" = [
            "0.0.0.0/1"
            "128.0.0.0/1"
            "::/1"
            "8000::/1"
          ];
          "dns-hijack" = [
            "any:53"
            "tcp://any:53"
          ];
          "route-exclude-address" = [
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
          ]
          ++ pinnedEdgeRouteExcludes;
        };

        dns = {
          enable = true;
          ipv6 = false;
          "respect-rules" = true;
          "use-hosts" = true;
          # +.ts.net: Tailscale MagicDNS must resolve to real 100.x via DoH→AdGuardHome
          # (which forwards tail971c03.ts.net to 100.100.100.100), not to a fake-ip.
          # Without this, a client running this profile (e.g. Clash Verge on the dev
          # mac) hijacks *.ts.net → 198.18.x and can't reach tailnet hosts by FQDN.
          "fake-ip-filter" = settings.tailnetAdminDomains ++ [ "+.ts.net" ];
          # Every configured DoH hostname is pinned in root hosts. Mihomo 1.19.30
          # checks those pins before its bootstrap resolver, preserving the URL
          # hostname for HTTP Host and TLS SNI while dialing the declared IPv4.
          # Literal-IP HTTPS defaults are a fail-closed guard for an unexpected
          # unpinned resolver hostname; no public or plaintext resolver is used.
          "default-nameserver" = dohBootstrapNameservers;
          nameserver = dohNameservers;
          "proxy-server-nameserver" = dohNameservers;
        };

        hosts = pinnedHosts;
        inherit proxies;

        "proxy-groups" = [
          {
            name = modeGroup;
            type = "select";
            proxies = lib.optional (autoProxyNames != [ ]) "${modeGroup}-AUTO" ++ orderedProxyNames;
          }
        ]
        ++ lib.optional (autoProxyNames != [ ]) {
          name = "${modeGroup}-AUTO";
          type = "url-test";
          url = probeUrl64k;
          interval = 300;
          proxies = autoProxyNames;
        }
        ++ lib.optional (udpProxyNames != [ ]) {
          name = "UDP";
          type = "select";
          proxies = lib.optional (autoUdpProxyNames != [ ]) "UDP-AUTO" ++ udpProxyNames;
        }
        ++ lib.optional (autoUdpProxyNames != [ ]) {
          name = "UDP-AUTO";
          type = "url-test";
          url = probeUrl64k;
          interval = 300;
          proxies = autoUdpProxyNames;
        };

        "rule-providers" = mkRuleProviders;
        rules =
          localDirectRules
          ++ ipv6RejectRules
          ++ (
            if finalTarget == "FULL" then
              [ "NETWORK,UDP,${if udpProxyNames == [ ] then "REJECT" else "UDP"}" ]
            else
              map (
                ruleSet:
                "AND,((NETWORK,UDP),(RULE-SET,${ruleSet})),${if udpProxyNames == [ ] then "REJECT" else "UDP"}"
              ) protectedRuleSetsWithPersonal
          )
          ++ map (lib.replaceStrings [ "PROXY" ] [ modeGroup ]) protectedRules
          ++ [ "MATCH,${finalTarget}" ];
      };
      mihomoSelectiveTemplate = if publishMihomo then mkMihomoTemplate "SELECTIVE" "DIRECT" else null;
      mihomoFullTemplate = if publishMihomo then mkMihomoTemplate "FULL" "FULL" else null;
      proxyIndex = tag: indexOf (candidate: candidate.name == tag) proxies;
      mkBinding = secretName: decoding: targetPath: placeholder: {
        inherit
          secretName
          decoding
          targetPath
          placeholder
          ;
      };
      mihomoBindings =
        lib.concatMap (cred: [
          (mkBinding cred.vlessUuidSecretName "literal" [
            "proxies"
            (proxyIndex cred.vlessTag)
            "uuid"
          ] "__MIHOMO_VLESS_UUID_${cred.machineName}__")
        ]) upstreamCredentials
        ++ lib.concatMap (cred: [
          (mkBinding cred.clientPrivateKeySecretName "wireguard-private-key" [
            "proxies"
            (proxyIndex cred.amneziawgTag)
            "private-key"
          ] "__MIHOMO_AMNEZIAWG_PRIVATE_KEY_${cred.machineName}__")
          (mkBinding cred.headerProtectionKeySecretName "literal" [
            "proxies"
            (proxyIndex cred.amneziawgTag)
            "amnezia-wg-option"
            "header-protection-key"
          ] "__MIHOMO_AMNEZIAWG_HEADER_PROTECTION_KEY_${cred.machineName}_${profile.name}__")
        ]) amneziawgCredentials
        ++ lib.concatMap (
          cred:
          [
            (mkBinding cred.passwordSecretName "literal" [
              "proxies"
              (proxyIndex cred.tag)
              "password"
            ] "__MIHOMO_HY2_PASSWORD_${cred.machineName}_${cred.profileName}__")
          ]
          ++ lib.optional (cred.obfsPasswordSecretName != null) (
            mkBinding cred.obfsPasswordSecretName "literal" [
              "proxies"
              (proxyIndex cred.tag)
              "obfs-password"
            ] "__MIHOMO_HY2_OBFS_PASSWORD_${cred.machineName}__"
          )
        ) hysteria2Credentials
        ++ lib.concatMap (cred: [
          (mkBinding cred.passwordSecretName "base64url" [
            "proxies"
            (proxyIndex cred.tag)
            "password"
          ] "__MIHOMO_MIERU_PASSWORD_${cred.machineName}_${cred.profileName}__")
        ]) mieruCredentials;
      mihomoAssetRefs = [
        "secure-dns-domains"
      ]
      ++ map (ruleSet: "mihomo-${ruleSet.tag}") mihomoMrsUpstream
      ++ lib.optional (personalProxyDomains != [ ]) "personal-proxy-domains";

      mkSingBoxNaiveOutbound = cred: {
        type = "naive";
        inherit (cred) tag;
        server = cred.endpointIPv4;
        server_port = cred.port;
        inherit (cred) username;
        password = "__PROFILE_NAIVE_PASSWORD_${cred.machineName}__";
        insecure_concurrency = 0;
        udp_over_tcp = false;
        quic = false;
        tls = {
          enabled = true;
          server_name = cred.tlsServerName;
        };
      };
      mkSingBoxHysteria2Outbound = cred: {
        type = "hysteria2";
        inherit (cred) tag;
        server = cred.endpointIPv4;
        server_port = cred.port;
        password = "__PROFILE_HY2_PASSWORD_${cred.machineName}_${cred.profileName}__";
        obfs = {
          type = "gecko";
          password =
            if cred.obfsPasswordSecretName == null then
              throw "Sing-box Hysteria2 Gecko password is required for ${cred.machineName}/${cred.profileName}"
            else
              "__PROFILE_HY2_OBFS_PASSWORD_${cred.machineName}__";
          min_packet_size = cred.obfsMinPacketSize;
          max_packet_size = cred.obfsMaxPacketSize;
        };
        tls = {
          enabled = true;
          server_name = cred.sni;
          insecure = !cred.tlsVerify;
          inherit (cred) alpn;
        };
      };
      naiveOutboundTags = map (cred: cred.tag) naiveCredentials;
      singBoxHysteria2OutboundTags = map (cred: cred.tag) hysteria2Credentials;
      singBoxTcpOutboundTags = naiveOutboundTags ++ singBoxHysteria2OutboundTags;
      singBoxAutoTcpOutboundTags =
        lib.optionals (autoProtocolEnabled "naiveproxy") naiveOutboundTags
        ++ lib.optionals (autoProtocolEnabled "hysteria2") singBoxHysteria2OutboundTags;
      singBoxAutoUdpOutboundTags = lib.optionals (autoProtocolEnabled "hysteria2") singBoxHysteria2OutboundTags;
      mkSingBoxUdpPolicyRule =
        rule:
        rule
        // (if singBoxHysteria2OutboundTags == [ ] then { action = "reject"; } else { outbound = "UDP"; });
      singBoxDohServers = lib.imap0 (index: endpoint: {
        tag = "own-doh-${toString index}";
        type = "https";
        server = endpoint.ipv4;
        server_port = endpoint.port;
        inherit (endpoint) path;
        headers.Host =
          endpoint.domain + lib.optionalString (endpoint.port != 443) ":${toString endpoint.port}";
        tls = {
          enabled = true;
          server_name = endpoint.domain;
        };
      }) clientDnsEndpoints;
      singBoxDohRules = lib.concatLists (
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
              // lib.optionalAttrs (index > 0) {
                speculative = true;
              }
            )
            {
              match_response = responseTag;
              action = "respond";
              race = true;
            }
          ]
        ) clientDnsEndpoints
      );
      singBoxFakeIpRule = {
        type = "logical";
        mode = "and";
        rules = [
          { rule_set = singBoxFakeIpDomainRuleSets; }
          {
            type = "logical";
            mode = "or";
            rules =
              lib.optional (settings.tailnetAdminDomains != [ ]) {
                domain = settings.tailnetAdminDomains;
              }
              ++ [ { domain_suffix = [ "ts.net" ]; } ];
            invert = true;
          }
        ];
        action = "route";
        server = "fakeip";
      };
      profileJsonTemplate = {
        log = {
          level = "info";
          timestamp = true;
        };
        experimental.cache_file.enabled = true;
        experimental.clash_api.default_mode = "Rule";
        dns = {
          servers = singBoxDohServers ++ [
            {
              tag = "fakeip";
              type = "fakeip";
              inet4_range = "198.18.0.0/15";
            }
            {
              # Keep the bootstrap portable across Linux, Apple and Windows
              # clients. Predefined entries pin owned endpoints; omitting path
              # lets the hosts transport use the platform's normal hosts file.
              tag = "bootstrap-hosts";
              type = "hosts";
              predefined = pinnedHosts;
            }
          ];
          rules = [ singBoxFakeIpRule ] ++ singBoxDohRules ++ [ { action = "reject"; } ];
          strategy = "ipv4_only";
        };
        inbounds = [
          {
            type = "tun";
            tag = "tun-in";
            address = [
              "172.19.0.1/30"
              "fdfe:dcba:9876::1/126"
            ];
            stack = "system";
            auto_route = true;
            strict_route = true;
            route_exclude_address = [
              "10.0.0.0/8"
              "100.64.0.0/10"
              "169.254.0.0/16"
              "172.16.0.0/12"
              "192.168.0.0/16"
              "224.0.0.0/4"
              "::1/128"
              "fc00::/7"
              "fe80::/10"
              "ff00::/8"
            ];
          }
        ];
        outbounds = [
          {
            type = "selector";
            tag = "SELECTIVE";
            outbounds =
              lib.optional (singBoxAutoTcpOutboundTags != [ ]) "SELECTIVE-AUTO" ++ singBoxTcpOutboundTags;
            default =
              if singBoxAutoTcpOutboundTags == [ ] then
                builtins.head singBoxTcpOutboundTags
              else
                "SELECTIVE-AUTO";
          }
          {
            type = "selector";
            tag = "FULL";
            outbounds = lib.optional (singBoxAutoTcpOutboundTags != [ ]) "FULL-AUTO" ++ singBoxTcpOutboundTags;
            default =
              if singBoxAutoTcpOutboundTags == [ ] then builtins.head singBoxTcpOutboundTags else "FULL-AUTO";
          }
        ]
        ++ lib.optionals (singBoxAutoTcpOutboundTags != [ ]) [
          {
            type = "urltest";
            tag = "SELECTIVE-AUTO";
            outbounds = singBoxAutoTcpOutboundTags;
            url = probeUrl64k;
            interval = "5m";
          }
          {
            type = "urltest";
            tag = "FULL-AUTO";
            outbounds = singBoxAutoTcpOutboundTags;
            url = probeUrl64k;
            interval = "5m";
          }
        ]
        ++ lib.optional (singBoxHysteria2OutboundTags != [ ]) {
          type = "selector";
          tag = "UDP";
          outbounds =
            lib.optional (singBoxAutoUdpOutboundTags != [ ]) "UDP-AUTO" ++ singBoxHysteria2OutboundTags;
          default =
            if singBoxAutoUdpOutboundTags == [ ] then
              builtins.head singBoxHysteria2OutboundTags
            else
              "UDP-AUTO";
        }
        ++ lib.optional (singBoxAutoUdpOutboundTags != [ ]) {
          type = "urltest";
          tag = "UDP-AUTO";
          outbounds = singBoxAutoUdpOutboundTags;
          url = probeUrl64k;
          interval = "5m";
        }
        ++ [
          {
            type = "direct";
            tag = "DIRECT";
          }
        ]
        ++ map mkSingBoxNaiveOutbound naiveCredentials
        ++ map mkSingBoxHysteria2Outbound hysteria2Credentials;
        route = {
          auto_detect_interface = true;
          default_domain_resolver = {
            server = "bootstrap-hosts";
            strategy = "ipv4_only";
          };
          final = "DIRECT";
          rule_set = mkSingBoxRuleSets ++ [
            (mkSingBoxRemoteRuleSet {
              tag = "secure_dns_domains";
              url = "https://${configGatewayDomain}${secureDnsRuleSetPublicPath}";
            })
          ];
          rules = [
            {
              inbound = "tun-in";
              action = "sniff";
            }
            {
              protocol = "dns";
              action = "hijack-dns";
            }
            {
              ip_cidr = [
                "10.0.0.0/8"
                "100.64.0.0/10"
                "127.0.0.0/8"
                "169.254.0.0/16"
                "172.16.0.0/12"
                "192.168.0.0/16"
                "::1/128"
                "fc00::/7"
                "fe80::/10"
              ];
              outbound = "DIRECT";
            }
            {
              ip_cidr = [
                "224.0.0.0/4"
                "ff00::/8"
              ];
              outbound = "DIRECT";
            }
          ]
          ++ lib.optionals (settings.tailnetAdminDomains != [ ]) [
            {
              domain = settings.tailnetAdminDomains;
              action = "resolve";
              strategy = "ipv4_only";
            }
            {
              domain = settings.tailnetAdminDomains;
              outbound = "DIRECT";
            }
          ]
          ++ [
            {
              ip_version = 6;
              action = "reject";
            }
          ]
          ++ [
            (mkSingBoxUdpPolicyRule {
              clash_mode = "Global";
              network = "udp";
            })
          ]
          ++ [
            {
              clash_mode = "Global";
              outbound = "FULL";
            }
          ]
          ++ [
            (mkSingBoxUdpPolicyRule {
              network = "udp";
              rule_set = protectedRuleSets;
            })
          ]
          ++ lib.optional (personalProxyDomains != [ ]) (mkSingBoxUdpPolicyRule {
            network = "udp";
            domain_suffix = personalProxyDomains;
          })
          ++ lib.optional (personalProxyDomains != [ ]) {
            domain_suffix = personalProxyDomains;
            outbound = "SELECTIVE";
          }
          ++ [
            {
              rule_set = protectedRuleSets;
              outbound = "SELECTIVE";
            }
            # Resolve only the ordinary Rule-mode DIRECT fallback here. Global
            # and protected traffic has already selected its proxy policy.
            # Omitting server keeps this lookup inside dns.rules.
            {
              action = "resolve";
              strategy = "ipv4_only";
            }
            { outbound = "DIRECT"; }
          ];
        };
      };
      singBoxBindings =
        map (
          cred:
          let
            outboundIndex = indexOf (
              candidate: (candidate.tag or null) == cred.tag
            ) profileJsonTemplate.outbounds;
          in
          mkBinding cred.passwordSecretName "literal" [
            "outbounds"
            outboundIndex
            "password"
          ] "__PROFILE_NAIVE_PASSWORD_${cred.machineName}__"
        ) naiveCredentials
        ++ lib.concatMap (
          cred:
          let
            outboundIndex = indexOf (
              candidate: (candidate.tag or null) == cred.tag
            ) profileJsonTemplate.outbounds;
          in
          [
            (mkBinding cred.passwordSecretName "literal" [
              "outbounds"
              outboundIndex
              "password"
            ] "__PROFILE_HY2_PASSWORD_${cred.machineName}_${cred.profileName}__")
            (mkBinding cred.obfsPasswordSecretName "literal" [
              "outbounds"
              outboundIndex
              "obfs"
              "password"
            ] "__PROFILE_HY2_OBFS_PASSWORD_${cred.machineName}__")
          ]
        ) hysteria2Credentials;
      singBoxAssetRefs = [
        "secure-dns-filter"
      ]
      ++ map (ruleSet: "sing-box-${ruleSet.tag}") upstreamRuleSets;
      selectiveTemplatePath =
        if publishMihomo then
          pkgs.writeText "mihomo-client-${basename}.template.json" (builtins.toJSON mihomoSelectiveTemplate)
        else
          null;
      fullTemplatePath =
        if publishMihomo then
          pkgs.writeText "mihomo-client-${basename}-full.template.json" (builtins.toJSON mihomoFullTemplate)
        else
          null;
      profileJsonTemplatePath =
        if publishProfileJson then
          pkgs.writeText "client-profile-${basename}.template.json" (builtins.toJSON profileJsonTemplate)
        else
          null;
      artifacts =
        lib.optionals publishMihomo [
          {
            id = "${profile.name}-mihomo-selective";
            outputName = "mihomo.yaml";
            format = "mihomo";
            template = mihomoSelectiveTemplate;
            templatePath = selectiveTemplatePath;
            assetRefs = mihomoAssetRefs;
            bindings = mihomoBindings;
          }
          {
            id = "${profile.name}-mihomo-full";
            outputName = "mihomo-full.yaml";
            format = "mihomo";
            template = mihomoFullTemplate;
            templatePath = fullTemplatePath;
            assetRefs = mihomoAssetRefs;
            bindings = mihomoBindings;
          }
        ]
        ++ lib.optional publishProfileJson {
          id = "${profile.name}-sing-box";
          outputName = "profile.json";
          format = "json";
          template = profileJsonTemplate;
          templatePath = profileJsonTemplatePath;
          assetRefs = singBoxAssetRefs;
          bindings = singBoxBindings;
        };
    in
    {
      inherit
        basename
        pathTokenSecret
        upstreamCredentials
        amneziawgCredentials
        hysteria2Credentials
        naiveCredentials
        mieruCredentials
        ;
      inherit (profile) name;
      inherit publishProfileJson;
      templatePath = selectiveTemplatePath;
      inherit fullTemplatePath artifacts;
      inherit mihomoSelectiveTemplate mihomoFullTemplate;
      profileJsonTemplate = if publishProfileJson then profileJsonTemplate else null;
      inherit profileJsonTemplatePath;
    };

  generatedProfiles = map mkProfile profiles;
  manifest = {
    schemaVersion = 1;
    inherit assetCatalog;
    profiles = map (profile: {
      inherit (profile) name artifacts;
      pathTokenBinding = {
        secretName = profile.pathTokenSecret;
        decoding = "path-token";
      };
    }) generatedProfiles;
    publicationPhases = manifestLib.expectedPublicationPhases;
  };
in
{
  renderedProfiles = map (profile: {
    inherit (profile)
      name
      publishProfileJson
      mihomoSelectiveTemplate
      mihomoFullTemplate
      profileJsonTemplate
      ;
  }) generatedProfiles;
  inherit
    manifest
    generatedProfiles
    upstreamRuleSets
    mihomoMrsUpstream
    personalProxyDomainsTxt
    secureDnsRuleSetPublicPath
    personalProxyDomainsTxtPublicPath
    secureDnsDomainsTxtPublicPath
    ruleSetMirrorPublicPath
    ruleSetMirrorMrsPublicPath
    ;
}
