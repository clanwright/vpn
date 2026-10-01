{ inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  clanLib = inputs.clan-core.lib;
  policy = import ../modules/contracts/protocol-policy.nix;
  identities = import ../modules/contracts/identities.nix { inherit lib; };
  vpnExports = import ../modules/contracts/vpn-exports.nix { inherit lib; };
  machine = "fixture.machine";
  instance = "fixture.provider";
  endpoint = {
    hostname = "vpn.example.invalid";
    ipv4 = "192.0.2.10";
    port = 443;
  };
  passwordPayload = {
    inherit endpoint;
    clients."device.one".passwordSecret = "fixture/device.one-password";
  };
  fixtures =
    lib.mapAttrs
      (_tag: payload: {
        schemaVersion = 3;
        connection.${_tag} = payload;
      })
      {
        naiveproxy = passwordPayload;
        anytls = passwordPayload;
        trusttunnel = passwordPayload;
        mieru = passwordPayload // {
          endpoint = builtins.removeAttrs endpoint [ "hostname" ];
        };
        vless-xhttp = {
          inherit endpoint;
          clients."device.one" = {
            uuidSecret = "fixture/device.one-vless-uuid";
            shortId = "0123456789abcdef";
          };
          reality = {
            serverName = "donor.example.invalid";
            publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
            fingerprint = "edge";
            supportX25519MLKEM768 = false;
          };
          xhttp.path = "/fixture";
          doh = {
            hostname = "dns.example.invalid";
            ipv4 = "192.0.2.53";
          };
        };
        amneziawg = {
          inherit endpoint;
          serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          headerProtectionKeySecret = "fixture/awg-header-protection-key";
          clients."device.one" = {
            ipv4 = "10.77.0.2";
            privateKeySecret = "fixture/device.one-awg-private-key";
            keepaliveSeconds = null;
          };
        };
      };
  evalDefinitions =
    definitions:
    (lib.evalModules {
      modules = [
        {
          options.provider = lib.mkOption {
            type = lib.types.submodule vpnExports.vpnProviderModule;
          };
        }
      ]
      ++ map (value: { config.provider = value; }) definitions;
    }).config.provider;
  evalProvider = value: evalDefinitions [ value ];
  accepts = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  typeAccepts = value: accepts (evalProvider value);
  update = tag: patch: lib.recursiveUpdate fixtures.${tag} { connection.${tag} = patch; };
  replacePayload = tag: payload: fixtures.${tag} // { connection.${tag} = payload; };
  scopedExport = tag: value: {
    "${
      policy.protocols.${tag}.service
    }:${instance}:${policy.protocols.${tag}.role}:${machine}".vpnProvider =
      value;
  };
  select =
    exports:
    vpnExports.selectVpnProvider {
      providerMachine = machine;
      providerInstanceId = instance;
      inherit (clanLib) selectExports;
      inherit exports;
      consumerInstanceId = "fixture.publisher";
    };
  selectorAccepts = tag: value: accepts (select (scopedExport tag value));
  extraOptionModule = value: { lib, ... }: {
    options.unexpected = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "synthetic";
    };
    config = value;
  };
  forFixtures = f: lib.mapAttrs f fixtures;
  every = values: builtins.all (value: value) (builtins.attrValues values);

  # Unknown/null fields are deliberately left in each definition. Native closed
  # submodules must reject them before any consumer sees a selected projection.
  shapeCases = forFixtures (
    tag: value: {
      valid = typeAccepts value;
      emptyTag = !(typeAccepts (value // { connection = { }; }));
      unknownTag = !(typeAccepts (value // { connection.unsupported = value.connection.${tag}; }));
      conflictingTags =
        !(typeAccepts (
          value
          // {
            connection = value.connection // {
              unsupported = { };
            };
          }
        ));
      unknownRoot = !(typeAccepts (value // { unexpected = true; }));
      nullUnknownRoot = !(typeAccepts (value // { unexpected = null; }));
      rootCheckControl =
        !(typeAccepts (
          value
          // {
            _module.check = false;
            unexpected = null;
          }
        ));
      rootExplicitCheck = !(typeAccepts (value // { _module.check = true; }));
      rootFreeformControl =
        !(typeAccepts (
          value
          // {
            _module.freeformType = lib.types.attrs;
            unexpected = null;
          }
        ));
      payloadCheckControl =
        !(typeAccepts (
          update tag {
            _module.check = false;
            unexpected = null;
          }
        ));
      payloadFreeformControl =
        !(typeAccepts (
          update tag {
            _module.freeformType = lib.types.attrs;
            unexpected = null;
          }
        ));
      endpointCheckControl =
        !(typeAccepts (
          update tag {
            endpoint._module.check = false;
            endpoint.unexpected = null;
          }
        ));
      clientCheckControl =
        !(typeAccepts (
          update tag {
            clients."device.one"._module.check = false;
            clients."device.one".unexpected = null;
          }
        ));
      specialRootControls = builtins.all (field: !(typeAccepts (value // { ${field} = { }; }))) [
        "imports"
        "options"
        "config"
      ];
      specialPayloadControls = builtins.all (field: !(typeAccepts (update tag { ${field} = { }; }))) [
        "imports"
        "options"
        "config"
      ];
      specialAccountNamesAllowed = typeAccepts (
        replacePayload tag (
          value.connection.${tag}
          // {
            clients.config = value.connection.${tag}.clients."device.one";
          }
        )
      );
      oldEnvelope =
        !(typeAccepts (
          value
          // {
            protocol = tag;
            inherit machine;
          }
        ));
      legacyVersion = !(typeAccepts (value // { schemaVersion = 2; }));
      nullVersion = !(typeAccepts (value // { schemaVersion = null; }));
      nullConnection = !(typeAccepts (value // { connection = null; }));
      nullPayload = !(typeAccepts (replacePayload tag null));
      unknownPayload = !(typeAccepts (update tag { unexpected = true; }));
      nullUnknownPayload = !(typeAccepts (update tag { unexpected = null; }));
      nullEndpoint = !(typeAccepts (update tag { endpoint = null; }));
      unknownEndpoint = !(typeAccepts (update tag { endpoint.unexpected = true; }));
      nullUnknownEndpoint = !(typeAccepts (update tag { endpoint.unexpected = null; }));
      missingIpv4 =
        !(typeAccepts (
          replacePayload tag (
            value.connection.${tag}
            // {
              endpoint = builtins.removeAttrs value.connection.${tag}.endpoint [ "ipv4" ];
            }
          )
        ));
      nullIpv4 = !(typeAccepts (update tag { endpoint.ipv4 = null; }));
      malformedIpv4 = !(typeAccepts (update tag { endpoint.ipv4 = "192.0.2.999"; }));
      noncanonicalIpv4 = !(typeAccepts (update tag { endpoint.ipv4 = "192.00.2.10"; }));
      zeroPort = !(typeAccepts (update tag { endpoint.port = 0; }));
      highPort = !(typeAccepts (update tag { endpoint.port = 65536; }));
      nullPort = !(typeAccepts (update tag { endpoint.port = null; }));
      emptyClients = !(typeAccepts (replacePayload tag (value.connection.${tag} // { clients = { }; })));
      nullClients = !(typeAccepts (update tag { clients = null; }));
      unknownClientField = !(typeAccepts (update tag { clients."device.one".unexpected = true; }));
      nullUnknownClientField = !(typeAccepts (update tag { clients."device.one".unexpected = null; }));
      unsafeClient =
        !(typeAccepts (
          replacePayload tag (
            value.connection.${tag}
            // {
              clients."unsafe/client" = value.connection.${tag}.clients."device.one";
            }
          )
        ));
      duplicatedCredential =
        !(typeAccepts (
          update tag {
            clients."device.two" = value.connection.${tag}.clients."device.one";
          }
        ));
      versionForcesPayload =
        !(accepts
          (evalProvider (
            update tag {
              endpoint.unexpected = null;
            }
          )).schemaVersion
        );
      requiredPayloadFields = builtins.all (
        field: !(typeAccepts (replacePayload tag (builtins.removeAttrs value.connection.${tag} [ field ])))
      ) (builtins.attrNames value.connection.${tag});
      requiredClientFields = builtins.all (
        field:
        field == "keepaliveSeconds"
        || !(typeAccepts (
          replacePayload tag (
            value.connection.${tag}
            // {
              clients."device.one" = builtins.removeAttrs value.connection.${tag}.clients."device.one" [ field ];
            }
          )
        ))
      ) (builtins.attrNames value.connection.${tag}.clients."device.one");
      nullClientFields = builtins.all (
        field:
        field == "keepaliveSeconds"
        || !(typeAccepts (
          update tag {
            clients."device.one".${field} = null;
          }
        ))
      ) (builtins.attrNames value.connection.${tag}.clients."device.one");
    }
  );
  hostnameCases =
    lib.genAttrs [ "naiveproxy" "vless-xhttp" "amneziawg" "anytls" "trusttunnel" ]
      (tag: {
        missing =
          !(typeAccepts (
            replacePayload tag (
              fixtures.${tag}.connection.${tag}
              // {
                endpoint = builtins.removeAttrs endpoint [ "hostname" ];
              }
            )
          ));
        null = !(typeAccepts (update tag { endpoint.hostname = null; }));
        empty = !(typeAccepts (update tag { endpoint.hostname = ""; }));
        malformed = !(typeAccepts (update tag { endpoint.hostname = "vpn..example.invalid"; }));
        wildcard = !(typeAccepts (update tag { endpoint.hostname = "*.example.invalid"; }));
      });
  specificCases = {
    mieruHostnameRejected =
      !(typeAccepts (update "mieru" { endpoint.hostname = "vpn.example.invalid"; }));
    vlessShortIdLength =
      !(typeAccepts (update "vless-xhttp" { clients."device.one".shortId = "abc"; }));
    vlessShortIdCase =
      !(typeAccepts (update "vless-xhttp" { clients."device.one".shortId = "0123456789ABCDEF"; }));
    vlessRepeatedShortId =
      !(typeAccepts (
        update "vless-xhttp" {
          clients."device.two" = {
            uuidSecret = "fixture/device.two-vless-uuid";
            shortId = "0123456789abcdef";
          };
        }
      ));
    vlessPublicKey = !(typeAccepts (update "vless-xhttp" { reality.publicKey = "invalid"; }));
    vlessMissingPolicy =
      !(typeAccepts (
        replacePayload "vless-xhttp" (
          fixtures.vless-xhttp.connection.vless-xhttp
          // {
            reality = builtins.removeAttrs fixtures.vless-xhttp.connection.vless-xhttp.reality [
              "supportX25519MLKEM768"
            ];
          }
        )
      ));
    vlessEnabledPolicy = typeAccepts (update "vless-xhttp" { reality.supportX25519MLKEM768 = true; });
    vlessWrongPolicyType =
      !(typeAccepts (update "vless-xhttp" { reality.supportX25519MLKEM768 = "true"; }));
    vlessUnknownReality = !(typeAccepts (update "vless-xhttp" { reality.unexpected = null; }));
    vlessPath = !(typeAccepts (update "vless-xhttp" { xhttp.path = "relative"; }));
    vlessWhitespacePath = !(typeAccepts (update "vless-xhttp" { xhttp.path = "/white space"; }));
    vlessFixedModeRemoved = !(typeAccepts (update "vless-xhttp" { xhttp.mode = "auto"; }));
    vlessDohIpv4 = !(typeAccepts (update "vless-xhttp" { doh.ipv4 = "192.0.2.999"; }));
    vlessDohHostname = !(typeAccepts (update "vless-xhttp" { doh.hostname = "dns..invalid"; }));
    awgPublicKey = !(typeAccepts (update "amneziawg" { serverPublicKey = "invalid"; }));
    awgNoncanonicalPublicKey =
      !(typeAccepts (
        update "amneziawg" { serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB="; }
      ));
    awgHeaderBindingOverlap =
      !(typeAccepts (
        update "amneziawg" {
          headerProtectionKeySecret = "fixture/device.one-awg-private-key";
        }
      ));
    awgRepeatedClientIp =
      !(typeAccepts (
        update "amneziawg" {
          clients."device.two" = {
            ipv4 = "10.77.0.2";
            privateKeySecret = "fixture/device.two-awg-private-key";
            keepaliveSeconds = 25;
          };
        }
      ));
    awgNullKeepalivePreserved =
      (evalProvider fixtures.amneziawg).connection.amneziawg.clients."device.one".keepaliveSeconds
      == null;
    awgPositiveKeepalive = typeAccepts (
      update "amneziawg" { clients."device.one".keepaliveSeconds = 25; }
    );
    awgZeroKeepalive =
      !(typeAccepts (update "amneziawg" { clients."device.one".keepaliveSeconds = 0; }));
    awgLargeKeepalive =
      !(typeAccepts (update "amneziawg" { clients."device.one".keepaliveSeconds = 65536; }));
    unsafeSecret =
      !(typeAccepts (update "anytls" { clients."device.one".passwordSecret = "../unsafe"; }));
    oldFixedPolicyRejected = !(typeAccepts (update "anytls" { tlsVerify = true; }));
  };
  mergeCases = {
    validSplitDefinitions = accepts (evalDefinitions [
      {
        schemaVersion = 3;
        connection.anytls.endpoint = endpoint;
      }
      { connection.anytls.clients = passwordPayload.clients; }
    ]);
    conflictingNativeTags =
      !(accepts (evalDefinitions [
        fixtures.anytls
        fixtures.trusttunnel
      ]));
    sharedPasswordAcrossDefinitions =
      !(accepts (evalDefinitions [
        fixtures.anytls
        {
          connection.anytls.clients."device.two" = passwordPayload.clients."device.one";
        }
      ]));
    sharedUuidAcrossDefinitions =
      !(accepts (evalDefinitions [
        fixtures.vless-xhttp
        {
          connection.vless-xhttp.clients."device.two" = {
            uuidSecret = "fixture/device.one-vless-uuid";
            shortId = "fedcba9876543210";
          };
        }
      ]));
    unknownAcrossDefinitions =
      !(accepts (evalDefinitions [
        fixtures.anytls
        { unexpected = null; }
      ]));
  };
  nativeModuleCases = forFixtures (
    tag: value: {
      closedModuleExpression = typeAccepts (_: {
        config = value;
      });
      rootOptionExtension = !(typeAccepts (extraOptionModule value));
      versionForcesRootExtension = !(accepts (evalProvider (extraOptionModule value)).schemaVersion);
      payloadOptionExtension =
        !(typeAccepts (replacePayload tag (extraOptionModule value.connection.${tag})));
      endpointOptionExtension =
        !(typeAccepts (
          replacePayload tag (
            value.connection.${tag}
            // {
              endpoint = extraOptionModule value.connection.${tag}.endpoint;
            }
          )
        ));
      clientOptionExtension =
        !(typeAccepts (
          replacePayload tag (
            value.connection.${tag}
            // {
              clients."device.one" = extraOptionModule value.connection.${tag}.clients."device.one";
            }
          )
        ));
    }
  );
  # Exercise the pinned Clan registration wrapper, rather than substituting a
  # more restrictive root type than producers actually receive.
  registrationModule =
    (
      (import (inputs.clan-core.outPath + "/modules/clan/top-level-interface.nix") {
        inherit lib clanLib;
        self = { };
        config = { };
      }).options.exportInterfaces.apply
        { vpnProvider = vpnExports.vpnProviderModule; }
    ).vpnProvider;
  registeredProvider =
    value:
    (lib.evalModules {
      modules = [
        registrationModule
        { config.vpnProvider = value; }
      ];
    }).config.vpnProvider;
  registrationCases = {
    realClanRegistration = accepts (registeredProvider fixtures.anytls);
    realClanRootOptionExtension = !(accepts (registeredProvider (extraOptionModule fixtures.anytls)));
    realClanPayloadOptionExtension =
      !(accepts (registeredProvider (replacePayload "anytls" (extraOptionModule passwordPayload))));
    realClanRealityOptionExtension =
      !(accepts (
        registeredProvider (
          replacePayload "vless-xhttp" (
            fixtures.vless-xhttp.connection.vless-xhttp
            // {
              reality = extraOptionModule fixtures.vless-xhttp.connection.vless-xhttp.reality;
            }
          )
        )
      ));
    realClanRootControl =
      !(accepts (
        registeredProvider (
          fixtures.anytls
          // {
            _module.check = false;
            unexpected = null;
          }
        )
      ));
    realClanPayloadControl =
      !(accepts (
        registeredProvider (
          update "anytls" {
            _module.check = false;
            unexpected = null;
          }
        )
      ));
    realClanRootFreeform =
      !(accepts (
        registeredProvider (
          fixtures.anytls
          // {
            _module.freeformType = lib.types.attrs;
            unexpected = null;
          }
        )
      ));
    nativeDocsDiscovery =
      builtins.attrNames (registrationModule.options.vpnProvider.type.getSubOptions [ "vpnProvider" ])
      == [
        "_module"
        "connection"
        "schemaVersion"
      ];
    nativePayloadDocsDiscovery =
      builtins.attrNames (
        (
          (registrationModule.options.vpnProvider.type.getSubOptions [ "vpnProvider" ])
          .connection.type.getSubOptions
            [
              "vpnProvider"
              "connection"
            ]
        ).anytls.type.getSubOptions
          [
            "vpnProvider"
            "connection"
            "anytls"
          ]
      ) == [
        "_module"
        "clients"
        "endpoint"
      ];
  };
  nativeSelectionCases = forFixtures (
    tag: value: {
      valid = selectorAccepts tag value;
      internalScopeOnly =
        select (scopedExport tag value) == {
          inherit machine;
          instanceId = instance;
          inherit (value) connection;
        };
      tagMustMatchScope =
        !(selectorAccepts tag fixtures.${if tag == "anytls" then "trusttunnel" else "anytls"});
      wrongRole =
        !(accepts (select {
          "${policy.protocols.${tag}.service}:${instance}:wrong-role:${machine}".vpnProvider = value;
        }));
      wrongService =
        !(accepts (select {
          "@foreign/vpn:${instance}:${policy.protocols.${tag}.role}:${machine}".vpnProvider = value;
        }));
      wrongMachine =
        !(accepts (select {
          "${
            policy.protocols.${tag}.service
          }:${instance}:${policy.protocols.${tag}.role}:other-machine".vpnProvider =
            value;
        }));
      wrongInstance =
        !(accepts (select {
          "${
            policy.protocols.${tag}.service
          }:other-instance:${policy.protocols.${tag}.role}:${machine}".vpnProvider =
            value;
        }));
      nullUnknownFieldRejected = !(selectorAccepts tag (update tag { unexpected = null; }));
    }
  );
  selectorCases = {
    noProvider = !(accepts (select { }));
    multipleKnownProviders =
      !(accepts (
        select (
          (scopedExport "anytls" fixtures.anytls) // (scopedExport "trusttunnel" fixtures.trusttunnel)
        )
      ));
    missingInterface =
      !(accepts (select {
        "${policy.protocols.anytls.service}:${instance}:gateway:${machine}" = { };
      }));
    disabledNullInterface = !(selectorAccepts "anytls" null);
    invalidSelectorResult =
      !(accepts (
        vpnExports.selectVpnProvider {
          providerMachine = machine;
          providerInstanceId = instance;
          selectExports = _: _: [ ];
          exports = { };
        }
      ));
    unknownExports = !(accepts (select null));
  };
  expectedCatalog = {
    naiveproxy = {
      role = "addon";
      service = "@clanwright/vpn-naiveproxy";
    };
    vless-xhttp = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-vless-xhttp";
    };
    amneziawg = {
      role = "gateway";
      service = "@clanwright/vpn-amneziawg";
    };
    mieru = {
      role = "gateway";
      service = "@clanwright/vpn-mieru";
    };
    anytls = {
      role = "gateway";
      service = "@clanwright/vpn-anytls";
    };
    trusttunnel = {
      role = "gateway";
      service = "@clanwright/vpn-trusttunnel";
    };
  };
  policyContract =
    vpnExports.schemaVersion == 3
    && policy.protocols == expectedCatalog
    && policy.awgGeneration == 3
    && policy.awgMtu == 1280
    &&
      policy.awgProfile == {
        s1 = 12;
        s2 = 12;
        s3 = 12;
        s4 = 12;
        h1 = 1;
        h2 = 2;
        h3 = 3;
        h4 = 4;
        contentPaddingAddition = {
          min = 2;
          max = 10;
        };
        randomTrailers = true;
        disableCookies = false;
      };
  identityCases = {
    stableCertificateKey = identities.certificateKeyType.check "existing_cert.example.invalid";
    maxCertificateKey = identities.certificateKeyType.check (lib.concatStrings (lib.replicate 253 "x"));
    overlongCertificateKey =
      !(identities.certificateKeyType.check (lib.concatStrings (lib.replicate 254 "x")));
    wildcardCertificateKey = !(identities.certificateKeyType.check "*.example.invalid");
    unsafeCertificatePath = !(identities.certificateKeyType.check "cert/child");
    strictDeviceLength =
      !(identities.safeIdentityType.check (lib.concatStrings (lib.replicate 65 "x")));
    maxDeviceLength = identities.safeIdentityType.check (lib.concatStrings (lib.replicate 64 "x"));
    distinctDnsPunctuation =
      identities.certificateKeyType.check "a-b.example"
      && identities.certificateKeyType.check "a.b.example";
  };
  addressValidation = import ../modules/contracts/address-validation.nix { inherit lib; };
  repeat = count: lib.concatStrings (lib.replicate count "a");
  maxHostname = lib.concatStringsSep "." [
    (repeat 63)
    (repeat 63)
    (repeat 63)
    (repeat 61)
  ];
  addressCases = {
    validHostnames = builtins.all addressValidation.validHostname [
      "Vpn.Example.INVALID"
      "localhost"
      "123"
      "1.2.3.4"
      "a-b.example"
      (repeat 63)
      maxHostname
    ];
    invalidHostnames = builtins.all (value: !addressValidation.validHostname value) [
      null
      1
      [ ]
      { }
      ""
      "a..b"
      "a.-b"
      "a.b-"
      "*.example"
      "a_b.example"
      "example:443"
      "example."
      (repeat 64)
      "${maxHostname}a"
    ];
    validIPv4s = builtins.all addressValidation.validIPv4 [
      "0.0.0.0"
      "255.255.255.255"
      "192.0.2.1"
    ];
    invalidIPv4s = builtins.all (value: !addressValidation.validIPv4 value) [
      null
      1
      [ ]
      { }
      ""
      "256.0.0.1"
      "192.00.2.1"
      "192.0.2"
      "192.0.2.1.1"
      "192.0.2.-1"
      "192.0.2.1:443"
      "2001:db8::1"
    ];
  };
  results = {
    inherit policyContract;
    typeContract =
      every (lib.mapAttrs (_: every) shapeCases)
      && every (lib.mapAttrs (_: every) hostnameCases)
      && every specificCases
      && every mergeCases
      && every (lib.mapAttrs (_: every) nativeModuleCases)
      && every registrationCases;
    selectorContract = every (lib.mapAttrs (_: every) nativeSelectionCases) && every selectorCases;
    identityContract = every identityCases;
    addressContract = every addressCases;
  };
  details = {
    inherit
      shapeCases
      hostnameCases
      specificCases
      mergeCases
      nativeSelectionCases
      selectorCases
      identityCases
      addressCases
      registrationCases
      nativeModuleCases
      ;
  };
in
builtins.deepSeq details (
  if !every results then
    throw "Provider native type, policy or scope selector contract failed: ${builtins.toJSON details}"
  else
    results // { all = true; }
)
