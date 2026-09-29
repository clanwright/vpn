{
  inputs,
  root,
  self,
  pkgs,
  ...
}:
let
  inherit (inputs.nixpkgs) lib;
  providerEnvelope = import ../modules/contracts/provider-envelope.nix { inherit lib; };
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

  # One synthetic provider with only the fields the renderer reads.
  mkProvider =
    {
      machine,
      instanceId,
      protocol,
      display ? null,
    }:
    let
      profileNames = [ "alice" ];
      domain = "${instanceId}.example.invalid";
      secretPrefix = "fixture-${machine}-${instanceId}";
      protocolData = {
        naiveproxy = {
          transportMetadata = {
            tlsServerName = domain;
            userNames = profileNames;
            port = 443;
          };
          secretNames.password.alice = "${secretPrefix}-naive";
        };
        vless-xhttp = {
          transportMetadata = {
            reality = {
              serverName = "donor.example.invalid";
              serverNames = [ "donor.example.invalid" ];
              target = "donor.example.invalid:443";
              publicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
              shortIdsByProfile.alice = "0123456789abcdef";
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
            realityPrivateKey = "${secretPrefix}-reality";
            vlessUuid.alice = "${secretPrefix}-vless";
          };
        };
        amneziawg = {
          transportMetadata = {
            serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            interfaceName = "awg-fixture";
            address = "10.77.0.1/24";
            mtu = 1280;
            peers = [
              {
                name = "alice";
                publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
                allowedIPs = [ "10.77.0.2/32" ];
                clientPersistentKeepalive = 25;
              }
            ];
          };
          secretNames = {
            clientPrivateKey.alice = "${secretPrefix}-awg";
            headerProtectionKey = "${secretPrefix}-awg-header";
          };
        };
        anytls = {
          transportMetadata = {
            tlsServerName = domain;
            userNames = profileNames;
          };
          secretNames.users.alice = "${secretPrefix}-anytls";
        };
      };
    in
    providerEnvelope.mkProvider (
      {
        inherit
          protocol
          machine
          instanceId
          profileNames
          ;
        endpoint = {
          inherit domain;
          ipv4 = "192.0.2.21";
          port = 443;
        };
      }
      // protocolData.${protocol}
    )
    // {
      inherit display;
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
    secretPrefix = "publisher-a";
    tailnetAdminDomains = [ "admin.example.invalid" ];
    personalProxyDomains = [ "personal.example.invalid" ];
  };
  aliceProfile = autoProtocols: {
    name = "alice";
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
    import ../clanServices/vpn-client-profiles/client-profiles.nix {
      inherit lib pkgs providers;
      settings = settings // {
        profiles = [ (aliceProfile allProtocols) ];
      };
    };
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
      noAuto = import ../clanServices/vpn-client-profiles/client-profiles.nix {
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
      };
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
        protocol = "anytls";
        profileNames = [ "alice" ];
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
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  instanceNames = builtins.filter (
    name: !(lib.hasPrefix "network-" name) && name != "edge-wildcard-certificate"
  ) (builtins.attrNames fixture.instances);
  externalSource = {
    urlSecretName = "fixture/subscription-url";
    profileNames = [ "cHJvYmU" ];
  };
  consumerWithExternal =
    name: externalSubscriptions:
    consume {
      inherit instanceNames;
      includeNetwork = true;
      fixtureName = "vpn-display-names-${name}-fixture";
      instanceOverrides.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings = {
        inherit externalSubscriptions;
      };
    };
  evaluates =
    candidate:
    (builtins.tryEval (builtins.deepSeq candidate.machine.system.build.toplevel.drvPath true)).success;
  externalLabelResults = {
    ownLabelRejected =
      !(evaluates (
        consumerWithExternal "same-label" {
          fixture = externalSource // {
            label = "A";
          };
        }
      ));
    identifierFallbackRejected = !(evaluates (consumerWithExternal "same-id" { A = externalSource; }));
    distinctLabelAccepted = evaluates (
      consumerWithExternal "distinct-label" {
        fixture = externalSource // {
          label = "Skala";
        };
      }
    );
    distinctIdentifierAccepted = evaluates (
      consumerWithExternal "distinct-id" { fixture = externalSource; }
    );
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
