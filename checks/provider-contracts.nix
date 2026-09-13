{ inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  providerEnvelope = import ../modules/contracts/provider-envelope.nix { inherit lib; };
  vpnExports = import ../modules/contracts/vpn-exports.nix { inherit lib; };

  validProvider = providerEnvelope.mkProvider {
    protocol = "vless-xhttp";
    instanceId = "fixture.vless";
    machine = "fixture.machine";
    endpoint = {
      domain = "vless.example.invalid";
      ipv4 = "192.0.2.10";
      port = 443;
    };
    transportMetadata = {
      reality = {
        serverName = "donor.example.invalid";
        serverNames = [ "donor.example.invalid" ];
        target = "donor.example.invalid:443";
        shortIdsByProfile."device.one" = "0123456789abcdef";
        publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
      };
      xhttp = {
        path = "/fixture";
        mode = "auto";
      };
      fingerprint = "edge";
      doh = {
        domain = "dns.example.invalid";
        ipv4 = "192.0.2.53";
      };
    };
    profileNames = [ "device.one" ];
    secretNames = {
      realityPrivateKey = "fixture/reality-private-key";
      vlessUuid."device.one" = "fixture/device.one-vless-uuid";
    };
  };

  validHysteria = providerEnvelope.mkProvider {
    protocol = "hysteria2";
    instanceId = "fixture.hysteria";
    machine = "fixture.machine";
    endpoint = {
      domain = "hysteria.example.invalid";
      ipv4 = "192.0.2.11";
      port = 443;
    };
    transportMetadata = {
      sni = "hysteria.example.invalid";
      userNames = [ "device.one" ];
    };
    profileNames = [ "device.one" ];
    secretNames = {
      users."device.one" = "fixture/device.one-hysteria-password";
      obfsPassword = "fixture/hysteria-obfs-password";
    };
  };
  validMieru = providerEnvelope.mkProvider {
    protocol = "mieru";
    instanceId = "fixture.mieru";
    machine = "fixture.machine";
    endpoint = {
      domain = null;
      ipv4 = "192.0.2.12";
      port = 443;
    };
    transportMetadata.userNames = [ "device.one" ];
    profileNames = [ "device.one" ];
    secretNames.users."device.one" = "fixture/device.one-mieru-password";
  };
  validAnytls = providerEnvelope.mkProvider {
    protocol = "anytls";
    instanceId = "fixture.anytls";
    machine = "fixture.machine";
    endpoint = {
      domain = "anytls.example.invalid";
      ipv4 = "192.0.2.14";
      port = 443;
    };
    transportMetadata = {
      tlsServerName = "anytls.example.invalid";
      userNames = [ "device.one" ];
    };
    profileNames = [ "device.one" ];
    secretNames.users."device.one" = "fixture/device.one-anytls-password";
  };
  validTrustTunnel = providerEnvelope.mkProvider {
    protocol = "trusttunnel";
    instanceId = "fixture.trusttunnel";
    machine = "fixture.machine";
    endpoint = {
      domain = "trusttunnel.example.invalid";
      ipv4 = "192.0.2.15";
      port = 443;
    };
    transportMetadata = {
      tlsServerName = "trusttunnel.example.invalid";
      userNames = [ "device.one" ];
    };
    profileNames = [ "device.one" ];
    secretNames.users."device.one" = "fixture/device.one-trusttunnel-password";
  };
  validAwg = providerEnvelope.mkProvider {
    protocol = "amneziawg";
    instanceId = "fixture.awg";
    machine = "fixture.machine";
    endpoint = {
      domain = "awg.example.invalid";
      ipv4 = "192.0.2.13";
      port = 443;
    };
    transportMetadata = {
      serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      interfaceName = "awg0";
      address = "10.77.0.1/24";
      mtu = 1280;
      peers = [
        {
          name = "device.one";
          publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
          allowedIPs = [ "10.77.0.2/32" ];
          clientPersistentKeepalive = 25;
        }
      ];
    };
    profileNames = [ "device.one" ];
    secretNames = {
      clientPrivateKey."device.one" = "fixture/device.one-awg-private-key";
      headerProtectionKey = "fixture/awg-header-protection-key";
    };
  };

  evalProvider =
    value:
    (lib.evalModules {
      modules = [
        {
          options.provider = lib.mkOption {
            type = lib.types.submodule vpnExports.vpnProviderModule;
          };
        }
        { config.provider = value; }
      ];
    }).config.provider;
  typeAccepts = value: (builtins.tryEval (builtins.deepSeq (evalProvider value) true)).success;

  selectProvider =
    protocol: value:
    let
      metadata = providerEnvelope.protocols.${protocol};
      selectExports =
        predicate: exports:
        if
          predicate {
            serviceName = metadata.service;
            instanceName = value.instanceId;
            roleName = metadata.role;
            machineName = value.machine;
          }
        then
          exports
        else
          { };
    in
    vpnExports.selectVpnProvider {
      providerInstanceId = value.instanceId;
      providerMachine = value.machine;
      inherit protocol selectExports;
      exports.selected.vpnProvider = value;
      consumerInstanceId = "fixture.publisher";
    };
  selectorAccepts =
    protocol: value: (builtins.tryEval (builtins.deepSeq (selectProvider protocol value) true)).success;

  wrongMode = lib.recursiveUpdate validProvider {
    transportMetadata.xhttp.mode = "stream-one";
  };
  wrongRole = validProvider // {
    role = "addon";
  };
  wrongTransport = lib.recursiveUpdate validProvider {
    endpoint.transport = "udp";
  };
  wrongMetadataProtocol = lib.recursiveUpdate validProvider {
    transportMetadata.protocol = "hysteria2";
  };

  fixedPolicyCases = [
    {
      name = "hysteriaAlpn";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.alpn = [ "h2" ]; };
    }
    {
      name = "hysteriaObfsName";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.obfsName = "salamander"; };
    }
    {
      name = "hysteriaObfsMinPacketSize";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.obfsMinPacketSize = 511; };
    }
    {
      name = "hysteriaObfsMaxPacketSize";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.obfsMaxPacketSize = 1201; };
    }
    {
      name = "hysteriaTlsVerify";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.tlsVerify = false; };
    }
    {
      name = "hysteriaCredentialEncoding";
      protocol = "hysteria2";
      value = lib.recursiveUpdate validHysteria { transportMetadata.credentialEncoding = "plain"; };
    }
    {
      name = "mieruCredentialEncoding";
      protocol = "mieru";
      value = lib.recursiveUpdate validMieru { transportMetadata.credentialEncoding = "plain"; };
    }
    {
      name = "anytlsTlsVerify";
      protocol = "anytls";
      value = lib.recursiveUpdate validAnytls { transportMetadata.tlsVerify = false; };
    }
    {
      name = "anytlsTlsMinVersion";
      protocol = "anytls";
      value = lib.recursiveUpdate validAnytls { transportMetadata.tlsMinVersion = "1.2"; };
    }
    {
      name = "anytlsCredentialEncoding";
      protocol = "anytls";
      value = lib.recursiveUpdate validAnytls { transportMetadata.credentialEncoding = "plain"; };
    }
    {
      name = "trustTunnelTlsVerify";
      protocol = "trusttunnel";
      value = lib.recursiveUpdate validTrustTunnel { transportMetadata.tlsVerify = false; };
    }
    {
      name = "trustTunnelCredentialEncoding";
      protocol = "trusttunnel";
      value = lib.recursiveUpdate validTrustTunnel { transportMetadata.credentialEncoding = "plain"; };
    }
    {
      name = "trustTunnelUpstreamProtocol";
      protocol = "trusttunnel";
      value = lib.recursiveUpdate validTrustTunnel { transportMetadata.upstreamProtocol = "http3"; };
    }
    {
      name = "awgGeneration";
      protocol = "amneziawg";
      value = lib.recursiveUpdate validAwg { transportMetadata.generation = 2; };
    }
    {
      name = "awgProfile";
      protocol = "amneziawg";
      value = lib.recursiveUpdate validAwg { transportMetadata.profile.s1 = 13; };
    }
  ];

  fixedPolicyTypeResults = lib.listToAttrs (
    map (case: {
      inherit (case) name;
      value = !(typeAccepts case.value);
    }) fixedPolicyCases
  );
  fixedPolicySelectorResults = lib.listToAttrs (
    map (case: {
      inherit (case) name;
      value = !(selectorAccepts case.protocol case.value);
    }) fixedPolicyCases
  );

  canonicalizedMieru = providerEnvelope.mkProvider {
    protocol = "mieru";
    instanceId = "fixture.mieru";
    machine = "fixture.machine";
    endpoint = validMieru.endpoint // {
      transport = "udp";
    };
    transportMetadata = {
      protocol = "hysteria2";
      userNames = [ "device.one" ];
      credentialEncoding = "plain";
    };
    inherit (validMieru) profileNames secretNames;
  };

  /*
    Retain this exact catalog assertion so adding a protocol requires an explicit
    role, service, and transport decision in the public contract check.
  */
  expectedCatalog = {
    anytls = {
      role = "gateway";
      service = "@clanwright/vpn-anytls";
      transport = "tcp";
    };
    amneziawg = {
      role = "gateway";
      service = "@clanwright/vpn-amneziawg";
      transport = "udp";
    };
    hysteria2 = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-hysteria2";
      transport = "udp";
    };
    mieru = {
      role = "gateway";
      service = "@clanwright/vpn-mieru";
      transport = "tcp";
    };
    naiveproxy = {
      role = "addon";
      service = "@clanwright/vpn-naiveproxy";
      transport = "tcp";
    };
    trusttunnel = {
      role = "gateway";
      service = "@clanwright/vpn-trusttunnel";
      transport = "tcp";
    };
    vless-xhttp = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-vless-xhttp";
      transport = "tcp";
    };
  };

  unsupportedConstructor = builtins.tryEval (
    builtins.deepSeq (providerEnvelope.mkProvider {
      protocol = "unsupported";
      instanceId = "fixture";
      machine = "fixture";
      endpoint = { };
      transportMetadata = { };
      profileNames = [ "fixture" ];
      secretNames = { };
    }) true
  );
  constructorContract =
    providerEnvelope.schemaVersion == 2
    && providerEnvelope.protocols == expectedCatalog
    && validProvider.schemaVersion == 2
    && validProvider.role == "gateway"
    && validProvider.enabled
    && validProvider.endpoint.transport == "tcp"
    && validProvider.transportMetadata.protocol == "vless-xhttp"
    && canonicalizedMieru.endpoint.transport == "tcp"
    && canonicalizedMieru.transportMetadata.protocol == "mieru"
    && canonicalizedMieru.transportMetadata.credentialEncoding == "base64url"
    && validAnytls.endpoint.transport == "tcp"
    &&
      validAnytls.transportMetadata == {
        protocol = "anytls";
        tlsServerName = "anytls.example.invalid";
        userNames = [ "device.one" ];
        tlsVerify = true;
        tlsMinVersion = "1.3";
        credentialEncoding = "base64url";
      }
    && validTrustTunnel.endpoint.transport == "tcp"
    &&
      validTrustTunnel.transportMetadata == {
        protocol = "trusttunnel";
        userNames = [ "device.one" ];
        tlsServerName = "trusttunnel.example.invalid";
        tlsVerify = true;
        credentialEncoding = "base64url";
        upstreamProtocol = "http2";
      }
    && !unsupportedConstructor.success;
  typeResults = {
    valid = typeAccepts validProvider;
    validAnytls = typeAccepts validAnytls;
    validTrustTunnel = typeAccepts validTrustTunnel;
    wrongMode = !(typeAccepts wrongMode);
    wrongRole = !(typeAccepts wrongRole);
    wrongTransport = !(typeAccepts wrongTransport);
    wrongMetadataProtocol = !(typeAccepts wrongMetadataProtocol);
    fixedPolicies = builtins.all (value: value) (builtins.attrValues fixedPolicyTypeResults);
  };
  typeContract = builtins.all (value: value) (builtins.attrValues typeResults);
  selectorResults = {
    validVless = selectorAccepts "vless-xhttp" validProvider;
    validHysteria = selectorAccepts "hysteria2" validHysteria;
    validMieru = selectorAccepts "mieru" validMieru;
    validAnytls = selectorAccepts "anytls" validAnytls;
    validTrustTunnel = selectorAccepts "trusttunnel" validTrustTunnel;
    validAwg = selectorAccepts "amneziawg" validAwg;
    anytlsMissingIpv4 =
      !(selectorAccepts "anytls" (
        validAnytls // { endpoint = builtins.removeAttrs validAnytls.endpoint [ "ipv4" ]; }
      ));
    anytlsMissingDomain =
      !(selectorAccepts "anytls" (
        validAnytls // { endpoint = builtins.removeAttrs validAnytls.endpoint [ "domain" ]; }
      ));
    anytlsWrongIpv4 =
      !(selectorAccepts "anytls" (lib.recursiveUpdate validAnytls { endpoint.ipv4 = "192.0.2.999"; }));
    anytlsSniMismatch =
      !(selectorAccepts "anytls" (
        lib.recursiveUpdate validAnytls { transportMetadata.tlsServerName = "other.example.invalid"; }
      ));
    anytlsUdpTransportRejected =
      !(selectorAccepts "anytls" (lib.recursiveUpdate validAnytls { endpoint.transport = "udp"; }));
    anytlsUnknownMetadataRejected =
      !(selectorAccepts "anytls" (
        lib.recursiveUpdate validAnytls { transportMetadata.alpn = [ "h2" ]; }
      ));
    anytlsUsersMismatch =
      !(selectorAccepts "anytls" (
        lib.recursiveUpdate validAnytls { transportMetadata.userNames = [ "other" ]; }
      ));
    anytlsSecretMapMismatch =
      !(selectorAccepts "anytls" (
        lib.recursiveUpdate validAnytls { secretNames.users.other = "fixture/other-anytls-password"; }
      ));
    trustTunnelMissingIpv4 =
      !(selectorAccepts "trusttunnel" (
        validTrustTunnel // { endpoint = builtins.removeAttrs validTrustTunnel.endpoint [ "ipv4" ]; }
      ));
    trustTunnelMissingDomain =
      !(selectorAccepts "trusttunnel" (
        validTrustTunnel // { endpoint = builtins.removeAttrs validTrustTunnel.endpoint [ "domain" ]; }
      ));
    trustTunnelWrongIpv4 =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel { endpoint.ipv4 = "192.0.2.999"; }
      ));
    trustTunnelSniMismatch =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel {
          transportMetadata.tlsServerName = "other.example.invalid";
        }
      ));
    trustTunnelUdpTransportRejected =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel { endpoint.transport = "udp"; }
      ));
    trustTunnelUnknownTopLevelRejected =
      !(selectorAccepts "trusttunnel" (validTrustTunnel // { unexpected = true; }));
    trustTunnelUnknownEndpointRejected =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel { endpoint.path = "/unexpected"; }
      ));
    trustTunnelUnknownMetadataRejected =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel { transportMetadata.alpn = [ "h2" ]; }
      ));
    trustTunnelUsersMismatch =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel { transportMetadata.userNames = [ "other" ]; }
      ));
    trustTunnelSecretMapMismatch =
      !(selectorAccepts "trusttunnel" (
        lib.recursiveUpdate validTrustTunnel {
          secretNames.users.other = "fixture/other-trusttunnel-password";
        }
      ));
    dottedIdentity = (selectProvider "vless-xhttp" validProvider).profileNames == [ "device.one" ];
    wrongMode = !(selectorAccepts "vless-xhttp" wrongMode);
    wrongRole = !(selectorAccepts "vless-xhttp" wrongRole);
    wrongTransport = !(selectorAccepts "vless-xhttp" wrongTransport);
    wrongMetadataProtocol = !(selectorAccepts "vless-xhttp" wrongMetadataProtocol);
    fixedPolicies = builtins.all (value: value) (builtins.attrValues fixedPolicySelectorResults);
  };
  selectorContract = builtins.all (value: value) (builtins.attrValues selectorResults);
  contract = constructorContract && typeContract && selectorContract;
in
if !contract then
  throw "Provider constructor, type, or selector contract failed: ${
    builtins.toJSON {
      inherit
        constructorContract
        selectorContract
        selectorResults
        typeContract
        typeResults
        ;
    }
  }"
else
  {
    all = true;
    inherit constructorContract selectorContract typeContract;
  }
