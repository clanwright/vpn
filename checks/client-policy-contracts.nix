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
        hysteria2 = {
          transportMetadata = {
            sni = domain;
            userNames = profileNames;
          };
          secretNames = {
            users = secretMap "hy2-${machine}" profileNames;
            obfsPassword = "fixture-hy2-obfs-${machine}";
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
      };
    in
    providerEnvelope.mkProvider (common // protocolData.${protocol});
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
      "hysteria2"
      "mieru"
    ];
  };
  matrixRenders = lib.mapAttrs (
    _: publisher: render publisher providers (map profile users)
  ) publishers;
  renderedByName =
    publisherName: name:
    builtins.head (
      builtins.filter (entry: entry.name == name) matrixRenders.${publisherName}.renderedProfiles
    );
  providerTag =
    user: provider:
    let
      id = "${toString (builtins.stringLength provider.machine)}-${provider.machine}-${toString (builtins.stringLength provider.instanceId)}-${provider.instanceId}";
      suffix =
        {
          naiveproxy = "edge";
          vless-xhttp = "vless";
          hysteria2 = "hysteria2";
          amneziawg = "amneziawg";
          mieru = "mieru";
        }
        .${provider.protocol};
    in
    "${id}-${user}-${suffix}";
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
            "hysteria2"
          ]
        ) renderedProfile.profileJsonTemplate.outbounds
      )
    );
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
  matrixResults = lib.mapAttrs (
    publisherName: publisher:
    lib.genAttrs users (
      user:
      let
        renderedProfile = renderedByName publisherName user;
      in
      {
        mihomoContainsExactlyCompatibleAuthorizedProviders =
          mihomoTags renderedProfile == sorted (
            map (providerTag user) (
              eligible user [
                "vless-xhttp"
                "hysteria2"
                "amneziawg"
                "mieru"
              ]
            )
          );
        singBoxContainsExactlyCompatibleAuthorizedProviders =
          singBoxTags renderedProfile == sorted (
            map (providerTag user) (
              eligible user [
                "naiveproxy"
                "hysteria2"
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
          && builtins.length renderedProfile.mihomoFullTemplate.dns.nameserver == 3
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
            automaticGroups = builtins.filter (group: group.type == "url-test") (
              renderedProfile.mihomoSelectiveTemplate."proxy-groups"
              ++ renderedProfile.mihomoFullTemplate."proxy-groups"
            );
            manualGroups = builtins.filter (group: group.type == "select") (
              renderedProfile.mihomoSelectiveTemplate."proxy-groups"
              ++ renderedProfile.mihomoFullTemplate."proxy-groups"
            );
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
      outputs = map (artifact: artifact.outputName) (builtins.head candidate.manifest.profiles).artifacts;
    in
    {
      artifactCompatibility =
        if protocol == "naiveproxy" then
          outputs == [ "profile.json" ]
          && renderedProfile.mihomoSelectiveTemplate == null
          && renderedProfile.mihomoFullTemplate == null
        else if protocol == "hysteria2" then
          outputs == [
            "mihomo.yaml"
            "mihomo-full.yaml"
            "profile.json"
          ]
        else
          outputs == [
            "mihomo.yaml"
            "mihomo-full.yaml"
          ]
          && renderedProfile.profileJsonTemplate == null;
      naiveOnlyProtectedUdpRejects =
        protocol != "naiveproxy"
        || builtins.any (
          rule:
          (rule.network or null) == "udp"
          && (rule.rule_set or [ ]) != [ ]
          && (rule.action or null) == "reject"
          && !(rule ? outbound)
        ) renderedProfile.profileJsonTemplate.route.rules;
    }
  );
  noAutoRender = render publishers.publisher-a providers [
    ((profile "alice") // { autoProtocols = [ ]; })
  ];
  noAutoProfile = builtins.head noAutoRender.renderedProfiles;
  noAutoMihomoGroups =
    noAutoProfile.mihomoSelectiveTemplate."proxy-groups"
    ++ noAutoProfile.mihomoFullTemplate."proxy-groups";
  noAutoSingBoxOutbounds = noAutoProfile.profileJsonTemplate.outbounds;
  noAutoResults = {
    noBackgroundTestsInEitherFormat =
      builtins.filter (group: group.type == "url-test") noAutoMihomoGroups == [ ]
      && builtins.filter (outbound: outbound.type == "urltest") noAutoSingBoxOutbounds == [ ];
    mihomoManualSelectorsRetainCompatibleProviders =
      let
        expectedTcp = map (providerTag "alice") (
          eligible "alice" [
            "vless-xhttp"
            "hysteria2"
            "mieru"
            "amneziawg"
          ]
        );
        expectedUdp = expectedTcp;
        selective = builtins.head (builtins.filter (group: group.name == "SELECTIVE") noAutoMihomoGroups);
        udp = builtins.head (builtins.filter (group: group.name == "UDP") noAutoMihomoGroups);
      in
      sorted selective.proxies == sorted expectedTcp
      && sorted udp.proxies == sorted expectedUdp
      &&
        builtins.head selective.proxies
        == providerTag "alice" (builtins.head (eligible "alice" [ "vless-xhttp" ]))
      &&
        builtins.head udp.proxies
        == providerTag "alice" (builtins.head (eligible "alice" [ "vless-xhttp" ]));
    singBoxManualSelectorsRetainCompatibleProviders =
      let
        expectedTcp = map (providerTag "alice") (
          eligible "alice" [
            "naiveproxy"
            "hysteria2"
          ]
        );
        expectedUdp = map (providerTag "alice") (eligible "alice" [ "hysteria2" ]);
        selective = builtins.head (
          builtins.filter (outbound: (outbound.tag or null) == "SELECTIVE") noAutoSingBoxOutbounds
        );
        udp = builtins.head (
          builtins.filter (outbound: (outbound.tag or null) == "UDP") noAutoSingBoxOutbounds
        );
      in
      sorted selective.outbounds == sorted expectedTcp
      && sorted udp.outbounds == sorted expectedUdp
      && selective.default == builtins.head selective.outbounds
      && udp.default == builtins.head udp.outbounds;
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
          "hysteria2"
          "hysteria2"
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
      matrixResults
      noAutoResults
      protocolOnlyResults
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
