{
  inputs,
  pkgs,
  root,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  privateDnsFixture = import ./fixtures/adguard-private-dns.nix;
  adguardPackage = self.packages.${system}.adguardhome;
  dnsproxyPackage = self.packages.${system}.dnsproxy;
  service = import ../clanServices/adguardhome/default.nix {
    adguardPackageFor = _: adguardPackage;
    dnsproxyPackageFor = _: dnsproxyPackage;
  };
  interface = service.roles.resolver.interface { inherit lib; };
  fixtureSettings = fixture.instances.dns-adguardhome.roles.resolver.machines.vpn-fixture.settings;
  baseSettings =
    lib.recursiveUpdate
      (
        (builtins.removeAttrs fixtureSettings [
          "acme"
          "ingress"
        ])
        // {
          ui = builtins.removeAttrs fixtureSettings.ui [ "domain" ];
        }
      )
      {
        tls = {
          certificateFile = "/run/certificates/adguardhome/fullchain.pem";
          privateKeyFile = "/run/certificates/adguardhome/key.pem";
        };
      };
  evalSettings =
    rawSettings:
    (lib.evalModules {
      modules = [
        interface
        { config = rawSettings; }
      ];
    }).config;
  schemaAccepts =
    rawSettings: (builtins.tryEval (builtins.deepSeq (evalSettings rawSettings) true)).success;
  moduleFor =
    rawSettings: config:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.resolver.perInstance {
        inherit settings;
        instanceName = "dns-adguardhome";
        machine.name = "vpn-fixture";
      };
      module = instance.nixosModule { inherit config lib pkgs; };
    in
    module.config;
  # Evaluate security assertions against native NixOS option merging, including
  # systemd's preStart -> ExecStartPre projection and real sops template paths.
  evaluate =
    rawSettings: extraModule:
    let
      instance = service.roles.resolver.perInstance {
        settings = evalSettings rawSettings;
        instanceName = "dns-adguardhome";
        machine.name = "vpn-fixture";
      };
      evaluated = lib.nixosSystem {
        inherit system;
        modules = [
          (lib.setDefaultModuleLocation "adguardhome-fixture-owned" instance.nixosModule)
          inputs.clan-core.inputs.sops-nix.nixosModules.sops
          ({ lib, ... }: {
            options.clan.core.state = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options.folders = lib.mkOption { type = lib.types.listOf lib.types.str; };
                }
              );
              default = { };
            };
            config = {
              nixpkgs.pkgs = inputs.nixpkgs.legacyPackages.${system};
              boot.isContainer = true;
              system.stateVersion = "26.11";
              sops = {
                defaultSopsFile = ./fixtures/empty-sops.yaml;
                age.keyFile = "/run/vpn-fixture/age-key";
                validateSopsFiles = false;
              };
            };
          })
          extraModule
        ];
      };
      ownedAssertions = lib.concatMap (definition: definition.value) (
        builtins.filter (
          definition: definition.file == "adguardhome-fixture-owned"
        ) evaluated.options.assertions.definitionsWithLocations
      );
      ownedValues = map (entry: entry.assertion) ownedAssertions;
      nativeValues = map (entry: entry.assertion) evaluated.config.assertions;
    in
    evaluated.config
    // {
      assertions = ownedAssertions;
      ownedAssertionsPass = builtins.deepSeq ownedValues (
        ownedAssertions != [ ] && builtins.all (value: value) ownedValues
      );
      nativeAssertionsPass = builtins.deepSeq nativeValues (builtins.all (value: value) nativeValues);
    };
  baselineConfig = evaluate baseSettings { };
  placeholderConfig = baselineConfig;
  baselineModule = moduleFor baseSettings baselineConfig;
  # Select only this module's definition values by source metadata above.
  # Native diagnostics are never examined or deep-forced on successful cases.
  matchesMessage = predicate: entry: predicate entry.message;
  ownedAssertion =
    message: assertions:
    let
      selected = builtins.filter (matchesMessage (value: value == message)) assertions;
    in
    assert builtins.length selected == 1;
    (builtins.head selected).assertion;
  assertionFor =
    message: rawSettings: extraModule:
    ownedAssertion message (evaluate rawSettings extraModule).assertions;
  rejectsSetting = message: rawSettings: !(assertionFor message rawSettings { });
  active = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = [ "dns-adguardhome" ];
    includeNetwork = false;
  };
  twoActiveAttempt = builtins.tryEval (
    builtins.deepSeq ((import ./lib/consumer.nix { inherit inputs root self; }) {
      instances = {
        dns-adguardhome = fixture.instances.dns-adguardhome;
        dns-second-adguardhome = fixture.instances.dns-adguardhome;
      };
      includeNetwork = false;
      fixtureName = "vpn-adguard-two-active-fixture";
    }) true
  );
  activeWithDisabled = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instances = {
      dns-adguardhome = fixture.instances.dns-adguardhome;
      dns-disabled-adguardhome = lib.recursiveUpdate fixture.instances.dns-adguardhome {
        roles.resolver.machines.vpn-fixture.settings.enable = false;
      };
    };
    includeNetwork = false;
    fixtureName = "vpn-adguard-active-disabled-fixture";
  };
  disabledModule = moduleFor (baseSettings // { enable = false; }) {
    clanwright.dns.adguardhome.activeInstances = [ ];
  };
  duplicateInstancesModule = evaluate baseSettings {
    clanwright.dns.adguardhome.activeInstances = [ "dns-second-adguardhome" ];
  };
  missingInstanceClaimModule = evaluate baseSettings {
    clanwright.dns.adguardhome.activeInstances = lib.mkForce [ ];
  };
  disabledSiblingModule = moduleFor (baseSettings // { enable = false; }) placeholderConfig;
  privateSettings = lib.recursiveUpdate baseSettings {
    dns = privateDnsFixture;
    filtering.userRules = [
      "! important note"
      "||important.example.invalid^"
      "||telemetry.example.invalid^"
    ];
  };
  privateModule = evaluate privateSettings { };
  privateEffective =
    builtins.fromJSON
      privateModule.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  privateFilteringDisabledSettings = lib.recursiveUpdate privateSettings {
    filtering.enable = false;
  };
  privateFilteringDisabledModule = evaluate privateFilteringDisabledSettings { };
  privateFilteringDisabledEffective =
    builtins.fromJSON
      privateFilteringDisabledModule.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  privateDisabledModule = moduleFor (privateSettings // { enable = false; }) {
    clanwright.dns.adguardhome.activeInstances = [ ];
  };
  sharedEvaluation = lib.evalModules {
    modules = [ ../clanServices/adguardhome/shared.nix ];
  };
  disabledIntegration = sharedEvaluation.config.clanwright.dns.adguardhome.integration;
  customRulesAccepted = effective.user_rules == baseSettings.filtering.userRules;
  timeoutAssertionMessage = "adguardhome: retry-aware silent DNS failure model requires five dnsproxy attempts within each AdGuard upstream attempt and four AdGuard attempts within the consumer budget, including one second of scheduling and loopback allowance; it models silence only, not TCP truncation, slow connects, or filtering-helper guarantees.";
  alternateTimeoutSettings = lib.recursiveUpdate baseSettings {
    dns = {
      upstreamTimeoutSeconds = 11;
      fallbackTimeoutSeconds = 2;
      silentFailureBudgetSeconds = 45;
    };
  };
  alternateTimeoutModule = evaluate alternateTimeoutSettings { };
  alternateTimeoutEffective =
    builtins.fromJSON
      alternateTimeoutModule.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  settingOverrideResults = [
    (rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ ]; }
    ))
    (rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ "8.8.8.8:53" ]; }
    ))
    (rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ "127.0.0.1:0" ]; }
    ))
    (rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ "127.0.0.1:65536" ]; }
    ))
    (rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ "127.0.0.1:not-a-port" ]; }
    ))
    (rejectsSetting "adguardhome: dns.bindHosts must be unique private addresses and include 127.0.0.1."
      (baseSettings // { dns.bindHosts = [ "0.0.0.0" ]; })
    )
    (rejectsSetting timeoutAssertionMessage (
      lib.recursiveUpdate baseSettings {
        dns = {
          upstreamTimeoutSeconds = 15;
          fallbackTimeoutSeconds = 3;
        };
      }
    ))
    (rejectsSetting
      "adguardhome: listener ports must be nonzero and distinct; DoT must remain disabled."
      (baseSettings // { dns.fallbackPort = 5335; })
    )
    (rejectsSetting
      "adguardhome: the enabled system resolver must target configured AdGuard listeners on port 53."
      (lib.recursiveUpdate baseSettings { systemResolver.nameservers = [ "127.0.0.2" ]; })
    )
  ];
  rejectsOverride = message: extraModule: !(assertionFor message baseSettings extraModule);
  packageOverrideResults = [
    (rejectsOverride "adguardhome: the runtime package must come from the VPN domain platform pin." {
      services.adguardhome.package = lib.mkOverride 0 pkgs.hello;
    })
    (rejectsOverride
      "adguardhome: the fallback dnsproxy package must come from the VPN domain platform pin."
      { services.dnsproxy.package = lib.mkOverride 0 pkgs.hello; }
    )
  ];
  dnsproxyOverrideResults =
    map
      (rejectsOverride "adguardhome: dnsproxy settings and flags must preserve the loopback encrypted-to-plaintext cascade.")
      [
        { services.dnsproxy.settings.listen-addrs = lib.mkForce [ "0.0.0.0" ]; }
        { services.dnsproxy.settings.upstream = lib.mkForce [ "1.1.1.1:53" ]; }
        { services.dnsproxy.settings.fallback = lib.mkForce [ ]; }
        { services.dnsproxy.settings.insecure = lib.mkForce true; }
        { services.dnsproxy.settings.timeout = lib.mkForce "4s"; }
        { services.dnsproxy.flags = lib.mkForce [ "--insecure" ]; }
      ];
  templateOverrideRejected =
    rejectsOverride "adguardhome: the final template must exactly preserve the generated policy."
      {
        sops.templates."dns-adguardhome-adguardhome.yaml".content = lib.mkForce "{}";
      };
  startupOverrideResults =
    lib.imap0
      (
        index: extraModule:
        rejectsOverride (
          if index < 3 then
            "adguardhome: the native service must retain credential-owned settings and closed firewall defaults."
          else
            "adguardhome: the effective native unit must install and validate its credential before starting the closed DNS runtime without DHCP capabilities."
        ) extraModule
      )
      [
        { services.adguardhome.enable = lib.mkForce false; }
        { services.adguardhome.extraArgs = [ "--config /run/override.yaml" ]; }
        { services.adguardhome.allowDHCP = true; }
        {
          systemd.services.adguardhome.serviceConfig.LoadCredential = lib.mkForce "config:/run/override.yaml";
        }
        { systemd.services.adguardhome.serviceConfig.ExecStartPre = lib.mkForce [ ]; }
        { systemd.services.adguardhome.serviceConfig.ExecStartPre = lib.mkForce [ "echo bypass" ]; }
        { systemd.services.adguardhome.serviceConfig.ExecStart = lib.mkForce "echo bypass"; }
        { systemd.services.adguardhome.preStart = "echo bypass"; }
        { systemd.services.adguardhome.serviceConfig.DynamicUser = lib.mkForce false; }
        { systemd.services.adguardhome.serviceConfig.StateDirectory = lib.mkForce "OtherState"; }
        { systemd.services.adguardhome.serviceConfig.RuntimeDirectory = lib.mkForce "OtherRuntime"; }
        { systemd.services.adguardhome.serviceConfig.NoNewPrivileges = lib.mkForce false; }
        { systemd.services.adguardhome.serviceConfig.ProtectSystem = lib.mkForce false; }
        {
          systemd.services.adguardhome.serviceConfig.CapabilityBoundingSet = lib.mkForce [ "CAP_NET_RAW" ];
        }
        { systemd.services.adguardhome.serviceConfig.AmbientCapabilities = lib.mkForce [ "CAP_NET_RAW" ]; }
        {
          systemd.services.adguardhome.serviceConfig.RestrictAddressFamilies = lib.mkForce [
            "AF_INET"
            "AF_PACKET"
          ];
        }
      ];
  inherit (active) machine;
  templateNames = builtins.filter (lib.hasSuffix "-adguardhome.yaml") (
    builtins.attrNames machine.sops.templates
  );
  templateName = builtins.head templateNames;
  template = machine.sops.templates.${templateName};
  rawTemplate = baselineModule.sops.templates."dns-adguardhome-adguardhome.yaml";
  effective = builtins.fromJSON rawTemplate.content;
  placeholder = placeholderConfig.sops.placeholder.${baseSettings.auth.passwordSecretName};
  secret = machine.sops.secrets.${baseSettings.auth.passwordSecretName};
  adguardUnit = machine.systemd.services.adguardhome;
  dnsproxyUnit = machine.systemd.services.dnsproxy;
  dnsproxySettings = machine.services.dnsproxy.settings;
  expectedEncrypted = [
    "sdns://AgEAAAAAAAAABzEuMS4xLjEAEmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5"
    "sdns://AgEAAAAAAAAACDkuOS45LjEwABNkbnMxMC5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk"
    "sdns://AgEAAAAAAAAABzguOC44LjgACmRucy5nb29nbGUKL2Rucy1xdWVyeQ"
  ];
  malformedQuad9Stamp = "sdns://AgEAAAAAAAAACDkuOS45LjEwABRkbnMxMC5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk";
  stampExpectations = [
    {
      address = "1.1.1.1";
      hostname = "cloudflare-dns.com";
    }
    {
      address = "9.9.9.10";
      hostname = "dns10.quad9.net:443";
    }
    {
      address = "8.8.8.8";
      hostname = "dns.google";
    }
  ];
  base64UrlValues = builtins.listToAttrs (
    lib.imap0 (value: name: { inherit name value; }) (
      lib.stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )
  );
  modulo = dividend: divisor: dividend - builtins.div dividend divisor * divisor;
  decodeBase64Url =
    encoded:
    let
      characters = lib.stringToCharacters encoded;
      count = builtins.length characters;
      remainder = modulo count 4;
      characterAt =
        offset:
        assert offset >= 0 && offset < count;
        builtins.elemAt characters offset;
      valueAt = offset: base64UrlValues.${characterAt offset};
      decodeGroup =
        offset:
        if offset >= count then
          [ ]
        else
          let
            remaining = count - offset;
            first = valueAt offset;
            second = valueAt (offset + 1);
            third = if remaining > 2 then valueAt (offset + 2) else 0;
            fourth = if remaining > 3 then valueAt (offset + 3) else 0;
          in
          [ (first * 4 + builtins.div second 16) ]
          ++ lib.optional (remaining > 2) (modulo second 16 * 16 + builtins.div third 4)
          ++ lib.optional (remaining > 3) (modulo third 4 * 64 + fourth)
          ++ decodeGroup (offset + 4);
    in
    assert remainder != 1;
    decodeGroup 0;
  characterIndex =
    wanted: characters:
    let
      find = index: if builtins.elemAt characters index == wanted then index else find (index + 1);
    in
    find 0;
  asciiByte =
    character:
    let
      digits = lib.stringToCharacters "0123456789";
      lowercase = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz";
    in
    if builtins.elem character digits then
      48 + characterIndex character digits
    else if builtins.elem character lowercase then
      97 + characterIndex character lowercase
    else
      {
        "." = 46;
        "/" = 47;
        ":" = 58;
        "-" = 45;
      }
      .${character};
  asciiBytes = value: map asciiByte (lib.stringToCharacters value);
  parseDohStamp =
    stamp:
    let
      encoded = lib.removePrefix "sdns://" stamp;
      bytes = decodeBase64Url encoded;
      byteCount = builtins.length bytes;
      byteAt =
        offset:
        assert offset >= 0 && offset < byteCount;
        builtins.elemAt bytes offset;
      slice =
        offset: length:
        assert offset >= 0 && length >= 0 && offset + length <= byteCount;
        builtins.genList (index: byteAt (offset + index)) length;
      parseLengthPrefixed =
        offset:
        let
          length = byteAt offset;
        in
        {
          next = offset + 1 + length;
          value = slice (offset + 1) length;
        };
      parseVariableLengthPrefixed =
        offset:
        let
          encodedLength = byteAt offset;
          length = modulo encodedLength 128;
          value = slice (offset + 1) length;
          next = offset + 1 + length;
        in
        if encodedLength < 128 then
          {
            inherit next;
            values = [ value ];
          }
        else
          let
            rest = parseVariableLengthPrefixed next;
          in
          {
            inherit (rest) next;
            values = [ value ] ++ rest.values;
          };
      address = parseLengthPrefixed 9;
      hashes = parseVariableLengthPrefixed address.next;
      hostname = parseLengthPrefixed hashes.next;
      path = parseLengthPrefixed hostname.next;
      bootstrap =
        if path.next == byteCount then
          {
            inherit (path) next;
            values = [ ];
          }
        else
          parseVariableLengthPrefixed path.next;
    in
    assert lib.hasPrefix "sdns://" stamp;
    {
      protocol = byteAt 0;
      properties = slice 1 8;
      addressBytes = address.value;
      hashes = hashes.values;
      hostnameBytes = hostname.value;
      pathBytes = path.value;
      bootstraps = bootstrap.values;
      complete = bootstrap.next == byteCount;
    };
  validDohStamp =
    expectation: stamp:
    let
      attempt = builtins.tryEval (builtins.deepSeq (parseDohStamp stamp) (parseDohStamp stamp));
    in
    attempt.success
    && attempt.value.protocol == 2
    &&
      attempt.value.properties == [
        1
        0
        0
        0
        0
        0
        0
        0
      ]
    && attempt.value.addressBytes == asciiBytes expectation.address
    && attempt.value.hashes == [ [ ] ]
    && attempt.value.hostnameBytes == asciiBytes expectation.hostname
    && attempt.value.pathBytes == asciiBytes "/dns-query"
    && attempt.value.bootstraps == [ ]
    && attempt.value.complete;
  validQuad9Stamp = builtins.elemAt expectedEncrypted 1;
  truncatedQuad9Stamp = lib.removeSuffix "k" validQuad9Stamp;
  appendedQuad9Stamp = "${validQuad9Stamp}AAA";
  expectedPlaintext = [
    "1.1.1.1:53"
    "9.9.9.10:53"
    "8.8.8.8:53"
  ];
  expectedPrivateUpstreams = [
    "[/internal.example.invalid/admin.example.invalid/]10.20.0.53:53"
    "[/internal.example.invalid/admin.example.invalid/][::1]:5354"
    "[/services.example.invalid/]192.168.50.53:5353"
  ];
  expectedPrivateRewrites = [
    {
      answer = "10.20.0.1";
      domain = "router.internal.example.invalid";
      enabled = true;
    }
    {
      answer = "router-ui.internal.example.invalid";
      domain = "control.admin.example.invalid";
      enabled = true;
    }
  ];
  expectedPrivateRules = [
    "@@||internal.example.invalid^$important,dnsrewrite"
    "@@||internal.example.invalid^$important"
    "@@||admin.example.invalid^$important,dnsrewrite"
    "@@||admin.example.invalid^$important"
    "@@||services.example.invalid^$important,dnsrewrite"
    "@@||services.example.invalid^$important"
  ];
  expectedPrivateDsGuards = [
    "||internal.example.invalid^$dnstype=DS"
    "||admin.example.invalid^$dnstype=DS"
    "||services.example.invalid^$dnstype=DS"
  ];
  schemaContract =
    schemaAccepts baseSettings
    && (evalSettings baseSettings).dns.privateZones == [ ]
    && (evalSettings baseSettings).dns.rewrites == [ ]
    && (evalSettings baseSettings).filtering.enable
    && !(schemaAccepts (baseSettings // { unexpected = true; }))
    && !(schemaAccepts (baseSettings // { dns.port = "53"; }))
    && !(schemaAccepts (baseSettings // { dns.fallbackTimeoutSeconds = 0; }))
    && !(schemaAccepts (baseSettings // { dns.fallbackTimeoutSeconds = -1; }))
    && !(schemaAccepts (baseSettings // { dns.fallbackTimeoutSeconds = 1.5; }))
    && !(schemaAccepts (baseSettings // { dns.fallbackTimeoutSeconds = "3"; }))
    && !(schemaAccepts (baseSettings // { dns.fallbackTimeoutSeconds = 9223372037; }))
    && !(schemaAccepts (baseSettings // { dns.upstreamTimeoutSeconds = 0; }))
    && !(schemaAccepts (baseSettings // { dns.upstreamTimeoutSeconds = -1; }))
    && !(schemaAccepts (baseSettings // { dns.upstreamTimeoutSeconds = 1.5; }))
    && !(schemaAccepts (baseSettings // { dns.upstreamTimeoutSeconds = "16"; }))
    && !(schemaAccepts (baseSettings // { dns.upstreamTimeoutSeconds = 9223372037; }))
    && !(schemaAccepts (baseSettings // { dns.silentFailureBudgetSeconds = 0; }))
    && !(schemaAccepts (baseSettings // { dns.silentFailureBudgetSeconds = -1; }))
    && !(schemaAccepts (baseSettings // { dns.silentFailureBudgetSeconds = 1.5; }))
    && !(schemaAccepts (baseSettings // { dns.silentFailureBudgetSeconds = "65"; }))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings {
        filtering.userRules = "||invalid.example^";
      }
    ))
    && rejectsSetting "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint." (
      baseSettings // { dns.upstream = [ "127.0.0.1:not-a-port" ]; }
    )
    && !(schemaAccepts (baseSettings // { lifecycle = "enabled"; }))
    && !(schemaAccepts (lib.recursiveUpdate baseSettings { auth.enable = true; }))
    && !(schemaAccepts (lib.recursiveUpdate baseSettings { tls.dotPort = 0; }))
    && !(schemaAccepts (baseSettings // { ingress = { }; }))
    && !(schemaAccepts (baseSettings // { acme.certName = "example.invalid"; }))
    && !(schemaAccepts (lib.recursiveUpdate baseSettings { ui.domain = "adguard.example.invalid"; }))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings { tls.certificateFile = "relative/cert.pem"; }
    ))
    && !(schemaAccepts (lib.recursiveUpdate baseSettings { tls.privateKeyFile = "relative/key.pem"; }));
  privateSchemaResults = {
    fixtureAccepted = schemaAccepts privateSettings;
    emptyDomainsRejected =
      !(schemaAccepts (
        lib.recursiveUpdate baseSettings {
          dns.privateZones = [
            {
              domains = [ ];
              upstreams = [ { address = "10.0.0.53"; } ];
            }
          ];
        }
      ));
    emptyUpstreamsRejected =
      !(schemaAccepts (
        lib.recursiveUpdate baseSettings {
          dns.privateZones = [
            {
              domains = [ "internal.example.invalid" ];
              upstreams = [ ];
            }
          ];
        }
      ));
    closedZoneRejected =
      !(schemaAccepts (
        lib.recursiveUpdate privateSettings {
          dns.privateZones = privateDnsFixture.privateZones ++ [
            {
              domains = [ "extra.example.invalid" ];
              upstreams = [ { address = "10.0.0.53"; } ];
              unexpected = true;
            }
          ];
        }
      ));
    closedUpstreamRejected =
      !(schemaAccepts (
        lib.recursiveUpdate privateSettings {
          dns.privateZones = [
            {
              domains = [ "internal.example.invalid" ];
              upstreams = [
                {
                  address = "10.0.0.53";
                  transport = "udp";
                }
              ];
            }
          ];
        }
      ));
    closedRewriteRejected =
      !(schemaAccepts (
        lib.recursiveUpdate privateSettings {
          dns.rewrites = [
            {
              domain = "router.internal.example.invalid";
              answer = "10.0.0.1";
              enabled = false;
            }
          ];
        }
      ));
  };
  privateAssertionResults = {
    benignImportantTextAccepted =
      assertionFor
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        privateSettings
        { };
    malformedZoneRejected =
      !(schemaAccepts (
        lib.recursiveUpdate baseSettings {
          dns.privateZones = [
            {
              domains = [ "*.Internal.example.invalid." ];
              upstreams = [ { address = "10.0.0.53"; } ];
            }
          ];
        }
      ));
    duplicateZoneRejected =
      rejectsSetting
        "adguardhome: private zone domains must be unique canonical lowercase DNS names without wildcards or trailing dots."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [ { address = "10.0.0.53"; } ];
              }
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [ { address = "192.168.0.53"; } ];
              }
            ];
          }
        );
    publicEndpointRejected =
      !(schemaAccepts (
        lib.recursiveUpdate baseSettings {
          dns.privateZones = [
            {
              domains = [ "internal.example.invalid" ];
              upstreams = [ { address = "8.8.8.8"; } ];
            }
          ];
        }
      ));
    hostnameEndpointRejected =
      !(schemaAccepts (
        lib.recursiveUpdate baseSettings {
          dns.privateZones = [
            {
              domains = [ "internal.example.invalid" ];
              upstreams = [ { address = "resolver.internal.example.invalid"; } ];
            }
          ];
        }
      ));
    zeroPortRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [
                  {
                    address = "10.0.0.53";
                    port = 0;
                  }
                ];
              }
            ];
          }
        );
    duplicateEndpointRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [
                  { address = "10.0.0.53"; }
                  { address = "10.0.0.53"; }
                ];
              }
            ];
          }
        );
    ownListenerRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns = {
              bindHosts = [
                "127.0.0.1"
                "10.0.0.53"
              ];
              privateZones = [
                {
                  domains = [ "internal.example.invalid" ];
                  upstreams = [ { address = "10.0.0.53"; } ];
                }
              ];
            };
          }
        );
    unboundLoopRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [
                  {
                    address = "127.0.0.1";
                    port = 5335;
                  }
                ];
              }
            ];
          }
        );
    fallbackLoopRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [
                  {
                    address = "::1";
                    port = 5336;
                  }
                ];
              }
            ];
          }
        );
    outsideSourceRejected =
      rejectsSetting
        "adguardhome: private rewrite sources must be unique canonical lowercase DNS names within a declared private zone."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "outside.example.invalid";
                answer = "10.0.0.1";
              }
            ];
          }
        );
    siblingSourceRejected =
      rejectsSetting
        "adguardhome: private rewrite sources must be unique canonical lowercase DNS names within a declared private zone."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "evilinternal.example.invalid";
                answer = "10.0.0.1";
              }
            ];
          }
        );
    duplicateSourceRejected =
      rejectsSetting
        "adguardhome: private rewrite sources must be unique canonical lowercase DNS names within a declared private zone."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "router.internal.example.invalid";
                answer = "10.0.0.1";
              }
              {
                domain = "router.internal.example.invalid";
                answer = "10.0.0.2";
              }
            ];
          }
        );
    publicAnswerRejected =
      !(schemaAccepts (
        lib.recursiveUpdate privateSettings {
          dns = {
            privateZones = privateDnsFixture.privateZones ++ [
              {
                domains = [ "8.8.8.8" ];
                upstreams = [ { address = "10.0.0.53"; } ];
              }
            ];
            rewrites = [
              {
                domain = "alias.8.8.8.8";
                answer = "8.8.8.8";
              }
            ];
          };
        }
      ));
    outsideCnameRejected =
      rejectsSetting
        "adguardhome: private rewrite answers must be private numeric IPs or canonical private-zone CNAME targets that are not rewrite sources."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "router.internal.example.invalid";
                answer = "outside.example.invalid";
              }
            ];
          }
        );
    siblingCnameRejected =
      rejectsSetting
        "adguardhome: private rewrite answers must be private numeric IPs or canonical private-zone CNAME targets that are not rewrite sources."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "router.internal.example.invalid";
                answer = "evilinternal.example.invalid";
              }
            ];
          }
        );
    selfAliasRejected =
      rejectsSetting
        "adguardhome: private rewrite answers must be private numeric IPs or canonical private-zone CNAME targets that are not rewrite sources."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "router.internal.example.invalid";
                answer = "router.internal.example.invalid";
              }
            ];
          }
        );
    aliasChainRejected =
      rejectsSetting
        "adguardhome: private rewrite answers must be private numeric IPs or canonical private-zone CNAME targets that are not rewrite sources."
        (
          lib.recursiveUpdate privateSettings {
            dns.rewrites = [
              {
                domain = "first.internal.example.invalid";
                answer = "second.internal.example.invalid";
              }
              {
                domain = "second.internal.example.invalid";
                answer = "10.0.0.2";
              }
            ];
          }
        );
    dnsrewriteRuleRejected =
      rejectsSetting
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        (
          lib.recursiveUpdate privateSettings {
            filtering.userRules = [ "||router.internal.example.invalid^$dnsrewrite=NOERROR;A;10.0.0.1" ];
          }
        );
    badfilterRuleRejected =
      rejectsSetting
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        (
          lib.recursiveUpdate privateSettings {
            filtering.userRules = [ "@@||internal.example.invalid^$BADFILTER" ];
          }
        );
    importantRuleRejected =
      rejectsSetting
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        (
          lib.recursiveUpdate privateSettings {
            filtering.userRules = [ "||router.internal.example.invalid^$ImPoRtAnT" ];
          }
        );
    importantValueRuleRejected =
      rejectsSetting
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        (
          lib.recursiveUpdate privateSettings {
            filtering.userRules = [ "||router.internal.example.invalid^$important=foo" ];
          }
        );
  };
  effectiveContract =
    baselineConfig.ownedAssertionsPass
    && baselineConfig.nativeAssertionsPass
    && builtins.all (entry: entry.assertion) machine.assertions
    && !twoActiveAttempt.success
    && activeWithDisabled.machine.clanwright.dns.adguardhome.activeInstances == [ "dns-adguardhome" ]
    && builtins.all (entry: entry.assertion) activeWithDisabled.machine.assertions
    && !(ownedAssertion "adguardhome: only one active instance may claim the native AdGuard Home and dnsproxy runtimes per machine." duplicateInstancesModule.assertions)
    && !(ownedAssertion "adguardhome: only one active instance may claim the native AdGuard Home and dnsproxy runtimes per machine." missingInstanceClaimModule.assertions)
    && builtins.all (entry: entry.assertion) disabledSiblingModule.assertions
    && (disabledSiblingModule.services or { }) == { }
    && (disabledSiblingModule.sops or { }) == { }
    && machine.services.adguardhome.enable
    && machine.services.adguardhome.package == adguardPackage
    && machine.services.adguardhome.settings == null
    && !machine.services.adguardhome.mutableSettings
    && machine.services.dnsproxy.enable
    && machine.services.dnsproxy.package == dnsproxyPackage
    && machine.services.dnsproxy.flags == [ ]
    && effective.http.address == "127.0.0.1:3000"
    && effective.dns.bind_hosts == [ "127.0.0.1" ]
    && effective.dns.upstream_dns == [ "127.0.0.1:5335" ]
    && effective.dns.fallback_dns == [ "127.0.0.1:5336" ]
    && effective.dns.bootstrap_dns == [ ]
    && effective.dns.upstream_mode == "load_balance"
    && effective.dns.upstream_timeout == "16s"
    && effective.dns.enable_dnssec
    && effective.dns.cache_enabled
    && effective.dns.cache_ttl_min == 0
    && effective.dns.cache_ttl_max == 0
    && !effective.dns.cache_optimistic
    && !effective.dns.handle_ddr
    && !effective.dns.hostsfile_enabled
    && effective.dns.ratelimit == 0
    && effective.filtering.parental_enabled
    && effective.filtering.filtering_enabled
    && effective.filtering.rewrites_enabled
    && effective.filtering.protection_enabled
    && effective.filtering.rewrites == [ ]
    && effective.user_rules == baseSettings.filtering.userRules
    && effective.filtering.safe_search.enabled
    && !effective.filtering.safebrowsing_enabled
    && effective.querylog.interval == "168h"
    && effective.statistics.interval == "2160h"
    && !effective.dns.anonymize_client_ip
    && effective.tls.certificate_path == baseSettings.tls.certificateFile
    && effective.tls.private_key_path == baseSettings.tls.privateKeyFile
    &&
      effective.users == [
        {
          name = "admin";
          password = placeholder;
        }
      ];
  privateDnsContract =
    privateModule.ownedAssertionsPass
    && privateModule.nativeAssertionsPass
    && privateEffective.dns.upstream_dns == [ "127.0.0.1:5335" ] ++ expectedPrivateUpstreams
    && privateEffective.dns.fallback_dns == [ "127.0.0.1:5336" ] ++ expectedPrivateUpstreams
    &&
      privateEffective.dns.blocked_hosts == [
        "version.bind"
        "id.server"
        "hostname.bind"
      ]
      ++ expectedPrivateDsGuards
    && privateEffective.user_rules == expectedPrivateRules ++ privateSettings.filtering.userRules
    && privateEffective.filtering.rewrites == expectedPrivateRewrites
    && privateEffective.filtering.filtering_enabled
    && privateEffective.filtering.rewrites_enabled
    && privateEffective.filtering.protection_enabled
    && privateModule.services.dnsproxy.settings == baselineModule.services.dnsproxy.settings
    && privateModule.services.dnsproxy.flags == baselineModule.services.dnsproxy.flags;
  filteringDisabledContract =
    privateFilteringDisabledModule.ownedAssertionsPass
    && privateFilteringDisabledModule.nativeAssertionsPass
    && privateFilteringDisabledEffective.filtering.filtering_enabled
    && privateFilteringDisabledEffective.filtering.rewrites_enabled
    && !privateFilteringDisabledEffective.filtering.protection_enabled
    && privateFilteringDisabledEffective.filtering.rewrites == expectedPrivateRewrites
    && privateFilteringDisabledEffective.dns.upstream_dns == privateEffective.dns.upstream_dns
    && privateFilteringDisabledEffective.dns.fallback_dns == privateEffective.dns.fallback_dns
    && privateFilteringDisabledEffective.dns.blocked_hosts == privateEffective.dns.blocked_hosts
    && privateFilteringDisabledEffective.user_rules == privateEffective.user_rules
    &&
      builtins.removeAttrs privateFilteringDisabledEffective.filtering [ "protection_enabled" ]
      == builtins.removeAttrs privateEffective.filtering [ "protection_enabled" ];
  cascadeContract =
    dnsproxySettings.listen-addrs == [ "127.0.0.1" ]
    && dnsproxySettings.listen-ports == [ 5336 ]
    && dnsproxySettings.upstream == expectedEncrypted
    && dnsproxySettings.fallback == expectedPlaintext
    && dnsproxySettings.upstream-mode == "parallel"
    && dnsproxySettings.timeout == "3s"
    && dnsproxySettings.bootstrap == [ ]
    && !dnsproxySettings.cache
    && !dnsproxySettings.cache-optimistic
    && dnsproxySettings.dnssec
    && !dnsproxySettings.hosts-file-enabled
    && !dnsproxySettings.http3
    && !dnsproxySettings.insecure
    && dnsproxySettings.pending-requests-enabled
    && dnsproxySettings.ratelimit == 0
    && dnsproxyUnit.serviceConfig.DynamicUser
    && dnsproxyUnit.serviceConfig.NoNewPrivileges
    && dnsproxyUnit.serviceConfig.MemoryDenyWriteExecute
    &&
      dnsproxyUnit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_INET6"
      ];
  stampStructureContract =
    builtins.length dnsproxySettings.upstream == builtins.length stampExpectations
    && builtins.all (value: value) (
      lib.zipListsWith validDohStamp stampExpectations dnsproxySettings.upstream
    )
    && builtins.all (value: value) (builtins.attrValues stampNegativeResults);
  stampNegativeResults = {
    malformedLengthRejected =
      !(validDohStamp (builtins.elemAt stampExpectations 1) malformedQuad9Stamp);
    truncatedPayloadRejected =
      !(validDohStamp (builtins.elemAt stampExpectations 1) truncatedQuad9Stamp);
    appendedPayloadRejected = !(validDohStamp (builtins.elemAt stampExpectations 1) appendedQuad9Stamp);
  };
  credentialContract =
    builtins.length templateNames == 1
    && template.owner == "root"
    && template.group == "root"
    && template.mode == "0400"
    && template.restartUnits == [ "adguardhome.service" ]
    && secret.owner == "root"
    && secret.group == "root"
    && secret.mode == "0400"
    && secret.restartUnits == [ ]
    && !(lib.hasInfix "$2" rawTemplate.content)
    && adguardUnit.serviceConfig.LoadCredential == "config:${template.path}"
    && adguardUnit.serviceConfig.DynamicUser
    && adguardUnit.serviceConfig.StateDirectory == "AdGuardHome"
    && adguardUnit.serviceConfig.NoNewPrivileges
    && adguardUnit.serviceConfig.ProtectSystem == "strict"
    &&
      adguardUnit.serviceConfig.ExecStart
      == "${adguardPackage}/bin/AdGuardHome --no-check-update --pidfile /run/AdGuardHome/AdGuardHome.pid --work-dir /var/lib/AdGuardHome/ --config /var/lib/AdGuardHome/AdGuardHome.yaml"
    &&
      adguardUnit.serviceConfig.ExecStartPre == [
        "${pkgs.coreutils}/bin/install -m 600 %d/config /var/lib/AdGuardHome/AdGuardHome.yaml"
        "${adguardPackage}/bin/AdGuardHome -c /var/lib/AdGuardHome/AdGuardHome.yaml --check-config"
      ]
    && builtins.elem "dnsproxy.service" adguardUnit.wants
    && builtins.elem "dnsproxy.service" adguardUnit.after
    && !(builtins.elem "tailscaled.service" adguardUnit.wants)
    && !(builtins.elem "tailscaled.service" adguardUnit.after)
    && !(builtins.elem "tailscaled-autoconnect.service" adguardUnit.wants)
    && !(builtins.elem "tailscaled-autoconnect.service" adguardUnit.after)
    &&
      builtins.elem "sops-install-secrets.service" adguardUnit.after == machine.sops.useSystemdActivation
    &&
      builtins.elem "sops-install-secrets.service" adguardUnit.wants == machine.sops.useSystemdActivation
    && !(adguardUnit.serviceConfig ? SupplementaryGroups);
  integrationContract =
    !(baselineModule ? networkCore)
    && sharedEvaluation.options.clanwright.dns.adguardhome.integration.readOnly
    && disabledIntegration == null
    && ((baselineModule.networking or { }).firewall or { }) == { }
    &&
      machine.clanwright.dns.adguardhome.integration == {
        schemaVersion = 1;
        uiBackend = {
          host = baseSettings.ui.host;
          port = baseSettings.ui.port;
        };
        dohBackend = {
          host = baseSettings.ui.host;
          port = baseSettings.tls.httpsPort;
          serverName = baseSettings.tls.serverName;
        };
        reloadUnits = [ "adguardhome.service" ];
      };
  lifecycleContract =
    (disabledModule.services or { }) == { }
    && (disabledModule.systemd or { }) == { }
    && !(disabledModule ? networkCore)
    && disabledIntegration == null
    && ((disabledModule.sops or { }).templates or { }) == { }
    && ((disabledModule.sops or { }).secrets or { }) == { }
    && (disabledModule.clan or { }) == { };
  privateDisabledContract =
    (privateDisabledModule.services or { }) == { }
    && (privateDisabledModule.systemd or { }) == { }
    && !(privateDisabledModule ? networkCore)
    && ((privateDisabledModule.sops or { }).templates or { }) == { }
    && ((privateDisabledModule.sops or { }).secrets or { }) == { }
    && (privateDisabledModule.clan or { }) == { };
  privateSchemaContract = builtins.all (value: value) (builtins.attrValues privateSchemaResults);
  privateAssertionContract = builtins.all (value: value) (
    builtins.attrValues privateAssertionResults
  );
  negativeContract =
    customRulesAccepted
    && templateOverrideRejected
    && builtins.all (value: value) settingOverrideResults
    && builtins.all (value: value) packageOverrideResults
    && builtins.all (value: value) dnsproxyOverrideResults
    && builtins.all (value: value) startupOverrideResults;
  timeoutResults = {
    defaults =
      (evalSettings baseSettings).dns.upstreamTimeoutSeconds == 16
      && (evalSettings baseSettings).dns.fallbackTimeoutSeconds == 3
      && (evalSettings baseSettings).dns.silentFailureBudgetSeconds == 65;
    alternateAccepted =
      alternateTimeoutModule.ownedAssertionsPass
      && alternateTimeoutModule.nativeAssertionsPass
      && (assertionFor timeoutAssertionMessage alternateTimeoutSettings { })
      && alternateTimeoutEffective.dns.upstream_timeout == "11s"
      && alternateTimeoutModule.services.dnsproxy.settings.timeout == "2s";
    cascadeRejected = rejectsSetting timeoutAssertionMessage (
      lib.recursiveUpdate baseSettings {
        dns = {
          upstreamTimeoutSeconds = 15;
          fallbackTimeoutSeconds = 3;
        };
      }
    );
    budgetRejected = rejectsSetting timeoutAssertionMessage (
      lib.recursiveUpdate baseSettings {
        dns = {
          upstreamTimeoutSeconds = 16;
          silentFailureBudgetSeconds = 64;
        };
      }
    );
    oversizedFallbackRejected = rejectsSetting timeoutAssertionMessage (
      lib.recursiveUpdate baseSettings {
        dns = {
          upstreamTimeoutSeconds = 16;
          fallbackTimeoutSeconds = 9223372036;
        };
      }
    );
    boundaryAccepted = assertionFor timeoutAssertionMessage baseSettings { };
  };
  timeoutContract = builtins.all (value: value) (builtins.attrValues timeoutResults);
  contract =
    schemaContract
    && effectiveContract
    && cascadeContract
    && credentialContract
    && filteringDisabledContract
    && integrationContract
    && lifecycleContract
    && negativeContract
    && privateAssertionContract
    && privateDisabledContract
    && privateDnsContract
    && privateSchemaContract
    && stampStructureContract
    && timeoutContract;
in
if !contract then
  throw "AdGuard Home contract failed: ${
    builtins.toJSON {
      inherit
        cascadeContract
        credentialContract
        effectiveContract
        filteringDisabledContract
        integrationContract
        lifecycleContract
        negativeContract
        privateAssertionContract
        privateAssertionResults
        privateDisabledContract
        privateDnsContract
        privateSchemaContract
        privateSchemaResults
        schemaContract
        stampNegativeResults
        stampStructureContract
        timeoutContract
        timeoutResults
        ;
    }
  }"
else
  {
    all = true;
    inherit
      cascadeContract
      credentialContract
      effectiveContract
      filteringDisabledContract
      integrationContract
      lifecycleContract
      negativeContract
      privateAssertionContract
      privateAssertionResults
      privateDisabledContract
      privateDnsContract
      privateSchemaContract
      privateSchemaResults
      schemaContract
      stampNegativeResults
      stampStructureContract
      timeoutContract
      timeoutResults
      ;
  }
