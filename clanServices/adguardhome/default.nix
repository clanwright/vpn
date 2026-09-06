{
  adguardPackageFor ? (
    _system: throw "adguardhome requires an explicit adguardPackageFor dependency"
  ),
}:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/dns-adguardhome";
    description = "AdGuard Home DNS resolver with DoH";
    readme = builtins.readFile ./README.md;
  };

  roles.resolver = {
    description = "DNS resolver role";
    interface =
      { lib, ... }:
      {
        options = {
          ui = {
            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
            };
            port = lib.mkOption {
              type = lib.types.int;
              default = 3000;
            };
            domain = lib.mkOption {
              type = lib.types.str;
              default = "localhost";
              description = "Tailnet-only UI hostname served by the composition-owned Caddy claim.";
            };
          };

          ingress = {
            publicIPv4 = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
            };
            caddyBindIPv4 = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            tailnetIPv4 = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
            };
          };

          dns = {
            bindHosts = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "::" ];
            };
            port = lib.mkOption {
              type = lib.types.int;
              default = 53;
            };
            upstream = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "https://1.1.1.1/dns-query"
                "https://1.0.0.1/dns-query"
                "tls://9.9.9.9"
                "tls://149.112.112.112"
              ];
            };
            bootstrap = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "1.1.1.1"
                "1.0.0.1"
                "9.9.9.9"
                "149.112.112.112"
                "2606:4700:4700::1111"
                "2606:4700:4700::1001"
              ];
            };
          };

          tls = {
            serverName = lib.mkOption {
              type = lib.types.str;
            };
            httpsPort = lib.mkOption {
              type = lib.types.int;
              default = 8444;
            };
            dotPort = lib.mkOption {
              type = lib.types.port;
              default = 0;
            };
          };

          acme.certName = lib.mkOption {
            type = lib.types.str;
          };

          lifecycle = lib.mkOption {
            type = lib.types.enum [
              "enabled"
              "disabled-retained"
            ];
            default = "enabled";
            description = "Whether AdGuard runtime owners are active or retained for recovery.";
          };

          adguard.extraSettings = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };

          auth = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether to merge a runtime-provided Web UI admin user into the
                AdGuard Home config after the base declarative YAML is rendered.
              '';
            };
            username = lib.mkOption {
              type = lib.types.str;
              default = "admin";
            };
            passwordSecretName = lib.mkOption {
              type = lib.types.str;
              default = "adguard-admin-password";
            };
          };

          systemResolver.enableLocalStub = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          systemResolver.nameservers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "127.0.0.1"
              "::1"
            ];
            description = "Nameservers used by the host resolver when the local AdGuard stub is enabled.";
          };
        };
      };

    perInstance =
      {
        instanceName ? "dns-adguardhome",
        settings,
        ...
      }:
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            active = settings.lifecycle == "enabled";
            adguardPackage = adguardPackageFor pkgs.system;
            caddyBindIPv4 =
              if settings.ingress.caddyBindIPv4 == null then
                settings.ingress.publicIPv4
              else
                settings.ingress.caddyBindIPv4;
            certBase = "/var/lib/acme/${settings.acme.certName}";
            isTailscaleIPv4BindHost =
              host: builtins.match "100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\..*" host != null;
            needsTailscaleOrdering = builtins.any isTailscaleIPv4BindHost settings.dns.bindHosts;
            tailscaleUnits = [
              "tailscaled.service"
              "tailscaled-autoconnect.service"
            ];
            stableSettings =
              let
                localhostIpv4 = "127.0.0.1";
                localhostIpv6 = "::1";
                localhostIpv4Cidr = "127.0.0.0/8";
                localhostIpv6Cidr = "::1/128";
                pprofPort = 6060;
                dotPort = 0;
                dnsCacheSizeBytes = 33554432;
                filterCacheSizeBytes = 1048576;
                dhcpLeaseDurationSeconds = 86400;
                querylogInterval = "168h";
                statisticsInterval = "2160h";
                sessionTtl = "720h";
              in
              {
                http = {
                  pprof = {
                    port = pprofPort;
                    enabled = false;
                  };
                  session_ttl = sessionTtl;
                };
                auth_attempts = 5;
                block_auth_min = 15;
                http_proxy = "";
                language = "";
                theme = "auto";
                dns = {
                  anonymize_client_ip = false;
                  enable_dnssec = true;
                  ratelimit = 20;
                  ratelimit_subnet_len_ipv4 = 24;
                  ratelimit_subnet_len_ipv6 = 56;
                  refuse_any = true;
                  ratelimit_whitelist = [
                    localhostIpv4
                    localhostIpv6
                  ];
                  upstream_dns_file = "";
                  fallback_dns = [
                    "https://dns.google/dns-query"
                    "https://unfiltered.adguard-dns.com/dns-query"
                  ];
                  upstream_mode = "parallel";
                  fastest_timeout = "1s";
                  allowed_clients = [ ];
                  disallowed_clients = [ ];
                  blocked_hosts = [
                    "version.bind"
                    "id.server"
                    "hostname.bind"
                  ];
                  trusted_proxies = [
                    localhostIpv4Cidr
                    localhostIpv6Cidr
                  ];
                  cache_enabled = true;
                  cache_size = dnsCacheSizeBytes;
                  cache_ttl_min = 300;
                  cache_ttl_max = 0;
                  cache_optimistic = true;
                  cache_optimistic_answer_ttl = "30s";
                  cache_optimistic_max_age = "12h";
                  bogus_nxdomain = [ ];
                  aaaa_disabled = false;
                  edns_client_subnet = {
                    custom_ip = "";
                    enabled = false;
                    use_custom = false;
                  };
                  max_goroutines = 300;
                  handle_ddr = true;
                  ipset = [ ];
                  ipset_file = "";
                  bootstrap_prefer_ipv6 = false;
                  upstream_timeout = "3s";
                  private_networks = [ ];
                  use_private_ptr_resolvers = false;
                  local_ptr_upstreams = [ ];
                  use_dns64 = false;
                  dns64_prefixes = [ ];
                  serve_http3 = false;
                  use_http3_upstreams = false;
                  serve_plain_dns = true;
                  hostsfile_enabled = true;
                  pending_requests.enabled = true;
                };
                tls = {
                  port_dns_over_quic = dotPort;
                  port_dnscrypt = 0;
                  dnscrypt_config_file = "";
                  allow_unencrypted_doh = false;
                  strict_sni_check = false;
                };
                querylog = {
                  enabled = true;
                  dir_path = "";
                  ignored = [ ];
                  interval = querylogInterval;
                  size_memory = 1000;
                  file_enabled = true;
                };
                statistics = {
                  enabled = true;
                  dir_path = "";
                  ignored = [ ];
                  interval = statisticsInterval;
                };
                filters = [
                  {
                    enabled = true;
                    url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_34.txt";
                    name = "HaGeZi Multi NORMAL";
                    id = 34;
                  }
                  {
                    enabled = true;
                    url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt";
                    name = "Malicious URL Blocklist (URLHaus)";
                    id = 1772478066;
                  }
                ];
                whitelist_filters = [ ];
                user_rules = [
                  "||pikabu.ru^"
                  "/(^|\\.)intimcity\\..*$/"
                  "@@||boosty.to^"
                ];
                dhcp = {
                  enabled = false;
                  interface_name = "";
                  local_domain_name = "lan";
                  dhcpv4 = {
                    gateway_ip = "";
                    subnet_mask = "";
                    range_start = "";
                    range_end = "";
                    lease_duration = dhcpLeaseDurationSeconds;
                    icmp_timeout_msec = 1000;
                    options = [ ];
                  };
                  dhcpv6 = {
                    range_start = "";
                    lease_duration = dhcpLeaseDurationSeconds;
                    ra_slaac_only = false;
                    ra_allow_slaac = false;
                  };
                };
                filtering = {
                  blocking_ipv4 = "";
                  blocking_ipv6 = "";
                  blocked_services = {
                    schedule.time_zone = "UTC";
                    ids = [ ];
                  };
                  protection_disabled_until = null;
                  blocking_mode = "default";
                  parental_block_host = "family-block.dns.adguard.com";
                  safebrowsing_block_host = "standard-block.dns.adguard.com";
                  rewrites = [ ];
                  safe_fs_patterns = [ ];
                  safebrowsing_cache_size = filterCacheSizeBytes;
                  safesearch_cache_size = filterCacheSizeBytes;
                  parental_cache_size = filterCacheSizeBytes;
                  cache_time = 30;
                  filters_update_interval = 24;
                  filtering_enabled = true;
                  rewrites_enabled = true;
                  parental_enabled = true;
                  safebrowsing_enabled = true;
                  protection_enabled = true;
                  safe_search = {
                    enabled = true;
                    bing = true;
                    duckduckgo = true;
                    ecosia = true;
                    google = true;
                    pixabay = true;
                    yandex = true;
                    youtube = false;
                  };
                  blocked_response_ttl = 60;
                };
                clients = {
                  runtime_sources = {
                    whois = true;
                    arp = true;
                    rdns = true;
                    dhcp = true;
                    hosts = true;
                  };
                  persistent = [ ];
                };
                log = {
                  enabled = true;
                  file = "";
                  max_backups = 0;
                  max_size = 100;
                  max_age = 3;
                  compress = false;
                  local_time = false;
                  verbose = false;
                };
                os = {
                  group = "";
                  user = "";
                  rlimit_nofile = 0;
                };
              };
            baseSettings = lib.recursiveUpdate stableSettings {
              dns = {
                bind_hosts = settings.dns.bindHosts;
                inherit (settings.dns) port;
                upstream_dns = settings.dns.upstream;
                bootstrap_dns = settings.dns.bootstrap;
              };
              tls = {
                enabled = true;
                server_name = settings.tls.serverName;
                force_https = false;
                port_https = settings.tls.httpsPort;
                port_dns_over_tls = settings.tls.dotPort;
                certificate_path = "${certBase}/fullchain.pem";
                private_key_path = "${certBase}/key.pem";
              };
            };
          in
          {
            assertions = [
              {
                assertion = !active || config.services.adguardhome.package == adguardPackage;
                message = "adguardhome: the runtime package must come from the VPN domain platform pin.";
              }
            ];

            clan.core.state.adguardhome.folders = [ "/var/lib/private/AdGuardHome" ];

            sops.secrets."${settings.auth.passwordSecretName}" = {
              path = "/run/secrets/${settings.auth.passwordSecretName}";
              owner = "acme";
              group = "acme";
              mode = "0440";
              restartUnits = [ ];
            };

          }
          // lib.optionalAttrs active {
            networkCore = {
              acme.reloadServices.${settings.acme.certName} = [
                "caddy.service"
                "adguardhome.service"
              ];
              caddy.fragments = {
                "${instanceName}-ui" = {
                  hostName = settings.ui.domain;
                  listenAddresses = [
                    caddyBindIPv4
                    settings.ingress.tailnetIPv4
                  ];
                  useACMEHost = settings.acme.certName;
                  afterUnits = [
                    "tailscaled.service"
                    "tailscaled-autoconnect.service"
                  ];
                  wantsUnits = [
                    "tailscaled.service"
                    "tailscaled-autoconnect.service"
                  ];
                  logFile = "/var/log/caddy/adguardhome-ui-access.log";
                  extraConfig = ''
                    bind ${caddyBindIPv4} ${settings.ingress.tailnetIPv4}
                    tls /var/lib/acme/${settings.acme.certName}/fullchain.pem /var/lib/acme/${settings.acme.certName}/key.pem
                    @wrong_listener expression `{http.request.local.host} != "${settings.ingress.tailnetIPv4}"`
                    route {
                      respond @wrong_listener 404
                      reverse_proxy ${settings.ui.host}:${toString settings.ui.port}
                    }
                  '';
                };
                "${instanceName}-doh" = {
                  hostName = settings.tls.serverName;
                  listenAddresses = [ caddyBindIPv4 ];
                  useACMEHost = settings.acme.certName;
                  afterUnits = [
                    "tailscaled.service"
                    "tailscaled-autoconnect.service"
                  ];
                  wantsUnits = [
                    "tailscaled.service"
                    "tailscaled-autoconnect.service"
                  ];
                  logFile = "/var/log/caddy/adguardhome-doh-access.log";
                  extraConfig = ''
                    bind ${caddyBindIPv4}
                    tls /var/lib/acme/${settings.acme.certName}/fullchain.pem /var/lib/acme/${settings.acme.certName}/key.pem
                    handle /dns-query {
                      reverse_proxy https://127.0.0.1:${toString settings.tls.httpsPort} {
                        header_up Host ${settings.tls.serverName}
                        transport http {
                          tls
                          tls_server_name ${settings.tls.serverName}
                          tls_insecure_skip_verify
                        }
                      }
                    }
                    handle {
                      respond 404
                    }
                  '';
                };
              };
            };

            services.adguardhome = {
              enable = true;
              package = lib.mkForce adguardPackage;
              openFirewall = false;
              inherit (settings.ui) host port;
              mutableSettings = false;
              settings = lib.recursiveUpdate baseSettings settings.adguard.extraSettings;
            };

            systemd.services.adguardhome = {
              after = lib.mkIf needsTailscaleOrdering tailscaleUnits;
              wants = lib.mkIf needsTailscaleOrdering tailscaleUnits;
              serviceConfig = {
                SupplementaryGroups = [ "acme" ];
                PermissionsStartOnly = settings.auth.enable;
              };
              preStart = lib.mkAfter (
                lib.optionalString settings.auth.enable ''
                  state_owner="$(stat -c '%u:%g' "$(realpath "$STATE_DIRECTORY")")"
                  password="$(tr -d '\n' < ${config.sops.secrets."${settings.auth.passwordSecretName}".path})"
                  if [ -z "$password" ]; then
                    echo "adguardhome: ${settings.auth.passwordSecretName} must not be empty" >&2
                    exit 1
                  fi

                  password_hash="$(${pkgs.apacheHttpd}/bin/htpasswd -bnBC 10 "" "$password" | tr -d ':\n')"

                  auth_fragment="$(mktemp)"
                  cat > "$auth_fragment" <<EOF
                  users:
                    - name: ${settings.auth.username}
                      password: "$password_hash"
                  EOF

                  ${pkgs.yaml-merge}/bin/yaml-merge "$STATE_DIRECTORY/AdGuardHome.yaml" "$auth_fragment" > "$STATE_DIRECTORY/AdGuardHome.yaml.tmp"
                  mv "$STATE_DIRECTORY/AdGuardHome.yaml.tmp" "$STATE_DIRECTORY/AdGuardHome.yaml"
                  chown "$state_owner" "$STATE_DIRECTORY/AdGuardHome.yaml"
                  chmod 600 "$STATE_DIRECTORY/AdGuardHome.yaml"
                  rm -f "$auth_fragment"
                ''
              );
            };

            services.resolved.enable = lib.mkIf settings.systemResolver.enableLocalStub (lib.mkForce false);
            networking = {
              resolvconf.useLocalResolver = lib.mkIf settings.systemResolver.enableLocalStub true;
              nameservers = lib.mkIf settings.systemResolver.enableLocalStub (
                lib.mkForce settings.systemResolver.nameservers
              );
              firewall.interfaces.tailscale0.allowedTCPPorts = [
                settings.dns.port
                443
              ];
              firewall.interfaces.tailscale0.allowedUDPPorts = [ settings.dns.port ];
            };
          };
      };
  };
}
