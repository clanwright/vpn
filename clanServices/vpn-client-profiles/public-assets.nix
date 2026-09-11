{
  lib,
  pkgs,
  appsPkgs,
  render,
  assetRoot,
  statusPath,
  readerGroup,
  refreshService,
}:
let
  inherit (render)
    generatedProfiles
    mihomoMrsUpstream
    personalProxyDomainsTxt
    upstreamRuleSets
    ;

  hasProfiles = generatedProfiles != [ ];
  needsSingBoxAssets = builtins.any (profile: profile.publishProfileJson) generatedProfiles;
  hasPersonalDomains = builtins.any (
    profile: profile.mihomoSelectiveTemplate."rule-providers" ? personal_proxy_domains
  ) generatedProfiles;

  mihomoRemoteAssetPaths = lib.optionals hasProfiles (
    [ "${assetRoot}/secure-dns.txt" ]
    ++ map (ruleSet: "${assetRoot}/${ruleSet.tag}.mrs") mihomoMrsUpstream
  );
  singBoxAssetPaths = lib.optionals needsSingBoxAssets (
    [ "${assetRoot}/filters.srs" ] ++ map (ruleSet: "${assetRoot}/${ruleSet.tag}.srs") upstreamRuleSets
  );
  requiredRemoteAssetPaths = mihomoRemoteAssetPaths ++ singBoxAssetPaths;
  requiredAssetPaths =
    requiredRemoteAssetPaths ++ lib.optional hasPersonalDomains "${assetRoot}/segments.txt";

  refreshSrs = ruleSet: ''
    refresh_download srs ${lib.escapeShellArg "${ruleSet.tag}.srs"} ${lib.escapeShellArg ruleSet.url}
  '';
  refreshMrs = ruleSet: ''
    refresh_download nonempty ${lib.escapeShellArg "${ruleSet.tag}.mrs"} ${lib.escapeShellArg ruleSet.url}
  '';
in
{
  inherit requiredAssetPaths;
  localAssetSyncScript =
    if hasPersonalDomains then
      ''
        install -d -o root -g ${lib.escapeShellArg readerGroup} -m 0750 ${lib.escapeShellArg assetRoot}
        local_asset_tmp="$(mktemp ${lib.escapeShellArg "${assetRoot}/.segments.XXXXXX"})"
        install -o root -g ${lib.escapeShellArg readerGroup} -m 0440 ${lib.escapeShellArg personalProxyDomainsTxt} "$local_asset_tmp"
        mv -f "$local_asset_tmp" ${lib.escapeShellArg "${assetRoot}/segments.txt"}
      ''
    else
      ''
        rm -f ${lib.escapeShellArg "${assetRoot}/segments.txt"}
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
          local validator="$1" name="$2" url="$3" tmp
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
          publish_file "$tmp" "$name"
          record_status "$name" refreshed ok
        }

        ${lib.optionalString hasProfiles ''
          refresh_download nonempty secure-dns.txt \
            https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/doh-onlydomains.txt
          ${lib.concatMapStrings refreshMrs mihomoMrsUpstream}
        ''}

        ${lib.optionalString needsSingBoxAssets ''
          hagezi_source="$work_dir/hagezi-adblock.txt"
          hagezi_filtered="$work_dir/hagezi-adblock.filtered.txt"
          hagezi_srs="$work_dir/filters.srs"
          if ! curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 120 \
            --retry 6 --retry-delay 10 --retry-all-errors \
            --output "$hagezi_source" \
            https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh.txt; then
            record_status filters.srs failed download_failed
          elif ! sed '/^[[:space:]]*$/d' "$hagezi_source" > "$hagezi_filtered" \
            || [ ! -s "$hagezi_filtered" ]; then
            record_status filters.srs failed empty_download
          elif ! sing-box rule-set convert --type adguard --output "$hagezi_srs" "$hagezi_filtered" >/dev/null 2>&1 \
            || [ ! -s "$hagezi_srs" ] \
            || ! sing-box rule-set match --format binary "$hagezi_srs" dns.google >/dev/null 2>&1; then
            record_status filters.srs failed validation_failed
          else
            publish_file "$hagezi_srs" filters.srs
            record_status filters.srs refreshed ok
          fi

          ${lib.concatMapStrings refreshSrs upstreamRuleSets}
        ''}

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
