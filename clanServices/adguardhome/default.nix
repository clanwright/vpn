{
  adguardPackageFor ? (
    _system: throw "adguardhome requires an explicit adguardPackageFor dependency"
  ),
  dnsproxyPackageFor ? (
    _system: throw "adguardhome requires an explicit dnsproxyPackageFor dependency"
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
              type = lib.types.port;
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
              default = [ "127.0.0.1" ];
              description = "Loopback and explicitly selected private addresses for plain DNS.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 53;
            };
            upstream = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "127.0.0.1:5335" ];
              description = "The sole primary upstream: a consumer-owned loopback Unbound listener.";
            };
            fallbackPort = lib.mkOption {
              type = lib.types.port;
              default = 5336;
              description = "Loopback port for the module-owned encrypted-to-plaintext dnsproxy cascade.";
            };
            fallbackTimeoutSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 3;
              description = "Per-stage dnsproxy exchange timeout within AdGuard Home's 10-second budget.";
            };
          };

          tls = {
            serverName = lib.mkOption {
              type = lib.types.str;
            };
            httpsPort = lib.mkOption {
              type = lib.types.port;
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

          filtering.userRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Consumer-owned declarative AdGuard allow and deny rules.";
          };

          auth = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether the active Web UI uses the consumer-supplied bcrypt
                credential. Active instances require this to remain enabled.
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
            default = [ "127.0.0.1" ];
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
            adguardSchemaVersion = 34;
            dnsproxyPackage = dnsproxyPackageFor pkgs.system;
            templateName = "${instanceName}-adguardhome.yaml";
            configCredentialPath = config.sops.templates.${templateName}.path;
            secretSettings = {
              path = "/run/secrets/${settings.auth.passwordSecretName}";
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ ];
            };
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
            sopsUnits = lib.optionals config.sops.useSystemdActivation [ "sops-install-secrets.service" ];
            ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
            isIPv4 =
              host: builtins.match "${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null;
            isPrivateBindHost =
              host:
              host == "::1"
              || builtins.match "127\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null
              || builtins.match "10\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null
              || builtins.match "192\\.168\\.${ipv4Octet}\\.${ipv4Octet}" host != null
              || builtins.match "172\\.(1[6-9]|2[0-9]|3[01])\\.${ipv4Octet}\\.${ipv4Octet}" host != null
              ||
                builtins.match "100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.${ipv4Octet}\\.${ipv4Octet}" host
                != null;
            validName = value: builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" value != null;
            unboundPrefix = "127.0.0.1:";
            unboundPortText =
              if
                builtins.length settings.dns.upstream == 1
                && lib.hasPrefix unboundPrefix (builtins.head settings.dns.upstream)
              then
                lib.removePrefix unboundPrefix (builtins.head settings.dns.upstream)
              else
                "";
            unboundPortAttempt =
              if
                builtins.stringLength unboundPortText <= 5 && builtins.match "[1-9][0-9]*" unboundPortText != null
              then
                builtins.tryEval (builtins.fromJSON unboundPortText)
              else
                {
                  success = false;
                  value = 0;
                };
            unboundPort = if unboundPortAttempt.success then unboundPortAttempt.value else 0;
            encryptedFallbackUpstreams = [
              # DNS stamps pin a numeric connect address while retaining the
              # provider hostname as the certificate identity.
              "sdns://AgEAAAAAAAAABzEuMS4xLjEAEmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5"
              "sdns://AgEAAAAAAAAACDkuOS45LjEwABRkbnMxMC5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk"
              "sdns://AgEAAAAAAAAABzguOC44LjgACmRucy5nb29nbGUKL2Rucy1xdWVyeQ"
            ];
            plaintextFallbackUpstreams = [
              "1.1.1.1:53"
              "9.9.9.10:53"
              "8.8.8.8:53"
            ];
            dnsproxySettings = {
              bootstrap = [ ];
              cache = false;
              cache-optimistic = false;
              dnssec = true;
              hosts-file-enabled = false;
              http3 = false;
              insecure = false;
              listen-addrs = [ "127.0.0.1" ];
              listen-ports = [ settings.dns.fallbackPort ];
              max-go-routines = 300;
              pending-requests-enabled = true;
              ratelimit = 0;
              refuse-any = true;
              upstream = encryptedFallbackUpstreams;
              fallback = plaintextFallbackUpstreams;
              upstream-mode = "parallel";
              timeout = "${toString settings.dns.fallbackTimeoutSeconds}s";
            };
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
                sessionTtl = "24h";
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
                  ratelimit = 0;
                  ratelimit_subnet_len_ipv4 = 24;
                  ratelimit_subnet_len_ipv6 = 56;
                  refuse_any = true;
                  ratelimit_whitelist = [
                    localhostIpv4
                    localhostIpv6
                  ];
                  upstream_dns_file = "";
                  fallback_dns = [ "127.0.0.1:${toString settings.dns.fallbackPort}" ];
                  upstream_mode = "load_balance";
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
                  cache_ttl_min = 0;
                  cache_ttl_max = 0;
                  cache_optimistic = false;
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
                  handle_ddr = false;
                  ipset = [ ];
                  ipset_file = "";
                  bootstrap_prefer_ipv6 = false;
                  upstream_timeout = "10s";
                  private_networks = [ ];
                  use_private_ptr_resolvers = false;
                  local_ptr_upstreams = [ ];
                  use_dns64 = false;
                  dns64_prefixes = [ ];
                  serve_http3 = false;
                  use_http3_upstreams = false;
                  serve_plain_dns = true;
                  hostsfile_enabled = false;
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
                user_rules = settings.filtering.userRules;
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
                  safebrowsing_enabled = false;
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
                  blocked_response_ttl = 10;
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
              schema_version = adguardSchemaVersion;
              http.address =
                if builtins.match ".*:.*" settings.ui.host != null then
                  "[${settings.ui.host}]:${toString settings.ui.port}"
                else
                  "${settings.ui.host}:${toString settings.ui.port}";
              dns = {
                bind_hosts = settings.dns.bindHosts;
                inherit (settings.dns) port;
                upstream_dns = settings.dns.upstream;
                bootstrap_dns = [ ];
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
            effectiveSettings = lib.recursiveUpdate baseSettings {
              users = [
                {
                  name = settings.auth.username;
                  password = config.sops.placeholder.${settings.auth.passwordSecretName};
                }
              ];
            };
          in
          {
            assertions = [
              {
                assertion = !active || config.services.adguardhome.package == adguardPackage;
                message = "adguardhome: the runtime package must come from the VPN domain platform pin.";
              }
              {
                assertion =
                  !active
                  ||
                    config.services.adguardhome.enable
                    && config.services.adguardhome.settings == null
                    && !config.services.adguardhome.mutableSettings
                    && !config.services.adguardhome.openFirewall;
                message = "adguardhome: the native service must retain credential-owned settings and closed firewall defaults.";
              }
              {
                assertion = !active || config.services.dnsproxy.package == dnsproxyPackage;
                message = "adguardhome: the fallback dnsproxy package must come from the VPN domain platform pin.";
              }
              {
                assertion =
                  !active
                  ||
                    config.services.dnsproxy.enable
                    && config.services.dnsproxy.settings == dnsproxySettings
                    && config.services.dnsproxy.flags == [ ];
                message = "adguardhome: dnsproxy settings and flags must preserve the loopback encrypted-to-plaintext cascade.";
              }
              {
                assertion =
                  !active
                  ||
                    builtins.length settings.dns.upstream == 1
                    && unboundPortAttempt.success
                    && builtins.isInt unboundPort
                    && unboundPort > 0
                    && unboundPort <= 65535;
                message = "adguardhome: dns.upstream must contain one 127.0.0.1:<port> Unbound endpoint.";
              }
              {
                assertion =
                  !active
                  ||
                    settings.dns.bindHosts != [ ]
                    && builtins.elem "127.0.0.1" settings.dns.bindHosts
                    && builtins.all isPrivateBindHost settings.dns.bindHosts
                    && builtins.length settings.dns.bindHosts == builtins.length (lib.unique settings.dns.bindHosts);
                message = "adguardhome: dns.bindHosts must be unique private addresses and include 127.0.0.1.";
              }
              {
                assertion =
                  !active
                  ||
                    settings.ui.host == "127.0.0.1"
                    && isIPv4 settings.ingress.publicIPv4
                    && isIPv4 caddyBindIPv4
                    && caddyBindIPv4 != "0.0.0.0"
                    && isIPv4 settings.ingress.tailnetIPv4
                    && isPrivateBindHost settings.ingress.tailnetIPv4;
                message = "adguardhome: UI must use loopback and Caddy listeners must be explicit, non-wildcard addresses.";
              }
              {
                assertion =
                  validName settings.auth.passwordSecretName
                  && (
                    !active
                    ||
                      settings.auth.enable
                      && validName settings.auth.username
                      && validName settings.acme.certName
                      && validName settings.tls.serverName
                      && validName settings.ui.domain
                  );
                message = "adguardhome: the retained secret name must be safe; active instances also require auth and safe username, certificate and TLS names.";
              }
              {
                assertion =
                  !active
                  ||
                    settings.dns.port > 0
                    && settings.ui.port > 0
                    && settings.tls.httpsPort > 0
                    && settings.tls.dotPort == 0
                    && settings.dns.fallbackPort > 0
                    && (2 * settings.dns.fallbackTimeoutSeconds + 1) < 10
                    &&
                      builtins.length (
                        lib.unique [
                          settings.dns.port
                          unboundPort
                          settings.dns.fallbackPort
                          settings.ui.port
                          settings.tls.httpsPort
                        ]
                      ) == 5;
                message = "adguardhome: listener ports must be nonzero and distinct; DoT must remain disabled and two dnsproxy stages plus margin must fit the 10s outer budget.";
              }
              {
                assertion =
                  !active
                  || !settings.systemResolver.enableLocalStub
                  ||
                    settings.dns.port == 53
                    && settings.systemResolver.nameservers != [ ]
                    && builtins.all (
                      host: builtins.elem host settings.dns.bindHosts
                    ) settings.systemResolver.nameservers;
                message = "adguardhome: the enabled system resolver must target configured AdGuard listeners on port 53.";
              }
              {
                assertion =
                  !active
                  ||
                    config.networkCore.caddy.fragments."${instanceName}-ui".listenAddresses
                    == [ settings.ingress.tailnetIPv4 ]
                    && config.networkCore.caddy.fragments."${instanceName}-doh".listenAddresses == [ caddyBindIPv4 ];
                message = "adguardhome: Caddy UI and DoH fragments must retain their address-specific listeners.";
              }
              {
                assertion =
                  !active
                  ||
                    effectiveSettings.http.address == "${settings.ui.host}:${toString settings.ui.port}"
                    && !effectiveSettings.http.pprof.enabled
                    && effectiveSettings.dns.bind_hosts == settings.dns.bindHosts
                    && effectiveSettings.dns.port == settings.dns.port
                    && effectiveSettings.dns.upstream_dns == settings.dns.upstream
                    && effectiveSettings.dns.upstream_dns_file == ""
                    && effectiveSettings.dns.fallback_dns == [ "127.0.0.1:${toString settings.dns.fallbackPort}" ]
                    && effectiveSettings.dns.bootstrap_dns == [ ]
                    && effectiveSettings.dns.upstream_mode == "load_balance"
                    && effectiveSettings.dns.upstream_timeout == "10s"
                    && effectiveSettings.dns.enable_dnssec
                    && effectiveSettings.dns.refuse_any
                    && effectiveSettings.dns.pending_requests.enabled
                    && effectiveSettings.dns.cache_enabled
                    && effectiveSettings.dns.cache_ttl_min == 0
                    && effectiveSettings.dns.cache_ttl_max == 0
                    && !effectiveSettings.dns.cache_optimistic
                    && !effectiveSettings.dns.handle_ddr
                    && !effectiveSettings.dns.hostsfile_enabled
                    && effectiveSettings.dns.ratelimit == 0
                    && effectiveSettings.dns.serve_plain_dns
                    && effectiveSettings.dns.allowed_clients == [ ]
                    && effectiveSettings.dns.disallowed_clients == [ ]
                    && effectiveSettings.dns.trusted_proxies == stableSettings.dns.trusted_proxies
                    && effectiveSettings.dns.edns_client_subnet == stableSettings.dns.edns_client_subnet
                    && !effectiveSettings.dns.aaaa_disabled
                    && effectiveSettings.dns.private_networks == [ ]
                    && !effectiveSettings.dns.use_private_ptr_resolvers
                    && effectiveSettings.dns.local_ptr_upstreams == [ ]
                    && !effectiveSettings.dns.use_dns64
                    && !effectiveSettings.dhcp.enabled
                    && !effectiveSettings.dns.serve_http3
                    && !effectiveSettings.dns.use_http3_upstreams
                    && effectiveSettings.tls.enabled
                    && effectiveSettings.tls.server_name == settings.tls.serverName
                    && effectiveSettings.tls.port_https == settings.tls.httpsPort
                    && effectiveSettings.tls.port_dns_over_tls == 0
                    && effectiveSettings.tls.port_dns_over_quic == 0
                    && effectiveSettings.tls.port_dnscrypt == 0
                    && !effectiveSettings.tls.allow_unencrypted_doh
                    && !effectiveSettings.tls.force_https
                    && !effectiveSettings.tls.strict_sni_check
                    && effectiveSettings.tls.certificate_path == "${certBase}/fullchain.pem"
                    && effectiveSettings.tls.private_key_path == "${certBase}/key.pem"
                    && effectiveSettings.http.session_ttl == "24h"
                    && effectiveSettings.auth_attempts == 5
                    && effectiveSettings.block_auth_min == 15
                    && effectiveSettings.filters == stableSettings.filters
                    && effectiveSettings.whitelist_filters == [ ]
                    && effectiveSettings.user_rules == settings.filtering.userRules
                    && effectiveSettings.filtering.filtering_enabled
                    && effectiveSettings.filtering.protection_enabled
                    && effectiveSettings.filtering.parental_enabled
                    && effectiveSettings.filtering.rewrites_enabled
                    && effectiveSettings.filtering.safe_search == stableSettings.filtering.safe_search
                    && !effectiveSettings.filtering.safebrowsing_enabled
                    && effectiveSettings.filtering.blocked_response_ttl == 10
                    && effectiveSettings.clients.persistent == [ ]
                    && effectiveSettings.querylog.enabled
                    && effectiveSettings.querylog.file_enabled
                    && effectiveSettings.querylog.interval == "168h"
                    && effectiveSettings.statistics.enabled
                    && effectiveSettings.statistics.interval == "2160h"
                    && !effectiveSettings.dns.anonymize_client_ip
                    &&
                      effectiveSettings.users == [
                        {
                          name = settings.auth.username;
                          password = config.sops.placeholder.${settings.auth.passwordSecretName};
                        }
                      ];
                message = "adguardhome: the generated configuration must preserve cascade, listener, TLS, cache, filtering and retention policy.";
              }
            ];

            clan.core.state.adguardhome.folders = [ "/var/lib/private/AdGuardHome" ];

            sops.secrets."${settings.auth.passwordSecretName}" = secretSettings;

          }
          // lib.optionalAttrs active {
            sops = {
              secrets."${settings.auth.passwordSecretName}" = secretSettings;
              templates.${templateName} = {
                content = builtins.toJSON effectiveSettings;
                owner = "root";
                group = "root";
                mode = "0400";
                restartUnits = [ "adguardhome.service" ];
              };
            };

            networkCore = {
              acme.reloadServices.${settings.acme.certName} = [
                "caddy.service"
                "adguardhome.service"
              ];
              caddy.fragments = {
                "${instanceName}-ui" = {
                  hostName = settings.ui.domain;
                  listenAddresses = [ settings.ingress.tailnetIPv4 ];
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
                    bind ${settings.ingress.tailnetIPv4}
                    tls /var/lib/acme/${settings.acme.certName}/fullchain.pem /var/lib/acme/${settings.acme.certName}/key.pem
                    @wrong_listener expression `{http.request.local.host} != "${settings.ingress.tailnetIPv4}" || {http.request.local.port} != "443"`
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
                    @wrong_listener expression `{http.request.local.host} != "${caddyBindIPv4}" || {http.request.local.port} != "443"`
                    respond @wrong_listener 404
                    handle /dns-query {
                      reverse_proxy https://127.0.0.1:${toString settings.tls.httpsPort} {
                        header_up Host ${settings.tls.serverName}
                        transport http {
                          tls
                          tls_server_name ${settings.tls.serverName}
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

            services = {
              adguardhome = {
                enable = true;
                package = lib.mkForce adguardPackage;
                openFirewall = false;
                inherit (settings.ui) host port;
                mutableSettings = false;
                settings = null;
              };
              dnsproxy = {
                enable = true;
                package = lib.mkForce dnsproxyPackage;
                settings = dnsproxySettings;
                flags = [ ];
              };
              resolved.enable = lib.mkIf settings.systemResolver.enableLocalStub (lib.mkForce false);
            };

            systemd.services.adguardhome = {
              after = [
                "dnsproxy.service"
              ]
              ++ sopsUnits
              ++ lib.optionals needsTailscaleOrdering tailscaleUnits;
              wants = [
                "dnsproxy.service"
              ]
              ++ sopsUnits
              ++ lib.optionals needsTailscaleOrdering tailscaleUnits;
              serviceConfig = {
                SupplementaryGroups = [ "acme" ];
                LoadCredential = "config:${configCredentialPath}";
                ExecStartPre = [
                  "${pkgs.coreutils}/bin/install -m 600 %d/config /var/lib/AdGuardHome/AdGuardHome.yaml"
                  "${adguardPackage}/bin/AdGuardHome -c /var/lib/AdGuardHome/AdGuardHome.yaml --check-config"
                ];
              };
            };

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
