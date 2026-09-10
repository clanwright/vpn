{
  config,
  lib,
  pkgs,
  mihomoPackage,
  render,
  settings,
  runtimeBase,
  profileRoot,
  readerGroup,
  publicationService,
  requiredAssetPaths,
  localAssetSyncScript,
}:
let
  inherit (settings) localMachineName;
  inherit (render) generatedProfiles renderedProfiles;

  allSecretNames = lib.unique (
    lib.concatMap (
      profile:
      [ profile.pathTokenSecret ]
      ++ map (cred: cred.vlessUuidSecretName) profile.upstreamCredentials
      ++ map (cred: cred.clientPrivateKeySecretName) profile.amneziawgCredentials
      ++ map (cred: cred.headerProtectionKeySecretName) profile.amneziawgCredentials
      ++ map (cred: cred.passwordSecretName) profile.hysteria2Credentials
      ++ map (cred: cred.obfsPasswordSecretName) (
        builtins.filter (cred: cred.obfsPasswordSecretName != null) profile.hysteria2Credentials
      )
      ++ lib.optionals profile.publishProfileJson (
        map (cred: cred.passwordSecretName) profile.naiveCredentials
      )
    ) generatedProfiles
  );

  secretDecls = lib.genAttrs allSecretNames (_name: {
    format = lib.mkDefault "binary";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "${publicationService}.service" ];
  });

  # Escape punctuation distinctly so valid publisher identities remain
  # collision-free as shell and jq variable suffixes.
  toIdent = value: lib.replaceStrings [ "_" "-" "." ] [ "_u" "_h" "_d" ] value;

  mkUpstreamCred =
    cred:
    let
      machineId = toIdent cred.machineName;
    in
    {
      decl = ''
        make_secret_file vless_uuid_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.vlessUuidSecretName}.path
        } > "$vless_uuid_${machineId}_file"
      '';
      arg = ''--rawfile vless_uuid_${machineId} "$vless_uuid_${machineId}_file"'';
      filter = ''(.proxies[] | select(.name == "${cred.vlessTag}").uuid) = $vless_uuid_${machineId}'';
    };

  mkAmneziawgCred =
    cred:
    let
      machineId = toIdent cred.machineName;
      profileId = toIdent cred.amneziawgTag;
    in
    {
      decl = ''
        make_secret_file amneziawg_private_key_${machineId}_file
        read_wireguard_private_key ${lib.escapeShellArg cred.clientPrivateKeySecretName} ${
          lib.escapeShellArg config.sops.secrets.${cred.clientPrivateKeySecretName}.path
        } > "$amneziawg_private_key_${machineId}_file"
        make_secret_file amneziawg_header_protection_key_${profileId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.headerProtectionKeySecretName}.path
        } > "$amneziawg_header_protection_key_${profileId}_file"
      '';
      arg = ''--rawfile amneziawg_private_key_${machineId} "$amneziawg_private_key_${machineId}_file" --rawfile amneziawg_header_protection_key_${profileId} "$amneziawg_header_protection_key_${profileId}_file"'';
      filter = ''(.proxies[] | select(.name == "${cred.amneziawgTag}")."private-key") = $amneziawg_private_key_${machineId} | (.proxies[] | select(.name == "${cred.amneziawgTag}")."amnezia-wg-option"."header-protection-key") = $amneziawg_header_protection_key_${profileId}'';
    };

  mkHysteria2Cred =
    cred:
    let
      machineId = toIdent cred.machineName;
      profileId = toIdent cred.profileName;
    in
    {
      decl = ''
        make_secret_file hysteria2_password_${machineId}_${profileId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.passwordSecretName}.path
        } > "$hysteria2_password_${machineId}_${profileId}_file"
      ''
      + lib.optionalString (cred.obfsPasswordSecretName != null) ''
        make_secret_file hysteria2_obfs_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.obfsPasswordSecretName}.path
        } > "$hysteria2_obfs_${machineId}_file"
      '';
      arg =
        ''--rawfile hysteria2_password_${machineId}_${profileId} "$hysteria2_password_${machineId}_${profileId}_file"''
        + lib.optionalString (cred.obfsPasswordSecretName != null) (
          " " + ''--rawfile hysteria2_obfs_${machineId} "$hysteria2_obfs_${machineId}_file"''
        );
      filter =
        ''(.proxies[] | select(.name == "${cred.tag}").password) = $hysteria2_password_${machineId}_${profileId}''
        +
          lib.optionalString (cred.obfsPasswordSecretName != null)
            ''| (.proxies[] | select(.name == "${cred.tag}")."obfs-password") = $hysteria2_obfs_${machineId}'';
    };

  mkNaiveCred =
    cred:
    let
      machineId = toIdent cred.machineName;
    in
    {
      decl = ''
        make_secret_file naive_password_${machineId}_file
        read_secret ${
          lib.escapeShellArg config.sops.secrets.${cred.passwordSecretName}.path
        } > "$naive_password_${machineId}_file"
      '';
      arg = ''--rawfile naive_password_${machineId} "$naive_password_${machineId}_file"'';
      filter = ''(.outbounds[] | select(.tag == "${cred.tag}").password) = $naive_password_${machineId}'';
    };

  profileCase =
    profile:
    let
      yamlCredArtifacts =
        map mkUpstreamCred profile.upstreamCredentials
        ++ map mkAmneziawgCred profile.amneziawgCredentials
        ++ map mkHysteria2Cred profile.hysteria2Credentials;
      jqSecretFileDecls = lib.concatStringsSep "\n" (map (a: lib.strings.trim a.decl) yamlCredArtifacts);
      jqArgs = lib.concatStringsSep " \\\n          " (map (a: lib.strings.trim a.arg) yamlCredArtifacts);
      jqFilterItems = map (a: a.filter) yamlCredArtifacts;
      jqFilter =
        if jqFilterItems == [ ] then "." else lib.concatStringsSep "\n            | " jqFilterItems;
      naiveCredArtifacts = map mkNaiveCred profile.naiveCredentials;
      profileJsonDecls = lib.concatStringsSep "\n" (map (a: lib.strings.trim a.decl) naiveCredArtifacts);
      profileJsonArgs = lib.concatStringsSep " \\\n          " (
        map (a: lib.strings.trim a.arg) naiveCredArtifacts
      );
      profileJsonFilters = map (a: a.filter) naiveCredArtifacts;
      profileJsonFilter =
        if profileJsonFilters == [ ] then
          "."
        else
          lib.concatStringsSep "\n            | " profileJsonFilters;
      profileJsonCase = lib.optionalString profile.publishProfileJson ''
        ${profileJsonDecls}
        jq \
          ${profileJsonArgs} \
          '${profileJsonFilter}' \
          ${lib.escapeShellArg profile.profileJsonTemplatePath} > "$profile_json_tmp"
        install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 "$profile_json_tmp" "$profile_dir/profile.json"
      '';
      matchingLinks = builtins.filter (link: link.name == profile.name) settings.profileLinks;
      link = if matchingLinks == [ ] then null else builtins.head matchingLinks;
      linkCase = lib.optionalString (settings.linksPage.enable && link != null) ''
        escaped_domain="$(html_escape ${lib.escapeShellArg link.accountDomain})"
        escaped_label="$(html_escape ${lib.escapeShellArg link.label})"
        printf '<li><a href="https://%s/%s/mihomo.yaml">%s (mihomo.yaml)</a></li>\n' "$escaped_domain" "$path_token" "$escaped_label" >> "$links_tmp"
        printf '<li><a href="https://%s/%s/mihomo-full.yaml">%s (mihomo-full.yaml)</a></li>\n' "$escaped_domain" "$path_token" "$escaped_label" >> "$links_tmp"
        ${lib.optionalString profile.publishProfileJson ''
          printf '<li><a href="https://%s/%s/profile.json">%s (profile.json)</a></li>\n' "$escaped_domain" "$path_token" "$escaped_label" >> "$links_tmp"
        ''}
      '';
    in
    ''
      path_token="$(read_path_token ${
        lib.escapeShellArg config.sops.secrets.${profile.pathTokenSecret}.path
      })"
      profile_dir="$stage/profiles/$path_token"
      test ! -e "$profile_dir"
      install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$profile_dir"
      json_tmp="$(mktemp "$runtime_base/.mihomo.XXXXXX.json")"
      yaml_tmp="$(mktemp "$runtime_base/.mihomo.XXXXXX.yaml")"
      full_json_tmp="$(mktemp "$runtime_base/.mihomo-full.XXXXXX.json")"
      full_yaml_tmp="$(mktemp "$runtime_base/.mihomo-full.XXXXXX.yaml")"
      profile_json_tmp="$(mktemp "$runtime_base/.profile.XXXXXX.json")"
      private_tmp_files+=("$json_tmp" "$yaml_tmp" "$full_json_tmp" "$full_yaml_tmp" "$profile_json_tmp")

      ${jqSecretFileDecls}
      jq ${jqArgs} '${jqFilter}' ${lib.escapeShellArg profile.templatePath} > "$json_tmp"
      yq -P -o=yaml '.' "$json_tmp" > "$yaml_tmp"
      mihomo -t -f "$yaml_tmp"
      install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 "$yaml_tmp" "$profile_dir/mihomo.yaml"

      jq ${jqArgs} '${jqFilter}' ${lib.escapeShellArg profile.fullTemplatePath} > "$full_json_tmp"
      yq -P -o=yaml '.' "$full_json_tmp" > "$full_yaml_tmp"
      mihomo -t -f "$full_yaml_tmp"
      install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 "$full_yaml_tmp" "$profile_dir/mihomo-full.yaml"
      ${profileJsonCase}
      ${linkCase}
      rm -f "$json_tmp" "$yaml_tmp" "$full_json_tmp" "$full_yaml_tmp" "$profile_json_tmp"
    '';

  title = settings.linksPage.title;
in
{
  inherit renderedProfiles;
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
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
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
        private_tmp_files=()
          cleanup() {
          rc="$?"
          if [ -n "$stage" ]; then rm -rf -- "$stage"; fi
          if [ -n "$generation" ]; then rm -rf -- "$generation"; fi
            if [ "''${#private_tmp_files[@]}" -ne 0 ]; then rm -f -- "''${private_tmp_files[@]}"; fi
            if [ "$rc" -ne 0 ]; then
              rm -f -- ${lib.escapeShellArg profileRoot}
              printf 'VPN client profile publication failed; endpoint remains unpublished\n' >&3
            fi
            exit "$rc"
          }
        trap cleanup EXIT

        find "$runtime_base/generations" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        ${localAssetSyncScript}
          ${lib.concatMapStringsSep "\n" (path: ''
            test -s ${lib.escapeShellArg path}
          '') requiredAssetPaths}

          stage="$(mktemp -d ${lib.escapeShellArg "${runtimeBase}/generations/.staging.XXXXXX"})"
          install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$stage/profiles"
          html_escape() { printf '%s' "$1" | jq -sRr @html; }
          ${lib.optionalString settings.linksPage.enable ''
            install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 "$stage/links"
            links_tmp="$stage/links/index.html"
            escaped_title="$(html_escape ${lib.escapeShellArg title})"
            printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head><body><h1>%s</h1><ul>\n' "$escaped_title" "$escaped_title" > "$links_tmp"
          ''}

          read_secret() { tr -d '\r\n' < "$1"; }
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
            chmod 0400 "$tmp"
            private_tmp_files+=("$tmp")
            printf -v "$var_name" '%s' "$tmp"
          }
          read_wireguard_private_key() {
            local value decoded_len
            value="$(read_secret "$2")"
            decoded_len="$(printf '%s' "$value" | base64 -d 2>/dev/null | wc -c)"
            test "$decoded_len" = 32
            printf '%s' "$value"
          }

          ${lib.concatStringsSep "\n" (map profileCase generatedProfiles)}
          ${lib.optionalString settings.linksPage.enable ''
            printf '</ul></body></html>\n' >> "$links_tmp"
            chown root:${lib.escapeShellArg readerGroup} "$links_tmp"
            chmod 0440 "$links_tmp"
          ''}

          find "$stage" -type d -exec chown root:${lib.escapeShellArg readerGroup} {} +
          find "$stage" -type d -exec chmod 0750 {} +
          find "$stage" -type f -exec chown root:${lib.escapeShellArg readerGroup} {} +
          find "$stage" -type f -exec chmod 0440 {} +

          generation="$runtime_base/generations/generation-$(date -u +%Y%m%dT%H%M%SZ)-$$"
          mv -- "$stage" "$generation"
          stage=""
          link_tmp="$runtime_base/published/.current.$$"
          ln -s -- "$generation" "$link_tmp"
          mv -Tf -- "$link_tmp" ${lib.escapeShellArg profileRoot}
        find "$runtime_base/generations" -mindepth 1 -maxdepth 1 ! -path "$generation" -exec rm -rf -- {} +
          if [ "''${#private_tmp_files[@]}" -ne 0 ]; then rm -f -- "''${private_tmp_files[@]}"; fi
        private_tmp_files=()
        generation=""
        trap - EXIT
      '';
    };
  };
}
