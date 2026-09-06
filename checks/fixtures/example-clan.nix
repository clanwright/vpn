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
      name = "probe";
      kind = "probe";
      publishProfileJson = false;
      vlessUuidSecretName = "fixture-vless-uuid";
    }
  ];
  awgOptions = {
    H1 = 101;
    H2 = 202;
    H3 = 303;
    H4 = 404;
    I1 = "<b 0x1234567890><t><r 16>";
    I2 = "<b 0x2234567890><r 96>";
    I3 = "";
    I4 = "";
    I5 = "";
    Jc = 5;
    Jmin = 128;
    Jmax = 768;
    S1 = 60;
    S2 = 42;
    S3 = 33;
    S4 = 16;
  };
in
rec {
  machine = {
    nixpkgs.hostPlatform = "x86_64-linux";
    boot.isContainer = true;
    sops.defaultSopsFile = ./empty-sops.yaml;
    sops.age.keyFile = "/run/vpn-fixture/age-key";
    system.stateVersion = "26.11";
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
        serverName = "donor.example.invalid";
        dest = "donor.example.invalid:443";
        shortIds = [
          "0123456789abcdef"
          "1123456789abcdef"
          "2123456789abcdef"
          "3123456789abcdef"
          "4123456789abcdef"
          "5123456789abcdef"
          "6123456789abcdef"
          "7123456789abcdef"
        ];
        publicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
        privateKeySecretName = "fixture-reality-private-key";
      };
      xhttp = {
        path = "/fixture";
        mode = "packet-up";
      };
      inherit profiles;
    };

    vpn-mihomo-hysteria2 = vpnInstance "vpn-mihomo-hysteria2" "gateway" {
      enable = true;
      listenIPv4 = "192.0.2.11";
      port = 443;
      serverName = "hysteria.example.invalid";
      users = [
        {
          name = "probe";
          passwordSecretName = "fixture-hysteria-password";
        }
      ];
      masqueradeUrl = "https://cover.example.invalid";
      ignoreClientBandwidth = true;
      acmeCertName = "fixture";
      obfsPasswordSecretName = "fixture-hysteria-obfs-password";
    };

    vpn-amneziawg = vpnInstance "vpn-amneziawg" "gateway" {
      enable = true;
      lifecycle = "enabled";
      interfaceName = "awg-fixture";
      listenIPv4 = "192.0.2.12";
      endpointDomain = "awg.example.invalid";
      listenPort = 443;
      mtu = 1280;
      address = "10.77.0.1/24";
      privateKeySecretName = "fixture-awg-server-private-key";
      serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      peers = [
        {
          name = "probe";
          publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
          allowedIPs = [ "10.77.0.2/32" ];
          clientPersistentKeepalive = 25;
        }
      ];
      extraOptions = awgOptions;
      egressIPv4 = "192.0.2.12";
      clientSubnetIPv4 = "10.77.0.0/24";
      enableNat = true;
    };

    vpn-naiveproxy = vpnInstance "vpn-naiveproxy" "addon" {
      enable = true;
      machineName = "fixture";
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
      };
    };

    vpn-client-profiles = vpnInstance "vpn-client-profiles" "publisher" {
      enable = true;
      localMachineName = "fixture";
      configGatewayDomain = "profiles.example.invalid";
      publicIPv4 = "192.0.2.10";
      caddyBindIPv4 = "192.0.2.10";
      tailnetIPv4 = "100.64.0.10";
      edgeDomain = "edge.example.invalid";
      acmeCertName = "fixture";
      secretPrefix = "fixture";
      excludedProfileNames = [ ];
      profiles = [
        {
          name = "probe";
          kind = "probe";
          publishProfileJson = true;
          vlessUuidSecretName = "fixture-vless-uuid";
        }
      ];
      providerRefs = [
        {
          instanceId = "vpn-mihomo-vless-xhttp";
          machine = machineName;
          protocol = "vless-xhttp";
          profileNames = [ "probe" ];
        }
        {
          instanceId = "vpn-mihomo-hysteria2";
          machine = machineName;
          protocol = "hysteria2";
          profileNames = [ "probe" ];
        }
        {
          instanceId = "vpn-amneziawg";
          machine = machineName;
          protocol = "amneziawg";
          profileNames = [ "probe" ];
        }
        {
          instanceId = "vpn-naiveproxy";
          machine = machineName;
          protocol = "naiveproxy";
          profileNames = [ "probe" ];
        }
      ];
    };

    dns-unbound = vpnInstance "dns-unbound" "recursive-backend" {
      listen.hosts = [ "127.0.0.1" ];
      listen.port = 5335;
      adguardIntegrationProvider = "dns-adguardhome";
    };

    dns-adguardhome = vpnInstance "dns-adguardhome" "resolver" {
      lifecycle = "enabled";
      ui = {
        host = "127.0.0.1";
        port = 3000;
        domain = "adguard.example.invalid";
      };
      ingress = {
        publicIPv4 = "192.0.2.10";
        caddyBindIPv4 = "192.0.2.10";
        tailnetIPv4 = "100.64.0.10";
      };
      dns = {
        bindHosts = [ "127.0.0.1" ];
        port = 53;
        upstream = [ "127.0.0.1:5335" ];
        bootstrap = [ ];
      };
      tls = {
        serverName = "dns.example.invalid";
        httpsPort = 8444;
        dotPort = 0;
      };
      acme.certName = "fixture";
      auth.enable = false;
      systemResolver = {
        enableLocalStub = true;
        nameservers = [ "127.0.0.1" ];
      };
    };
  };
}
