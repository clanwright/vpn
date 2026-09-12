{ pkgs, ... }:
let
  inherit (pkgs) lib;
  manifestLib = import ../clanServices/vpn-client-profiles/artifact-manifest.nix { inherit lib; };
  placeholderA = "__SECRET_A__";
  placeholderB = "__SECRET_B__";
  asset = {
    id = "fixture-asset";
    filename = "fixture.srs";
    publicPath = "/assets/v1/catalog/fixture.srs";
    legacyPublicPaths = [ "/assets/v1/catalog/fixture-legacy.srs" ];
    routePriority = 0;
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
    publicationPhases = manifestLib.expectedPublicationPhases;
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
    validManifestAccepted = manifestLib.validateManifest manifest;
    sameSecretMayBindDistinctTargets = manifestLib.validateManifest manifest;
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
    unsafeLegacyPublicPathRejected = invalid {
      assetCatalog.fixture-asset.legacyPublicPaths = [ "/assets/v1/catalog/../fixture.srs" ];
    };
    canonicalPathRepeatedAsLegacyRejected = invalid {
      assetCatalog.fixture-asset.legacyPublicPaths = [ asset.publicPath ];
    };
    duplicateLegacyPublicPathRejected = invalid {
      assetCatalog.fixture-asset.legacyPublicPaths = [
        "/assets/v1/catalog/fixture-legacy.srs"
        "/assets/v1/catalog/fixture-legacy.srs"
      ];
    };
    canonicalAndLegacyPathCollisionRejected = invalid {
      assetCatalog.second-asset = asset // {
        id = "second-asset";
        filename = "second.srs";
        publicPath = "/assets/v1/catalog/fixture-legacy.srs";
        legacyPublicPaths = [ ];
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
          legacyPublicPaths = [ ];
        };
      }
    );
    mrsIpcidrValidatorAccepted = manifestLib.validateManifest (
      lib.recursiveUpdate manifest {
        assetCatalog.fixture-asset = {
          validator = "mrs-ipcidr";
          filename = "fixture.mrs";
          publicPath = "/assets/v1/catalog/fixture.mrs";
          legacyPublicPaths = [ ];
        };
      }
    );
    arbitraryMrsValidatorRejected = invalid {
      assetCatalog.fixture-asset.validator = "mrs";
    };
    reorderedPhasesRejected = invalid {
      publicationPhases = builtins.tail manifest.publicationPhases ++ [
        (builtins.head manifest.publicationPhases)
      ];
    };
    missingPhaseRejected = invalid {
      publicationPhases = builtins.tail manifest.publicationPhases;
    };
    changedPrerequisiteRejected = invalid {
      publicationPhases = map (
        phase:
        if phase.id == "expose-generation" then
          phase // { prerequisites = [ "render-artifacts" ]; }
        else
          phase
      ) manifest.publicationPhases;
    };
    publicationHasNoProtocolBranches = builtins.all (token: !(lib.hasInfix token publicationSource)) [
      "vless-xhttp"
      "hysteria2Credentials"
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
  contract = builtins.all (value: value) (builtins.attrValues results);
in
if !contract then
  throw "Publisher artifact manifest contract failed: ${builtins.toJSON results}"
else
  {
    all = true;
    inherit contract results;
  }
