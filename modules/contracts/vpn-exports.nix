{ lib }:
let
  inherit (lib) types;
  inherit (types) nonEmptyListOf nonEmptyStr;
  identities = import ./identities.nix { inherit lib; };
  inherit (identities)
    safeIdentity
    safeSecretName
    safeIdentityType
    safeSecretNameType
    ;
  fixed = value: types.enum [ value ];
  nullableNonEmptyStr = types.nullOr nonEmptyStr;
  mkSubmodule = options: { inherit options; };
  mkOption = type: lib.mkOption { inherit type; };

  realityModule = mkSubmodule {
    serverName = mkOption nonEmptyStr;
    serverNames = mkOption (nonEmptyListOf nonEmptyStr);
    target = mkOption nonEmptyStr;
    shortIdsByProfile = mkOption (types.attrsOf nonEmptyStr);
    publicKey = mkOption nonEmptyStr;
  };
  xhttpModule = mkSubmodule {
    path = mkOption nonEmptyStr;
    mode = mkOption (
      types.enum [
        "auto"
        "stream-one"
        "stream-up"
        "packet-up"
      ]
    );
  };
  dohModule = mkSubmodule {
    domain = mkOption nonEmptyStr;
    ipv4 = mkOption nonEmptyStr;
  };
  awgPeerModule = mkSubmodule {
    name = mkOption safeIdentityType;
    publicKey = mkOption nonEmptyStr;
    allowedIPs = mkOption (nonEmptyListOf nonEmptyStr);
    clientPersistentKeepalive = lib.mkOption {
      type = types.nullOr types.int;
      default = null;
    };
    serverPersistentKeepalive = lib.mkOption {
      type = types.nullOr types.int;
      default = null;
    };
  };
  awgPaddingModule = mkSubmodule {
    min = mkOption types.int;
    max = mkOption types.int;
  };
  awgProfileModule = mkSubmodule {
    s1 = mkOption types.int;
    s2 = mkOption types.int;
    s3 = mkOption types.int;
    s4 = mkOption types.int;
    h1 = mkOption types.int;
    h2 = mkOption types.int;
    h3 = mkOption types.int;
    h4 = mkOption types.int;
    contentPaddingAddition = mkOption (types.submodule awgPaddingModule);
    randomTrailers = mkOption types.bool;
    disableCookies = mkOption types.bool;
  };

  metadataModule = {
    options = {
      protocol = mkOption (
        types.enum [
          "naiveproxy"
          "vless-xhttp"
          "hysteria2"
          "amneziawg"
        ]
      );
      tlsServerName = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      userNames = lib.mkOption {
        type = types.nullOr (nonEmptyListOf safeIdentityType);
        default = null;
      };
      port = lib.mkOption {
        type = types.nullOr types.port;
        default = null;
      };
      reality = lib.mkOption {
        type = types.nullOr (types.submodule realityModule);
        default = null;
      };
      xhttp = lib.mkOption {
        type = types.nullOr (types.submodule xhttpModule);
        default = null;
      };
      fingerprint = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      doh = lib.mkOption {
        type = types.nullOr (types.submodule dohModule);
        default = null;
      };
      sni = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      alpn = lib.mkOption {
        type = types.nullOr (nonEmptyListOf nonEmptyStr);
        default = null;
      };
      obfsName = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      obfsMinPacketSize = lib.mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      obfsMaxPacketSize = lib.mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      tlsVerify = lib.mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      credentialEncoding = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      generation = lib.mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      profile = lib.mkOption {
        type = types.nullOr (types.submodule awgProfileModule);
        default = null;
      };
      serverPublicKey = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      interfaceName = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      address = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      mtu = lib.mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      peers = lib.mkOption {
        type = types.listOf (types.submodule awgPeerModule);
        default = [ ];
      };
    };
  };
  protocolMetadataFields = {
    naiveproxy = [
      "protocol"
      "tlsServerName"
      "userNames"
      "port"
    ];
    vless-xhttp = [
      "protocol"
      "reality"
      "xhttp"
      "fingerprint"
      "doh"
    ];
    hysteria2 = [
      "protocol"
      "sni"
      "alpn"
      "userNames"
      "obfsName"
      "obfsMinPacketSize"
      "obfsMaxPacketSize"
      "tlsVerify"
      "credentialEncoding"
    ];
    amneziawg = [
      "protocol"
      "serverPublicKey"
      "interfaceName"
      "address"
      "mtu"
      "peers"
      "generation"
      "profile"
    ];
  };
  validMetadataShape =
    value:
    builtins.isAttrs value
    && builtins.isString (value.protocol or null)
    && builtins.hasAttr value.protocol protocolMetadataFields
    && attrsHaveExactly protocolMetadataFields.${value.protocol} value;
  metadataType = types.addCheck (types.submodule metadataModule) validMetadataShape;

  secretNamesModule = {
    options = {
      password = lib.mkOption {
        type = types.nullOr (types.attrsOf safeSecretNameType);
        default = null;
      };
      realityPrivateKey = lib.mkOption {
        type = types.nullOr safeSecretNameType;
        default = null;
      };
      vlessUuid = lib.mkOption {
        type = types.nullOr (types.attrsOf safeSecretNameType);
        default = null;
      };
      users = lib.mkOption {
        type = types.nullOr (types.attrsOf safeSecretNameType);
        default = null;
      };
      obfsPassword = lib.mkOption {
        type = types.nullOr safeSecretNameType;
        default = null;
      };
      clientPrivateKey = lib.mkOption {
        type = types.nullOr (types.attrsOf safeSecretNameType);
        default = null;
      };
      headerProtectionKey = lib.mkOption {
        type = types.nullOr safeSecretNameType;
        default = null;
      };
    };
  };
  protocolSecretNameFields = {
    naiveproxy = [ "password" ];
    vless-xhttp = [
      "realityPrivateKey"
      "vlessUuid"
    ];
    hysteria2 = [
      "users"
      "obfsPassword"
    ];
    amneziawg = [
      "clientPrivateKey"
      "headerProtectionKey"
    ];
  };
  validSecretNamesShape =
    value:
    builtins.isAttrs value
    && builtins.any (fields: attrsHaveExactly fields value) (
      builtins.attrValues protocolSecretNameFields
    );
  secretNamesType = types.addCheck (types.submodule secretNamesModule) validSecretNamesShape;

  endpointModule = mkSubmodule {
    domain = mkOption nonEmptyStr;
    ipv4 = mkOption nullableNonEmptyStr;
    port = mkOption types.port;
    transport = mkOption (
      types.enum [
        "tcp"
        "udp"
      ]
    );
  };

  vpnProviderModule = {
    options = {
      schemaVersion = mkOption (fixed 2);
      instanceId = mkOption safeIdentityType;
      machine = mkOption safeIdentityType;
      role = mkOption (
        types.enum [
          "gateway"
          "addon"
        ]
      );
      protocol = mkOption (
        types.enum [
          "naiveproxy"
          "vless-xhttp"
          "hysteria2"
          "amneziawg"
        ]
      );
      enabled = mkOption (fixed true);
      endpoint = mkOption (types.submodule endpointModule);
      transportMetadata = mkOption metadataType;
      profileNames = mkOption (nonEmptyListOf safeIdentityType);
      secretNames = mkOption secretNamesType;
    };
  };

  profileLinkModule = mkSubmodule {
    name = mkOption safeIdentityType;
    label = mkOption nonEmptyStr;
    accountDomain = mkOption nonEmptyStr;
  };
  vpnPublisherModule = {
    options = {
      schemaVersion = mkOption (fixed 1);
      instanceId = mkOption safeIdentityType;
      machine = mkOption safeIdentityType;
      role = mkOption (fixed "publisher");
      enabled = mkOption (fixed true);
      accountDomain = mkOption nonEmptyStr;
      pagePath = mkOption (fixed "/config-links/");
      profileLinks = lib.mkOption {
        type = types.listOf (types.submodule profileLinkModule);
        default = [ ];
      };
    };
  };
  protocolRoles = {
    naiveproxy = "addon";
    vless-xhttp = "gateway";
    hysteria2 = "gateway";
    amneziawg = "gateway";
  };

  protocolServices = {
    naiveproxy = "@clanwright/vpn-naiveproxy";
    vless-xhttp = "@clanwright/vpn-mihomo-vless-xhttp";
    hysteria2 = "@clanwright/vpn-mihomo-hysteria2";
    amneziawg = "@clanwright/vpn-amneziawg";
  };

  fail =
    {
      providerMachine,
      providerInstanceId,
      protocol,
      consumerInstanceId,
    }:
    reason:
    throw (
      "vpn integration requires enabled provider with machine='${providerMachine}', "
      + "instance='${providerInstanceId}', protocol='${protocol}', consumer='${consumerInstanceId}': ${reason}"
    );

  isNonEmptyString = value: builtins.isString value && value != "";
  dropNullAttrs =
    value: if builtins.isAttrs value then lib.filterAttrs (_name: item: item != null) value else value;
  attrsHaveOnly =
    allowed: value:
    builtins.isAttrs value && lib.subtractLists allowed (builtins.attrNames value) == [ ];
  attrsHaveExactly =
    required: value:
    builtins.isAttrs value
    && lib.subtractLists (builtins.attrNames value) required == [ ]
    && lib.subtractLists required (builtins.attrNames value) == [ ];
  allStrings =
    values: builtins.isList values && values != [ ] && builtins.all isNonEmptyString values;
  allSafeIdentities =
    values:
    builtins.isList values
    && values != [ ]
    && builtins.all safeIdentity values
    && values == lib.unique values;

  validAwgProfile =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [
      "s1"
      "s2"
      "s3"
      "s4"
      "h1"
      "h2"
      "h3"
      "h4"
      "contentPaddingAddition"
      "randomTrailers"
      "disableCookies"
    ] value
    && builtins.all (name: builtins.isInt (builtins.getAttr name value)) [
      "s1"
      "s2"
      "s3"
      "s4"
      "h1"
      "h2"
      "h3"
      "h4"
    ]
    && builtins.isAttrs value.contentPaddingAddition
    && attrsHaveExactly [ "min" "max" ] value.contentPaddingAddition
    && builtins.isInt value.contentPaddingAddition.min
    && builtins.isInt value.contentPaddingAddition.max
    && builtins.isBool value.randomTrailers
    && builtins.isBool value.disableCookies
    && value.s1 == 12
    && value.s2 == 12
    && value.s3 == 12
    && value.s4 == 12
    && value.h1 == 1
    && value.h2 == 2
    && value.h3 == 3
    && value.h4 == 4
    && value.contentPaddingAddition.min == 2
    && value.contentPaddingAddition.max == 10
    && value.randomTrailers == true
    && value.disableCookies == false;

  validReality =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [ "serverName" "serverNames" "target" "shortIdsByProfile" "publicKey" ] value
    && isNonEmptyString (value.serverName or null)
    && allStrings (value.serverNames or [ ])
    && isNonEmptyString (value.target or null)
    && builtins.match ".+:443" value.target != null
    && builtins.elem value.serverName value.serverNames
    && builtins.isAttrs value.shortIdsByProfile
    && builtins.all (name: isNonEmptyString (builtins.getAttr name value.shortIdsByProfile)) (
      builtins.attrNames value.shortIdsByProfile
    )
    && isNonEmptyString (value.publicKey or null);

  validXhttp =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [ "path" "mode" ] value
    && isNonEmptyString (value.path or null)
    && (value.mode or null) == "auto";

  validDoh =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [ "domain" "ipv4" ] value
    && isNonEmptyString (value.domain or null)
    && isNonEmptyString (value.ipv4 or null);

  validAwgPeer =
    value:
    builtins.isAttrs value
    && attrsHaveOnly [
      "name"
      "publicKey"
      "allowedIPs"
      "clientPersistentKeepalive"
      "serverPersistentKeepalive"
    ] value
    && isNonEmptyString (value.name or null)
    && isNonEmptyString (value.publicKey or null)
    && allStrings (value.allowedIPs or [ ])
    && (
      builtins.isNull (value.clientPersistentKeepalive or null)
      || builtins.isInt (value.clientPersistentKeepalive or null)
    )
    && (
      builtins.isNull (value.serverPersistentKeepalive or null)
      || builtins.isInt (value.serverPersistentKeepalive or null)
    );

  credentialMapExact =
    profileNames: value:
    builtins.isAttrs value
    && attrsHaveExactly profileNames value
    && builtins.all (
      name: builtins.hasAttr name value && safeSecretName (builtins.getAttr name value)
    ) profileNames;

  validateMetadata =
    context: protocol: value:
    let
      rawMetadata = if builtins.isAttrs value then value else { };
      allowedKeys = protocolMetadataFields.${protocol} or [ ];
      schemaFields = lib.unique (lib.concatLists (builtins.attrValues protocolMetadataFields));
      metadata = lib.filterAttrs (
        name: item:
        builtins.elem name allowedKeys
        || !(builtins.elem name schemaFields && (item == null || item == [ ] || item == { }))
      ) rawMetadata;
    in
    if !builtins.isAttrs metadata then
      fail context "transportMetadata must be an attrset"
    else if !(attrsHaveOnly protocolMetadataFields.${protocol} metadata) then
      fail context "transportMetadata contains an unsupported field"
    else if (metadata.protocol or null) != protocol then
      fail context "transportMetadata.protocol does not match the requested protocol"
    else if
      protocol == "naiveproxy"
      && (
        !isNonEmptyString (metadata.tlsServerName or null)
        || !allStrings (metadata.userNames or [ ])
        || !builtins.isInt (metadata.port or null)
        || metadata.port <= 0
      )
    then
      fail context "NaiveProxy public transport metadata is incomplete"
    else if
      protocol == "vless-xhttp"
      && (
        !validReality (metadata.reality or null)
        || !validXhttp (metadata.xhttp or null)
        || !isNonEmptyString (metadata.fingerprint or null)
        || !validDoh (metadata.doh or null)
      )
    then
      fail context "VLESS/XHTTP public transport metadata is incomplete"
    else if
      protocol == "hysteria2"
      && (
        !isNonEmptyString (metadata.sni or null)
        || !allStrings (metadata.alpn or [ ])
        || metadata.alpn != [ "h3" ]
        || !allStrings (metadata.userNames or [ ])
        || !isNonEmptyString (metadata.obfsName or null)
        || (metadata.obfsName or null) != "gecko"
        || (metadata.obfsMinPacketSize or null) != 512
        || (metadata.obfsMaxPacketSize or null) != 1200
        || (metadata.tlsVerify or null) != true
        || (metadata.credentialEncoding or null) != "base64url"
      )
    then
      fail context "Hysteria2 public transport metadata is incomplete"
    else if
      protocol == "amneziawg"
      && (
        !isNonEmptyString (metadata.serverPublicKey or null)
        || !isNonEmptyString (metadata.interfaceName or null)
        || !(builtins.isNull (metadata.address or null) || isNonEmptyString (metadata.address or null))
        || !builtins.isList (metadata.peers or [ ])
        || !(builtins.all validAwgPeer (metadata.peers or [ ]))
        || !(builtins.isNull (metadata.mtu or null) || builtins.isInt (metadata.mtu or null))
        || (metadata.generation or null) != 3
        || !validAwgProfile (metadata.profile or null)
      )
    then
      fail context "AmneziaWG public transport metadata is incomplete"
    else
      metadata;

  validateProvider =
    {
      providerMachine,
      providerInstanceId,
      protocol,
      consumerInstanceId,
    }:
    raw:
    let
      context = {
        inherit
          providerMachine
          providerInstanceId
          protocol
          consumerInstanceId
          ;
      };
      requiredFields = [
        "schemaVersion"
        "instanceId"
        "machine"
        "role"
        "protocol"
        "enabled"
        "endpoint"
        "transportMetadata"
        "profileNames"
        "secretNames"
      ];
      endpoint = raw.endpoint or { };
      metadata = dropNullAttrs (
        if builtins.isAttrs (raw.transportMetadata or null) then raw.transportMetadata else { }
      );
      secretNames = dropNullAttrs (
        if builtins.isAttrs (raw.secretNames or null) then raw.secretNames else { }
      );
      normalizedRaw = raw // {
        inherit secretNames;
        transportMetadata = metadata;
      };
      expectedRole = protocolRoles.${protocol};
      validSecretNames =
        builtins.isAttrs secretNames
        && attrsHaveExactly protocolSecretNameFields.${protocol} secretNames
        && (
          if protocol == "naiveproxy" then
            credentialMapExact metadata.userNames secretNames.password
          else if protocol == "vless-xhttp" then
            safeSecretName (secretNames.realityPrivateKey or null)
            && credentialMapExact (raw.profileNames or [ ]) secretNames.vlessUuid
          else if protocol == "hysteria2" then
            safeSecretName (secretNames.obfsPassword or null)
            && credentialMapExact metadata.userNames secretNames.users
          else if protocol == "amneziawg" then
            credentialMapExact (raw.profileNames or [ ]) secretNames.clientPrivateKey
            && safeSecretName (secretNames.headerProtectionKey or null)
          else
            false
        );
      validShape =
        builtins.isAttrs raw
        && attrsHaveExactly requiredFields raw
        && raw.schemaVersion == 2
        && raw.instanceId == providerInstanceId
        && raw.machine == providerMachine
        && raw.role == expectedRole
        && raw.protocol == protocol
        && raw.enabled == true
        && builtins.isAttrs endpoint
        && attrsHaveExactly [ "domain" "ipv4" "port" "transport" ] endpoint
        && isNonEmptyString endpoint.domain
        && (builtins.isNull endpoint.ipv4 || isNonEmptyString endpoint.ipv4)
        && builtins.isInt endpoint.port
        && endpoint.port > 0
        &&
          endpoint.transport == (
            if
              builtins.elem protocol [
                "hysteria2"
                "amneziawg"
              ]
            then
              "udp"
            else
              "tcp"
          )
        && safeIdentity (raw.instanceId or null)
        && safeIdentity (raw.machine or null)
        && allSafeIdentities (raw.profileNames or [ ])
        && (
          protocol != "amneziawg"
          || (
            let
              peerNames = map (peer: peer.name) (metadata.peers or [ ]);
            in
            peerNames == raw.profileNames && peerNames == lib.unique peerNames
          )
        )
        && (protocol != "hysteria2" || metadata.userNames == raw.profileNames)
        && (
          protocol != "naiveproxy"
          || (
            allSafeIdentities (metadata.userNames or [ ])
            && lib.subtractLists metadata.userNames raw.profileNames == [ ]
          )
        )
        && (
          protocol != "vless-xhttp"
          || credentialMapExact (raw.profileNames or [ ]) ((metadata.reality or { }).shortIdsByProfile or { })
        )
        && validSecretNames;
    in
    if !builtins.isAttrs raw then
      fail context "provider exports are missing"
    else if !(attrsHaveExactly requiredFields raw) then
      fail context "provider export shape is not the closed allowlist"
    else if !validShape then
      fail context "provider export metadata does not match the requested provider"
    else
      normalizedRaw
      // {
        transportMetadata = validateMetadata context protocol metadata;
      };

  selectExportInterface =
    {
      serviceName,
      instanceId,
      machine,
      role,
      interfaceName,
      allowedInterfaceNames,
      selectExports,
      exports,
      consumerInstanceId,
      validate,
    }:
    let
      context = {
        providerMachine = machine;
        providerInstanceId = instanceId;
        protocol = serviceName;
        inherit consumerInstanceId;
      };
      selectedScopes =
        if !builtins.isFunction selectExports then
          fail context "Clan selectExports selector is unavailable"
        else if !builtins.isAttrs exports then
          fail context "Clan exports are unavailable"
        else
          selectExports (
            scope:
            scope.serviceName == serviceName
            && scope.instanceName == instanceId
            && scope.roleName == role
            && scope.machineName == machine
          ) exports;
      selectedScopeNames =
        if builtins.isAttrs selectedScopes then
          builtins.attrNames selectedScopes
        else
          fail context "Clan selectExports did not return a scoped attrset";
      selected =
        if builtins.length selectedScopeNames != 1 then
          fail context "${interfaceName} scope selection matched ${toString (builtins.length selectedScopeNames)} exports; expected exactly one"
        else
          builtins.getAttr (builtins.head selectedScopeNames) selectedScopes;
      envelope =
        if builtins.isAttrs selected && attrsHaveExactly [ "exports" ] selected then
          selected.exports
        else
          selected;
    in
    if
      !builtins.isAttrs envelope
      || !(attrsHaveExactly allowedInterfaceNames envelope)
      || builtins.any (
        name: name != interfaceName && builtins.getAttr name envelope != null
      ) allowedInterfaceNames
    then
      fail context "selected export is not the closed ${interfaceName} interface"
    else
      validate context (builtins.getAttr interfaceName envelope);

  validatePublisher =
    context: raw:
    let
      fields = [
        "schemaVersion"
        "instanceId"
        "machine"
        "role"
        "enabled"
        "accountDomain"
        "pagePath"
        "profileLinks"
      ];
      validProfileLink =
        value:
        builtins.isAttrs value
        && attrsHaveExactly [ "name" "label" "accountDomain" ] value
        && safeIdentity (value.name or null)
        && isNonEmptyString (value.label or null)
        && isNonEmptyString (value.accountDomain or null);
      profileLinkNames = map (link: link.name or null) (raw.profileLinks or [ ]);
    in
    if !builtins.isAttrs raw || !(attrsHaveExactly fields raw) then
      fail context "vpnPublisher export shape is not the closed allowlist"
    else if
      raw.schemaVersion != 1
      || raw.instanceId != context.providerInstanceId
      || raw.machine != context.providerMachine
      || raw.role != "publisher"
      || raw.enabled != true
      || !safeIdentity (raw.instanceId or null)
      || !safeIdentity (raw.machine or null)
      || !isNonEmptyString (raw.accountDomain or null)
      || raw.pagePath != "/config-links/"
      || !builtins.isList (raw.profileLinks or [ ])
      || !(builtins.all validProfileLink (raw.profileLinks or [ ]))
      || profileLinkNames != lib.unique profileLinkNames
    then
      fail context "vpnPublisher metadata does not match the requested publisher"
    else
      raw;

in
{
  inherit
    vpnProviderModule
    vpnPublisherModule
    ;

  selectVpnProvider =
    {
      providerInstanceId,
      providerMachine,
      protocol,
      selectExports,
      exports,
      consumerInstanceId ? "unknown-consumer",
    }:
    let
      context = {
        inherit
          providerMachine
          providerInstanceId
          protocol
          consumerInstanceId
          ;
      };
      expectedRole = protocolRoles.${protocol} or null;
      selected =
        if expectedRole == null then
          null
        else
          let
            selectedScopes =
              if !builtins.isFunction selectExports then
                fail context "Clan selectExports selector is unavailable"
              else if !builtins.isAttrs exports then
                fail context "Clan provider exports are unavailable"
              else
                selectExports (
                  scope:
                  scope.serviceName == protocolServices.${protocol}
                  && scope.instanceName == providerInstanceId
                  && scope.roleName == expectedRole
                  && scope.machineName == providerMachine
                ) exports;
            selectedScopeNames =
              if builtins.isAttrs selectedScopes then
                builtins.attrNames selectedScopes
              else
                fail context "Clan selectExports did not return a scoped attrset";
          in
          if builtins.length selectedScopeNames != 1 then
            fail context "provider scope selection matched ${toString (builtins.length selectedScopeNames)} exports; expected exactly one"
          else
            builtins.getAttr (builtins.head selectedScopeNames) selectedScopes;
      raw =
        if selected == null then
          null
        else if builtins.isAttrs selected && selected ? vpnProvider then
          selected.vpnProvider
        else
          fail context "selected provider export is missing the declared vpnProvider interface";
    in
    if expectedRole == null then
      fail context "unsupported provider protocol"
    else if raw == null then
      fail context "provider is missing, disabled or has no active export"
    else
      validateProvider context raw;

  selectVpnPublisher =
    {
      publisherInstanceId,
      publisherMachine,
      selectExports,
      exports,
      consumerInstanceId ? "unknown-consumer",
    }:
    selectExportInterface {
      serviceName = "@clanwright/vpn-client-profiles";
      instanceId = publisherInstanceId;
      machine = publisherMachine;
      role = "publisher";
      interfaceName = "vpnPublisher";
      allowedInterfaceNames = [ "vpnPublisher" ];
      inherit
        selectExports
        exports
        consumerInstanceId
        ;
      validate = validatePublisher;
    };

}
