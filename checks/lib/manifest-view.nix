{ lib }:
manifest: {
  inherit manifest;
  # Checks inspect canonical artifact templates; no production diagnostic API.
  renderedProfiles = map (
    profile:
    let
      template =
        outputName:
        (lib.findFirst (artifact: artifact.outputName == outputName) { template = null; } profile.artifacts)
        .template;
      profileJsonTemplate = template "profile.json";
    in
    {
      inherit (profile) name;
      inherit profileJsonTemplate;
      mihomoSelectiveTemplate = template "mihomo.yaml";
      publishProfileJson = profileJsonTemplate != null;
    }
  ) manifest.profiles;
}
