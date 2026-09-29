{
  lib,
  config,
  settings,
  runtimeBase,
  ...
}:
let
  publishedProfileNames = map (profile: profile.name) (
    builtins.filter (profile: !(builtins.elem profile.name (settings.excludedProfileNames or [ ]))) (
      settings.profiles or [ ]
    )
  );
  displayNames = import ./display-names.nix { inherit lib; };
  inherit (displayNames) manualGroup autoGroup;
  sourceLabel = name: source: if (source.label or null) == null then name else source.label;
  sources = lib.filterAttrs (
    _name: source: builtins.any (name: builtins.elem name publishedProfileNames) source.profileNames
  ) (settings.externalSubscriptions or { });
  converter = ''
    def closed($allowed): type == "object" and ((keys - $allowed) | length == 0);
    def text: type == "string" and length > 0 and (test("[\u0000-\u0020\u007f]") | not);
    def fingerprint: IN("chrome","firefox","safari","ios","android","edge","360","qq","random","randomized");
    def node:
      select(closed(["tag","protocol","settings","streamSettings"]))
      | select(.protocol == "vless")
      | select(.settings | closed(["vnext"]))
      | select(.settings.vnext | type == "array" and length == 1)
      | . as $o | .settings.vnext[0] as $s
      | select($s | closed(["address","port","users"]))
      | select($s.address | text)
      | select($s.port | type == "number" and floor == . and . >= 1 and . <= 65535)
      | select($s.users | type == "array" and length == 1)
      | $s.users[0] as $u
      | select($u | closed(["id","encryption","flow"]))
      | select($u.id | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))
      | select($u.encryption == "none")
      | $o.streamSettings as $t
      | if $t.network == "tcp" and $t.security == "reality" then
          select($t | closed(["network","security","realitySettings","tcpSettings"]))
          | select($t.tcpSettings == null or $t.tcpSettings == {} or $t.tcpSettings == {header:{type:"none"}})
          | select($u.flow == "xtls-rprx-vision")
          | $t.realitySettings as $r
          | select($r | closed(["show","fingerprint","serverName","publicKey","shortId","spiderX"]))
          | select($r.show == null or $r.show == false)
          | select($r.serverName | text) | select($r.fingerprint | fingerprint)
          | select($r.publicKey | type == "string" and test("^[A-Za-z0-9_-]{43}$"))
          | select($r.shortId | type == "string" and test("^([0-9a-fA-F]{2}){0,8}$"))
          | select($r.spiderX == null or ($r.spiderX | type == "string" and startswith("/")))
          | {tcp:true,udp:true,auto:$auto,
             mihomo:{type:"vless",server:$s.address,port:$s.port,uuid:$u.id,network:"tcp",udp:true,tls:true,flow:$u.flow,servername:$r.serverName,"client-fingerprint":$r.fingerprint,"reality-opts":{"public-key":$r.publicKey,"short-id":$r.shortId}},
             singBox:{type:"vless",server:$s.address,server_port:$s.port,uuid:$u.id,flow:$u.flow,packet_encoding:"xudp",domain_resolver:{server:"own-doh-0",strategy:"ipv4_only"},tls:{enabled:true,server_name:$r.serverName,utls:{enabled:true,fingerprint:$r.fingerprint},reality:{enabled:true,public_key:$r.publicKey,short_id:$r.shortId}}}}
        elif $t.network == "xhttp" and $t.security == "tls" then
          select($t | closed(["network","security","tlsSettings","xhttpSettings"]))
          | select(($u.flow // "") == "")
          | $t.tlsSettings as $tls | $t.xhttpSettings as $x
          | select($tls | closed(["serverName","fingerprint","alpn","allowInsecure"]))
          | select($tls.allowInsecure == null or $tls.allowInsecure == false)
          | select($tls.serverName | text) | select($tls.fingerprint | fingerprint)
          | select($tls.alpn | type == "array" and length > 0 and all(.[]; . == "h2" or . == "http/1.1"))
          | select($x | closed(["path","mode","host"]))
          | select($x.mode == "packet-up")
          | select($x.path | type == "string" and startswith("/"))
          | select($x.host | text)
          | {tcp:true,udp:true,auto:$auto,singBox:null,
             mihomo:{type:"vless",server:$s.address,port:$s.port,uuid:$u.id,network:"xhttp",udp:true,tls:true,servername:$tls.serverName,"client-fingerprint":$tls.fingerprint,alpn:$tls.alpn,"skip-cert-verify":false,"xhttp-opts":{path:$x.path,mode:$x.mode,host:$x.host}}}
        else empty end;
    if type != "array" or length > 1024 or (all(.[]; type == "object" and (.outbounds | type == "array")) | not)
    then error("invalid-envelope") else
      if ([.[] | .outbounds[]] | length) > 1024 then error("too-many-outbounds") else
        [.[] as $profile | $profile.outbounds[] | try (node | . + {label: ($profile.remarks | if type == "string" then gsub("[\u0000-\u001f\u007f]"; " ") | .[0:64] | gsub("^\\s+|\\s+$"; "") | if length > 0 then . else null end else null end)}) catch empty] | unique
      end
    end
  '';
  # Subscription nodes are named here, after profile composition, so a
  # source label change applies without a new download. name_nodes mirrors
  # resolveNames in display-names.nix: a colliding base name gains the
  # transport, and a remaining collision gains an ordinal starting at 2.
  composer = ''
    def separator: ${builtins.toJSON displayNames.separator};
    def names($nodes): [$nodes[] | .name];
    def auto_names($nodes): [$nodes[] | select(.auto) | .name];
    def kind: if .mihomo.network == "xhttp" then "XHTTP" else "REALITY" end;
    def base: if .label == null then .source else .label + separator + .source end;
    def name_nodes($reserved):
      ($reserved | map({key: ., value: true}) | from_entries) as $reservedSet
      | (map(base)) as $bases
      | (reduce $bases[] as $b ({}; .[$b] += 1)) as $counts
      | map(base as $b
          | . + {name: (if $counts[$b] > 1 or $reservedSet[$b]
              then $b + separator + kind else $b end)})
      # Ordinals below next[name] are already taken, so resuming there
      # yields the first free ordinal without rescanning.
      | reduce .[] as $n ({nodes: [], seen: $reservedSet, next: {}};
          . as $st
          | (if $st.seen[$n.name] then
               first(range(($st.next[$n.name] // 2); infinite) | select($st.seen[$n.name + " " + tostring] | not))
             else null end) as $ordinal
          | (if $ordinal == null then $n.name else $n.name + " " + ($ordinal | tostring) end) as $name
          | .nodes += [$n + {name: $name}]
          | .seen[$name] = true
          | if $ordinal == null then . else .next[$n.name] = $ordinal + 1 end)
      | .nodes;
    ${builtins.toJSON manualGroup} as $manualGroup
    | ${builtins.toJSON autoGroup} as $autoGroup
    | ${builtins.toJSON displayNames.reservedNames} as $reservedNames
    | ($nodes[0] // []) as $all
    | if $format == "mihomo" then
      [.proxies[]?.name] as $templateNames
      | [($all | name_nodes($own + $templateNames + $reservedNames))[] | select(.mihomo != null)] as $ns
      | .proxies += [$ns[] | .mihomo + {name:.name}]
      | .["proxy-groups"] as $gs
      | ([$gs[] | select(.name == $manualGroup) | .proxies[] | select(. != $autoGroup)] + names($ns)) as $manual
      | ([$gs[] | select(.name == $autoGroup) | .proxies[]] + auto_names($ns)) as $auto
      | (if $auto|length > 0 then [$autoGroup] else [] end) as $autoRef
      | .["proxy-groups"] = [{name:$manualGroup,type:"select",proxies:($autoRef + $manual)}]
          + (if $auto|length > 0 then [{name:$autoGroup,type:"url-test",url:"https://speed.cloudflare.com/__down?bytes=65536",interval:300,proxies:$auto}] else [] end)
          + [{name:"GLOBAL",type:"select",proxies:([$manualGroup] + $autoRef)}]
      | if $manual|length == 0 then null else . end
    else
      [.outbounds[]?.tag] as $templateNames
      | [($all | name_nodes($own + $templateNames + $reservedNames))[] | select(.singBox != null)] as $ns
      | .outbounds as $os
      | ([$os[] | select(.tag == $manualGroup) | .outbounds[] | select(. != $autoGroup and . != "EXTERNAL-REJECT")] + names($ns)) as $manual
      | ([$os[] | select(.tag == $autoGroup) | .outbounds[]] + auto_names($ns)) as $auto
      | .outbounds = [$os[] | select(.tag != $manualGroup and .tag != $autoGroup)]
          + [$ns[] | .singBox + {tag:.name}]
          + [{tag:$manualGroup,type:"selector",outbounds:((if $auto|length > 0 then [$autoGroup] else [] end) + $manual),default:(if $auto|length > 0 then $autoGroup else $manual[0] end)}]
          + (if $auto|length > 0 then [{tag:$autoGroup,type:"urltest",url:"https://speed.cloudflare.com/__down?bytes=65536",interval:"5m",outbounds:$auto}] else [] end)
      | if $manual|length == 0 then null else . end
    end
  '';
  converterPath = builtins.toFile "external-subscription-converter.jq" converter;
  composerPath = builtins.toFile "external-subscription-composer.jq" composer;
  sourceNames = builtins.attrNames sources;
  sourcePrepare = name: source: ''
    source_dir="$external_cache/${name}"
    mkdir -p "$source_dir"
    chmod 0700 "$source_dir"
    if ! cmp -s ${
      lib.escapeShellArg config.sops.secrets.${source.urlSecretName}.path
    } "$source_dir/url"; then
      rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at" "$source_dir/next-at"
      cp ${
        lib.escapeShellArg config.sops.secrets.${source.urlSecretName}.path
      } "$source_dir/url" || rm -f -- "$source_dir/url"
    fi
    # Caches from the previous naming scheme store names built from tags or
    # server addresses; refetch them instead of renaming nodes twice.
    if [ -f "$source_dir/accepted.json" ] && ! jq -e 'all(.[]; has("name") | not)' "$source_dir/accepted.json" >/dev/null 2>&1; then
      rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at" "$source_dir/next-at"
    fi
    if [ -f "$source_dir/accepted-at" ]; then
      accepted_at="$(cat "$source_dir/accepted-at")"
      if [[ ! "$accepted_at" =~ ^(0|[1-9][0-9]{0,10})$ ]] || [ "$accepted_at" -gt "$now" ]; then
        rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at"
        accepted_at=0
      fi
      expires_at=$((accepted_at + ${toString (source.maxStaleSeconds or 86400)} - external_holdback))
      if [ "$now" -ge "$expires_at" ]; then
        rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at"
      elif [ "$expires_at" -lt "$external_next_due" ]; then external_next_due="$expires_at"; fi
    elif [ -f "$source_dir/accepted.json" ]; then
      rm -f -- "$source_dir/accepted.json"
    fi
    next_at=0
    if [ -f "$source_dir/next-at" ]; then next_at="$(cat "$source_dir/next-at")"; fi
    if [[ ! "$next_at" =~ ^(0|[1-9][0-9]{0,10})$ ]]; then next_at=0; fi
    if [ "$next_at" -lt "$external_next_due" ]; then external_next_due="$next_at"; fi
  '';
  sourceRefresh = name: source: ''
    source_dir="$external_cache/${name}"
    now="$(date +%s)"
    next_at=0
    if [ -f "$source_dir/next-at" ]; then next_at="$(cat "$source_dir/next-at")"; fi
    if [[ ! "$next_at" =~ ^(0|[1-9][0-9]{0,10})$ ]]; then next_at=0; fi
    if [ "$now" -ge "$next_at" ]; then
      next_at=$((now + ${toString (source.retryIntervalSeconds or 300)}))
      printf '%s' "$next_at" > "$source_dir/next-at"
      request_dir="$(mktemp -d "$external_cache/.request.XXXXXX")"
      http_code=000
      accepted_now=0
      curl_rc=1
      if jq -eRs 'test("^https://[^\\s\\\"\\\\]+$")' "$source_dir/url" >/dev/null; then
        jq -rRs '"url = " + tojson' "$source_dir/url" > "$request_dir/curl.conf"
        curl_rc=0
        http_code="$(curl --disable --silent --proxy "" --noproxy '*' --proto '=https' --connect-timeout 10 --max-time 45 --max-filesize 8388608 --config "$request_dir/curl.conf" --output "$request_dir/body.json" --write-out '%{http_code}')" || curl_rc="$?"
        if [ "$http_code" = 401 ] || [ "$http_code" = 403 ]; then
          rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at"
        elif [ "$http_code" = 200 ] && [ "$curl_rc" -eq 0 ] && jq --arg source ${lib.escapeShellArg name} --argjson auto ${
          if source.auto or true then "true" else "false"
        } -f ${lib.escapeShellArg converterPath} "$request_dir/body.json" > "$request_dir/accepted.json"; then
          mv -- "$request_dir/accepted.json" "$source_dir/accepted.json"
          accepted_now=1
          printf 'VPN external refresh: source=${name} result=accepted mihomo=%s sing-box=%s skipped=%s reason=compatible-tuples\n' \
            "$(jq 'length' "$source_dir/accepted.json")" \
            "$(jq '[.[] | select(.singBox != null)] | length' "$source_dir/accepted.json")" \
            "$(jq --slurpfile nodes "$source_dir/accepted.json" '[.[] | .outbounds[]] | length - ($nodes[0] | length)' "$request_dir/body.json")" >&3
          date +%s > "$source_dir/accepted-at"
          now="$(date +%s)"
          printf '%s' "$((now + ${
            toString (source.refreshIntervalSeconds or 3600)
          }))" > "$source_dir/next-at"
        fi
      fi
      if [ "$http_code" != 200 ] || [ "$curl_rc" -ne 0 ]; then
        case "$curl_rc/$http_code" in 0/408|0/429|0/5??|6/*|7/*|28/*|52/*|56/*) ;; *) rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at" ;; esac
        printf 'VPN external refresh: source=${name} result=failed reason=http-or-transport-failure\n' >&3
        printf '%s' "$(( $(date +%s) + ${
          toString (source.retryIntervalSeconds or 300)
        } ))" > "$source_dir/next-at"
      elif [ "$accepted_now" -eq 0 ]; then
        rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at"
        printf 'VPN external refresh: source=${name} result=failed reason=invalid-response\n' >&3
        printf '%s' "$(( $(date +%s) + ${
          toString (source.retryIntervalSeconds or 300)
        } ))" > "$source_dir/next-at"
      fi
      rm -rf -- "$request_dir"
    fi
  '';
  sourceRefreshPaths = lib.mapAttrs (
    name: source:
    builtins.toFile "external-refresh-${name}.sh" ''
      set -euo pipefail
      external_cache="$1"
      request_dir=""
      trap 'if [ -n "$request_dir" ]; then rm -rf -- "$request_dir"; fi' EXIT
      ${sourceRefresh name source}
    ''
  ) sources;
  profileNodes =
    profile:
    lib.concatMapStringsSep "\n" (
      name:
      lib.optionalString (builtins.elem profile sources.${name}.profileNames) ''
        if [ -f "$external_cache/${name}/accepted.json" ] && [ -f "$external_cache/${name}/accepted-at" ]; then jq --argjson auto ${
          if sources.${name}.auto or true then "true" else "false"
        } --arg source ${
          lib.escapeShellArg (sourceLabel name sources.${name})
        } 'map(.auto = $auto | .source = $source)' "$external_cache/${name}/accepted.json" >> "$nodes_file"; fi
        if [ -f "$external_cache/${name}/accepted-at" ]; then
          source_expiry=$(( $(cat "$external_cache/${name}/accepted-at") + ${
            toString (sources.${name}.maxStaleSeconds or 86400)
          } ))
          if [ "''${external_generation_expires:-0}" -eq 0 ] || [ "$source_expiry" -lt "$external_generation_expires" ]; then external_generation_expires="$source_expiry"; fi
        fi
      ''
    ) sourceNames;
  runtimeScript = ''
    external_cache=${lib.escapeShellArg "${runtimeBase}/external-cache"}
    mkdir -p "$external_cache"
    chmod 0700 "$external_cache"
    external_holdback=0
    external_last_index=-1
    external_prepare() {
      local now source_dir accepted_at expires_at next_at old_source
      now="$(date +%s)"
      external_next_due=$((now + 86400))
      for old_source in "$external_cache"/*; do
        [ -d "$old_source" ] || continue
        case "''${old_source##*/}" in ${
          if sourceNames == [ ] then "__none__" else lib.concatStringsSep "|" sourceNames
        }) ;; *) rm -rf -- "$old_source" ;; esac
      done
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList sourcePrepare sources)}
    }
    external_refresh() {
      local source_dir now next_at request_dir http_code curl_rc scan_pass
      for scan_pass in first wrap; do
      ${lib.concatStringsSep "\n" (
        lib.imap0 (index: name: ''
            now="$(date +%s)"
            next_at=0
            if [ -f "$external_cache/${name}/next-at" ]; then next_at="$(cat "$external_cache/${name}/next-at")"; fi
          if [[ ! "$next_at" =~ ^(0|[1-9][0-9]{0,10})$ ]]; then next_at=0; fi
            if [ ${toString index} -gt "$external_last_index" ] && [ "$now" -ge "$next_at" ]; then
              external_last_index=${toString index}
              if ! timeout --kill-after=5 60 bash ${
                lib.escapeShellArg sourceRefreshPaths.${name}
              } "$external_cache"; then
                printf 'VPN external refresh failed: source=${name} reason=refresh-timeout-or-local-failure\n' >&3
                printf '%s' "$(( $(date +%s) + ${
                  toString (sources.${name}.retryIntervalSeconds or 300)
                } ))" > "$external_cache/${name}/next-at"
              fi
              external_holdback=0
              external_prepare
              return
            fi
        '') sourceNames
      )}
      external_last_index=-1
      done
      external_holdback=0
      external_prepare
    }
    external_compose() {
      local profile="$1" format="$2" file="$3" own_names="''${4:-[]}" nodes_file composed source_expiry
      external_prepare
      nodes_file="$(mktemp "$external_cache/.nodes.XXXXXX")"
      composed="$(mktemp "$external_cache/.composed.XXXXXX")"
      private_tmp_files+=("$nodes_file" "$composed")
      case "$profile" in
        ${lib.concatMapStringsSep "\n" (
          profile: "${lib.escapeShellArg profile.name}) ${profileNodes profile.name} ;;"
        ) (settings.profiles or [ ])}
      esac
      jq -s 'add // []' "$nodes_file" > "$composed"
      mv -- "$composed" "$nodes_file"
      jq --arg format "$format" --argjson own "$own_names" --slurpfile nodes "$nodes_file" -f ${lib.escapeShellArg composerPath} "$file" > "$composed"
      mv -- "$composed" "$file"
    }
  '';
in
{
  inherit
    sources
    converter
    composer
    converterPath
    composerPath
    runtimeScript
    ;
}
