let
  machineName = "vpn-fixture";
  vpnInstance = name: role: settings: {
    module = {
      input = "vpn";
      name = "@clanwright/${name}";
    };
    roles.${role}.machines.${machineName}.settings = settings;
  };
  networkInstance = name: role: settings: {
    module = {
      input = "network";
      name = "@clanwright/${name}";
    };
    roles.${role}.machines.${machineName}.settings = settings;
  };
  profiles = [
    {
      name = "cHJvYmU";
      vlessUuidSecretName = "fixture-vless-uuid";
    }
  ];
in
rec {
  machine = {
    imports = [
      ({ lib, ... }: { networking.nameservers = lib.mkDefault [ "127.0.0.1" ]; })
    ];
    nixpkgs.hostPlatform = "x86_64-linux";
    boot.isContainer = true;
    networking.nftables.enable = true;
    sops.defaultSopsFile = ./empty-sops.yaml;
    sops.age.keyFile = "/run/vpn-fixture/age-key";
    system.stateVersion = "26.11";
  };

  # Consumer owns each native base once and composes complete native extensions.
  networkIntegrationModule =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      adguardIntegration = lib.attrByPath [ "clanwright" "dns" "adguardhome" "integration" ] null config;
      publisherIntegrations = lib.attrByPath [ "clanwright" "vpn" "publishers" ] { } config;
      publisherIntegration = publisherIntegrations.vpn-client-profiles or null;
      hasAdguard =
        lib.hasAttrByPath [ "clanwright" "dns" "adguardhome" "integration" ] options
        && adguardIntegration != null;
      hasPublisher = publisherIntegration != null;
      aliasRoute = matcher: alias: canonical: ''
        # fixture-alias-route
        route {
          @${matcher} host ${alias}
          redir @${matcher} https://${canonical}{uri} permanent
        }
      '';
    in
    {
      config = lib.mkMerge [
        {
          security.acme.certs.fixture = {
            domain = "example.invalid";
            extraDomainNames = [ "*.example.invalid" ];
            dnsProvider = "timewebcloud";
            group = "acme";
          };
          services.caddy.virtualHosts."site.example.invalid" = {
            owner = "fixture:site";
            listenAddresses = [ "192.0.2.10" ];
            serverAliases = [ "site-alias.example.invalid" ];
            useACMEHost = "fixture";
            extraConfig = lib.mkMerge [
              (aliasRoute "fixture_site_alias" "site-alias.example.invalid" "site.example.invalid")
              (lib.mkOrder 2000 ''
                # fixture-terminal-fallback
                route {
                  @fixture_site host site.example.invalid
                  respond @fixture_site "fixture"
                }
              '')
            ];
          };
        }
        (lib.mkIf hasAdguard {
          security.acme.certs.fixture.reloadServices = adguardIntegration.reloadUnits;
          services.caddy.virtualHosts = {
            "adguard.example.invalid" = lib.mkMerge [
              {
                owner = "fixture:adguard-ui";
                listenAddresses = [ "100.64.0.10" ];
                useACMEHost = "fixture";
                extraConfig = lib.mkOrder 2000 ''
                  route {
                    @adguard_ui_wrong_listener expression `{http.request.local.host} != "100.64.0.10" || {http.request.local.port} != 443`
                    respond @adguard_ui_wrong_listener 404
                    reverse_proxy ${adguardIntegration.uiBackend.host}:${toString adguardIntegration.uiBackend.port}
                  }
                '';
              }
            ];
            "dns.example.invalid" = lib.mkMerge [
              {
                owner = "fixture:adguard-doh";
                listenAddresses = [ "192.0.2.10" ];
                useACMEHost = "fixture";
                extraConfig = lib.mkOrder 2000 ''
                  route {
                    @adguard_doh_wrong_listener expression `{http.request.local.host} != "192.0.2.10" || {http.request.local.port} != 443`
                    respond @adguard_doh_wrong_listener 404
                    handle /dns-query {
                      reverse_proxy https://${adguardIntegration.dohBackend.host}:${toString adguardIntegration.dohBackend.port} {
                        header_up Host ${adguardIntegration.dohBackend.serverName}
                        transport http {
                          tls
                          tls_server_name ${adguardIntegration.dohBackend.serverName}
                        }
                      }
                    }
                    handle { respond 404 }
                  }
                '';
              }
              # Explicit public Host callsite; retain the exported local-listener guard.
              (lib.mkIf (lib.hasAttrByPath [ "clanwright" "vpn" "naiveproxy" "connectRoute" ] options) {
                extraConfig = lib.mkBefore config.clanwright.vpn.naiveproxy.connectRoute;
              })
            ];
          };
          networking.firewall.interfaces.tailscale0 = {
            allowedTCPPorts = [
              53
              443
            ];
            allowedUDPPorts = [ 53 ];
          };
          systemd.services.adguardhome.serviceConfig.SupplementaryGroups = [ "acme" ];
        })
        (lib.mkIf hasPublisher {
          services.caddy.virtualHosts.${publisherIntegration.configGatewayDomain} = lib.mkMerge [
            # A same-canonical fixture extends the existing base without an owner.
            (lib.mkIf (publisherIntegration.configGatewayDomain != "site.example.invalid") {
              owner = "fixture:publisher";
              listenAddresses = [
                "192.0.2.10"
                "100.64.0.10"
              ];
              serverAliases = [ "profiles-alias.example.invalid" ];
              useACMEHost = "fixture";
              extraConfig = lib.mkMerge [
                (aliasRoute "fixture_publisher_alias" "profiles-alias.example.invalid"
                  publisherIntegration.configGatewayDomain
                )
                (lib.mkOrder 2000 ''
                  # fixture-terminal-fallback
                  route { respond 404 }
                '')
              ];
            })
            # Explicit mixed-listener Host callsite; same-canonical catchall already owns one attachment.
            (lib.mkIf
              (
                publisherIntegration.configGatewayDomain != "site.example.invalid"
                && lib.hasAttrByPath [ "clanwright" "vpn" "naiveproxy" "connectRoute" ] options
              )
              {
                extraConfig = lib.mkBefore config.clanwright.vpn.naiveproxy.connectRoute;
              }
            )
            {
              extraConfig = lib.mkMerge [
                (lib.mkBefore publisherIntegration.logConfig)
                (lib.mkAfter ''
                  route {
                    @links_wrong_listener {
                      path /config-links/*
                      expression `{http.request.local.host} != "100.64.0.10" || {http.request.local.port} != 443`
                    }
                    respond @links_wrong_listener 404
                    handle /config-links/* {
                      root * ${publisherIntegration.linksRoot}
                      rewrite * /index.html
                      header Cache-Control "no-store"
                      file_server
                    }
                  }
                  ${publisherIntegration.routeConfig}
                '')
              ];
            }
          ];
          systemd.services.caddy.serviceConfig.SupplementaryGroups = [ publisherIntegration.readerGroup ];
        })
      ];
    };

  instances = {
    network-caddy = networkInstance "network-caddy" "ingress" { };
    network-certificates = networkInstance "network-certificates" "server" {
      email = "operator@example.invalid";
      secretName = "fixture-dns-api-token";
    };

    vpn-mihomo-vless-xhttp = vpnInstance "vpn-mihomo-vless-xhttp" "gateway" {
      enable = true;
      bindIPv4 = "192.0.2.10";
      port = 443;
      domain = "vless.example.invalid";
      clientFingerprint = "firefox";
      doh = {
        domain = "dns.example.invalid";
        ipv4 = "192.0.2.53";
      };
      reality = {
        targetHost = "donor.example.invalid";
        serverNames = [ "donor.example.invalid" ];
        publicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
        privateKeySecretName = "fixture-reality-private-key";
      };
      xhttp = {
        path = "/fixture";
      };
      profiles = map (profile: profile // { realityShortId = "0123456789abcdef"; }) profiles;
    };

    vpn-mieru = vpnInstance "vpn-mieru" "gateway" {
      enable = true;
      ingressIPv4 = "192.0.2.13";
      port = 8443;
      users = [
        {
          name = "cHJvYmU";
          passwordSecretName = "fixture-mieru-password";
        }
      ];
      dnsResolverIPv4s = [ "127.0.0.1" ];
    };

    vpn-anytls = vpnInstance "vpn-anytls" "gateway" {
      enable = true;
      bindIPv4 = "192.0.2.14";
      domain = "anytls.example.invalid";
      port = 9443;
      acmeCertName = "fixture";
      users = [
        {
          name = "cHJvYmU";
          passwordSecretName = "fixture-anytls-password";
        }
      ];
      dnsEndpoint = {
        domain = "dns.example.invalid";
        ipv4 = "93.184.216.34";
        port = 443;
        path = "/dns-query";
      };
    };

    vpn-trusttunnel = vpnInstance "vpn-trusttunnel" "gateway" {
      enable = true;
      bindIPv4 = "192.0.2.15";
      domain = "trusttunnel.example.invalid";
      port = 10443;
      acmeCertName = "fixture";
      users = [
        {
          name = "cHJvYmU";
          passwordSecretName = "fixture-trusttunnel-password";
        }
      ];
      dnsResolverIPv4s = [ "127.0.0.1" ];
    };

    vpn-amneziawg = vpnInstance "vpn-amneziawg" "gateway" {
      enable = true;
      interfaceName = "awg-fixture";
      listenIPv4 = "192.0.2.12";
      endpointDomain = "awg.example.invalid";
      listenPort = 443;
      address = "10.77.0.1/24";
      privateKeySecretName = "fixture-awg-server-private-key";
      headerProtectionKeySecretName = "fixture-awg-header-protection-key";
      serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      peers = [
        {
          name = "cHJvYmU";
          publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
          clientPrivateKeySecretName = "fixture-awg-client-private-key";
          allowedIPs = [ "10.77.0.2/32" ];
          clientPersistentKeepalive = 25;
        }
      ];
      egressIPv4 = "192.0.2.12";
      clientSubnetIPv4 = "10.77.0.0/24";
      enableNat = true;
    };

    vpn-naiveproxy = vpnInstance "vpn-naiveproxy" "addon" {
      enable = true;
      domain = "site.example.invalid";
      publicIPv4 = "192.0.2.10";
      bindIPv4 = "192.0.2.10";
      passwordSecretNames = {
        ibelyasov = "fixture-naive-first-password";
        bsv = "fixture-naive-second-password";
        cHJvYmU = "fixture-naive-published-password";
      };
    };

    vpn-client-profiles = vpnInstance "vpn-client-profiles" "publisher" {
      enable = true;
      localMachineName = "fixture";
      configGatewayDomain = "profiles.example.invalid";
      publicIPv4 = "192.0.2.10";
      edgeDomain = "edge.example.invalid";
      clientDnsEndpoints = [
        {
          domain = "dns-a.example.invalid";
          ipv4 = "192.0.2.53";
        }
        {
          domain = "dns-b.example.invalid";
          ipv4 = "198.51.100.53";
        }
        {
          domain = "dns-c.example.invalid";
          ipv4 = "203.0.113.53";
          port = 8443;
          path = "/fixture-dns-query";
        }
      ];
      tailnetAdminDomains = [ "admin.example.invalid" ];
      personalProxyDomains = [ "personal.example.invalid" ];
      profiles = [
        {
          name = "cHJvYmU";
          pathTokenSecretName = "publisher-profile-path-token-cHJvYmU";
          publishProfileJson = true;
        }
      ];
      profileLinks = [
        {
          name = "cHJvYmU";
          label = "Fixture profile";
          accountDomain = "profiles.example.invalid";
        }
      ];
      providerRefs = [
        {
          instanceId = "vpn-mihomo-vless-xhttp";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
        {
          instanceId = "vpn-mieru";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
        {
          instanceId = "vpn-anytls";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
        {
          instanceId = "vpn-trusttunnel";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
        {
          instanceId = "vpn-amneziawg";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
        {
          instanceId = "vpn-naiveproxy";
          machine = machineName;
          clients.cHJvYmU = "cHJvYmU";
          display = {
            label = "A";
            country = "Литва";
            countryCode = "LT";
          };
        }
      ];
    };

    dns-unbound = vpnInstance "dns-unbound" "recursive-backend" {
      listen.hosts = [ "127.0.0.1" ];
      listen.port = 5335;
    };

    dns-adguardhome = vpnInstance "dns-adguardhome" "resolver" {
      ui = {
        host = "127.0.0.1";
        port = 3000;
      };
      dns = {
        bindHosts = [ "127.0.0.1" ];
        port = 53;
        upstream = [ "127.0.0.1:5335" ];
        fallbackPort = 5336;
        fallbackTimeoutSeconds = 3;
      };
      tls = {
        serverName = "dns.example.invalid";
        httpsPort = 8444;
        certificateFile = "/var/lib/acme/fixture/fullchain.pem";
        privateKeyFile = "/var/lib/acme/fixture/key.pem";
      };
      auth = {
        passwordSecretName = "fixture-adguard-admin-bcrypt-hash";
      };
      filtering.userRules = [
        "@@||consumer-allow.example.invalid^"
        "||consumer-deny.example.invalid^"
      ];
      systemResolver = {
        enableLocalStub = true;
        nameservers = [ "127.0.0.1" ];
      };
    };
  };
}
