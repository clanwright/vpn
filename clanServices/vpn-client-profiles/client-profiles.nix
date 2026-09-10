{
  config,
  appsPkgs,
  lib,
  pkgs,
  settings,
  providers,
  mihomoPackage,
}:
let
  profileTypes = import ./types.nix { inherit lib; };
  inherit (settings) localMachineName;
  localPublicNetwork = {
    inherit (settings) publicIPv4;
    caddyBindIPv4 =
      if settings.caddyBindIPv4 == null then settings.publicIPv4 else settings.caddyBindIPv4;
    domains.edge = settings.edgeDomain;
    acme.config = settings.acmeCertName;
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
  providerId = profileTypes.providerNamespace;
  profilePolicy = profileName: provider: builtins.elem profileName provider.profileNames;

  profileRoot = "/run/mihomo-client-config/${localMachineName}";
  secureDnsRuleSetPath = "${profileRoot}/rules/hagezi-doh.srs";
  personalProxyDomainsTxtPath = "${profileRoot}/rules/personal-proxy-domains.txt";
  secureDnsRuleSetPublicPath = "/assets/v1/catalog/filters.srs";
  personalProxyDomainsTxtPublicPath = "/assets/v1/catalog/segments.txt";
  ruleSetMirrorPublicPath = tag: "/assets/v1/catalog/${tag}.srs";
  ruleSetMirrorMrsPublicPath = tag: "/assets/v1/catalog/${tag}.mrs";
  secureDnsDomainsTxtPath = "${profileRoot}/rules/secure-dns.txt";
  secureDnsDomainsTxtPublicPath = "/assets/v1/catalog/secure-dns.txt";
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
  caddyFragment = "/run/caddy-auth/mihomo-client-${localMachineName}.caddy";
  generatorService = "mihomo-client-caddy-${localMachineName}";
  secureDnsRuleSetService = "mihomo-client-hagezi-doh-${localMachineName}";
  ruleSetMirrorService = "mihomo-client-ruleset-mirror-${localMachineName}";
  configGatewayDomain =
    localPublicNetwork.serviceDomains.configGateway or localPublicNetwork.domains.config;
  probeUrl64k = "https://speed.cloudflare.com/__down?bytes=65536";

  mkRuleProvider =
    {
      name,
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
      path = "./ruleset/${name}.${if format == "mrs" then "mrs" else "txt"}";
      interval = 86400;
    };

  mkRuleProviders =
    proxy:
    lib.listToAttrs (
      map (
        ruleSet:
        lib.nameValuePair ruleSet.tag (mkRuleProvider {
          name = ruleSet.tag;
          inherit (ruleSet) behavior;
          inherit proxy;
          format = "mrs";
          url = "https://${configGatewayDomain}${ruleSetMirrorMrsPublicPath ruleSet.tag}";
        })
      ) mihomoMrsUpstream
    )
    // {
      secure_dns_domains = mkRuleProvider {
        name = "secure_dns_domains";
        behavior = "domain";
        inherit proxy;
        url = "https://${configGatewayDomain}${secureDnsDomainsTxtPublicPath}";
      };
    }
    // lib.optionalAttrs (personalProxyDomains != [ ]) {
      personal_proxy_domains = mkRuleProvider {
        name = "personal_proxy_domains";
        behavior = "domain";
        inherit proxy;
        url = "https://${configGatewayDomain}${personalProxyDomainsTxtPublicPath}";
      };
    };

  mkSingBoxRemoteRuleSet =
    {
      tag,
      url,
      downloadDetour,
    }:
    {
      type = "remote";
      inherit tag url;
      format = "binary";
      update_interval = "1d";
    }
    // lib.optionalAttrs (downloadDetour != null) {
      download_detour = downloadDetour;
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

  # Harbor fetches the upstream .srs on a timer (ruleSetMirrorService). Profiles
  # with Naive download the mirrored copy through a concrete outbound, avoiding
  # a cold-start dependency on the censored direct path. Profiles without an
  # eligible Naive provider use sing-box's default direct downloader.
  mkSingBoxRuleSets =
    downloadDetour:
    map (
      ruleSet:
      mkSingBoxRemoteRuleSet {
        inherit (ruleSet) tag;
        url = "https://${configGatewayDomain}${ruleSetMirrorPublicPath ruleSet.tag}";
        inherit downloadDetour;
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

  baseRules = [
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
    "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve"
    "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve"
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve"
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve"
    "IP-CIDR,224.0.0.0/4,DIRECT,no-resolve"
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve"
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve"
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

  mkProfile =
    profile:
    let
      basename = "${localMachineName}-${profile.name}";
      profileKind = profile.kind or "mobile";
      isRouterProfile = profileKind == "router";
      profileJsonRequested =
        if (profile.publishProfileJson or null) != null then
          profile.publishProfileJson
        else
          !isRouterProfile;
      pathTokenSecret = "mihomo-client-${secretPrefix}-${profile.name}-path-token";
      profileVlessProviders = builtins.filter (profilePolicy profile.name) vlessProviders;
      # Mihomo cannot encode the strict transport-error-only reserve cascade.
      # Keep its resolver on the primary AdGuardHome endpoint until the owner
      # chooses an explicit compatibility tradeoff.
      dohNameservers = [ "https://${localPublicNetwork.domains.edge}/dns-query" ];
      profileAmneziawgProviders = builtins.filter (profilePolicy profile.name) amneziawgProviders;
      profileHysteria2Providers = builtins.filter (profilePolicy profile.name) hysteria2Providers;
      profileNaiveProviders = builtins.filter (profilePolicy profile.name) naiveProviders;
      upstreamCredentials = map (mkVlessCredential profile.name) profileVlessProviders;
      amneziawgCredentials = map (mkAmneziawgCredential profile.name) profileAmneziawgProviders;
      hysteria2Credentials = map (mkHysteria2Credential profile.name) profileHysteria2Providers;
      naiveCredentials = map (mkNaiveCredential profile.name) profileNaiveProviders;
      publishProfileJson = profileJsonRequested && naiveCredentials != [ ];

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
          "persistent-keepalive" = cred.clientPersistentKeepalive or 25;
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

      unorderedProxies =
        (map mkVlessProxy upstreamCredentials)
        ++ (map mkHysteria2Proxy hysteria2Credentials)
        ++ (map mkAmneziawgProxy amneziawgCredentials);

      vlessProxyNames = map (cred: cred.vlessTag) upstreamCredentials;
      hysteria2ProxyNames = map (cred: cred.tag) hysteria2Credentials;
      amneziawgProxyNames = map (cred: cred.amneziawgTag) amneziawgCredentials;
      orderedProxyNames =
        if isRouterProfile then
          hysteria2ProxyNames ++ amneziawgProxyNames ++ vlessProxyNames
        else
          vlessProxyNames ++ hysteria2ProxyNames ++ amneziawgProxyNames;
      proxyByName = builtins.listToAttrs (
        map (proxy: {
          inherit (proxy) name;
          value = proxy;
        }) unorderedProxies
      );
      proxies = map (name: proxyByName.${name}) orderedProxyNames;
      ruleProviderProxy =
        if orderedProxyNames == [ ] then
          throw "Mihomo rule-provider requires at least one proxy for ${basename}"
        else
          builtins.head orderedProxyNames;
      pinnedHosts = builtins.listToAttrs (
        [
          {
            name = localPublicNetwork.domains.edge;
            value = localPublicNetwork.publicIPv4;
          }
          {
            name = configGatewayDomain;
            value = localPublicNetwork.publicIPv4;
          }
        ]
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
        ) (hysteria2Credentials ++ amneziawgCredentials)
      );
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
        ipv6 = false;
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
          nameserver = dohNameservers;
          "proxy-server-nameserver" = dohNameservers;
        };

        hosts = pinnedHosts;
        inherit proxies;

        "proxy-groups" = [
          {
            name = modeGroup;
            type = "select";
            proxies = [ "${modeGroup}-AUTO" ] ++ orderedProxyNames;
          }
          {
            name = "${modeGroup}-AUTO";
            type = "url-test";
            url = probeUrl64k;
            interval = 300;
            proxies = orderedProxyNames;
          }
        ];

        "rule-providers" = mkRuleProviders ruleProviderProxy;
        rules = map (lib.replaceStrings [ "PROXY" ] [ modeGroup ]) baseRules ++ [ "MATCH,${finalTarget}" ];
      };
      mihomoSelectiveTemplate = mkMihomoTemplate "SELECTIVE" "DIRECT";
      mihomoFullTemplate = mkMihomoTemplate "FULL" "FULL";

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
      naiveOutboundTags = map (cred: cred.tag) naiveCredentials;
      firstNaiveOutboundTag = if naiveOutboundTags == [ ] then null else builtins.head naiveOutboundTags;
      alternateNaiveCredentials = builtins.filter (
        cred: cred.endpointIPv4 != null && cred.endpointIPv4 != localPublicNetwork.publicIPv4
      ) naiveCredentials;
      ruleSetDownloadNaiveTag =
        if alternateNaiveCredentials != [ ] then
          (builtins.head alternateNaiveCredentials).tag
        else
          firstNaiveOutboundTag;
      profileJsonTemplate = {
        log = {
          level = "info";
          timestamp = true;
        };
        experimental.cache_file.enabled = true;
        experimental.clash_api.default_mode = "Rule";
        dns = {
          servers = [
            {
              tag = "edge-doh";
              type = "https";
              server = localPublicNetwork.publicIPv4;
              path = "/dns-query";
              headers.Host = localPublicNetwork.domains.edge;
              # No detour: sing-box >=1.12 rejects a detour to the empty DIRECT
              # outbound. Server is a literal IP, route.final = DIRECT, so the
              # DoH connection goes direct anyway with the same effect.
              tls = {
                enabled = true;
                server_name = localPublicNetwork.domains.edge;
              };
            }
            {
              tag = "reserve-cloudflare";
              type = "https";
              server = "1.1.1.1";
              path = "/dns-query";
              tls = {
                enabled = true;
                server_name = "cloudflare-dns.com";
              };
            }
            {
              tag = "reserve-quad9";
              type = "https";
              server = "9.9.9.10";
              path = "/dns-query";
              tls = {
                enabled = true;
                server_name = "dns10.quad9.net";
              };
            }
            {
              tag = "reserve-google";
              type = "https";
              server = "8.8.8.8";
              path = "/dns-query";
              tls = {
                enabled = true;
                server_name = "dns.google";
              };
            }
            {
              tag = "plain-cloudflare";
              type = "udp";
              server = "1.1.1.1";
              server_port = 53;
            }
            {
              tag = "plain-quad9";
              type = "udp";
              server = "9.9.9.10";
              server_port = 53;
            }
            {
              tag = "plain-google";
              type = "udp";
              server = "8.8.8.8";
              server_port = 53;
            }
            {
              tag = "fakeip";
              type = "fakeip";
              inet4_range = "198.18.0.0/15";
            }
          ];
          rules =
            lib.optional (settings.tailnetAdminDomains != [ ]) {
              domain = settings.tailnetAdminDomains;
              action = "route";
              server = "edge-doh";
            }
            ++ lib.optional (singBoxFakeIpDomainRuleSets != [ ]) {
              rule_set = singBoxFakeIpDomainRuleSets;
              action = "route";
              server = "fakeip";
            }
            ++ [
              {
                action = "evaluate";
                server = "edge-doh";
              }
              {
                match_response = true;
                action = "respond";
              }
              {
                action = "evaluate";
                server = "reserve-cloudflare";
                tag = "reserve-cloudflare-response";
              }
              {
                match_response = "reserve-cloudflare-response";
                action = "respond";
                race = true;
              }
              {
                action = "evaluate";
                server = "reserve-quad9";
                tag = "reserve-quad9-response";
                speculative = true;
                remove_client_subnet = true;
              }
              {
                match_response = "reserve-quad9-response";
                action = "respond";
                race = true;
              }
              {
                action = "evaluate";
                server = "reserve-google";
                tag = "reserve-google-response";
                speculative = true;
              }
              {
                match_response = "reserve-google-response";
                action = "respond";
                race = true;
              }
              {
                action = "evaluate";
                server = "plain-cloudflare";
                tag = "plain-cloudflare-response";
              }
              {
                match_response = "plain-cloudflare-response";
                action = "respond";
                race = true;
              }
              {
                action = "evaluate";
                server = "plain-quad9";
                tag = "plain-quad9-response";
                speculative = true;
                remove_client_subnet = true;
              }
              {
                match_response = "plain-quad9-response";
                action = "respond";
                race = true;
              }
              {
                action = "evaluate";
                server = "plain-google";
                tag = "plain-google-response";
                speculative = true;
              }
              {
                match_response = "plain-google-response";
                action = "respond";
                race = true;
              }
              { action = "reject"; }
            ];
          final = "edge-doh";
          strategy = "ipv4_only";
        };
        inbounds = [
          {
            type = "tun";
            tag = "tun-in";
            address = [ "172.19.0.1/30" ];
            stack = "system";
            auto_route = true;
            strict_route = true;
            # This profile is IPv4-only. Do not add partial IPv6 routes here.
            route_exclude_address = [
              "10.0.0.0/8"
              "100.64.0.0/10"
              "169.254.0.0/16"
              "172.16.0.0/12"
              "192.168.0.0/16"
              "224.0.0.0/4"
            ];
          }
        ];
        outbounds = [
          {
            type = "selector";
            tag = "SELECTIVE";
            # Profiles with Naive stay fail-closed. A profile with no eligible
            # This placeholder is never exposed when no Naive outbound exists;
            # publishProfileJson keeps profile.json and its link suppressed.
            outbounds =
              if naiveOutboundTags == [ ] then [ "DIRECT" ] else [ "SELECTIVE-AUTO" ] ++ naiveOutboundTags;
            default = if naiveOutboundTags == [ ] then "DIRECT" else "SELECTIVE-AUTO";
          }
          {
            type = "selector";
            tag = "FULL";
            outbounds = if naiveOutboundTags == [ ] then [ "DIRECT" ] else [ "FULL-AUTO" ] ++ naiveOutboundTags;
            default = if naiveOutboundTags == [ ] then "DIRECT" else "FULL-AUTO";
          }
        ]
        ++ lib.optionals (naiveOutboundTags != [ ]) [
          {
            type = "urltest";
            tag = "SELECTIVE-AUTO";
            outbounds = naiveOutboundTags;
            url = probeUrl64k;
            interval = "5m";
          }
          {
            type = "urltest";
            tag = "FULL-AUTO";
            outbounds = naiveOutboundTags;
            url = probeUrl64k;
            interval = "5m";
          }
        ]
        ++ [
          {
            type = "direct";
            tag = "DIRECT";
          }
        ]
        ++ map mkSingBoxNaiveOutbound naiveCredentials;
        route = {
          auto_detect_interface = true;
          default_domain_resolver.server = "edge-doh";
          final = "DIRECT";
          rule_set = (mkSingBoxRuleSets ruleSetDownloadNaiveTag) ++ [
            (mkSingBoxRemoteRuleSet {
              tag = "secure_dns_domains";
              url = "https://${configGatewayDomain}${secureDnsRuleSetPublicPath}";
              downloadDetour = ruleSetDownloadNaiveTag;
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
              ];
              outbound = "DIRECT";
            }
            {
              ip_cidr = [ "224.0.0.0/4" ];
              outbound = "DIRECT";
            }
          ]
          ++ lib.optional (settings.tailnetAdminDomains != [ ]) {
            domain = settings.tailnetAdminDomains;
            outbound = "DIRECT";
          }
          ++ lib.optional (naiveOutboundTags != [ ]) {
            clash_mode = "Global";
            network = "udp";
            action = "reject";
          }
          ++ [
            {
              clash_mode = "Global";
              outbound = "FULL";
            }
          ]
          ++ lib.optional (naiveOutboundTags != [ ]) {
            # Naive is TCP-only here (UoT and QUIC are disabled). Reject every
            # UDP flow selected by the protected rule sets instead of allowing
            # it to fall through to route.final = DIRECT. Private, multicast,
            # tailnet-admin and DNS rules stay ahead of this policy gate.
            network = "udp";
            rule_set = protectedRuleSets;
            action = "reject";
          }
          ++ lib.optional (naiveOutboundTags != [ ] && personalProxyDomains != [ ]) {
            network = "udp";
            domain_suffix = personalProxyDomains;
            action = "reject";
          }
          ++ lib.optional (personalProxyDomains != [ ]) {
            domain_suffix = personalProxyDomains;
            outbound = "SELECTIVE";
          }
          ++ [
            {
              rule_set = protectedRuleSets;
              outbound = "SELECTIVE";
            }
          ];
        };
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
        ;
      inherit (profile) name;
      inherit publishProfileJson;
      yamlPath = "${profileRoot}/${profile.name}/mihomo.yaml";
      fullYamlPath = "${profileRoot}/${profile.name}/mihomo-full.yaml";
      profileJsonPath =
        if publishProfileJson then "${profileRoot}/${profile.name}/profile.json" else null;
      templatePath = pkgs.writeText "mihomo-client-${basename}.template.json" (
        builtins.toJSON mihomoSelectiveTemplate
      );
      fullTemplatePath = pkgs.writeText "mihomo-client-${basename}-full.template.json" (
        builtins.toJSON mihomoFullTemplate
      );
      inherit mihomoSelectiveTemplate mihomoFullTemplate;
      profileJsonTemplate = if publishProfileJson then profileJsonTemplate else null;
      profileJsonTemplatePath =
        if publishProfileJson then
          pkgs.writeText "client-profile-${basename}.template.json" (builtins.toJSON profileJsonTemplate)
        else
          null;
    };

  generatedProfiles = map mkProfile profiles;

  mkSecretDecls =
    profile:
    lib.genAttrs
      (
        [
          profile.pathTokenSecret
        ]
        ++ map (cred: cred.vlessUuidSecretName) profile.upstreamCredentials
        ++ map (cred: cred.clientPrivateKeySecretName) profile.amneziawgCredentials
        ++ map (cred: cred.headerProtectionKeySecretName) profile.amneziawgCredentials
        ++ map (cred: cred.passwordSecretName) profile.hysteria2Credentials
        ++ map (cred: cred.obfsPasswordSecretName) (
          builtins.filter (cred: cred.obfsPasswordSecretName != null) profile.hysteria2Credentials
        )
        ++ lib.optionals profile.publishProfileJson (
          map (cred: cred.passwordSecretName) profile.naiveCredentials
        )
      )
      (_name: {
        format = lib.mkDefault "binary";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [
          "${generatorService}.service"
          "caddy.service"
        ];
      });

  # Escape every punctuation character distinctly so valid publisher identities
  # remain safe and collision-free as shell/JQ variable suffixes.
  toIdent = value: lib.replaceStrings [ "_" "-" "." ] [ "_u" "_h" "_d" ] value;

  mkUpstreamCred =
    cred:
    let
      machineId = toIdent cred.machineName;
    in
    {
      decl = ''
        make_secret_file vless_uuid_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.vlessUuidSecretName}.path
        } > "$vless_uuid_${machineId}_file"
      '';
      arg = ''--rawfile vless_uuid_${machineId} "$vless_uuid_${machineId}_file"'';
      filter = ''(.proxies[] | select(.name == "${cred.vlessTag}").uuid) = $vless_uuid_${machineId}'';
    };

  mkAmneziawgCred =
    cred:
    let
      machineId = toIdent cred.machineName;
      profileId = toIdent cred.amneziawgTag;
    in
    {
      decl = ''
        make_secret_file amneziawg_private_key_${machineId}_file
        read_wireguard_private_key ${lib.escapeShellArg cred.clientPrivateKeySecretName} ${
          lib.escapeShellArg config.sops.secrets.${cred.clientPrivateKeySecretName}.path
        } > "$amneziawg_private_key_${machineId}_file"
        make_secret_file amneziawg_header_protection_key_${profileId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.headerProtectionKeySecretName}.path
        } > "$amneziawg_header_protection_key_${profileId}_file"
      '';
      arg = ''--rawfile amneziawg_private_key_${machineId} "$amneziawg_private_key_${machineId}_file" --rawfile amneziawg_header_protection_key_${profileId} "$amneziawg_header_protection_key_${profileId}_file"'';
      filter = ''(.proxies[] | select(.name == "${cred.amneziawgTag}")."private-key") = $amneziawg_private_key_${machineId} | (.proxies[] | select(.name == "${cred.amneziawgTag}")."amnezia-wg-option"."header-protection-key") = $amneziawg_header_protection_key_${profileId}'';
    };

  mkHysteria2Cred =
    cred:
    let
      machineId = toIdent cred.machineName;
      profileId = toIdent cred.profileName;
    in
    {
      decl = ''
        make_secret_file hysteria2_password_${machineId}_${profileId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.passwordSecretName}.path
        } > "$hysteria2_password_${machineId}_${profileId}_file"
      ''
      + lib.optionalString (cred.obfsPasswordSecretName != null) ''
        make_secret_file hysteria2_obfs_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.obfsPasswordSecretName}.path
        } > "$hysteria2_obfs_${machineId}_file"
      '';
      arg =
        ''--rawfile hysteria2_password_${machineId}_${profileId} "$hysteria2_password_${machineId}_${profileId}_file"''
        + lib.optionalString (cred.obfsPasswordSecretName != null) (
          " " + ''--rawfile hysteria2_obfs_${machineId} "$hysteria2_obfs_${machineId}_file"''
        );
      filter =
        ''(.proxies[] | select(.name == "${cred.tag}").password) = $hysteria2_password_${machineId}_${profileId}''
        +
          lib.optionalString (cred.obfsPasswordSecretName != null)
            ''| (.proxies[] | select(.name == "${cred.tag}")."obfs-password") = $hysteria2_obfs_${machineId}'';
    };

  mkNaiveCred =
    cred:
    let
      machineId = toIdent cred.machineName;
    in
    {
      decl = ''
        make_secret_file naive_password_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.passwordSecretName}.path
        } > "$naive_password_${machineId}_file"
      '';
      arg = ''--rawfile naive_password_${machineId} "$naive_password_${machineId}_file"'';
      filter = ''(.outbounds[] | select(.tag == "${cred.tag}").password) = $naive_password_${machineId}'';
    };

  profileCase =
    profile:
    let
      yamlCredArtifacts =
        map mkUpstreamCred profile.upstreamCredentials
        ++ map mkAmneziawgCred profile.amneziawgCredentials
        ++ map mkHysteria2Cred profile.hysteria2Credentials;
      jqSecretFileDecls = lib.concatStringsSep "\n" (map (a: lib.strings.trim a.decl) yamlCredArtifacts);
      jqArgs = lib.concatStringsSep " \\\n          " (map (a: lib.strings.trim a.arg) yamlCredArtifacts);
      jqFilterItems = map (a: a.filter) yamlCredArtifacts;
      jqFilter =
        if jqFilterItems == [ ] then "." else lib.concatStringsSep "\n            | " jqFilterItems;
      naiveCredArtifacts = map mkNaiveCred profile.naiveCredentials;
      profileJsonJqSecretFileDecls = lib.concatStringsSep "\n" (
        map (a: lib.strings.trim a.decl) naiveCredArtifacts
      );
      profileJsonJqArgs = lib.concatStringsSep " \\\n          " (
        map (a: lib.strings.trim a.arg) naiveCredArtifacts
      );
      profileJsonJqFilterItems = map (a: a.filter) naiveCredArtifacts;
      profileJsonJqFilter =
        if profileJsonJqFilterItems == [ ] then
          "."
        else
          lib.concatStringsSep "\n            | " profileJsonJqFilterItems;
      profileJsonPathArg = if profile.publishProfileJson then profile.profileJsonPath else "";
      profileJsonCase = lib.optionalString profile.publishProfileJson ''
        ${profileJsonJqSecretFileDecls}

        jq \
          ${profileJsonJqArgs} \
          '
            ${profileJsonJqFilter}
          ' ${lib.escapeShellArg profile.profileJsonTemplatePath} > "$profile_json_tmp"

        install -o caddy -g caddy -m 0440 "$profile_json_tmp" ${lib.escapeShellArg profile.profileJsonPath}
      '';
    in
    ''
      json_tmp="$(mktemp /run/caddy-auth/${localMachineName}-mihomo.XXXXXX.json)"
      yaml_tmp="$(mktemp /run/caddy-auth/${localMachineName}-mihomo.XXXXXX.yaml)"
      full_json_tmp="$(mktemp /run/caddy-auth/${localMachineName}-mihomo-full.XXXXXX.json)"
      full_yaml_tmp="$(mktemp /run/caddy-auth/${localMachineName}-mihomo-full.XXXXXX.yaml)"
      profile_json_tmp="$(mktemp /run/caddy-auth/${localMachineName}-profile.XXXXXX.json)"
      secret_tmp_files=()
      cleanup_tmp() {
        rm -f "$json_tmp" "$yaml_tmp" "$full_json_tmp" "$full_yaml_tmp" "$profile_json_tmp" "''${secret_tmp_files[@]}"
      }
      trap cleanup_tmp EXIT

      ${jqSecretFileDecls}

      jq \
        ${jqArgs} \
        '
          ${jqFilter}
        ' ${lib.escapeShellArg profile.templatePath} > "$json_tmp"

      yq -P -o=yaml '.' "$json_tmp" > "$yaml_tmp"
      mihomo -t -f "$yaml_tmp"
      install -o caddy -g caddy -m 0440 "$yaml_tmp" ${lib.escapeShellArg profile.yamlPath}

      jq \
        ${jqArgs} \
        '
          ${jqFilter}
        ' ${lib.escapeShellArg profile.fullTemplatePath} > "$full_json_tmp"
      yq -P -o=yaml '.' "$full_json_tmp" > "$full_yaml_tmp"
      mihomo -t -f "$full_yaml_tmp"
      install -o caddy -g caddy -m 0440 "$full_yaml_tmp" ${lib.escapeShellArg profile.fullYamlPath}

      ${profileJsonCase}
      trap - EXIT
      cleanup_tmp

      emit_profile \
        ${lib.escapeShellArg config.sops.secrets.${profile.pathTokenSecret}.path} \
        ${lib.escapeShellArg profile.yamlPath} \
        ${lib.escapeShellArg profile.fullYamlPath} \
        ${lib.escapeShellArg profileJsonPathArg}
    '';
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
  sops.secrets = lib.mkMerge (map mkSecretDecls generatedProfiles);

  systemd = {
    tmpfiles.rules = [
      "d /run/caddy-auth 0750 root caddy -"
      "d ${profileRoot} 0750 caddy caddy -"
      "d ${profileRoot}/rules 0750 caddy caddy -"
    ]
    ++ map (profile: "d ${profileRoot}/${profile.name} 0750 caddy caddy -") generatedProfiles;

    timers.${secureDnsRuleSetService} = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1d";
        Unit = "${secureDnsRuleSetService}.service";
      };
    };

    timers.${ruleSetMirrorService} = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1d";
        Unit = "${ruleSetMirrorService}.service";
      };
    };

    services = {
      ${secureDnsRuleSetService} = {
        description = "Generate public HaGeZi DoH sing-box rule set for ${localMachineName}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          UMask = "0027";
        };
        path = [
          pkgs.coreutils
          pkgs.curl
          pkgs.gnused
          appsPkgs.sing-box
        ];
        script = ''
          set -euo pipefail

          source_url="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh.txt"
          source_tmp="$(mktemp /run/caddy-auth/hagezi-doh.XXXXXX.txt)"
          filtered_tmp="$(mktemp /run/caddy-auth/hagezi-doh-filtered.XXXXXX.txt)"
          srs_tmp="$(mktemp /run/caddy-auth/hagezi-doh.XXXXXX.srs)"

          cleanup_tmp() {
            rm -f "$source_tmp" "$filtered_tmp" "$srs_tmp"
          }
          trap cleanup_tmp EXIT

          # --retry-all-errors covers the boot window where the local resolver
          # (127.0.0.1) is not answering yet: curl exits non-zero on DNS failure.
          curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 120 \
            --retry 6 --retry-delay 10 --retry-all-errors \
            --output "$source_tmp" "$source_url"
          sed '/^[[:space:]]*$/d' "$source_tmp" > "$filtered_tmp"
          sing-box rule-set convert --type adguard --output "$srs_tmp" "$filtered_tmp"
          test -s "$srs_tmp"
          # sing-box cannot decompile binary AdGuard rule-sets; match parses the binary file.
          sing-box rule-set match --format binary "$srs_tmp" dns.google >/dev/null

          install -d -o caddy -g caddy -m 0750 ${lib.escapeShellArg "${profileRoot}/rules"}
          install -o caddy -g caddy -m 0444 "$srs_tmp" ${lib.escapeShellArg secureDnsRuleSetPath}
        '';
      };

      ${ruleSetMirrorService} = {
        description = "Mirror upstream client rule sets for ${localMachineName}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          UMask = "0027";
        };
        path = [
          pkgs.coreutils
          pkgs.curl
          appsPkgs.sing-box
        ];
        script = ''
          set -euo pipefail

          install -d -o caddy -g caddy -m 0750 ${lib.escapeShellArg "${profileRoot}/rules"}

          # Fetch each upstream rule set independently. Download or validation
          # failure logs and keeps the last-good file; only a validated,
          # non-empty temp file is installed, and other mirrors still refresh.

          mirror_one() {
            local tag="$1"
            local url="$2"
            local tmp
            tmp="$(mktemp /run/caddy-auth/ruleset-mirror.XXXXXX.srs)"

            # Retry through the boot window where the local resolver (127.0.0.1)
            # may not be answering yet; --retry-all-errors covers DNS failures.
            if ! curl --fail --location --silent --show-error \
              --connect-timeout 15 --max-time 120 \
              --retry 6 --retry-delay 10 --retry-all-errors \
              --output "$tmp" "$url"; then
              printf 'rule-set %s: download failed, keeping last-good\n' "$tag" >&2
              rm -f "$tmp"
              return 0
            fi
            if [ ! -s "$tmp" ]; then
              printf 'rule-set %s: empty download, keeping last-good\n' "$tag" >&2
              rm -f "$tmp"
              return 0
            fi
            # decompile parses binary rule sets; match --format binary is a
            # fallback for any set decompile cannot round-trip.
            if ! sing-box rule-set decompile "$tmp" >/dev/null 2>&1 \
              && ! sing-box rule-set match --format binary "$tmp" example.com >/dev/null 2>&1; then
              printf 'rule-set %s: failed validation, keeping last-good\n' "$tag" >&2
              rm -f "$tmp"
              return 0
            fi

            install -o caddy -g caddy -m 0444 "$tmp" "${profileRoot}/rules/$tag.srs"
            rm -f "$tmp"
          }

          ${lib.concatMapStringsSep "\n" (
            ruleSet: "mirror_one ${lib.escapeShellArg ruleSet.tag} ${lib.escapeShellArg ruleSet.url}"
          ) upstreamRuleSets}

          mirror_one_mrs() {
            local tag="$1"
            local url="$2"
            local tmp
            tmp="$(mktemp /run/caddy-auth/ruleset-mirror.XXXXXX.mrs)"

            if ! curl --fail --location --silent --show-error \
              --connect-timeout 15 --max-time 120 --output "$tmp" "$url"; then
              printf 'mrs rule-set %s: download failed, keeping last-good\n' "$tag" >&2
              rm -f "$tmp"
              return 0
            fi
            if [ ! -s "$tmp" ]; then
              printf 'mrs rule-set %s: empty download, keeping last-good\n' "$tag" >&2
              rm -f "$tmp"
              return 0
            fi
            # ponytail: curl --fail + non-empty only; mihomo has no standalone
            # .mrs verifier, so a corrupt-but-non-empty file breaks that one
            # provider until the next daily refresh. Fine for fail-soft lists.
            install -o caddy -g caddy -m 0444 "$tmp" "${profileRoot}/rules/$tag.mrs"
            rm -f "$tmp"
          }

          ${lib.concatMapStringsSep "\n" (
            ruleSet: "mirror_one_mrs ${lib.escapeShellArg ruleSet.tag} ${lib.escapeShellArg ruleSet.url}"
          ) mihomoMrsUpstream}

          # mihomo secure_dns list: plain domain text (mihomo cannot read .srs;
          # the sing-box side uses filters.srs built by ${secureDnsRuleSetService}).
          secure_dns_tmp="$(mktemp /run/caddy-auth/secure-dns.XXXXXX.txt)"
          if curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 120 --output "$secure_dns_tmp" \
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/doh.txt" \
            && [ -s "$secure_dns_tmp" ]; then
            install -o caddy -g caddy -m 0444 "$secure_dns_tmp" ${lib.escapeShellArg secureDnsDomainsTxtPath}
          else
            printf 'secure_dns mihomo text: download failed, keeping last-good\n' >&2
          fi
          rm -f "$secure_dns_tmp"
        '';
      };

      ${generatorService} = {
        description = "Generate Caddy auth fragment for ${localMachineName} Mihomo client profiles";
        wants = [ "${ruleSetMirrorService}.service" ];
        after = [ "${ruleSetMirrorService}.service" ];
        before = [ "caddy.service" ];
        requiredBy = [ "caddy.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
          UMask = "0027";
          # Re-import the fragment after a switch-time regen so Caddy does not
          # keep stale catalog routes. --no-block is REQUIRED: caddy `requires`+
          # `after` this unit, so a BLOCKING `systemctl reload caddy` from
          # ExecStartPost deadlocks — the generator waits on caddy while caddy
          # (pulled down with the generator restart) waits on the generator — at
          # every cold boot and co-restart. --no-block enqueues the job and returns
          # immediately; try-reload-or-restart is a no-op when caddy is not running.
          ExecStartPost = "-${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart caddy.service";
        };
        path = [
          pkgs.coreutils
          pkgs.jq
          mihomoPackage
          pkgs.yq-go
        ];
        script = ''
          set -euo pipefail

          fragment_tmp="$(mktemp /run/caddy-auth/${localMachineName}.XXXXXX)"

          read_secret() {
            tr -d '\r\n' < "$1"
          }

          read_path_token() {
            local value byte_count
            value="$(cat "$1")"
            byte_count="$(LC_ALL=C wc -c < "$1")"
            byte_count="''${byte_count//[[:space:]]/}"
            if [ "''${#value}" -ne "$byte_count" ]; then
              printf 'Profile path token must not contain a trailing newline or NUL byte\n' >&2
              exit 1
            fi
            if [[ ! "$value" =~ ^[A-Za-z0-9_-]{32,128}$ ]]; then
              printf 'Profile path token must be 32-128 unpadded base64url characters\n' >&2
              exit 1
            fi
            printf '%s' "$value"
          }

          make_secret_file() {
            local var_name="$1"
            local tmp

            tmp="$(mktemp /run/caddy-auth/${localMachineName}-secret.XXXXXX)"
            chmod 0400 "$tmp"
            secret_tmp_files+=("$tmp")
            printf -v "$var_name" '%s' "$tmp"
          }

          read_wireguard_private_key() {
            local secret_name="$1"
            local secret_path="$2"
            local value decoded_len

            value="$(read_secret "$secret_path")"
            decoded_len="$(printf '%s' "$value" | base64 -d 2>/dev/null | wc -c)" || {
              printf 'Secret %s is not valid WireGuard base64 private-key material\n' "$secret_name" >&2
              exit 1
            }

            if [ "$decoded_len" != 32 ]; then
              printf 'Secret %s must decode to 32 bytes for Mihomo WireGuard private-key, got %s\n' "$secret_name" "$decoded_len" >&2
              exit 1
            fi

            printf '%s' "$value"
          }

          emit_profile() {
            local path_token_secret_path="$1"
            local config_path="$2"
            local full_config_path="$3"
            local profile_json_path="$4"
            local path_token root_dir

            path_token="$(read_path_token "$path_token_secret_path")"
            root_dir="$(dirname "$config_path")"

            {
              printf 'handle /%s/mihomo.yaml {\n' "$path_token"
              printf '  root * %s\n' "$root_dir"
              printf '  rewrite * /mihomo.yaml\n'
              printf '  header Content-Type "text/yaml; charset=utf-8"\n'
              printf '  header Content-Disposition "attachment; filename=mihomo.yaml"\n'
              printf '  header Cache-Control "no-store"\n'
              printf '  header Referrer-Policy "no-referrer"\n'
              printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
              printf '  header X-Content-Type-Options "nosniff"\n'
              printf '  file_server\n'
              printf '}\n\n'
            } >> "$fragment_tmp"

            root_dir="$(dirname "$full_config_path")"
            {
              printf 'handle /%s/mihomo-full.yaml {\n' "$path_token"
              printf '  root * %s\n' "$root_dir"
              printf '  rewrite * /mihomo-full.yaml\n'
              printf '  header Content-Type "text/yaml; charset=utf-8"\n'
              printf '  header Content-Disposition "attachment; filename=mihomo-full.yaml"\n'
              printf '  header Cache-Control "no-store"\n'
              printf '  header Referrer-Policy "no-referrer"\n'
              printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
              printf '  header X-Content-Type-Options "nosniff"\n'
              printf '  file_server\n'
              printf '}\n\n'
            } >> "$fragment_tmp"

            if [ -n "$profile_json_path" ]; then
              root_dir="$(dirname "$profile_json_path")"
              {
              printf 'handle /%s/profile.json {\n' "$path_token"
              printf '  root * %s\n' "$root_dir"
              printf '  rewrite * /profile.json\n'
              printf '  header Content-Type "application/json; charset=utf-8"\n'
              printf '  header Content-Disposition "attachment; filename=profile.json"\n'
              printf '  header Profile-Title "Edge"\n'
              printf '  header profile-update-interval "24"\n'
              printf '  header Cache-Control "no-store"\n'
              printf '  header Referrer-Policy "no-referrer"\n'
              printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
              printf '  header X-Content-Type-Options "nosniff"\n'
              printf '  file_server\n'
              printf '}\n\n'
              } >> "$fragment_tmp"
            fi
          }

          {
            printf 'handle ${secureDnsRuleSetPublicPath} {\n'
            printf '  root * %s\n' ${lib.escapeShellArg profileRoot}
            printf '  rewrite * /rules/hagezi-doh.srs\n'
            printf '  header Content-Type "application/octet-stream"\n'
            printf '  header Cache-Control "public, max-age=3600"\n'
            printf '  header Referrer-Policy "no-referrer"\n'
            printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
            printf '  header X-Content-Type-Options "nosniff"\n'
            printf '  file_server\n'
            printf '}\n\n'
          } >> "$fragment_tmp"

          {
            printf 'handle ${personalProxyDomainsTxtPublicPath} {\n'
            printf '  root * %s\n' ${lib.escapeShellArg profileRoot}
            printf '  rewrite * /rules/personal-proxy-domains.txt\n'
            printf '  header Content-Type "text/plain; charset=utf-8"\n'
            printf '  header Cache-Control "public, max-age=3600"\n'
            printf '  header Referrer-Policy "no-referrer"\n'
            printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
            printf '  header X-Content-Type-Options "nosniff"\n'
            printf '  file_server\n'
            printf '}\n\n'
          } >> "$fragment_tmp"

          ${lib.concatMapStringsSep "\n" (ruleSet: ''
            {
              printf 'handle ${ruleSetMirrorPublicPath ruleSet.tag} {\n'
              printf '  root * %s\n' ${lib.escapeShellArg profileRoot}
              printf '  rewrite * /rules/${ruleSet.tag}.srs\n'
              printf '  header Content-Type "application/octet-stream"\n'
              printf '  header Cache-Control "public, max-age=3600"\n'
              printf '  header Referrer-Policy "no-referrer"\n'
              printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
              printf '  header X-Content-Type-Options "nosniff"\n'
              printf '  file_server\n'
              printf '}\n\n'
            } >> "$fragment_tmp"
          '') upstreamRuleSets}

          ${lib.concatMapStringsSep "\n" (ruleSet: ''
            {
              printf 'handle ${ruleSetMirrorMrsPublicPath ruleSet.tag} {\n'
              printf '  root * %s\n' ${lib.escapeShellArg profileRoot}
              printf '  rewrite * /rules/${ruleSet.tag}.mrs\n'
              printf '  header Content-Type "application/octet-stream"\n'
              printf '  header Cache-Control "public, max-age=3600"\n'
              printf '  header Referrer-Policy "no-referrer"\n'
              printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
              printf '  header X-Content-Type-Options "nosniff"\n'
              printf '  file_server\n'
              printf '}\n\n'
            } >> "$fragment_tmp"
          '') mihomoMrsUpstream}

          {
            printf 'handle ${secureDnsDomainsTxtPublicPath} {\n'
            printf '  root * %s\n' ${lib.escapeShellArg profileRoot}
            printf '  rewrite * /rules/secure-dns.txt\n'
            printf '  header Content-Type "text/plain; charset=utf-8"\n'
            printf '  header Cache-Control "public, max-age=3600"\n'
            printf '  header Referrer-Policy "no-referrer"\n'
            printf '  header X-Robots-Tag "noindex, nofollow, noarchive"\n'
            printf '  header X-Content-Type-Options "nosniff"\n'
            printf '  file_server\n'
            printf '}\n\n'
          } >> "$fragment_tmp"

          install -d -o caddy -g caddy -m 0750 ${lib.escapeShellArg "${profileRoot}/rules"}
          install -o caddy -g caddy -m 0444 ${lib.escapeShellArg personalProxyDomainsTxt} ${lib.escapeShellArg personalProxyDomainsTxtPath}

          ${lib.concatStringsSep "\n" (map profileCase generatedProfiles)}

          install -o root -g caddy -m 0640 "$fragment_tmp" ${lib.escapeShellArg caddyFragment}
          rm -f "$fragment_tmp"
        '';
      };

      caddy = {
        requires = [ "${generatorService}.service" ];
        after = [ "${generatorService}.service" ];
      };
    };
  };

  services.caddy.extraConfig = lib.mkAfter ''
    ${configGatewayDomain} {
      bind ${localPublicNetwork.caddyBindIPv4}
      tls /var/lib/acme/${localPublicNetwork.acme.config}/fullchain.pem /var/lib/acme/${localPublicNetwork.acme.config}/key.pem
      import ${caddyFragment}

      handle {
        respond 404
      }
    }
  '';
}
