{ lib }:
let
  inherit (lib) types;
  inherit (types) nonEmptyListOf nonEmptyStr;
  fixed = value: types.enum [ value ];
  nullableNonEmptyStr = types.nullOr nonEmptyStr;
  scalar = types.oneOf [
    types.int
    types.str
  ];

  mkSubmodule = options: { inherit options; };
  mkOption = type: lib.mkOption { inherit type; };

  realityModule = mkSubmodule {
    serverName = mkOption nonEmptyStr;
    dest = mkOption nonEmptyStr;
    shortIds = mkOption (nonEmptyListOf nonEmptyStr);
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
    name = mkOption nonEmptyStr;
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
  awgExtraOptionsModule = mkSubmodule (
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = mkOption scalar;
        })
        [
          "H1"
          "H2"
          "H3"
          "H4"
          "I1"
          "I2"
          "I3"
          "I4"
          "I5"
          "Jc"
          "Jmin"
          "Jmax"
          "S1"
          "S2"
          "S3"
          "S4"
        ]
    )
  );

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
        type = types.nullOr (nonEmptyListOf nonEmptyStr);
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
      peerPublicKeys = lib.mkOption {
        type = types.attrsOf nonEmptyStr;
        default = { };
      };
      extraOptions = lib.mkOption {
        type = types.nullOr (types.submodule awgExtraOptionsModule);
        default = null;
      };
    };
  };
  metadataFields = {
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
    ];
    amneziawg = [
      "protocol"
      "serverPublicKey"
      "interfaceName"
      "address"
      "mtu"
      "peers"
      "peerPublicKeys"
      "extraOptions"
    ];
  };
  validMetadataShape =
    value:
    builtins.isAttrs value
    && builtins.isString (value.protocol or null)
    && builtins.hasAttr value.protocol metadataFields
    && attrsHaveExactly metadataFields.${value.protocol} value;
  metadataType = types.addCheck (types.submodule metadataModule) validMetadataShape;

  secretNamesModule = {
    options = {
      password = lib.mkOption {
        type = types.nullOr (types.attrsOf nonEmptyStr);
        default = null;
      };
      realityPrivateKey = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      vlessUuid = lib.mkOption {
        type = types.nullOr (types.attrsOf nonEmptyStr);
        default = null;
      };
      users = lib.mkOption {
        type = types.nullOr (types.attrsOf nonEmptyStr);
        default = null;
      };
      obfsPassword = lib.mkOption {
        type = nullableNonEmptyStr;
        default = null;
      };
      clientPrivateKey = lib.mkOption {
        type = types.nullOr (types.attrsOf nonEmptyStr);
        default = null;
      };
    };
  };
  secretNamesFields = [
    [ "password" ]
    [
      "realityPrivateKey"
      "vlessUuid"
    ]
    [
      "users"
      "obfsPassword"
    ]
    [ "clientPrivateKey" ]
  ];
  validSecretNamesShape =
    value:
    builtins.isAttrs value && builtins.any (fields: attrsHaveExactly fields value) secretNamesFields;
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
      schemaVersion = mkOption (fixed 1);
      instanceId = mkOption nonEmptyStr;
      machine = mkOption nonEmptyStr;
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
      profileNames = mkOption (nonEmptyListOf nonEmptyStr);
      secretNames = mkOption secretNamesType;
    };
  };

  profileLinkModule = mkSubmodule {
    name = mkOption nonEmptyStr;
    label = mkOption nonEmptyStr;
    accountDomain = mkOption nonEmptyStr;
  };
  vpnPublisherModule = {
    options = {
      schemaVersion = mkOption (fixed 1);
      instanceId = mkOption nonEmptyStr;
      machine = mkOption nonEmptyStr;
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

  metadataKeys = {
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
    ];
    amneziawg = [
      "protocol"
      "serverPublicKey"
      "interfaceName"
      "address"
      "mtu"
      "peers"
      "peerPublicKeys"
      "extraOptions"
    ];
  };

  awgExtraOptionKeys = [
    "H1"
    "H2"
    "H3"
    "H4"
    "I1"
    "I2"
    "I3"
    "I4"
    "I5"
    "Jc"
    "Jmin"
    "Jmax"
    "S1"
    "S2"
    "S3"
    "S4"
  ];

  validAwgExtraOptions =
    value:
    builtins.isAttrs value
    && attrsHaveExactly awgExtraOptionKeys value
    && builtins.all (
      name:
      let
        option = builtins.getAttr name value;
      in
      builtins.isInt option || builtins.isString option
    ) (builtins.attrNames value);

  validReality =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [ "serverName" "dest" "shortIds" "publicKey" ] value
    && isNonEmptyString (value.serverName or null)
    && isNonEmptyString (value.dest or null)
    && allStrings (value.shortIds or [ ])
    && isNonEmptyString (value.publicKey or null);

  validXhttp =
    value:
    builtins.isAttrs value
    && attrsHaveExactly [ "path" "mode" ] value
    && isNonEmptyString (value.path or null)
    && builtins.elem (value.mode or null) [
      "auto"
      "stream-one"
      "stream-up"
      "packet-up"
    ];

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

  validPeerPublicKeys =
    value:
    builtins.isAttrs value
    && builtins.all (name: isNonEmptyString name && isNonEmptyString (builtins.getAttr name value)) (
      builtins.attrNames value
    );

  credentialMapExact =
    profileNames: value:
    builtins.isAttrs value
    && attrsHaveExactly profileNames value
    && builtins.all (
      name: builtins.hasAttr name value && isNonEmptyString (builtins.getAttr name value)
    ) profileNames;

  validateMetadata =
    context: protocol: value:
    let
      rawMetadata = if builtins.isAttrs value then value else { };
      allowedKeys = metadataKeys.${protocol} or [ ];
      schemaFields = lib.unique (lib.concatLists (builtins.attrValues metadataKeys));
      metadata = lib.filterAttrs (
        name: item:
        builtins.elem name allowedKeys
        || !(builtins.elem name schemaFields && (item == null || item == [ ] || item == { }))
      ) rawMetadata;
    in
    if !builtins.isAttrs metadata then
      fail context "transportMetadata must be an attrset"
    else if !(attrsHaveOnly metadataKeys.${protocol} metadata) then
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
        || !allStrings (metadata.userNames or [ ])
        || !isNonEmptyString (metadata.obfsName or null)
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
        || !validPeerPublicKeys (metadata.peerPublicKeys or { })
        || !(builtins.isNull (metadata.mtu or null) || builtins.isInt (metadata.mtu or null))
        || !builtins.hasAttr "extraOptions" metadata
        || !validAwgExtraOptions metadata.extraOptions
      )
    then
      fail context "AmneziaWG public transport metadata is incomplete"
    else
      metadata;

  validateProvider =
    {
      providerMachine,
      providerInstanceId,
      providerRole,
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
      expectedSecretNames = {
        naiveproxy = [ "password" ];
        vless-xhttp = [
          "realityPrivateKey"
          "vlessUuid"
        ];
        hysteria2 = [
          "users"
          "obfsPassword"
        ];
        amneziawg = [ "clientPrivateKey" ];
      };
      validSecretNames =
        builtins.isAttrs secretNames
        && attrsHaveExactly expectedSecretNames.${protocol} secretNames
        && (
          if protocol == "naiveproxy" then
            credentialMapExact metadata.userNames secretNames.password
          else if protocol == "vless-xhttp" then
            isNonEmptyString (secretNames.realityPrivateKey or null)
            && credentialMapExact (raw.profileNames or [ ]) secretNames.vlessUuid
          else if protocol == "hysteria2" then
            isNonEmptyString (secretNames.obfsPassword or null)
            && credentialMapExact metadata.userNames secretNames.users
          else if protocol == "amneziawg" then
            credentialMapExact (raw.profileNames or [ ]) secretNames.clientPrivateKey
          else
            false
        );
      validShape =
        builtins.isAttrs raw
        && attrsHaveExactly requiredFields raw
        && raw.schemaVersion == 1
        && raw.instanceId == providerInstanceId
        && raw.machine == providerMachine
        && raw.role == providerRole
        && raw.role == expectedRole
        && raw.protocol == protocol
        && raw.enabled == true
        && builtins.isAttrs endpoint
        && attrsHaveExactly [ "domain" "ipv4" "port" "transport" ] endpoint
        && isNonEmptyString endpoint.domain
        && (builtins.isNull endpoint.ipv4 || isNonEmptyString endpoint.ipv4)
        && builtins.isInt endpoint.port
        && endpoint.port > 0
        && isNonEmptyString endpoint.transport
        && allStrings (raw.profileNames or [ ])
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
        && isNonEmptyString (value.name or null)
        && isNonEmptyString (value.label or null)
        && isNonEmptyString (value.accountDomain or null);
    in
    if !builtins.isAttrs raw || !(attrsHaveExactly fields raw) then
      fail context "vpnPublisher export shape is not the closed allowlist"
    else if
      raw.schemaVersion != 1
      || raw.instanceId != context.providerInstanceId
      || raw.machine != context.providerMachine
      || raw.role != "publisher"
      || raw.enabled != true
      || !isNonEmptyString (raw.accountDomain or null)
      || raw.pagePath != "/config-links/"
      || !builtins.isList (raw.profileLinks or [ ])
      || !(builtins.all validProfileLink (raw.profileLinks or [ ]))
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
      providerRole,
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
                  && scope.roleName == providerRole
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
    else if providerRole != expectedRole then
      fail context "provider role does not match the closed protocol-role table"
    else if raw == null then
      fail context "provider is missing, disabled-retained or has no active export"
    else
      validateProvider (context // { inherit providerRole; }) raw;

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
