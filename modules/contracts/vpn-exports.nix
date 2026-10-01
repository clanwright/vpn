{ lib }:
let
  inherit (lib) types;
  identities = import ./identities.nix { inherit lib; };
  policy = import ./protocol-policy.nix;
  schemaVersion = 3;
  mkOption = type: lib.mkOption { inherit type; };
  # Preserve the module system's closed defaults. Validate each native option
  # on consumption, while documentation may still inspect options with its
  # intentional check=false module without evaluating payload values.
  closedOptions =
    config: nativeOptions: declaredOptions:
    let
      allowedNames = [ "_module" ] ++ builtins.attrNames declaredOptions;
    in
    lib.mapAttrs (
      _name: option:
      option
      // {
        apply =
          value:
          if
            !config._module.check
            || nativeOptions._module.check.highestPrio != (lib.mkOptionDefault true).priority
            || builtins.length nativeOptions._module.check.definitionsWithLocations != 1
            || lib.subtractLists allowedNames (builtins.attrNames nativeOptions) != [ ]
            || lib.subtractLists allowedNames (builtins.attrNames config) != [ ]
          then
            throw "vpnProvider cannot extend its closed schema or override native option checking"
          else
            (option.apply or lib.id) value;
      }
    ) declaredOptions
    // {
      _module.freeformType = lib.mkOption { readOnly = true; };
    };
  submodule =
    declaredOptions:
    types.submodule (
      { config, options, ... }: {
        options = closedOptions config options declaredOptions;
      }
    );

  inherit (import ./address-validation.nix { inherit lib; }) validHostname validIPv4;
  hostnameType = types.addCheck types.nonEmptyStr validHostname;
  ipv4Type = types.addCheck types.nonEmptyStr validIPv4;
  realityPublicKeyType = types.strMatching "[A-Za-z0-9_-]{43}";
  wireguardPublicKeyType = types.strMatching "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=";
  shortIdType = types.strMatching "[0-9a-f]{16}";
  httpPathType = types.strMatching "/[^[:space:]]*";
  ipEndpointOptions = {
    ipv4 = mkOption ipv4Type;
    port = mkOption (types.ints.between 1 65535);
  };
  endpointType = submodule (ipEndpointOptions // { hostname = mkOption hostnameType; });
  allUnique = values: builtins.length values == builtins.length (lib.unique values);

  # Check the effective merged map, so split definitions cannot share one
  # credential, short ID or AWG address between distinct device identities.
  checkClients =
    uniqueFields: clients:
    builtins.deepSeq clients (
      if
        clients != { }
        && builtins.all identities.safeIdentity (builtins.attrNames clients)
        && builtins.all (
          field: allUnique (map (client: client.${field}) (builtins.attrValues clients))
        ) uniqueFields
      then
        clients
      else
        throw "vpnProvider clients require safe nonempty identities and distinct credential bindings and device identifiers"
    );
  clientsOption =
    clientOptions: uniqueFields:
    lib.mkOption {
      type = types.attrsOf (submodule clientOptions);
      apply = checkClients uniqueFields;
    };
  passwordClients = clientsOption {
    passwordSecret = mkOption identities.safeSecretNameType;
  } [ "passwordSecret" ];
  passwordPayload =
    endpoint:
    submodule {
      inherit endpoint;
      clients = passwordClients;
    };
  connectionType = types.attrTag {
    naiveproxy = mkOption (passwordPayload (mkOption endpointType));
    mieru = mkOption (passwordPayload (mkOption (submodule ipEndpointOptions)));
    anytls = mkOption (passwordPayload (mkOption endpointType));
    trusttunnel = mkOption (passwordPayload (mkOption endpointType));
    vless-xhttp = mkOption (submodule {
      endpoint = mkOption endpointType;
      clients =
        clientsOption
          {
            uuidSecret = mkOption identities.safeSecretNameType;
            shortId = mkOption shortIdType;
          }
          [
            "uuidSecret"
            "shortId"
          ];
      reality = mkOption (submodule {
        serverName = mkOption hostnameType;
        publicKey = mkOption realityPublicKeyType;
        fingerprint = mkOption types.nonEmptyStr;
        supportX25519MLKEM768 = mkOption types.bool;
      });
      xhttp = mkOption (submodule {
        path = mkOption httpPathType;
      });
      doh = mkOption (submodule {
        hostname = mkOption hostnameType;
        ipv4 = mkOption ipv4Type;
      });
    });
    amneziawg = mkOption (
      types.submodule (
        { config, options, ... }:
        {
          options = closedOptions config options {
            endpoint = mkOption endpointType;
            serverPublicKey = mkOption wireguardPublicKeyType;
            headerProtectionKeySecret = mkOption identities.safeSecretNameType;
            clients =
              (clientsOption
                {
                  ipv4 = mkOption ipv4Type;
                  privateKeySecret = mkOption identities.safeSecretNameType;
                  keepaliveSeconds = lib.mkOption {
                    type = types.nullOr (types.ints.between 1 65535);
                    default = null;
                  };
                }
                [
                  "privateKeySecret"
                  "ipv4"
                ]
              )
              // {
                apply =
                  clients:
                  let
                    checked = checkClients [ "privateKeySecret" "ipv4" ] clients;
                  in
                  if
                    builtins.elem config.headerProtectionKeySecret (
                      map (client: client.privateKeySecret) (builtins.attrValues checked)
                    )
                  then
                    throw "vpnProvider AWG header and client private keys require distinct secret bindings"
                  else
                    checked;
              };
          };
        }
      )
    );
  };

  vpnProviderModule =
    { config, options, ... }:
    {
      options = closedOptions config options {
        schemaVersion = (mkOption (types.enum [ schemaVersion ])) // {
          # Reading the version must also check the complete closed payload.
          apply = value: builtins.deepSeq config.connection value;
        };
        connection = (mkOption connectionType) // {
          apply = value: builtins.deepSeq value value;
        };
      };
    };
  evalProvider =
    value:
    (lib.evalModules {
      modules = [
        { options.provider = mkOption (types.submodule vpnProviderModule); }
        { config.provider = value; }
      ];
    }).config.provider;
in
{
  inherit schemaVersion vpnProviderModule;

  selectVpnProvider =
    {
      providerInstanceId,
      providerMachine,
      selectExports,
      exports,
      consumerInstanceId ? "unknown-consumer",
    }:
    let
      fail =
        reason:
        throw (
          "vpn integration requires an active provider with machine='${providerMachine}', "
          + "instance='${providerInstanceId}', consumer='${consumerInstanceId}': ${reason}"
        );
      selectedScopes = lib.concatMap (
        tag:
        let
          metadata = policy.protocols.${tag};
          matching = selectExports (
            scope:
            scope.serviceName == metadata.service
            && scope.roleName == metadata.role
            && scope.machineName == providerMachine
            && scope.instanceName == providerInstanceId
          ) exports;
        in
        if !builtins.isAttrs matching then
          fail "Clan selectExports did not return a scoped attrset"
        else
          map (name: {
            inherit tag;
            export = matching.${name};
          }) (builtins.attrNames matching)
      ) (builtins.attrNames policy.protocols);
      selected = builtins.head selectedScopes;
      raw =
        if builtins.isAttrs selected.export && selected.export ? vpnProvider then
          selected.export.vpnProvider
        else
          fail "selected provider export is missing the declared vpnProvider interface";
      provider = evalProvider raw;
    in
    if !identities.safeIdentity providerMachine || !identities.safeIdentity providerInstanceId then
      fail "provider machine and instance identities are unsafe"
    else if !builtins.isFunction selectExports then
      fail "Clan selectExports selector is unavailable"
    else if !builtins.isAttrs exports then
      fail "Clan provider exports are unavailable"
    else if builtins.length selectedScopes != 1 then
      fail "provider scope selection matched ${toString (builtins.length selectedScopes)} exports; expected exactly one"
    else
      builtins.deepSeq provider (
        if builtins.attrNames provider.connection != [ selected.tag ] then
          fail "connection tag does not match the selected native service and role"
        else
          {
            machine = providerMachine;
            instanceId = providerInstanceId;
            inherit (provider) connection;
          }
      );
}
