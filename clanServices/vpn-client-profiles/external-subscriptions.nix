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
        [.[] as $profile | $profile.outbounds[] | try (node | . + {label: (($profile.remarks // $profile.tag // .mihomo.server) | tostring | gsub("[\u0000-\u001f\u007f]"; " ") | .[0:64])}) catch empty] | unique
      end
    end
  '';
  composer = ''
    def names($nodes): [$nodes[] | .name];
    def auto_names($nodes): [$nodes[] | select(.auto) | .name];
    def mihomo_group($name;$manual;$auto):
      [{name:$name,type:"select",proxies:((if $auto|length > 0 then [$name+"-AUTO"] else [] end)+$manual)}]
      + (if $auto|length > 0 then [{name:($name+"-AUTO"),type:"url-test",url:"https://speed.cloudflare.com/__down?bytes=65536",interval:300,proxies:$auto}] else [] end);
    def box_group($name;$manual;$auto):
      [{tag:$name,type:"selector",outbounds:((if $auto|length > 0 then [$name+"-AUTO"] else [] end)+$manual),default:(if $auto|length > 0 then $name+"-AUTO" else $manual[0] end)}]
      + (if $auto|length > 0 then [{tag:($name+"-AUTO"),type:"urltest",url:"https://speed.cloudflare.com/__down?bytes=65536",interval:"5m",outbounds:$auto}] else [] end);
    ($nodes[0] // []) as $all |
    if $format == "mihomo" then
      [$all[] | select(.mihomo != null)] as $ns
      | .proxies += [$ns[] | .mihomo + {name:.name}]
      | .["proxy-groups"] as $gs
      | ([ $gs[] | select(.name == "SELECTIVE" or .name == "FULL") ][0].name) as $mode
      | ([$gs[] | select(.name == $mode) | .proxies[] | select(. != ($mode+"-AUTO"))] + names($ns)) as $tcp
      | ([$gs[] | select(.name == ($mode+"-AUTO")) | .proxies[]] + auto_names($ns)) as $atcp
      | ([$gs[] | select(.name == "UDP") | .proxies[] | select(. != "UDP-AUTO")] + names([$ns[]|select(.udp)])) as $udp
      | ([$gs[] | select(.name == "UDP-AUTO") | .proxies[]] + auto_names([$ns[]|select(.udp)])) as $audp
      | .["proxy-groups"] = mihomo_group($mode;(if $tcp|length > 0 then $tcp else ["REJECT"] end);$atcp)
          + (if $udp|length > 0 then mihomo_group("UDP";$udp;$audp) else [] end)
      | .rules |= map(if test("NETWORK,UDP") then sub(",(REJECT|UDP)$"; if $udp|length > 0 then ",UDP" else ",REJECT" end) else . end)
      | if $tcp|length == 0 then null else . end
    else
      [$all[] | select(.singBox != null)] as $ns
      | .outbounds as $os
      | ([$os[]|select(.tag=="SELECTIVE")|.outbounds[]|select(.!="SELECTIVE-AUTO" and .!="EXTERNAL-REJECT")] + names($ns)) as $tcp
      | ([$os[]|select(.tag=="SELECTIVE-AUTO")|.outbounds[]] + auto_names($ns)) as $atcp
      | ([$os[]|select(.tag=="UDP")|.outbounds[]|select(.!="UDP-AUTO")] + names([$ns[]|select(.udp)])) as $udp
      | ([$os[]|select(.tag=="UDP-AUTO")|.outbounds[]] + auto_names([$ns[]|select(.udp)])) as $audp
      | .outbounds = [$os[]|select(.tag!="SELECTIVE" and .tag!="FULL" and .tag!="UDP" and .tag!="EXTERNAL-REJECT" and .tag!="SELECTIVE-AUTO" and .tag!="FULL-AUTO" and .tag!="UDP-AUTO")]
          + [$ns[]|.singBox + {tag:.name}]
          + box_group("SELECTIVE";(if $tcp|length > 0 then $tcp else ["EXTERNAL-REJECT"] end);$atcp)
          + box_group("FULL";(if $tcp|length > 0 then $tcp else ["EXTERNAL-REJECT"] end);$atcp)
          + (if $udp|length > 0 then box_group("UDP";$udp;$audp) else [] end)

      | .route.rules |= map(if (.network? == "udp" and (.outbound? == "UDP" or .action? == "reject")) then
          if $udp|length > 0 then del(.action) + {outbound:"UDP"} else del(.outbound) + {action:"reject"} end else . end)
      | if $tcp|length == 0 then null else . end
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
      curl_rc=1
      if jq -eRs 'test("^https://[^\\s\\\"\\\\]+$")' "$source_dir/url" >/dev/null; then
        jq -rRs '"url = " + tojson' "$source_dir/url" > "$request_dir/curl.conf"
        curl_rc=0
        http_code="$(curl --disable --silent --proxy "" --noproxy '*' --proto '=https' --connect-timeout 10 --max-time 45 --max-filesize 8388608 --config "$request_dir/curl.conf" --output "$request_dir/body.json" --write-out '%{http_code}')" || curl_rc="$?"
        if [ "$http_code" = 401 ] || [ "$http_code" = 403 ]; then
          rm -f -- "$source_dir/accepted.json" "$source_dir/accepted-at"
        elif [ "$http_code" = 200 ] && [ "$curl_rc" -eq 0 ] && jq --arg source ${lib.escapeShellArg name} --argjson auto ${
          if source.auto or true then "true" else "false"
        } -f ${lib.escapeShellArg converterPath} "$request_dir/body.json" > "$request_dir/nodes.json"; then
          : > "$request_dir/named.jsonl"
          while IFS= read -r node; do
            digest="$(printf '%s' "$node" | jq -Sc 'del(.auto,.label)' | sha256sum)"
            digest="''${digest%% *}"
            printf '%s' "$node" | jq --arg name "external-${name}-$(printf '%s' "$node" | jq -r '.label')-''${digest:0:16}" '. + {name:$name}' >> "$request_dir/named.jsonl"
          done < <(jq -Sc '.[]' "$request_dir/nodes.json")
          jq -s '.' "$request_dir/named.jsonl" > "$request_dir/accepted.json"
          mv -- "$request_dir/accepted.json" "$source_dir/accepted.json"
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
      elif [ ! -f "$request_dir/accepted.json" ] && [ ! -f "$request_dir/named.jsonl" ]; then
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
        } 'map(.auto = $auto)' "$external_cache/${name}/accepted.json" >> "$nodes_file"; fi
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
      local source_dir now next_at request_dir http_code node digest curl_rc scan_pass
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
      local profile="$1" format="$2" file="$3" nodes_file composed source_expiry
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
      jq --arg format "$format" --slurpfile nodes "$nodes_file" -f ${lib.escapeShellArg composerPath} "$file" > "$composed"
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
