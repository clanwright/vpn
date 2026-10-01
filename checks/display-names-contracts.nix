{
  inputs,
  self,
  pkgs,
  ...
}:
let
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  manifestView = import ./lib/manifest-view.nix { inherit lib; };
  inherit (inputs.nixpkgs) lib;
  service = builtins.head self.clan.modules."@clanwright/vpn-client-profiles".imports;
  evalSettings =
    settings:
    (lib.evalModules {
      modules = [
        (service.roles.publisher.interface { inherit lib; })
        { config = settings; }
      ];
    }).config;
  accepts = settings: (builtins.tryEval (builtins.deepSeq (evalSettings settings) true)).success;

  manualGroup = "Ручной";
  autoGroup = "Авто";
  lithuania = {
    label = "A";
    country = "Литва";
    countryCode = "LT";
  };
  baseA = "🇱🇹 Литва · A";

  # Explicit selected connection records, with safe synthetic bindings.
  mkProvider =
    {
      machine,
      instanceId,
      protocol,
      display ? null,
    }:
    let
      endpoint = {
        hostname = "${instanceId}.example.invalid";
        ipv4 = "192.0.2.21";
        port = 443;
      };
      secretPrefix = "fixture-${machine}-${instanceId}";
      payloads = {
        naiveproxy = {
          inherit endpoint;
          clients.alice.passwordSecret = "${secretPrefix}-naive";
        };
        vless-xhttp = {
          inherit endpoint;
          clients.alice = {
            uuidSecret = "${secretPrefix}-vless";
            shortId = "0123456789abcdef";
          };
          reality = {
            serverName = "donor.example.invalid";
            publicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
            fingerprint = "firefox";
            supportX25519MLKEM768 = false;
          };
          xhttp.path = "/fixture";
          doh = {
            hostname = "dns-a.example.invalid";
            ipv4 = "192.0.2.53";
          };
        };
        amneziawg = {
          inherit endpoint;
          serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          headerProtectionKeySecret = "${secretPrefix}-awg-header";
          clients.alice = {
            ipv4 = "10.77.0.2";
            privateKeySecret = "${secretPrefix}-awg";
            keepaliveSeconds = 25;
          };
        };
        anytls = {
          inherit endpoint;
          clients.alice.passwordSecret = "${secretPrefix}-anytls";
        };
      };
    in
    {
      inherit machine instanceId display;
      connection.${protocol} = payloads.${protocol};
      profileClients.alice = "alice";
    };

  settings = {
    localMachineName = "publisher-a";
    publicIPv4 = "192.0.2.31";
    edgeDomain = "edge-a.example.invalid";
    configGatewayDomain = "profiles-a.example.invalid";
    clientDnsEndpoints = [
      {
        domain = "dns-a.example.invalid";
        ipv4 = "192.0.2.53";
        port = 443;
        path = "/dns-query";
      }
    ];
    tailnetAdminDomains = [ "admin.example.invalid" ];
    personalProxyDomains = [ "personal.example.invalid" ];
  };
  aliceProfile = autoProtocols: {
    name = "alice";
    pathTokenSecretName = "publisher-a-alice-path-token";
    kind = "mobile";
    publishProfileJson = true;
    inherit autoProtocols;
  };
  allProtocols = [
    "naiveproxy"
    "vless-xhttp"
    "anytls"
    "amneziawg"
  ];
  render =
    providers:
    manifestView
      (import ../clanServices/vpn-client-profiles/client-profiles.nix {
        inherit lib pkgs providers;
        settings = settings // {
          profiles = [ (aliceProfile allProtocols) ];
        };
      }).manifest;
  renderedOf = providers: builtins.head (render providers).renderedProfiles;

  mihomoNames =
    rendered:
    map (proxy: proxy.name) (
      builtins.filter (proxy: proxy.type != "direct") rendered.mihomoSelectiveTemplate.proxies
    );
  mihomoNameOf =
    type: rendered:
    (builtins.head (
      builtins.filter (proxy: proxy.type == type) rendered.mihomoSelectiveTemplate.proxies
    )).name;
  singBoxOutbounds =
    type: rendered:
    builtins.filter (outbound: outbound.type == type) rendered.profileJsonTemplate.outbounds;
  singBoxNames =
    rendered:
    map (outbound: outbound.tag) (
      lib.concatMap (type: singBoxOutbounds type rendered) [
        "naive"
        "anytls"
      ]
    );
  sorted = lib.sort builtins.lessThan;
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;

  # The option type fills absent country fields with null; do the same here.
  withNullDefaults =
    display:
    if display == null then
      null
    else
      {
        country = null;
        countryCode = null;
      }
      // display;
  provider =
    args:
    let
      merged = {
        machine = "edge-a";
        display = lithuania;
      }
      // args;
    in
    mkProvider (merged // { display = withNullDefaults merged.display; });

  # (a) Country and code render as flag, country and label.
  singleAnytls = renderedOf [
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
    })
  ];
  labelOnly = renderedOf [
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
      display.label = "B";
    })
  ];
  countryResults = {
    mihomoFlagCountryLabel = mihomoNames singleAnytls == [ baseA ];
    singBoxFlagCountryLabel = singBoxNames singleAnytls == [ baseA ];
    literalExpectation = baseA == "🇱🇹 Литва · A";
    labelWithoutCountryHasNoFlag =
      mihomoNames labelOnly == [ "B" ] && singBoxNames labelOnly == [ "B" ];
    otherFlag =
      mihomoNames (renderedOf [
        (provider {
          instanceId = "anytls-a";
          protocol = "anytls";
          display = {
            label = "C";
            country = "Германия";
            countryCode = "DE";
          };
        })
      ]) == [ "🇩🇪 Германия · C" ];
  };

  # (b) Protocols of one provider label gain their kind, in both formats.
  multiProtocol = renderedOf [
    (provider {
      instanceId = "vless-a";
      protocol = "vless-xhttp";
    })
    (provider {
      instanceId = "awg-a";
      protocol = "amneziawg";
    })
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
    })
    (provider {
      instanceId = "naive-a";
      protocol = "naiveproxy";
    })
  ];
  protocolSuffixResults = {
    mihomoKinds =
      sorted (mihomoNames multiProtocol) == sorted [
        "${baseA} · VLESS"
        "${baseA} · AWG"
        "${baseA} · AnyTLS"
      ];
    singBoxKinds =
      sorted (singBoxNames multiProtocol) == sorted [
        "${baseA} · Naive"
        "${baseA} · AnyTLS"
      ];
    anytlsNameIdenticalInBothFormats =
      mihomoNameOf "anytls" multiProtocol == (builtins.head (singBoxOutbounds "anytls" multiProtocol)).tag
      && mihomoNameOf "anytls" multiProtocol == "${baseA} · AnyTLS";
    # Names resolve over every provider of the profile, not per format: Naive
    # is absent from Mihomo but still forces the suffix on a sole Mihomo entry.
    formatAbsentProviderStillQualifies =
      let
        rendered = renderedOf [
          (provider {
            instanceId = "anytls-a";
            protocol = "anytls";
          })
          (provider {
            instanceId = "naive-a";
            protocol = "naiveproxy";
          })
        ];
      in
      mihomoNames rendered == [ "${baseA} · AnyTLS" ]
      &&
        sorted (singBoxNames rendered) == sorted [
          "${baseA} · Naive"
          "${baseA} · AnyTLS"
        ];
  };

  # (c) Same label and protocol on two providers gain an ordinal.
  duplicateProviders = renderedOf [
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
    })
    (provider {
      machine = "edge-b";
      instanceId = "anytls-b";
      protocol = "anytls";
    })
    (provider {
      machine = "edge-c";
      instanceId = "anytls-c";
      protocol = "anytls";
    })
  ];
  ordinalResults = {
    mihomoOrdinals =
      mihomoNames duplicateProviders == [
        "${baseA} · AnyTLS"
        "${baseA} · AnyTLS 2"
        "${baseA} · AnyTLS 3"
      ];
    singBoxOrdinalsMatchMihomo = singBoxNames duplicateProviders == mihomoNames duplicateProviders;
    namesUnique =
      builtins.length (lib.unique (mihomoNames duplicateProviders))
      == builtins.length (mihomoNames duplicateProviders);
  };

  # (d) display = null falls back to the machine name without a flag.
  fallbackRendered = renderedOf [
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
      display = null;
    })
  ];
  fallbackQualified = renderedOf [
    (provider {
      instanceId = "anytls-a";
      protocol = "anytls";
      display = null;
    })
    (provider {
      instanceId = "vless-a";
      protocol = "vless-xhttp";
      display = null;
    })
  ];
  reservedFallback = renderedOf [
    (provider {
      machine = "DIRECT";
      instanceId = "anytls-a";
      protocol = "anytls";
      display = null;
    })
  ];
  fallbackResults = {
    machineNameWithoutFlag =
      mihomoNames fallbackRendered == [ "edge-a" ] && singBoxNames fallbackRendered == [ "edge-a" ];
    machineNameQualifiedByKind =
      sorted (mihomoNames fallbackQualified) == sorted [
        "edge-a · AnyTLS"
        "edge-a · VLESS"
      ];
    # A machine name equal to a reserved client name never becomes a name.
    reservedMachineNameQualified =
      mihomoNames reservedFallback == [ "DIRECT · AnyTLS" ]
      && singBoxNames reservedFallback == [ "DIRECT · AnyTLS" ];
  };

  # (e) Generated names carry no instance id, profile name or hash.
  technicalIdentifiers = [
    "vless-a"
    "awg-a"
    "anytls-a"
    "naive-a"
    "alice"
    "vpn-"
    "edge-a.example"
  ];
  allVisibleNames =
    rendered:
    map (proxy: proxy.name) rendered.mihomoSelectiveTemplate.proxies
    ++ map (group: group.name) rendered.mihomoSelectiveTemplate."proxy-groups"
    ++ map (outbound: outbound.tag) rendered.profileJsonTemplate.outbounds;
  namesHaveNoTechnicalParts =
    rendered:
    builtins.all (
      name:
      builtins.all (part: !(lib.hasInfix part name)) technicalIdentifiers
      && builtins.match ".*[0-9a-f]{16,}.*" name == null
      && builtins.match ".*[A-Za-z0-9_-]{22,}.*" name == null
    ) (allVisibleNames rendered);
  technicalNameResults = {
    multiProtocol = namesHaveNoTechnicalParts multiProtocol;
    duplicates = namesHaveNoTechnicalParts duplicateProviders;
    fallback = namesHaveNoTechnicalParts fallbackQualified;
  };

  # (f) Only Ручной, Авто and GLOBAL exist, and there is no full variant.
  groupResults =
    let
      full = render [
        (provider {
          instanceId = "vless-a";
          protocol = "vless-xhttp";
        })
        (provider {
          instanceId = "anytls-a";
          protocol = "anytls";
        })
      ];
      noAuto =
        manifestView
          (import ../clanServices/vpn-client-profiles/client-profiles.nix {
            inherit lib pkgs;
            providers = [
              (provider {
                instanceId = "vless-a";
                protocol = "vless-xhttp";
              })
            ];
            settings = settings // {
              profiles = [ (aliceProfile [ ]) ];
            };
          }).manifest;
      groupNames =
        candidate:
        map (group: group.name)
          (builtins.head candidate.renderedProfiles).mihomoSelectiveTemplate."proxy-groups";
      globalOf =
        candidate:
        builtins.head (
          builtins.filter (group: group.name == "GLOBAL")
            (builtins.head candidate.renderedProfiles).mihomoSelectiveTemplate."proxy-groups"
        );
      outputs =
        candidate:
        map (artifact: artifact.outputName) (builtins.head candidate.manifest.profiles).artifacts;
    in
    {
      exactGroupsWithAuto =
        groupNames full == [
          manualGroup
          autoGroup
          "GLOBAL"
        ];
      globalOffersManualThenAuto =
        (globalOf full).proxies == [
          manualGroup
          autoGroup
        ];
      exactGroupsWithoutAuto =
        groupNames noAuto == [
          manualGroup
          "GLOBAL"
        ];
      globalOffersOnlyManualWithoutAuto = (globalOf noAuto).proxies == [ manualGroup ];
      noFullArtifact =
        outputs full == [
          "mihomo.yaml"
          "profile.json"
        ]
        && !(builtins.any (output: lib.hasInfix "full" output) (outputs noAuto))
        && !((builtins.head full.renderedProfiles) ? mihomoFullTemplate);
    };

  # (g) Invalid display data.
  countryOnly = rejects (
    mihomoNames (renderedOf [
      (provider {
        instanceId = "anytls-a";
        protocol = "anytls";
        display = {
          label = "A";
          country = "Литва";
        };
      })
    ])
  );
  codeOnly = rejects (
    mihomoNames (renderedOf [
      (provider {
        instanceId = "anytls-a";
        protocol = "anytls";
        display = {
          label = "A";
          countryCode = "LT";
        };
      })
    ])
  );
  countryOnlyInSingBox = rejects (
    singBoxNames (renderedOf [
      (provider {
        instanceId = "anytls-a";
        protocol = "anytls";
        display = {
          label = "A";
          country = "Литва";
        };
      })
    ])
  );
  refWith = display: {
    providerRefs = [
      {
        instanceId = "anytls-a";
        machine = "edge-a";
        clients.alice = "alice";
        inherit display;
      }
    ];
  };
  validRefAccepted = accepts (refWith lithuania);
  reservedLabels = [
    "DIRECT"
    "REJECT"
    "REJECT-DROP"
    "PASS-RULE"
    "PASS"
    "COMPATIBLE"
    "GLOBAL"
    "EXTERNAL-REJECT"
    manualGroup
    autoGroup
  ];
  invalidDisplayResults = {
    countryWithoutCodeFailsEvaluation = countryOnly && countryOnlyInSingBox;
    codeWithoutCountryFailsEvaluation = codeOnly;
    validReferenceAccepted = validRefAccepted;
    reservedLabelsRejected = builtins.all (
      label: !(accepts (refWith (lithuania // { inherit label; })))
    ) reservedLabels;
    reservedLabelAcceptedOnlyAsSubstring = accepts (refWith (lithuania // { label = "DIRECT 2"; }));
    malformedFieldsRejected = builtins.all (value: !(accepts (refWith value))) [
      (lithuania // { label = ""; })
      (lithuania // { label = " A"; })
      (lithuania // { label = "A "; })
      (lithuania // { label = "A\nB"; })
      (lithuania // { label = builtins.concatStringsSep "" (builtins.genList (_: "a") 65); })
      (lithuania // { countryCode = "lt"; })
      (lithuania // { countryCode = "LTU"; })
      (lithuania // { country = " Литва"; })
      (lithuania // { flag = "🇱🇹"; })
    ];
  };

  # A duplicate label between an external subscription and an own provider is
  # rejected at evaluation; the identifier fallback counts as a label.
  fixture = import ./fixtures/example-clan.nix;
  publisherCompiler = import ../clanServices/vpn-client-profiles/publisher.nix { inherit lib; };
  nativeExports = (import ./lib/provider-exports.nix { inherit inputs self; }) fixture.instances;
  externalSource = {
    urlSecretName = "fixture/subscription-url";
    profileNames = [ "cHJvYmU" ];
  };
  compiledWithExternal =
    externalSubscriptions:
    publisherCompiler.compile {
      inherit pkgs;
      instanceName = "vpn-client-profiles";
      exports = nativeExports;
      selectExports = inputs.clan-core.lib.selectExports;
      settings = fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings // {
        inherit externalSubscriptions;
      };
    };
  evaluates =
    candidate:
    let
      attempt = builtins.tryEval (
        builtins.deepSeq candidate.settings (manifestLib.validateManifest candidate.manifest)
      );
    in
    attempt.success && attempt.value;
  externalLabelResults = {
    ownLabelRejected =
      !(evaluates (compiledWithExternal {
        fixture = externalSource // {
          label = "A";
        };
      }));
    identifierFallbackRejected =
      !(evaluates (compiledWithExternal {
        A = externalSource;
      }));
    distinctLabelAccepted = evaluates (compiledWithExternal {
      fixture = externalSource // {
        label = "Skala";
      };
    });
    distinctIdentifierAccepted = evaluates (compiledWithExternal {
      fixture = externalSource;
    });
  };

  results = {
    inherit
      countryResults
      externalLabelResults
      fallbackResults
      groupResults
      invalidDisplayResults
      ordinalResults
      protocolSuffixResults
      technicalNameResults
      ;
  };
  allTrue =
    value: if builtins.isBool value then value else builtins.all allTrue (builtins.attrValues value);
in
if !allTrue results then
  throw "Display name contract failed: ${builtins.toJSON results}"
else
  {
    all = true;
    inherit results;
  }
