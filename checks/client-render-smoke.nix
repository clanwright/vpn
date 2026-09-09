{
  inputs,
  root,
  self,
  ...
}:
let
  lib = inputs.nixpkgs.lib;
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
            imports = (fixture.machine.imports or [ ]) ++ [ renderCaptureModule ];
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
  linkUnitName = "vpn-client-profiles-links-${runtimeMachineName}";
  publisherWith =
    settings:
    lib.recursiveUpdate fixture.instances {
      vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings = settings;
    };
  rejectsInstances =
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
            machines.${fixtureMachineName} = _: fixture.machine;
            inventory = {
              meta.name = "vpn-consumer-${name}-fixture";
              machines.${fixtureMachineName} = { };
              inherit instances;
            };
          }
        ];
      };
    in
    !(builtins.tryEval (
      builtins.deepSeq
        candidate.config.nixosConfigurations.${fixtureMachineName}.config.system.build.toplevel.drvPath
        true
    )).success;
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
  consumerMachine = consumer.config.nixosConfigurations.${fixtureMachineName}.config;
  rendered = builtins.head consumerMachine.clanwright.checks.vpnClientProfileRender;
  zeroNaiveMachine = zeroNaiveConsumer.config.nixosConfigurations.${fixtureMachineName}.config;
  zeroNaiveRendered = builtins.head zeroNaiveMachine.clanwright.checks.vpnClientProfileRender;
  zeroNaiveLinksScript = zeroNaiveMachine.systemd.services.${linkUnitName}.script;
  linksScript = consumerMachine.systemd.services.${linkUnitName}.script;
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
  evaluatedDnsServers = map (rule: rule.server) (
    builtins.filter (rule: (rule.action or null) == "evaluate") profile.dns.rules
  );
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
    && vless.uuid == "__MIHOMO_VLESS_UUID_vpn-fixture__"
    && vless."reality-opts"."short-id" == "0123456789abcdef"
    && hysteria."obfs-min-packet-size" == 512
    && hysteria."obfs-max-packet-size" == 1200
    && hysteria.password == "__MIHOMO_HY2_PASSWORD_vpn-fixture_cHJvYmU__"
    && awg."private-key" == "__MIHOMO_AMNEZIAWG_PRIVATE_KEY_vpn-fixture__"
    && awg."amnezia-wg-option".version == 3
    &&
      awg."amnezia-wg-option"."header-protection-key"
      == "__MIHOMO_AMNEZIAWG_HEADER_PROTECTION_KEY_vpn-fixture_cHJvYmU__"
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
    && dnsIndex < protectedUdpIndex
    && privateIndex < protectedUdpIndex
    && multicastIndex < protectedUdpIndex
    && privateIndex < globalUdpIndex
    && globalUdpIndex < globalFullIndex
    && protectedUdpIndex < protectedProxyIndex
    && builtins.all (rule: !(rule ? port)) (udpRejects profile);
  dnsContract =
    evaluatedDnsServers == [
      "edge-doh"
      "reserve-cloudflare"
      "reserve-quad9"
      "reserve-google"
      "plain-cloudflare"
      "plain-quad9"
      "plain-google"
    ]
    && (builtins.elemAt profile.dns.rules ((builtins.length profile.dns.rules) - 1)).action == "reject"
    && profile.dns.final == "edge-doh";
  zeroNaiveResults = {
    linksUnitPresent = builtins.hasAttr linkUnitName zeroNaiveMachine.systemd.services;
    mihomoLinksRetained =
      lib.hasInfix "/mihomo.yaml" zeroNaiveLinksScript
      && lib.hasInfix "/mihomo-full.yaml" zeroNaiveLinksScript;
    profileLinkSuppressed = !(lib.hasInfix "/profile.json" zeroNaiveLinksScript);
    publicationDisabled = !zeroNaiveRendered.publishProfileJson;
    templateSuppressed = zeroNaiveRendered.profileJsonTemplate == null;
  };
  zeroNaiveContract = builtins.all (value: value) (builtins.attrValues zeroNaiveResults);
  negativeResults = {
    inherit
      duplicateProfileRejected
      duplicateProviderRefRejected
      missingCredentialRejected
      unknownProfileRejected
      ;
    tokenLengthValidationPresent = lib.hasInfix "wc -c" linksScript;
    tokenPatternValidationPresent = lib.hasInfix "^[A-Za-z0-9_-]{32,128}$" linksScript;
    tokenRawByteValidationPresent = lib.hasInfix "trailing newline or NUL byte" linksScript;
  };
  negativeContract = builtins.all (value: value) (builtins.attrValues negativeResults);
  contract =
    mihomoContract
    && singBoxContract
    && routeContract
    && dnsContract
    && zeroNaiveContract
    && negativeContract;
in
if !contract then
  throw "Pure client renderer contract failed: ${
    builtins.toJSON {
      inherit
        dnsContract
        mihomoContract
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
      dnsContract
      mihomoContract
      negativeContract
      negativeResults
      routeContract
      singBoxContract
      zeroNaiveContract
      zeroNaiveResults
      ;
  }
