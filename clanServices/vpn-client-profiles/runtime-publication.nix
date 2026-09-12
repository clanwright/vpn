{
  config,
  lib,
  pkgs,
  mihomoPackage,
  manifest,
  renderedProfiles,
  settings,
  runtimeBase,
  profileRoot,
  readerGroup,
  publicationService,
  refreshUnit,
  requiredAssetPaths,
  localAssetSyncScript,
}:
let
  inherit (settings) localMachineName;
  manifestLib = import ./artifact-manifest.nix { inherit lib; };
  checkedManifest =
    if manifestLib.validateManifest manifest then
      manifest
    else
      throw "vpn-client-profiles: invalid internal artifact manifest";
  allSecretNames = lib.unique (
    lib.concatMap (
      profile:
      [ profile.pathTokenBinding.secretName ]
      ++ lib.concatMap (artifact: map (binding: binding.secretName) artifact.bindings) profile.artifacts
    ) checkedManifest.profiles
  );
  secretDecls = lib.genAttrs allSecretNames (_name: {
    format = lib.mkDefault "binary";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "${publicationService}.service" ];
  });
  toIdent = value: lib.replaceStrings [ "_" "-" "." ] [ "_u" "_h" "_d" ] value;
  shellVariable = name: "$" + "{${name}}";
  jqVariable = name: "$" + name;
  decoderFunction =
    decoding:
    {
      literal = "read_literal_secret";
      wireguard-private-key = "read_wireguard_private_key";
      base64url = "read_base64url_secret";
    }
    .${decoding};

  artifactCase =
    artifact:
    let
      artifactId = toIdent artifact.id;
      bindingRecords = lib.imap0 (
        index: binding:
        let
          id = "binding_${artifactId}_${toString index}";
        in
        {
          inherit id binding;
          fileVariable = "${id}_file";
          valueVariable = id;
        }
      ) artifact.bindings;
      bindingDeclarations = lib.concatMapStringsSep "\n" (record: ''
        make_secret_file ${record.fileVariable}
        ${decoderFunction record.binding.decoding} ${
          lib.escapeShellArg config.sops.secrets.${record.binding.secretName}.path
        } > "${shellVariable record.fileVariable}"
      '') bindingRecords;
      jqArguments = lib.concatMapStringsSep " \\\n          " (
        record: ''--rawfile ${record.valueVariable} "${shellVariable record.fileVariable}"''
      ) bindingRecords;
      jqFilter = lib.concatStringsSep "\n            | " (
        [ "." ]
        ++ map (
          record: "setpath(${builtins.toJSON record.binding.targetPath}; ${jqVariable record.valueVariable})"
        ) bindingRecords
      );
      jsonVariable = "artifact_${artifactId}_json";
      outputVariable = "artifact_${artifactId}_output";
      renderOutput =
        if artifact.format == "mihomo" then
          ''
            yq -P -o=yaml '.' "${shellVariable jsonVariable}" > "${shellVariable outputVariable}"
            failure_stage=mihomo-validation
            failure_reason=config-rejected
            mihomo -t -f "${shellVariable outputVariable}"
          ''
        else
          ''
            cp "${shellVariable jsonVariable}" "${shellVariable outputVariable}"
          '';
    in
    ''
      failure_stage=preparation
      failure_reason=temporary-file-failed
      ${jsonVariable}="$(mktemp "$runtime_base/.artifact.XXXXXX.json")"
      private_tmp_files+=("${shellVariable jsonVariable}")
      ${outputVariable}="$(mktemp "$runtime_base/.artifact.XXXXXX.output")"
      private_tmp_files+=("${shellVariable outputVariable}")
      failure_stage=credential-loading
      failure_reason=credential-invalid-or-unavailable
      ${bindingDeclarations}
      failure_stage=profile-rendering
      failure_reason=render-failed
      jq \
        ${jqArguments} \
        ${lib.escapeShellArg jqFilter} \
        ${lib.escapeShellArg artifact.templatePath} > "${shellVariable jsonVariable}"
      ${renderOutput}
      failure_stage=file-installation
      failure_reason=install-failed
      install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 \
        "${shellVariable outputVariable}" "$profile_dir/${artifact.outputName}"
    '';

  profileCase =
    profile:
    let
      matchingLinks = builtins.filter (link: link.name == profile.name) settings.profileLinks;
      link = if matchingLinks == [ ] then null else builtins.head matchingLinks;
      linkItems = lib.concatMapStringsSep "\n" (artifact: ''
        printf '<li><a href="https://%s/%s/${artifact.outputName}">%s (${artifact.outputName})</a></li>\n' \
          "$escaped_domain" "$path_token" "$escaped_label" >> "$links_tmp"
      '') profile.artifacts;
      linkCase = lib.optionalString (settings.linksPage.enable && link != null) ''
        escaped_domain="$(html_escape ${lib.escapeShellArg link.accountDomain})"
        escaped_label="$(html_escape ${lib.escapeShellArg link.label})"
        ${linkItems}
      '';
    in
    ''
      failure_stage=credential-loading
      failure_reason=credential-invalid-or-unavailable
      path_token="$(read_path_token ${
        lib.escapeShellArg config.sops.secrets.${profile.pathTokenBinding.secretName}.path
      })"
      failure_stage=file-installation
      failure_reason=install-failed
      profile_dir="$stage/profiles/$path_token"
      test ! -e "$profile_dir"
      install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$profile_dir"
      ${lib.concatMapStringsSep "\n" artifactCase profile.artifacts}
      ${linkCase}
    '';

  title = settings.linksPage.title;
  phaseScripts = {
    revoke-current = ''
      failure_stage=revocation
      failure_reason=current-generation-revocation-failed
      rm -f -- ${lib.escapeShellArg profileRoot}
      find "$runtime_base/generations" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    '';
    sync-local-assets = ''
      failure_stage=assets-readiness
      failure_reason=local-asset-sync-failed
      ${localAssetSyncScript}
    '';
    check-assets = ''
      failure_stage=assets-readiness
      failure_reason=required-assets-missing-or-empty
      ${lib.concatMapStringsSep "\n" (path: ''
        test -s ${lib.escapeShellArg path}
      '') requiredAssetPaths}
    '';
    prepare-generation = ''
      failure_stage=file-installation
      failure_reason=install-failed
      stage="$(mktemp -d ${lib.escapeShellArg "${runtimeBase}/generations/.staging.XXXXXX"})"
      install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$stage/profiles"
      html_escape() { printf '%s' "$1" | jq -sRr @html; }
      ${lib.optionalString settings.linksPage.enable ''
        install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$stage/links"
        links_tmp="$stage/links/index.html"
        escaped_title="$(html_escape ${lib.escapeShellArg title})"
        printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head><body><h1>%s</h1><ul>\n' \
          "$escaped_title" "$escaped_title" > "$links_tmp"
      ''}
    '';
    render-artifacts = ''
      ${lib.concatMapStringsSep "\n" profileCase checkedManifest.profiles}
    '';
    finalize-links = ''
      failure_stage=file-installation
      failure_reason=install-failed
      ${lib.optionalString settings.linksPage.enable ''
        printf '</ul></body></html>\n' >> "$links_tmp"
        chown root:${lib.escapeShellArg readerGroup} "$links_tmp"
        chmod 0440 "$links_tmp"
      ''}
    '';
    seal-generation = ''
      failure_stage=file-installation
      failure_reason=install-failed
      find "$stage" -type d -exec chown root:${lib.escapeShellArg readerGroup} {} +
      find "$stage" -type d -exec chmod 0750 {} +
      find "$stage" -type f -exec chown root:${lib.escapeShellArg readerGroup} {} +
      find "$stage" -type f -exec chmod 0440 {} +
      generation="$runtime_base/generations/generation-$(date -u +%Y%m%dT%H%M%SZ)-$$"
      mv -- "$stage" "$generation"
      stage=""
    '';
    expose-generation = ''
      failure_stage=file-installation
      failure_reason=install-failed
      link_tmp="$runtime_base/published/.current.$$"
      ln -s -- "$generation" "$link_tmp"
      mv -Tf -- "$link_tmp" ${lib.escapeShellArg profileRoot}
    '';
    retire-old-generations = ''
      failure_stage=cleanup
      failure_reason=generation-cleanup-failed
      find "$runtime_base/generations" -mindepth 1 -maxdepth 1 ! -path "$generation" -exec rm -rf -- {} +
    '';
    cleanup-private-temporaries = ''
      failure_stage=cleanup
      failure_reason=temporary-file-cleanup-failed
      if [ "''${#private_tmp_files[@]}" -ne 0 ]; then rm -f -- "''${private_tmp_files[@]}"; fi
      private_tmp_files=()
      generation=""
      trap - EXIT
    '';
  };
  publicationScript = lib.concatMapStringsSep "\n" (phase: ''
    # publication-phase:${phase.id}
    ${phaseScripts.${phase.id}}
  '') checkedManifest.publicationPhases;
in
{
  inherit renderedProfiles;
  inherit (checkedManifest) publicationPhases;
  sops.secrets = secretDecls;
  systemd = {
    tmpfiles.rules = [
      "d ${runtimeBase} 0750 root ${readerGroup} -"
      "d ${runtimeBase}/published 0750 root ${readerGroup} -"
      "d ${runtimeBase}/generations 0750 root ${readerGroup} -"
    ];
    services.${publicationService} = {
      description = "Atomically publish VPN client profiles for ${localMachineName}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        refreshUnit
      ];
      wants = [
        "network-online.target"
        refreshUnit
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "60s";
        User = "root";
        Group = "root";
        UMask = "0027";
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${profileRoot}";
      };
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.jq
        mihomoPackage
        pkgs.yq-go
      ];
      postStop = ''
        exec 3>&2
        exec >/dev/null 2>&1
        if ! ${pkgs.coreutils}/bin/rm -f -- ${lib.escapeShellArg profileRoot} \
          || ! ${pkgs.findutils}/bin/find ${lib.escapeShellArg "${runtimeBase}/generations"} \
            -mindepth 1 -maxdepth 1 -exec ${pkgs.coreutils}/bin/rm -rf -- {} +; then
          printf 'VPN client profile stop cleanup failed\n' >&3
          exit 1
        fi
      '';
      script = ''
        set -euo pipefail
        exec 3>&2
        exec >/dev/null 2>&1
        runtime_base=${lib.escapeShellArg runtimeBase}
        stage=""
        generation=""
        failure_stage=preparation
        failure_reason=unexpected-failure
        private_tmp_files=()
        cleanup() {
          rc="$?"
          set +e
          if [ -n "$stage" ]; then rm -rf -- "$stage"; fi
          if [ -n "$generation" ]; then rm -rf -- "$generation"; fi
          if [ "''${#private_tmp_files[@]}" -ne 0 ]; then rm -f -- "''${private_tmp_files[@]}"; fi
          if [ "$rc" -ne 0 ]; then
            rm -f -- ${lib.escapeShellArg profileRoot}
            printf 'VPN client profile publication failed: stage=%s reason=%s; endpoint remains unpublished\n' \
              "$failure_stage" "$failure_reason" >&3
          fi
          exit "$rc"
        }
        trap cleanup EXIT

        read_literal_secret() { tr -d '\r\n' < "$1"; }
        read_path_token() {
          local value byte_count
          value="$(cat "$1")"
          byte_count="$(LC_ALL=C wc -c < "$1")"
          byte_count="''${byte_count//[[:space:]]/}"
          if [ "''${#value}" -ne "$byte_count" ] || [[ ! "$value" =~ ^[A-Za-z0-9_-]{32,128}$ ]]; then
            return 1
          fi
          printf '%s' "$value"
        }
        make_secret_file() {
          local var_name="$1" tmp
          tmp="$(mktemp "$runtime_base/.secret.XXXXXX")"
          private_tmp_files+=("$tmp")
          chmod 0400 "$tmp"
          printf -v "$var_name" '%s' "$tmp"
        }
        read_wireguard_private_key() {
          local value decoded_len
          value="$(read_literal_secret "$1")"
          decoded_len="$(printf '%s' "$value" | base64 -d 2>/dev/null | wc -c)"
          test "$decoded_len" = 32
          printf '%s' "$value"
        }
        read_base64url_secret() {
          local value byte_count value_count
          value="$(cat "$1")"
          byte_count="$(LC_ALL=C wc -c < "$1")"
          byte_count="''${byte_count//[[:space:]]/}"
          value_count="$(LC_ALL=C printf '%s' "$value" | wc -c)"
          value_count="''${value_count//[[:space:]]/}"
          if [ -z "$value" ] \
            || [ "$byte_count" -ne "$value_count" ] \
            || [ "$value_count" -gt 64 ] \
            || [[ ! "$value" =~ ^[A-Za-z0-9_-]+$ ]]; then
            return 1
          fi
          printf '%s' "$value"
        }

        ${publicationScript}
      '';
    };
  };
}
