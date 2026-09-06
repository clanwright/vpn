{
  config,
  lib,
  pkgs,
  ...
}:
let
  profileType = lib.types.submodule (_: {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      vlessUuidSecretName = lib.mkOption { type = lib.types.str; };
      kind = lib.mkOption {
        type = lib.types.enum [
          "mobile"
          "router"
          "probe"
        ];
        default = "mobile";
      };
      publishProfileJson = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
      };
    };
  });

  realityType = lib.types.submodule {
    options = {
      serverName = lib.mkOption { type = lib.types.str; };
      dest = lib.mkOption { type = lib.types.str; };
      shortIds = lib.mkOption { type = lib.types.listOf lib.types.str; };
      publicKey = lib.mkOption { type = lib.types.str; };
      privateKeySecretName = lib.mkOption { type = lib.types.str; };
    };
  };

  xhttpType = lib.types.submodule {
    options = {
      path = lib.mkOption { type = lib.types.str; };
      mode = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "stream-one"
          "stream-up"
          "packet-up"
        ];
        default = "packet-up";
      };
    };
  };

  h2UserType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      passwordSecretName = lib.mkOption { type = lib.types.str; };
    };
  };

  vlessType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      bindIPv4 = lib.mkOption { type = lib.types.str; };
      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
      };
      domain = lib.mkOption { type = lib.types.str; };
      reality = lib.mkOption { type = realityType; };
      xhttp = lib.mkOption { type = xhttpType; };
      profiles = lib.mkOption {
        type = lib.types.listOf profileType;
        default = [ ];
      };
    };
  };

  h2Type = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      listenIPv4 = lib.mkOption { type = lib.types.str; };
      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
      };
      serverName = lib.mkOption {
        type = lib.types.str;
        description = "Existing Hysteria2 endpoint name; listener ALPN remains h3.";
      };
      users = lib.mkOption {
        type = lib.types.listOf h2UserType;
        default = [ ];
      };
      masqueradeUrl = lib.mkOption { type = lib.types.str; };
      ignoreClientBandwidth = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      acmeCertName = lib.mkOption { type = lib.types.str; };
      obfsPasswordSecretName = lib.mkOption { type = lib.types.str; };
      alpn = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "h3" ];
      };
    };
  };

  isIPv4 =
    value:
    let
      octets = lib.splitString "." value;
    in
    builtins.length octets == 4
    && builtins.all (
      octet:
      octet != ""
      && builtins.match "0|[1-9][0-9]*" octet != null
      && lib.toInt octet >= 0
      && lib.toInt octet <= 255
    ) octets;

  isRealityShortId =
    value: value != "" && builtins.match "([0-9A-Fa-f][0-9A-Fa-f]){1,8}" value != null;
  isLoopbackDest =
    value: lib.hasPrefix "127." value || lib.hasPrefix "::1" value || lib.hasPrefix "[::1]" value;
in
{
  options.networkCore.mihomo = {
    vlessXhttp = lib.mkOption {
      type = lib.types.listOf vlessType;
      default = [ ];
      description = "Private VLESS/XHTTP fragments consumed by the shared Mihomo runtime (at most one).";
    };
    hysteria2 = lib.mkOption {
      type = lib.types.listOf h2Type;
      default = [ ];
      description = "Private Hysteria2 fragments consumed by the shared Mihomo runtime (at most one).";
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      apply = lib.unique;
      internal = true;
      description = "Explicit Mihomo packages supplied by active gateway services.";
    };
  };

  config =
    let
      vlessFragments = config.networkCore.mihomo.vlessXhttp;
      h2Fragments = config.networkCore.mihomo.hysteria2;
      vless = if builtins.length vlessFragments == 1 then builtins.head vlessFragments else null;
      h2 = if builtins.length h2Fragments == 1 then builtins.head h2Fragments else null;
      vlessCardinalityValid = builtins.length vlessFragments <= 1;
      h2CardinalityValid = builtins.length h2Fragments <= 1;
      vlessEnabled = vless != null && vless.enable;
      h2Enabled = h2 != null && h2.enable;
      runtimeEnabled = vlessEnabled || h2Enabled;
      mihomoPackages = lib.unique config.networkCore.mihomo.packages;
      mihomoPackage = if mihomoPackages == [ ] then null else builtins.head mihomoPackages;
      generatorService = "mihomo-gateway-config-generator.service";
      mihomoService = "mihomo-gateway.service";
      runtimeRoot = "/run/mihomo-gateway";
      configPath = "${runtimeRoot}/config.yaml";
      certPath = "${runtimeRoot}/hysteria2-fullchain.pem";
      keyPath = "${runtimeRoot}/hysteria2-key.pem";
      vlessListener = {
        name = "vless-in";
        type = "vless";
        inherit (vless) port;
        listen = vless.bindIPv4;
        users = map (profile: {
          username = profile.name;
          uuid = "__MIHOMO_GATEWAY_VLESS_UUID_${profile.name}__";
        }) vless.profiles;
        "reality-config" = {
          dest = vless.reality.dest;
          "private-key" = "__MIHOMO_GATEWAY_REALITY_PRIVATE_KEY__";
          "short-id" = vless.reality.shortIds;
          "server-names" = [ vless.reality.serverName ];
        };
        "xhttp-config" = {
          inherit (vless.xhttp) path mode;
        };
      };
      h2Users = builtins.listToAttrs (
        map (user: {
          inherit (user) name;
          value = "__MIHOMO_GATEWAY_HY2_PASSWORD_${user.name}__";
        }) (if h2 == null then [ ] else h2.users)
      );
      h2Listener = {
        name = "hysteria2-in";
        type = "hysteria2";
        inherit (h2) port;
        listen = h2.listenIPv4;
        users = h2Users;
        masquerade = h2.masqueradeUrl;
        "ignore-client-bandwidth" = h2.ignoreClientBandwidth;
        alpn = [ "h3" ];
        certificate = certPath;
        "private-key" = keyPath;
        obfs = "salamander";
        "obfs-password" = "__MIHOMO_GATEWAY_HY2_OBFS_PASSWORD__";
      };
      listeners = lib.optional vlessEnabled vlessListener ++ lib.optional h2Enabled h2Listener;
      configTemplate = pkgs.writeText "mihomo-gateway.template.json" (
        builtins.toJSON {
          ipv6 = false;
          "log-level" = "info";
          dns = {
            enable = true;
            ipv6 = false;
          };
          inherit listeners;
        }
      );
      toIdent = value: lib.replaceStrings [ "-" ] [ "_" ] value;
      vlessProfiles = if vlessEnabled then vless.profiles else [ ];
      h2UsersList = if h2Enabled then h2.users else [ ];
      jqReplacementFilter = lib.concatStringsSep "\n| " (
        (lib.optional vlessEnabled ''(.listeners[] | select(.name == "vless-in")."reality-config"."private-key") = $reality_private_key'')
        ++ map (
          profile:
          ''(.listeners[] | select(.name == "vless-in").users[] | select(.username == "${profile.name}").uuid) = $vless_uuid_${toIdent profile.name}''
        ) vlessProfiles
        ++ map (
          user:
          ''(.listeners[] | select(.name == "hysteria2-in").users[${builtins.toJSON user.name}]) = $hy2_password_${toIdent user.name}''
        ) h2UsersList
        ++ lib.optional h2Enabled ''(.listeners[] | select(.name == "hysteria2-in")."obfs-password") = $hy2_obfs_password''
      );
      jqSecretFileDecls = lib.concatStringsSep "\n" (
        (lib.optional vlessEnabled ''
          make_secret_file reality_private_key_file
          read_secret ${
            lib.escapeShellArg config.sops.secrets.${vless.reality.privateKeySecretName}.path
          } > "$reality_private_key_file"
        '')
        ++ lib.concatMap (
          profile:
          lib.optional vlessEnabled ''
            make_secret_file vless_uuid_${toIdent profile.name}_file
            read_secret ${
              lib.escapeShellArg config.sops.secrets.${profile.vlessUuidSecretName}.path
            } > "$vless_uuid_${toIdent profile.name}_file"
          ''
        ) (if vless == null then [ ] else vless.profiles)
        ++ lib.optionals h2Enabled [
          ''
            install -o root -g root -m 0400 ${lib.escapeShellArg "/var/lib/acme/${h2.acmeCertName}/fullchain.pem"} ${lib.escapeShellArg certPath}
            install -o root -g root -m 0400 ${lib.escapeShellArg "/var/lib/acme/${h2.acmeCertName}/key.pem"} ${lib.escapeShellArg keyPath}
          ''
        ]
        ++ lib.concatMap (
          user:
          lib.optional h2Enabled ''
            make_secret_file hy2_password_${toIdent user.name}_file
            read_secret ${
              lib.escapeShellArg config.sops.secrets.${user.passwordSecretName}.path
            } > "$hy2_password_${toIdent user.name}_file"
          ''
        ) (if h2 == null then [ ] else h2.users)
        ++ lib.optional h2Enabled ''
          make_secret_file hy2_obfs_password_file
          read_secret ${
            lib.escapeShellArg config.sops.secrets.${h2.obfsPasswordSecretName}.path
          } > "$hy2_obfs_password_file"
        ''
      );
      jqReplacementArgs = lib.concatStringsSep " " (
        (lib.optional vlessEnabled ''--rawfile reality_private_key "$reality_private_key_file"'')
        ++ map (
          profile: ''--rawfile vless_uuid_${toIdent profile.name} "$vless_uuid_${toIdent profile.name}_file"''
        ) vlessProfiles
        ++ map (
          user: ''--rawfile hy2_password_${toIdent user.name} "$hy2_password_${toIdent user.name}_file"''
        ) h2UsersList
        ++ lib.optional h2Enabled ''--rawfile hy2_obfs_password "$hy2_obfs_password_file"''
      );
      secretNames =
        (lib.optional vlessEnabled vless.reality.privateKeySecretName)
        ++ map (profile: profile.vlessUuidSecretName) vlessProfiles
        ++ map (user: user.passwordSecretName) h2UsersList
        ++ lib.optional h2Enabled h2.obfsPasswordSecretName;
      secretDeclarations = lib.listToAttrs (
        map (name: {
          inherit name;
          value = {
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [
              generatorService
              mihomoService
            ];
          };
        }) (lib.unique secretNames)
      );
      listenerChecks =
        (lib.optional vlessEnabled ''
          for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
            if ${pkgs.iproute2}/bin/ss -H -ltn sport = :${toString vless.port} | ${pkgs.gnugrep}/bin/grep -Fq '${vless.bindIPv4}:${toString vless.port}'; then
              vless_ready=1
              break
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          test "''${vless_ready:-0}" = 1
        '')
        ++ (lib.optional h2Enabled ''
          for attempt in $(${pkgs.coreutils}/bin/seq 1 15); do
            if ${pkgs.iproute2}/bin/ss -H -lun sport = :${toString h2.port} | ${pkgs.gnugrep}/bin/grep -Fq '${h2.listenIPv4}:${toString h2.port}'; then
              h2_ready=1
              break
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          test "''${h2_ready:-0}" = 1
        '');
      fragmentAssertions = [
        {
          assertion = vlessCardinalityValid;
          message = "Mihomo shared runtime supports at most one VLESS/XHTTP fragment per machine";
        }
        {
          assertion = h2CardinalityValid;
          message = "Mihomo shared runtime supports at most one Hysteria2 fragment per machine";
        }
        {
          assertion = !vlessEnabled || isIPv4 vless.bindIPv4;
          message = "VLESS/XHTTP requires a valid IPv4 bind address";
        }
        {
          assertion = !vlessEnabled || vless.domain != "";
          message = "VLESS/XHTTP requires a non-empty domain";
        }
        {
          assertion = !vlessEnabled || vless.reality.serverName != "";
          message = "VLESS/XHTTP requires a REALITY server name";
        }
        {
          assertion = !vlessEnabled || vless.reality.dest != "";
          message = "VLESS/XHTTP requires a REALITY destination";
        }
        {
          assertion = !vlessEnabled || builtins.length vless.reality.shortIds >= 8;
          message = "VLESS/XHTTP requires at least eight REALITY short ids";
        }
        {
          assertion = !vlessEnabled || builtins.all isRealityShortId vless.reality.shortIds;
          message = "VLESS/XHTTP REALITY short ids must be even-length hexadecimal strings";
        }
        {
          assertion = !vlessEnabled || vless.xhttp.path != "";
          message = "VLESS/XHTTP requires a non-empty XHTTP path";
        }
        {
          assertion = !vlessEnabled || vless.profiles != [ ];
          message = "VLESS/XHTTP requires at least one profile";
        }
        {
          assertion =
            !vlessEnabled || vless.reality.serverName != vless.domain || isLoopbackDest vless.reality.dest;
          message = "VLESS/XHTTP REALITY server name must differ from domain unless destination is loopback";
        }
        {
          assertion = !h2Enabled || isIPv4 h2.listenIPv4;
          message = "Hysteria2 requires a valid IPv4 bind address";
        }
        {
          assertion = !h2Enabled || h2.users != [ ];
          message = "Hysteria2 requires at least one user";
        }
        {
          assertion = !h2Enabled || h2.serverName != "";
          message = "Hysteria2 requires a server name";
        }
        {
          assertion = !h2Enabled || h2.alpn == [ "h3" ];
          message = "Hysteria2 ALPN is fixed to h3";
        }
        {
          assertion = !h2Enabled || h2.masqueradeUrl != "";
          message = "Hysteria2 requires a masquerade URL";
        }
        {
          assertion = !h2Enabled || h2.acmeCertName != "";
          message = "Hysteria2 requires an ACME certificate name";
        }
        {
          assertion = !h2Enabled || h2.obfsPasswordSecretName != "";
          message = "Hysteria2 requires a Salamander password secret";
        }
        {
          assertion = !runtimeEnabled || builtins.length mihomoPackages == 1;
          message = "Mihomo shared runtime requires exactly one explicit package across active gateway services";
        }
      ];
    in
    {
      assertions = fragmentAssertions;
      sops.secrets = lib.mkIf runtimeEnabled secretDeclarations;
      systemd.tmpfiles.rules = lib.mkIf runtimeEnabled [ "d ${runtimeRoot} 0750 root root -" ];
      systemd.services = lib.mkIf runtimeEnabled {
        mihomo-gateway-config-generator = {
          description = "Generate runtime config for mihomo-gateway";
          before = [ mihomoService ];
          requiredBy = [ mihomoService ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            Group = "root";
            UMask = "0027";
          };
          restartTriggers = [ configTemplate ];
          path = [
            pkgs.coreutils
            pkgs.jq
            pkgs.yq-go
          ];
          script = ''
            set -euo pipefail

            read_secret() {
              tr -d '\r\n' < "$1"
            }

            secret_tmp_files=()
            make_secret_file() {
              local var_name="$1"
              local tmp
              tmp="$(mktemp ${runtimeRoot}/secret.XXXXXX)"
              chmod 0400 "$tmp"
              secret_tmp_files+=("$tmp")
              printf -v "$var_name" '%s' "$tmp"
            }

            tmp_json="$(mktemp ${runtimeRoot}/config.XXXXXX.json)"
            tmp_yaml="$(mktemp ${runtimeRoot}/config.XXXXXX.yaml)"
            cleanup_tmp() {
              rm -f "$tmp_json" "$tmp_yaml" "''${secret_tmp_files[@]}"
            }
            trap cleanup_tmp EXIT

            ${jqSecretFileDecls}

            jq \
              ${jqReplacementArgs} \
              '
                ${jqReplacementFilter}
              ' ${lib.escapeShellArg configTemplate} > "$tmp_json"

            yq -P '.' "$tmp_json" > "$tmp_yaml"
            install -o root -g root -m 0400 "$tmp_yaml" ${lib.escapeShellArg configPath}
            trap - EXIT
            cleanup_tmp
          '';
        };
        mihomo-gateway = {
          description = "Mihomo VPN gateway";
          after = [
            "network-online.target"
            "mihomo-gateway-config-generator.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "mihomo-gateway-config-generator.service" ];
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [ configTemplate ];
          serviceConfig = {
            Type = "simple";
            User = "root";
            Group = "root";
            Environment = "SAFE_PATHS=${runtimeRoot}";
            Restart = "on-failure";
            RestartSec = "2s";
            ExecStart = "${lib.getExe mihomoPackage} -f ${configPath}";
          };
          preStart = ''
            set -euo pipefail
            ${lib.getExe mihomoPackage} -t -f ${lib.escapeShellArg configPath} >/dev/null
            for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
              required_binds=0
              ready_binds=0
              ${lib.optionalString vlessEnabled ''
                required_binds=$((required_binds + 1))
                if ${pkgs.iproute2}/bin/ip -4 -o addr show | ${pkgs.gnugrep}/bin/grep -Fq ' ${vless.bindIPv4}/'; then
                  ready_binds=$((ready_binds + 1))
                fi
              ''}
              ${lib.optionalString h2Enabled ''
                required_binds=$((required_binds + 1))
                if ${pkgs.iproute2}/bin/ip -4 -o addr show | ${pkgs.gnugrep}/bin/grep -Fq ' ${h2.listenIPv4}/'; then
                  ready_binds=$((ready_binds + 1))
                fi
              ''}
              if [ "$ready_binds" -eq "$required_binds" ]; then
                exit 0
              fi
              ${pkgs.coreutils}/bin/sleep 1
            done
            echo "mihomo-gateway: required bind IPv4 is not assigned after waiting" >&2
            exit 1
          '';
          postStart = ''
            set -euo pipefail
            ${lib.concatStringsSep "\n" listenerChecks}
          '';
        };
      };
      networking.firewall = {
        allowedTCPPorts = lib.optional vlessEnabled vless.port;
      }
      // lib.optionalAttrs h2Enabled {
        extraInputRules = lib.mkAfter ''
          ip daddr ${h2.listenIPv4} udp dport ${toString h2.port} accept comment "mihomo hysteria2 destination-scoped ingress"
        '';
      };
      networkCore.acme.reloadServices = lib.optionalAttrs h2Enabled {
        ${h2.acmeCertName} = [
          generatorService
          mihomoService
        ];
      };
    };
}
