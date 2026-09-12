{ lib }:
let
  placeholderPattern = "__[A-Za-z0-9_.-]+__";
  decodingRules = [
    "literal"
    "wireguard-private-key"
    "base64url"
    "path-token"
  ];
  artifactDecodingRules = builtins.filter (rule: rule != "path-token") decodingRules;
  artifactFormats = [
    "mihomo"
    "json"
  ];
  expectedPublicationPhases = [
    {
      id = "revoke-current";
      prerequisites = [ ];
    }
    {
      id = "sync-local-assets";
      prerequisites = [ "revoke-current" ];
    }
    {
      id = "check-assets";
      prerequisites = [ "sync-local-assets" ];
    }
    {
      id = "prepare-generation";
      prerequisites = [ "check-assets" ];
    }
    {
      id = "render-artifacts";
      prerequisites = [ "prepare-generation" ];
    }
    {
      id = "finalize-links";
      prerequisites = [ "render-artifacts" ];
    }
    {
      id = "seal-generation";
      prerequisites = [ "finalize-links" ];
    }
    {
      id = "expose-generation";
      prerequisites = [ "seal-generation" ];
    }
    {
      id = "retire-old-generations";
      prerequisites = [ "expose-generation" ];
    }
    {
      id = "cleanup-private-temporaries";
      prerequisites = [ "retire-old-generations" ];
    }
  ];
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

  valueAtPath =
    value: path:
    if path == [ ] then
      value
    else
      let
        component = builtins.head path;
        remaining = builtins.tail path;
        next =
          if
            builtins.isInt component
            && builtins.isList value
            && component >= 0
            && component < builtins.length value
          then
            builtins.elemAt value component
          else if
            builtins.isString component && builtins.isAttrs value && builtins.hasAttr component value
          then
            value.${component}
          else
            throw "vpn-client-profiles: manifest binding target path does not exist";
      in
      valueAtPath next remaining;

  hasPlaceholderSyntax = value: builtins.match ".*__[A-Za-z0-9_.-]+__.*" value != null;
  collectPlaceholders =
    value:
    if builtins.isString value then
      lib.optional (builtins.match placeholderPattern value != null) value
    else if builtins.isList value then
      lib.concatMap collectPlaceholders value
    else if builtins.isAttrs value then
      lib.concatMap collectPlaceholders (builtins.attrValues value)
    else
      [ ];
  invalidPlaceholderPlacement =
    value:
    if builtins.isString value then
      hasPlaceholderSyntax value && builtins.match placeholderPattern value == null
    else if builtins.isList value then
      builtins.any invalidPlaceholderPlacement value
    else if builtins.isAttrs value then
      builtins.any hasPlaceholderSyntax (builtins.attrNames value)
      || builtins.any invalidPlaceholderPlacement (builtins.attrValues value)
    else
      false;

  validPath =
    path:
    builtins.isList path
    && path != [ ]
    && builtins.all (
      component: builtins.isString component || (builtins.isInt component && component >= 0)
    ) path;

  validateBinding =
    template: binding:
    let
      fields = builtins.attrNames binding;
      targetAttempt =
        if validPath (binding.targetPath or null) then
          builtins.tryEval (valueAtPath template binding.targetPath)
        else
          {
            success = false;
            value = null;
          };
    in
    fields == [
      "decoding"
      "placeholder"
      "secretName"
      "targetPath"
    ]
    && builtins.isString binding.secretName
    && binding.secretName != ""
    && builtins.elem binding.decoding artifactDecodingRules
    && builtins.isString binding.placeholder
    && builtins.match placeholderPattern binding.placeholder != null
    && targetAttempt.success
    && targetAttempt.value == binding.placeholder;

  validateArtifact =
    assetCatalog: artifact:
    let
      placeholders = collectPlaceholders artifact.template;
      bindingPlaceholders = map (binding: binding.placeholder) artifact.bindings;
      fields = builtins.attrNames artifact;
    in
    fields == [
      "assetRefs"
      "bindings"
      "format"
      "id"
      "outputName"
      "template"
      "templatePath"
    ]
    && builtins.isString artifact.id
    && builtins.match "[A-Za-z0-9_.-]+" artifact.id != null
    && builtins.isString artifact.outputName
    && builtins.match "[A-Za-z0-9._-]+" artifact.outputName != null
    && builtins.elem artifact.format artifactFormats
    && (
      builtins.isPath artifact.templatePath
      || builtins.isString artifact.templatePath
      || (builtins.isAttrs artifact.templatePath && artifact.templatePath ? outPath)
    )
    && artifact.assetRefs == lib.unique artifact.assetRefs
    && builtins.all (assetId: builtins.hasAttr assetId assetCatalog) artifact.assetRefs
    && builtins.all (validateBinding artifact.template) artifact.bindings
    && !invalidPlaceholderPlacement artifact.template
    && bindingPlaceholders == lib.unique bindingPlaceholders
    && lib.sort builtins.lessThan placeholders == lib.sort builtins.lessThan bindingPlaceholders;

  validateProfile =
    assetCatalog: profile:
    let
      artifactIds = map (artifact: artifact.id) profile.artifacts;
      outputNames = map (artifact: artifact.outputName) profile.artifacts;
      token = profile.pathTokenBinding;
    in
    builtins.attrNames profile == [
      "artifacts"
      "name"
      "pathTokenBinding"
    ]
    && builtins.isString profile.name
    && builtins.match "[A-Za-z0-9_.-]+" profile.name != null
    &&
      builtins.attrNames token == [
        "decoding"
        "secretName"
      ]
    && token.decoding == "path-token"
    && builtins.isString token.secretName
    && token.secretName != ""
    && profile.artifacts != [ ]
    && artifactIds == lib.unique artifactIds
    && outputNames == lib.unique outputNames
    && builtins.all (validateArtifact assetCatalog) profile.artifacts;

  validateAsset =
    id: asset:
    let
      source = asset.source or { };
      validPublicPath =
        path:
        builtins.isString path
        && builtins.match "/assets/v1/catalog/[A-Za-z0-9._/-]+" path != null
        && !(lib.hasInfix ".." path)
        && !(lib.hasInfix "//" path);
      sourceShapeValid =
        if (source.kind or null) == "local-file" then
          builtins.attrNames source == [
            "kind"
            "path"
          ]
          && (
            builtins.isPath source.path
            || builtins.isString source.path
            || (builtins.isAttrs source.path && source.path ? outPath)
          )
        else
          builtins.attrNames source == [
            "kind"
            "url"
          ]
          && builtins.isString source.url
          && lib.hasPrefix "https://" source.url;
    in
    builtins.attrNames asset == [
      "contentType"
      "filename"
      "id"
      "legacyPublicPaths"
      "publicPath"
      "routePriority"
      "source"
      "validator"
    ]
    && asset.id == id
    && builtins.match "[A-Za-z0-9_-]+" asset.id != null
    && builtins.isString asset.filename
    && builtins.match "[A-Za-z0-9._-]+" asset.filename != null
    && validPublicPath asset.publicPath
    && builtins.isList asset.legacyPublicPaths
    && builtins.all validPublicPath asset.legacyPublicPaths
    && asset.legacyPublicPaths == lib.unique asset.legacyPublicPaths
    && !(builtins.elem asset.publicPath asset.legacyPublicPaths)
    && builtins.elem asset.contentType [
      "application/octet-stream"
      "text/plain; charset=utf-8"
    ]
    && builtins.isInt asset.routePriority
    && asset.routePriority >= 0
    && builtins.elem asset.validator [
      "nonempty"
      "mrs-domain"
      "mrs-ipcidr"
      "srs"
    ]
    && builtins.isAttrs asset.source
    && builtins.elem (asset.source.kind or null) [
      "download"
      "adguard-to-srs"
      "local-file"
    ]
    && sourceShapeValid
    && (
      (source.kind == "local-file" && asset.validator == "nonempty")
      || (source.kind == "adguard-to-srs" && asset.validator == "srs")
      || source.kind == "download"
    );

  validatePublicationPhases =
    phases:
    let
      ids = map (phase: phase.id or null) phases;
      prerequisitesKnown = builtins.all (
        phase: builtins.all (prerequisite: builtins.elem prerequisite ids) (phase.prerequisites or [ ])
      ) phases;
      prerequisitesEarlier = builtins.all (
        phase:
        let
          phaseIndex = indexOf (id: id == phase.id) ids;
        in
        builtins.all (prerequisite: indexOf (id: id == prerequisite) ids < phaseIndex) phase.prerequisites
      ) phases;
    in
    phases == expectedPublicationPhases && prerequisitesKnown && prerequisitesEarlier;

  validateManifest =
    manifest:
    let
      profileNames = map (profile: profile.name) manifest.profiles;
      inherit (manifest) assetCatalog;
      assetFilenames = map (asset: asset.filename) (builtins.attrValues assetCatalog);
      assetPublicPaths = lib.concatMap (asset: [ asset.publicPath ] ++ asset.legacyPublicPaths) (
        builtins.attrValues assetCatalog
      );
      assetRoutePriorities = map (asset: asset.routePriority) (builtins.attrValues assetCatalog);
    in
    builtins.attrNames manifest == [
      "assetCatalog"
      "profiles"
      "publicationPhases"
      "schemaVersion"
    ]
    && manifest.schemaVersion == 1
    && builtins.all (id: validateAsset id assetCatalog.${id}) (builtins.attrNames assetCatalog)
    && assetFilenames == lib.unique assetFilenames
    && assetPublicPaths == lib.unique assetPublicPaths
    && assetRoutePriorities == lib.unique assetRoutePriorities
    && profileNames == lib.unique profileNames
    && builtins.all (validateProfile assetCatalog) manifest.profiles
    && validatePublicationPhases manifest.publicationPhases;
in
{
  inherit
    artifactFormats
    artifactDecodingRules
    collectPlaceholders
    decodingRules
    expectedPublicationPhases
    hasPlaceholderSyntax
    invalidPlaceholderPlacement
    validateArtifact
    validateManifest
    validatePublicationPhases
    valueAtPath
    ;
}
