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
      kind = "probe";
      publishProfileJson = false;
      vlessUuidSecretName = "fixture-vless-uuid";
    }
  ];
in
rec {
  machine = {
    imports = [
      (
        { lib, options, ... }:
        {
          config =
            lib.optionalAttrs
              (lib.hasAttrByPath [
                "clanwright"
                "vpn"
                "hysteria2"
                "masqueradeRoot"
              ] options)
              {
                clanwright.vpn.hysteria2.masqueradeRoot = "/nix/store/00000000000000000000000000000000-hysteria-static-cover/share/hysteria";
              };
        }
      )
    ];
    nixpkgs.hostPlatform = "x86_64-linux";
    boot.isContainer = true;
    networking.nftables.enable = true;
    sops.defaultSopsFile = ./empty-sops.yaml;
    sops.age.keyFile = "/run/vpn-fixture/age-key";
    system.stateVersion = "26.11";
  };

  networkIntegrationModule =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      adguardOptionPresent = lib.hasAttrByPath [ "clanwright" "dns" "adguardhome" "integration" ] options;
      adguardIntegration = lib.attrByPath [ "clanwright" "dns" "adguardhome" "integration" ] null config;
      publisherOptionPresent = lib.hasAttrByPath [ "clanwright" "vpn" "publishers" ] options;
      publisherIntegrations = lib.attrByPath [ "clanwright" "vpn" "publishers" ] { } config;
      publisherIntegration = publisherIntegrations.vpn-client-profiles or null;
    in
    {
      config = lib.mkMerge [
        {
          networkCore.caddy.fragments.fixture-site = {
            hostName = "site.example.invalid";
            listenAddresses = [ "192.0.2.10" ];
            useACMEHost = "fixture";
            logFile = "/var/log/caddy/fixture-access.log";
            publicSite = true;
            siteOwners = [ "fixture" ];
            capabilities = [ ];
            extraConfig = ''respond "fixture"'';
          };
        }
        (lib.mkIf (adguardOptionPresent && adguardIntegration != null) {
          networkCore = {
            acme.reloadServices.fixture = [
              "caddy.service"
            ]
            ++ adguardIntegration.reloadUnits;
            caddy.fragments = {
              dns-adguardhome-ui = {
                hostName = "adguard.example.invalid";
                listenAddresses = [ "100.64.0.10" ];
                useACMEHost = "fixture";
                logFile = "/var/log/caddy/adguardhome-ui-access.log";
                extraConfig = ''
                  bind 100.64.0.10
                  tls /var/lib/acme/fixture/fullchain.pem /var/lib/acme/fixture/key.pem
                  @wrong_listener expression `{http.request.local.host} != "100.64.0.10" || {http.request.local.port} != "443"`
                  route {
                    respond @wrong_listener 404
                    reverse_proxy ${adguardIntegration.uiBackend.host}:${toString adguardIntegration.uiBackend.port}
                  }
                '';
              };
              dns-adguardhome-doh = {
                hostName = "dns.example.invalid";
                listenAddresses = [ "192.0.2.10" ];
                useACMEHost = "fixture";
                logFile = "/var/log/caddy/adguardhome-doh-access.log";
                extraConfig = ''
                  bind 192.0.2.10
                  tls /var/lib/acme/fixture/fullchain.pem /var/lib/acme/fixture/key.pem
                  @wrong_listener expression `{http.request.local.host} != "192.0.2.10" || {http.request.local.port} != "443"`
                  respond @wrong_listener 404
                  handle /dns-query {
                    reverse_proxy https://${adguardIntegration.dohBackend.host}:${toString adguardIntegration.dohBackend.port} {
                      header_up Host ${adguardIntegration.dohBackend.serverName}
                      transport http {
                        tls
                        tls_server_name ${adguardIntegration.dohBackend.serverName}
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
          networking.firewall.interfaces.tailscale0 = {
            allowedTCPPorts = [
              53
              443
            ];
            allowedUDPPorts = [ 53 ];
          };
          systemd.services.adguardhome.serviceConfig.SupplementaryGroups = [ "acme" ];
        })
        (lib.mkIf (publisherOptionPresent && publisherIntegration != null) {
          networkCore.caddy.fragments.vpn-client-profiles = {
            hostName = publisherIntegration.configGatewayDomain;
            listenAddresses = [
              "192.0.2.10"
              "100.64.0.10"
            ];
            useACMEHost = "fixture";
            logFile = "/var/log/caddy/vpn-client-profiles-access.log";
            publicSite = true;
            siteOwners = [ "vpn-client-profiles" ];
            capabilities = [ ];
            extraConfig = ''
              bind 192.0.2.10 100.64.0.10
              tls /var/lib/acme/fixture/fullchain.pem /var/lib/acme/fixture/key.pem
              @links_wrong_listener {
                path /config-links/*
                expression `{http.request.local.host} != "100.64.0.10" || {http.request.local.port} != "443"`
              }
              respond @links_wrong_listener 404
              handle /config-links/* {
                root * ${publisherIntegration.linksRoot}
                rewrite * /index.html
                header Cache-Control "no-store"
                file_server
              }
              ${publisherIntegration.routeConfig}
            '';
          };
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
    edge-wildcard-certificate = networkInstance "edge-wildcard-certificate" "certificate" {
      certName = "fixture";
      domain = "example.invalid";
      extraDomainNames = [ "*.example.invalid" ];
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

    vpn-mihomo-hysteria2 = vpnInstance "vpn-mihomo-hysteria2" "gateway" {
      enable = true;
      listenIPv4 = "192.0.2.11";
      port = 443;
      serverName = "hysteria.example.invalid";
      users = [
        {
          name = "cHJvYmU";
          passwordSecretName = "fixture-hysteria-password";
        }
      ];
      acmeCertName = "fixture";
      obfsPasswordSecretName = "fixture-hysteria-obfs-password";
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
      selectedPublicSiteClaim = "fixture-site";
      selectedPublicSiteEndpoint = {
        domain = "site.example.invalid";
        publicIPv4 = "192.0.2.10";
        caddyBindIPv4 = "192.0.2.10";
      };
      passwordSecretNames = {
        ibelyasov = "fixture-naive-first-password";
        bsv = "fixture-naive-second-password";
        probe = "fixture-naive-probe-password";
        cHJvYmU = "fixture-naive-published-password";
      };
    };

    vpn-client-profiles = vpnInstance "vpn-client-profiles" "publisher" {
      enable = true;
      localMachineName = "fixture";
      configGatewayDomain = "profiles.example.invalid";
      publicIPv4 = "192.0.2.10";
      edgeDomain = "edge.example.invalid";
      secretPrefix = "fixture";
      excludedProfileNames = [ ];
      profiles = [
        {
          name = "cHJvYmU";
          kind = "probe";
          publishProfileJson = true;
        }
      ];
      profileLinks = [
        {
          name = "cHJvYmU";
          label = "Fixture profile";
          accountDomain = "profiles.example.invalid";
          pathTokenSecretName = "mihomo-client-fixture-cHJvYmU-path-token";
        }
      ];
      providerRefs = [
        {
          instanceId = "vpn-mihomo-vless-xhttp";
          machine = machineName;
          protocol = "vless-xhttp";
          profileNames = [ "cHJvYmU" ];
        }
        {
          instanceId = "vpn-mihomo-hysteria2";
          machine = machineName;
          protocol = "hysteria2";
          profileNames = [ "cHJvYmU" ];
        }
        {
          instanceId = "vpn-amneziawg";
          machine = machineName;
          protocol = "amneziawg";
          profileNames = [ "cHJvYmU" ];
        }
        {
          instanceId = "vpn-naiveproxy";
          machine = machineName;
          protocol = "naiveproxy";
          profileNames = [ "cHJvYmU" ];
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
