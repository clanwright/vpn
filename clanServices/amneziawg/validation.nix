{ lib }:
let
  inRange =
    value: min: max:
    builtins.isInt value && value >= min && value <= max;

  allUnique = values: builtins.length values == builtins.length (lib.unique values);
  validToken =
    value: builtins.isString value && builtins.match "[A-Za-z0-9][A-Za-z0-9_.+-]*" value != null;
  validSecretName =
    value:
    builtins.isString value
    && builtins.match "[A-Za-z0-9][A-Za-z0-9_./-]*" value != null
    && !(lib.hasInfix ".." value)
    && !(lib.hasPrefix "/" value)
    && !(lib.hasSuffix "/" value);
  validKey =
    value:
    builtins.isString value && builtins.match "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=" value != null;
  validHostname =
    value:
    let
      labels = if builtins.isString value then lib.splitString "." value else [ ];
      validLabel =
        label:
        builtins.stringLength label <= 63
        && builtins.match "[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?" label != null;
    in
    builtins.isString value && builtins.stringLength value <= 253 && builtins.all validLabel labels;

  validIPv4 =
    value:
    let
      parts = if builtins.isString value then lib.splitString "." value else [ ];
      validPart =
        part: builtins.match "(0|[1-9][0-9]{0,2})" part != null && inRange (builtins.fromJSON part) 0 255;
    in
    builtins.length parts == 4 && builtins.all validPart parts;

  validIPv4Cidr =
    value:
    let
      parts = if builtins.isString value then lib.splitString "/" value else [ ];
      prefix = if builtins.length parts == 2 then builtins.elemAt parts 1 else "";
    in
    builtins.length parts == 2
    && validIPv4 (builtins.elemAt parts 0)
    && builtins.match "(0|[1-9]|[12][0-9]|3[0-2])" prefix != null;

  ipv4ToInt =
    value:
    lib.foldl' (accumulator: octet: accumulator * 256 + builtins.fromJSON octet) 0 (
      lib.splitString "." value
    );
  pow2 = exponent: if exponent == 0 then 1 else 2 * pow2 (exponent - 1);
  cidrContains =
    cidr: address:
    let
      cidrParts = if validIPv4Cidr cidr then lib.splitString "/" cidr else [ ];
      prefix = if cidrParts == [ ] then 0 else builtins.fromJSON (builtins.elemAt cidrParts 1);
      networkAddress = if cidrParts == [ ] then "" else builtins.elemAt cidrParts 0;
      mask = 4294967295 - (pow2 (32 - prefix) - 1);
    in
    cidrParts != [ ]
    && validIPv4 address
    && builtins.bitAnd (ipv4ToInt networkAddress) mask == builtins.bitAnd (ipv4ToInt address) mask;
  cidrNetworkEqual =
    left: right:
    let
      leftParts = if validIPv4Cidr left then lib.splitString "/" left else [ ];
      rightParts = if validIPv4Cidr right then lib.splitString "/" right else [ ];
    in
    leftParts != [ ]
    && rightParts != [ ]
    && builtins.elemAt leftParts 1 == builtins.elemAt rightParts 1
    && cidrContains left (builtins.elemAt rightParts 0)
    && cidrContains right (builtins.elemAt leftParts 0);

  isPackageFamily =
    package: family:
    package != null
    && builtins.isAttrs package
    && builtins.hasAttr "version" package
    && builtins.isString package.version
    && lib.hasPrefix family package.version;

  profile = {
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

  interfaceExtraOptions = {
    S1 = profile.s1;
    S2 = profile.s2;
    S3 = profile.s3;
    S4 = profile.s4;
    H1 = profile.h1;
    H2 = profile.h2;
    H3 = profile.h3;
    H4 = profile.h4;
    "Content-Padding-Addition" =
      "${toString profile.contentPaddingAddition.min}-${toString profile.contentPaddingAddition.max}";
    "Random-Trailers" = if profile.randomTrailers then "on" else "off";
    "Disable-Cookies" = if profile.disableCookies then "on" else "off";
  };
in
{
  inherit
    allUnique
    cidrContains
    cidrNetworkEqual
    interfaceExtraOptions
    profile
    validHostname
    validIPv4
    validIPv4Cidr
    validKey
    validSecretName
    validToken
    ;

  packageFamiliesValid =
    packages:
    isPackageFamily (packages.amneziawg-go or null) "3.1."
    && isPackageFamily (packages.amneziawg-tools or null) "3.1.";

  assertions =
    {
      settings,
      serviceName ? "amneziawg",
    }:
    let
      peers = settings.peers or [ ];
      peerNames = map (peer: peer.name) peers;
      peerPublicKeys = map (peer: peer.publicKey) peers;
      allowedIPs = lib.concatMap (peer: peer.allowedIPs) peers;
      clientAddresses = map (
        peer: if peer.allowedIPs == [ ] then "" else lib.removeSuffix "/32" (builtins.head peer.allowedIPs)
      ) peers;
      serverAddressParts =
        if validIPv4Cidr settings.address then lib.splitString "/" settings.address else [ ];
      serverAddress = if serverAddressParts == [ ] then "" else builtins.head serverAddressParts;
      clientAddressShapeValid =
        peer:
        builtins.length peer.allowedIPs == 1
        && validIPv4Cidr (builtins.head peer.allowedIPs)
        && lib.hasSuffix "/32" (builtins.head peer.allowedIPs);
      keepaliveValid =
        peer:
        let
          value = peer.clientPersistentKeepalive or null;
        in
        value == null || inRange value 1 65535;
    in
    [
      {
        assertion = validToken settings.interfaceName && builtins.stringLength settings.interfaceName <= 15;
        message = "${serviceName}: interfaceName must be a valid Linux interface token of at most 15 characters.";
      }
      {
        assertion = validIPv4 settings.listenIPv4 && settings.listenIPv4 != "0.0.0.0";
        message = "${serviceName}: listenIPv4 must be a concrete, non-wildcard IPv4 address.";
      }
      {
        assertion = validHostname settings.endpointDomain;
        message = "${serviceName}: endpointDomain must be a non-empty hostname.";
      }
      {
        assertion = validIPv4Cidr settings.address;
        message = "${serviceName}: address must be a valid IPv4 CIDR.";
      }
      {
        assertion = validSecretName settings.privateKeySecretName;
        message = "${serviceName}: privateKeySecretName must be a safe relative SOPS secret name.";
      }
      {
        assertion = validSecretName settings.headerProtectionKeySecretName;
        message = "${serviceName}: headerProtectionKeySecretName must be a safe relative SOPS secret name.";
      }
      {
        assertion = settings.privateKeySecretName != settings.headerProtectionKeySecretName;
        message = "${serviceName}: private and header protection keys must use distinct secret names.";
      }
      {
        assertion = validKey settings.serverPublicKey;
        message = "${serviceName}: serverPublicKey must be a canonical base64 WireGuard public key.";
      }
      {
        assertion = peers != [ ];
        message = "${serviceName}: at least one peer is required.";
      }
      {
        assertion = builtins.all validToken peerNames && allUnique peerNames;
        message = "${serviceName}: peer names must be non-empty safe tokens and unique.";
      }
      {
        assertion = builtins.all validKey peerPublicKeys && allUnique peerPublicKeys;
        message = "${serviceName}: peer public keys must be canonical and unique.";
      }
      {
        assertion = builtins.all clientAddressShapeValid peers;
        message = "${serviceName}: every peer must have exactly one canonical IPv4 /32 allowed IP.";
      }
      {
        assertion =
          builtins.all clientAddressShapeValid peers
          && validIPv4Cidr settings.address
          && validIPv4Cidr settings.clientSubnetIPv4
          && builtins.all (cidrContains settings.address) clientAddresses
          && builtins.all (cidrContains settings.clientSubnetIPv4) clientAddresses
          && !(builtins.elem serverAddress clientAddresses)
          && allUnique allowedIPs;
        message = "${serviceName}: peer /32 addresses must be unique, inside clientSubnetIPv4, and distinct from the server interface address.";
      }
      {
        assertion = builtins.all keepaliveValid peers;
        message = "${serviceName}: clientPersistentKeepalive must be null or within 1..65535.";
      }
      {
        assertion = !settings.enableNat || validIPv4 settings.egressIPv4;
        message = "${serviceName}: egressIPv4 must be a valid IPv4 address when NAT is enabled.";
      }
      {
        assertion = validIPv4Cidr settings.clientSubnetIPv4;
        message = "${serviceName}: clientSubnetIPv4 must be a valid IPv4 CIDR.";
      }
      {
        assertion = !settings.enableNat || cidrNetworkEqual settings.address settings.clientSubnetIPv4;
        message = "${serviceName}: clientSubnetIPv4 must describe the interface IPv4 subnet when NAT is enabled.";
      }
    ];
}
