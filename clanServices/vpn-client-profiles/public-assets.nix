{
  lib,
  pkgs,
  appsPkgs,
  manifest,
  assetRoot,
  statusPath,
  readerGroup,
  refreshService,
}:
let
  inherit (manifest) assetCatalog;
  referencedAssetIds = lib.unique (
    lib.concatMap (
      profile: lib.concatMap (artifact: artifact.assetRefs) profile.artifacts
    ) manifest.profiles
  );
  referencedAssets = lib.sort (left: right: left.routePriority < right.routePriority) (
    map (id: assetCatalog.${id}) referencedAssetIds
  );
  remoteAssets = builtins.filter (asset: asset.source.kind != "local-file") referencedAssets;
  allLocalAssets = builtins.filter (asset: asset.source.kind == "local-file") (
    builtins.attrValues assetCatalog
  );
  requiredAssetPaths = map (asset: "${assetRoot}/${asset.filename}") referencedAssets;
  requiredRemoteAssetPaths = map (asset: "${assetRoot}/${asset.filename}") remoteAssets;

  localAssetAction =
    asset:
    if builtins.elem asset.id referencedAssetIds then
      ''
        local_asset_tmp="$(mktemp ${lib.escapeShellArg "${assetRoot}/.${asset.id}.XXXXXX"})"
        install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 \
          ${lib.escapeShellArg asset.source.path} "$local_asset_tmp"
        mv -f "$local_asset_tmp" ${lib.escapeShellArg "${assetRoot}/${asset.filename}"}
      ''
    else
      ''
        rm -f ${lib.escapeShellArg "${assetRoot}/${asset.filename}"}
      '';

  remoteAssetAction =
    asset:
    if asset.source.kind == "download" then
      ''
        refresh_download ${lib.escapeShellArg asset.validator} ${lib.escapeShellArg asset.filename} ${lib.escapeShellArg asset.source.url}
      ''
    else
      ''
        adguard_source="$work_dir/${asset.id}.adguard.txt"
        adguard_filtered="$work_dir/${asset.id}.filtered.txt"
        adguard_srs="$work_dir/${asset.filename}"
        if ! curl --fail --location --silent --show-error \
          --connect-timeout 15 --max-time 120 \
          --retry 6 --retry-delay 10 --retry-all-errors \
          --output "$adguard_source" ${lib.escapeShellArg asset.source.url}; then
          record_status ${lib.escapeShellArg asset.filename} failed download_failed
        elif ! sed '/^[[:space:]]*$/d' "$adguard_source" > "$adguard_filtered" \
          || [ ! -s "$adguard_filtered" ]; then
          record_status ${lib.escapeShellArg asset.filename} failed empty_download
        elif ! sing-box rule-set convert --type adguard --output "$adguard_srs" "$adguard_filtered" >/dev/null 2>&1 \
          || [ ! -s "$adguard_srs" ] \
          || ! sing-box rule-set match --format binary "$adguard_srs" dns.google >/dev/null 2>&1; then
          record_status ${lib.escapeShellArg asset.filename} failed validation_failed
        else
          publish_file "$adguard_srs" ${lib.escapeShellArg asset.filename}
          record_status ${lib.escapeShellArg asset.filename} refreshed ok
        fi
      '';
in
{
  inherit
    referencedAssets
    referencedAssetIds
    requiredAssetPaths
    ;
  localAssetSyncScript = ''
    install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 ${lib.escapeShellArg assetRoot}
    ${lib.concatMapStringsSep "\n" localAssetAction allLocalAssets}
  '';
  systemd = {
    tmpfiles.rules = [
      "d ${assetRoot} 0750 root ${readerGroup} -"
      "d ${builtins.dirOf statusPath} 0750 root ${readerGroup} -"
    ];
    timers.${refreshService} = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1d";
        Persistent = true;
        Unit = "${refreshService}.service";
      };
    };
    services.${refreshService} = {
      description = "Refresh persistent public VPN client rule assets";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "60s";
      };
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnused
        pkgs.jq
        appsPkgs.mihomo
        appsPkgs.sing-box
      ];
      script = ''
        set -euo pipefail

        install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 ${lib.escapeShellArg assetRoot}
        install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 ${lib.escapeShellArg (builtins.dirOf statusPath)}

        work_dir="$(mktemp -d ${lib.escapeShellArg "${assetRoot}/.refresh.XXXXXX"})"
        status_stage="$(mktemp ${lib.escapeShellArg "${builtins.dirOf statusPath}/.status.XXXXXX"})"
        status_work="$work_dir/status.json"
        trap 'rm -rf "$work_dir"; rm -f "$status_stage"' EXIT

        if [ -s ${lib.escapeShellArg statusPath} ] && jq -e 'type == "object"' ${lib.escapeShellArg statusPath} >/dev/null 2>&1; then
          cp ${lib.escapeShellArg statusPath} "$status_work"
        else
          printf '{}\n' > "$status_work"
        fi

        record_status() {
          local asset="$1" result="$2" reason="$3" now next
          now="$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
          next="$work_dir/status.next"
          jq --arg asset "$asset" --arg result "$result" --arg reason "$reason" --arg now "$now" '
            .[$asset] = ((.[$asset] // {}) + {
              attempted_at: $now,
              result: $result,
              reason: $reason
            } + (if $result == "refreshed" then { refreshed_at: $now } else {} end))
          ' "$status_work" > "$next" && mv "$next" "$status_work"
        }

        publish_file() {
          local source="$1" name="$2" staged
          staged="$work_dir/.publish.$name"
          install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 "$source" "$staged"
          mv -f "$staged" ${lib.escapeShellArg assetRoot}/"$name"
        }

        refresh_download() {
          local validator="$1" name="$2" url="$3" tmp mrs_behavior mrs_output
          tmp="$work_dir/$name"
          if ! curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 120 \
            --retry 6 --retry-delay 10 --retry-all-errors \
            --output "$tmp" "$url"; then
            record_status "$name" failed download_failed
            return 0
          fi
          if [ ! -s "$tmp" ]; then
            record_status "$name" failed empty_download
            return 0
          fi
          if [ "$validator" = srs ] \
            && ! sing-box rule-set decompile "$tmp" >/dev/null 2>&1 \
            && ! sing-box rule-set match --format binary "$tmp" example.com >/dev/null 2>&1; then
            record_status "$name" failed validation_failed
            return 0
          fi
          case "$validator" in
            mrs-domain)
              mrs_behavior=domain
              ;;
            mrs-ipcidr)
              mrs_behavior=ipcidr
              ;;
            *)
              mrs_behavior=
              ;;
          esac
          if [ -n "$mrs_behavior" ]; then
            mrs_output="$work_dir/.validate.$name.txt"
            if ! mihomo convert-ruleset "$mrs_behavior" mrs "$tmp" "$mrs_output" >/dev/null 2>&1 \
              || [ ! -s "$mrs_output" ]; then
              record_status "$name" failed validation_failed
              return 0
            fi
          fi
          publish_file "$tmp" "$name"
          record_status "$name" refreshed ok
        }

        ${lib.concatMapStringsSep "\n" remoteAssetAction remoteAssets}

        install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 "$status_work" "$status_stage"
        mv -f "$status_stage" ${lib.escapeShellArg statusPath}

        missing=0
        ${lib.concatMapStringsSep "\n" (path: ''
          if [ ! -s ${lib.escapeShellArg path} ]; then
            printf 'required public asset is missing or empty: %s\n' ${lib.escapeShellArg path} >&2
            missing=1
          fi
        '') requiredRemoteAssetPaths}
        exit "$missing"
      '';
    };
  };
}
