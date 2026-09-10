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
    module.config // { inherit (module) options; };
  placeholderConfig = {
    sops.placeholder.${baseSettings.auth.passwordSecretName} =
      "<SOPS:fixture-adguard-bcrypt:PLACEHOLDER>";
  };
  baselineModule = moduleFor baseSettings placeholderConfig;
  baselineConfig = lib.recursiveUpdate placeholderConfig {
    services = {
      inherit (baselineModule.services) adguardhome dnsproxy;
    };
  };
  assertionFor =
    message: rawSettings: config:
    builtins.head (
      builtins.filter (entry: entry.message == message) (moduleFor rawSettings config).assertions
    );
  rejectsSetting =
    message: rawSettings: !(assertionFor message rawSettings placeholderConfig).assertion;
  active = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = [ "dns-adguardhome" ];
    includeNetwork = false;
  };
  disabledModule = moduleFor (baseSettings // { enable = false; }) { };
  privateSettings = lib.recursiveUpdate baseSettings {
    dns = privateDnsFixture;
    filtering.userRules = [
      "! important note"
      "||important.example.invalid^"
      "||telemetry.example.invalid^"
    ];
  };
  privateDeclaredModule = moduleFor privateSettings placeholderConfig;
  privateConfig = lib.recursiveUpdate placeholderConfig {
    services = {
      adguardhome = privateDeclaredModule.services.adguardhome // {
        package = adguardPackage;
      };
      dnsproxy = privateDeclaredModule.services.dnsproxy // {
        package = dnsproxyPackage;
      };
    };
    sops.templates = privateDeclaredModule.sops.templates;
  };
  privateModule = moduleFor privateSettings privateConfig;
  privateEffective =
    builtins.fromJSON
      privateModule.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  privateFilteringDisabledSettings = lib.recursiveUpdate privateSettings {
    filtering.enable = false;
  };
  privateFilteringDisabledDeclaredModule = moduleFor privateFilteringDisabledSettings placeholderConfig;
  privateFilteringDisabledConfig = lib.recursiveUpdate placeholderConfig {
    services = {
      adguardhome = privateFilteringDisabledDeclaredModule.services.adguardhome // {
        package = adguardPackage;
      };
      dnsproxy = privateFilteringDisabledDeclaredModule.services.dnsproxy // {
        package = dnsproxyPackage;
      };
    };
    sops.templates = privateFilteringDisabledDeclaredModule.sops.templates;
  };
  privateFilteringDisabledModule = moduleFor privateFilteringDisabledSettings privateFilteringDisabledConfig;
  privateFilteringDisabledEffective =
    builtins.fromJSON
      privateFilteringDisabledModule.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  privateDisabledModule = moduleFor (privateSettings // { enable = false; }) { };
  disabledIntegration =
    (lib.evalModules {
      modules = [
        {
          options.clanwright.dns.adguardhome.integration =
            disabledModule.options.clanwright.dns.adguardhome.integration;
        }
      ];
    }).config.clanwright.dns.adguardhome.integration;
  customRulesAccepted = effective.user_rules == baseSettings.filtering.userRules;
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
    (rejectsSetting
      "adguardhome: listener ports must be nonzero and distinct; DoT must remain disabled and two dnsproxy stages plus margin must fit the 10s outer budget."
      (baseSettings // { dns.fallbackTimeoutSeconds = 5; })
    )
    (rejectsSetting
      "adguardhome: listener ports must be nonzero and distinct; DoT must remain disabled and two dnsproxy stages plus margin must fit the 10s outer budget."
      (baseSettings // { dns.fallbackPort = 5335; })
    )
    (rejectsSetting
      "adguardhome: the enabled system resolver must target configured AdGuard listeners on port 53."
      (lib.recursiveUpdate baseSettings { systemResolver.nameservers = [ "127.0.0.2" ]; })
    )
  ];
  packageOverrideResults = [
    (
      !(assertionFor "adguardhome: the runtime package must come from the VPN domain platform pin."
        baseSettings
        (lib.recursiveUpdate baselineConfig { services.adguardhome.package = pkgs.hello; })
      ).assertion
    )
    (
      !(assertionFor
        "adguardhome: the fallback dnsproxy package must come from the VPN domain platform pin."
        baseSettings
        (lib.recursiveUpdate baselineConfig { services.dnsproxy.package = pkgs.hello; })
      ).assertion
    )
  ];
  dnsproxyOverrideResults =
    map
      (
        override:
        !(assertionFor
          "adguardhome: dnsproxy settings and flags must preserve the loopback encrypted-to-plaintext cascade."
          baseSettings
          (lib.recursiveUpdate baselineConfig { services.dnsproxy = override; })
        ).assertion
      )
      [
        { settings.listen-addrs = [ "0.0.0.0" ]; }
        { settings.upstream = [ "1.1.1.1:53" ]; }
        { settings.fallback = [ ]; }
        { settings.insecure = true; }
        { flags = [ "--insecure" ]; }
      ];
  templateOverrideRejected =
    !(assertionFor "adguardhome: the final template must exactly preserve the generated policy."
      baseSettings
      (
        lib.recursiveUpdate baselineConfig {
          sops.templates."dns-adguardhome-adguardhome.yaml".content = "{}";
        }
      )
    ).assertion;
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
    "sdns://AgEAAAAAAAAACDkuOS45LjEwABRkbnMxMC5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk"
    "sdns://AgEAAAAAAAAABzguOC44LjgACmRucy5nb29nbGUKL2Rucy1xdWVyeQ"
  ];
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
      (assertionFor
        "adguardhome: userRules must not use dnsrewrite, badfilter, or important modifiers when private zones are configured."
        privateSettings
        placeholderConfig
      ).assertion;
    malformedZoneRejected =
      rejectsSetting
        "adguardhome: private zone domains must be unique canonical lowercase DNS names without wildcards or trailing dots."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "*.Internal.example.invalid." ];
                upstreams = [ { address = "10.0.0.53"; } ];
              }
            ];
          }
        );
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
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [ { address = "8.8.8.8"; } ];
              }
            ];
          }
        );
    hostnameEndpointRejected =
      rejectsSetting
        "adguardhome: private DNS endpoints must be unique private numeric addresses with nonzero ports and must not loop to local DNS, Unbound, or fallback listeners."
        (
          lib.recursiveUpdate baseSettings {
            dns.privateZones = [
              {
                domains = [ "internal.example.invalid" ];
                upstreams = [ { address = "resolver.internal.example.invalid"; } ];
              }
            ];
          }
        );
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
      rejectsSetting
        "adguardhome: private rewrite answers must be private numeric IPs or canonical private-zone CNAME targets that are not rewrite sources."
        (
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
        );
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
    builtins.all (entry: entry.assertion) machine.assertions
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
    && effective.dns.upstream_timeout == "10s"
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
    builtins.all (entry: entry.assertion) privateModule.assertions
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
    builtins.all (entry: entry.assertion) privateFilteringDisabledModule.assertions
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
    && baselineModule.options.clanwright.dns.adguardhome.integration.readOnly
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
    && builtins.all (value: value) dnsproxyOverrideResults;
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
    && privateSchemaContract;
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
      ;
  }
