{ pkgs, ... }:
let
  inherit (pkgs) lib;
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  integrationModule = import ../clanServices/vpn-client-profiles/integration.nix { inherit lib; };
  publisherType = integrationModule.options.clanwright.vpn.publishers.type.nestedTypes.elemType;
  publisherFieldOptions = publisherType.getSubOptions [ ];
  publisherContext = pkgs.writeText "publisher-integration-context" "synthetic fixture\n";
  publisher = {
    schemaVersion = 2;
    profileRoot = "/run/vpn-client-profiles/fixture/published/current";
    assetRoot = "/var/lib/vpn-client-profiles/fixture/assets";
    configGatewayDomain = "profiles.example.invalid";
    linksRoot = "/run/vpn-client-profiles/fixture/published/current/links";
    logConfig = "log_skip\n";
    routeConfig = ''
      # ${publisherContext}
      route {
        @fixture host profiles.example.invalid
        respond @fixture "fixture" 200
      }
    '';
    publicationUnit = "vpn-client-profiles-publish-fixture.service";
    refreshUnit = "vpn-client-profiles-public-assets-fixture.service";
    statusPath = "/var/lib/vpn-client-profiles/fixture/status.json";
    readerGroup = "vpn-client-profiles";
  };
  evaluatePublisherWith =
    extraModules: raw:
    (lib.evalModules {
      modules = [
        integrationModule
        { config.clanwright.vpn.publishers.fixture = raw; }
      ]
      ++ extraModules;
    }).config.clanwright.vpn.publishers.fixture;
  evaluatePublisher = evaluatePublisherWith [ ];
  publisherAcceptedWith =
    extraModules: raw:
    (builtins.tryEval (builtins.deepSeq (evaluatePublisherWith extraModules raw) true)).success;
  publisherAccepted = publisherAcceptedWith [ ];
  publisherTypeDeclaration.options.clanwright.vpn.publishers = lib.mkOption {
    type = integrationModule.options.clanwright.vpn.publishers.type;
  };
  duplicatePublisherField.config.clanwright.vpn.publishers.fixture.readerGroup =
    publisher.readerGroup;
  evaluatedPublisher = evaluatePublisher publisher;
  evaluatedPublisherAfterTypeMerge = evaluatePublisherWith [ publisherTypeDeclaration ] publisher;
  publisherNegativeInputs = {
    extraField = publisher // {
      unexpected = true;
    };
    callableExtra = _: {
      options.unexpected = lib.mkOption { type = lib.types.bool; };
      config = publisher // {
        unexpected = true;
      };
    };
    callableKnownFields = _: { config = publisher; };
    checkingDisabled = publisher // {
      _module.check = false;
      unexpected = true;
    };
    freeformMetadata = publisher // {
      _module.freeformType = lib.types.attrsOf lib.types.raw;
      unexpected = true;
    };
    pathDefinition = ../clanServices/vpn-client-profiles/integration.nix;
  };
  placeholderA = "__SECRET_A__";
  placeholderB = "__SECRET_B__";
  asset = {
    id = "fixture-asset";
    filename = "fixture.srs";
    publicPath = "/assets/v1/catalog/fixture.srs";
    contentType = "application/octet-stream";
    validator = "srs";
    source = {
      kind = "download";
      url = "https://example.invalid/fixture.srs";
    };
  };
  bindingA = {
    secretName = "fixture-secret";
    decoding = "literal";
    targetPath = [
      "entries"
      0
      "password"
    ];
    placeholder = placeholderA;
  };
  bindingB = {
    secretName = "fixture-secret";
    decoding = "base64url";
    targetPath = [
      "entries"
      1
      "password"
    ];
    placeholder = placeholderB;
  };
  artifact = {
    id = "fixture-json";
    outputName = "profile.json";
    format = "json";
    template = {
      entries = [
        { password = placeholderA; }
        { password = placeholderB; }
      ];
    };
    templatePath = /.;
    assetRefs = [ "fixture-asset" ];
    bindings = [
      bindingA
      bindingB
    ];
  };
  manifest = {
    schemaVersion = 1;
    assetCatalog.fixture-asset = asset;
    profiles = [
      {
        name = "fixture";
        pathTokenBinding = {
          secretName = "fixture-token";
          decoding = "path-token";
        };
        artifacts = [ artifact ];
      }
    ];
  };
  publicationSource = builtins.readFile ../clanServices/vpn-client-profiles/runtime-publication.nix;
  assetLifecycleSource = builtins.readFile ../clanServices/vpn-client-profiles/public-assets.nix;
  sourceIndex =
    needle:
    let
      go =
        index: lines:
        if lines == [ ] then
          -1
        else if lib.hasInfix needle (builtins.head lines) then
          index
        else
          go (index + 1) (builtins.tail lines);
    in
    go 0 (lib.splitString "\n" assetLifecycleSource);
  invalid = change: !(manifestLib.validateManifest (lib.recursiveUpdate manifest change));
  results = {
    publisherLiteralDataAccepted =
      publisherAccepted publisher
      && builtins.attrNames evaluatedPublisher == builtins.attrNames publisher;
    publisherFieldsRemainReadOnly = builtins.all (name: publisherFieldOptions.${name}.readOnly) (
      builtins.attrNames publisher
    );
    publisherFieldDiscoveryPreserved =
      builtins.attrNames (builtins.removeAttrs publisherFieldOptions [ "_module" ])
      == builtins.attrNames publisher;
    publisherRouteContextPreserved =
      builtins.getContext publisher.routeConfig != { }
      && builtins.getContext evaluatedPublisher.routeConfig == builtins.getContext publisher.routeConfig;
    publisherMetadataInputsRejected = builtins.mapAttrs (
      _name: raw: !publisherType.check raw && !publisherAccepted raw
    ) publisherNegativeInputs;
    publisherLiteralDataAcceptedAfterTypeMerge =
      publisherAcceptedWith [ publisherTypeDeclaration ] publisher
      && builtins.attrNames evaluatedPublisherAfterTypeMerge == builtins.attrNames publisher
      &&
        builtins.getContext evaluatedPublisherAfterTypeMerge.routeConfig
        == builtins.getContext publisher.routeConfig;
    publisherMetadataInputsRejectedAfterTypeMerge = builtins.mapAttrs (
      _name: raw: !publisherType.check raw && !publisherAcceptedWith [ publisherTypeDeclaration ] raw
    ) publisherNegativeInputs;
    publisherReadOnlyDuplicateDefinitionsRejected = {
      singleTypeDeclaration = !publisherAcceptedWith [ duplicatePublisherField ] publisher;
      mergedTypeDeclarations =
        !publisherAcceptedWith [
          publisherTypeDeclaration
          duplicatePublisherField
        ] publisher;
    };
    validManifestAccepted = manifestLib.validateManifest manifest;
    unboundPlaceholderRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [ bindingA ];
                }
              )
            ];
          }
        )
      ];
    };
    duplicatePlaceholderRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  template.entries = [
                    { password = placeholderA; }
                    { password = placeholderA; }
                  ];
                  bindings = [ bindingA ];
                }
              )
            ];
          }
        )
      ];
    };
    duplicateBindingRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    bindingA
                    bindingA
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    nonexistentTargetRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    (bindingA // { targetPath = [ "missing" ]; })
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    wrongTargetPlaceholderRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    (bindingA // { placeholder = placeholderB; })
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    arbitraryDecoderRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    (bindingA // { decoding = "shell"; })
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    pathTokenDecoderRejectedForArtifact = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    (bindingA // { decoding = "path-token"; })
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    embeddedPlaceholderRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  template.entries = [
                    { password = "prefix${placeholderA}suffix"; }
                    { password = placeholderB; }
                  ];
                  bindings = [ bindingB ];
                }
              )
            ];
          }
        )
      ];
    };
    placeholderAttributeNameRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  template = {
                    ${placeholderA} = "value";
                    entries = [ { password = placeholderB; } ];
                  };
                  bindings = [ bindingB ];
                }
              )
            ];
          }
        )
      ];
    };
    arbitraryBindingFieldRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  bindings = [
                    (bindingA // { jq = ".entries[0].password"; })
                    bindingB
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    unknownAssetReferenceRejected = invalid {
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [ (artifact // { assetRefs = [ "missing" ]; }) ];
          }
        )
      ];
    };
    arbitraryAssetSourceRejected = invalid {
      assetCatalog.fixture-asset.source = {
        kind = "shell";
        command = "fetch something";
      };
    };
    localSrsWithoutValidationRejected = invalid {
      assetCatalog.fixture-asset = asset // {
        validator = "srs";
        source = {
          kind = "local-file";
          path = /.;
        };
      };
    };
    invalidLocalPathRejected = invalid {
      assetCatalog.fixture-asset = asset // {
        validator = "nonempty";
        source = {
          kind = "local-file";
          path = { };
        };
      };
    };
    nonStringContentTypeRejected = invalid {
      assetCatalog.fixture-asset.contentType = 1;
    };
    unsafeContentTypeRejected = invalid {
      assetCatalog.fixture-asset.contentType = "text/plain\nrespond hacked";
    };
    unsafePublicPathRejected = invalid {
      assetCatalog.fixture-asset.publicPath = "/assets/v1/catalog/../fixture.srs";
    };
    unknownLegacyAssetFieldRejected = invalid {
      assetCatalog.fixture-asset.legacyPublicPaths = [ "/assets/v1/catalog/fixture-legacy.srs" ];
    };
    canonicalPathCollisionRejected = invalid {
      assetCatalog.second-asset = asset // {
        id = "second-asset";
        filename = "second.srs";
        inherit (asset) publicPath;
      };
      profiles = [
        (
          (builtins.head manifest.profiles)
          // {
            artifacts = [
              (
                artifact
                // {
                  assetRefs = [
                    "fixture-asset"
                    "second-asset"
                  ];
                }
              )
            ];
          }
        )
      ];
    };
    mrsDomainValidatorAccepted = manifestLib.validateManifest (
      lib.recursiveUpdate manifest {
        assetCatalog.fixture-asset = {
          validator = "mrs-domain";
          filename = "fixture.mrs";
          publicPath = "/assets/v1/catalog/fixture.mrs";
        };
      }
    );
    mrsIpcidrValidatorAccepted = manifestLib.validateManifest (
      lib.recursiveUpdate manifest {
        assetCatalog.fixture-asset = {
          validator = "mrs-ipcidr";
          filename = "fixture.mrs";
          publicPath = "/assets/v1/catalog/fixture.mrs";
        };
      }
    );
    arbitraryMrsValidatorRejected = invalid {
      assetCatalog.fixture-asset.validator = "mrs";
    };
    legacyPublicationPhasesRejected = invalid { publicationPhases = [ ]; };
    unknownRootFieldRejected = invalid { unexpected = true; };
    publicationHasNoProtocolBranches = builtins.all (token: !(lib.hasInfix token publicationSource)) [
      "vless-xhttp"
      "amneziawgCredentials"
      "naiveCredentials"
      "mieruCredentials"
    ];
    publicationHasNoProtocolFieldPaths = builtins.all (token: !(lib.hasInfix token publicationSource)) [
      ".proxies[]"
      ".outbounds[]"
      ".\"private-key\""
      ".\"obfs-password\""
    ];
    assetLifecycleDoesNotInspectRenderedTrees =
      builtins.all (token: !(lib.hasInfix token assetLifecycleSource))
        [
          "mihomoSelectiveTemplate"
          "rule-providers"
          "profileJsonTemplate"
        ];
    mrsValidationUsesPinnedMihomoBeforePublish =
      lib.hasInfix "appsPkgs.mihomo" assetLifecycleSource
      && lib.hasInfix ''mihomo convert-ruleset "$mrs_behavior" mrs "$tmp" "$mrs_output"'' assetLifecycleSource
      && lib.hasInfix "mrs-domain" assetLifecycleSource
      && lib.hasInfix "mrs-ipcidr" assetLifecycleSource
      &&
        sourceIndex ''mihomo convert-ruleset "$mrs_behavior" mrs "$tmp" "$mrs_output"''
        < sourceIndex ''publish_file "$tmp" "$name"'';
  };
  allBooleansTrue =
    value:
    if builtins.isBool value then
      value
    else if builtins.isAttrs value then
      builtins.all allBooleansTrue (builtins.attrValues value)
    else
      false;
  contract = allBooleansTrue results;
in
if !contract then
  throw "Publisher artifact manifest contract failed: ${builtins.toJSON results}"
else
  {
    all = true;
    inherit contract results;
  }
