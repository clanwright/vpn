{ lib }:
let
  schemaVersion = 2;

  protocols = {
    naiveproxy = {
      role = "addon";
      service = "@clanwright/vpn-naiveproxy";
      transport = "tcp";
    };
    vless-xhttp = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-vless-xhttp";
      transport = "tcp";
    };
    hysteria2 = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-hysteria2";
      transport = "udp";
    };
    amneziawg = {
      role = "gateway";
      service = "@clanwright/vpn-amneziawg";
      transport = "udp";
    };
    mieru = {
      role = "gateway";
      service = "@clanwright/vpn-mieru";
      transport = "tcp";
    };
    anytls = {
      role = "gateway";
      service = "@clanwright/vpn-anytls";
      transport = "tcp";
    };
  };

  protocolRoles = lib.mapAttrs (_protocol: metadata: metadata.role) protocols;
  protocolServices = lib.mapAttrs (_protocol: metadata: metadata.service) protocols;
  protocolTransports = lib.mapAttrs (_protocol: metadata: metadata.transport) protocols;

  awgProfile = {
    s1 = 12;
    s2 = 12;
    s3 = 12;
    s4 = 12;
    h1 = 1;
    h2 = 2;
    h3 = 3;
    h4 = 4;
    contentPaddingAddition = {
      min = 2;
      max = 10;
    };
    randomTrailers = true;
    disableCookies = false;
  };

  fixedTransportMetadata = {
    naiveproxy = { };
    vless-xhttp = { };
    hysteria2 = {
      alpn = [ "h3" ];
      obfsName = "gecko";
      obfsMinPacketSize = 512;
      obfsMaxPacketSize = 1200;
      tlsVerify = true;
      credentialEncoding = "base64url";
    };
    amneziawg = {
      generation = 3;
      profile = awgProfile;
    };
    mieru = {
      credentialEncoding = "base64url";
    };
    anytls = {
      tlsVerify = true;
      tlsMinVersion = "1.3";
      credentialEncoding = "base64url";
    };
  };

  mkProvider =
    {
      protocol,
      instanceId,
      machine,
      endpoint,
      transportMetadata,
      profileNames,
      secretNames,
    }:
    let
      metadata =
        protocols.${protocol} or (throw "vpn provider envelope: unsupported protocol '${protocol}'");
    in
    {
      inherit
        schemaVersion
        instanceId
        machine
        protocol
        profileNames
        secretNames
        ;
      inherit (metadata) role;
      enabled = true;
      endpoint = endpoint // {
        inherit (metadata) transport;
      };
      transportMetadata =
        transportMetadata
        // fixedTransportMetadata.${protocol}
        // {
          inherit protocol;
        };
    };
in
{
  inherit
    fixedTransportMetadata
    mkProvider
    protocols
    protocolRoles
    protocolServices
    protocolTransports
    schemaVersion
    ;
}
