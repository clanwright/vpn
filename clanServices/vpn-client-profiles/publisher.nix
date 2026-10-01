{ lib }:
let
  types = import ./types.nix { inherit lib; };
  vpnExports = import ../../modules/contracts/vpn-exports.nix { inherit lib; };
  inherit (types) linksPageDefaults;
  publisherDefaults = {
    enable = false;
    localMachineName = "";
    configGatewayDomain = null;
    publicIPv4 = null;
    edgeDomain = null;
    clientDnsEndpoints = null;
    tailnetAdminDomains = [ ];
    personalProxyDomains = [ ];
    profiles = [ ];
    providerRefs = [ ];
    externalSubscriptions = { };
    profileLinks = [ ];
    linksPage = linksPageDefaults;
  };
  profileClientsFor =
    publisherProfileNames: ref: provider:
    let
      selected = ref.clients or { };
      connection = builtins.head (builtins.attrValues provider.connection);
      unknownProfiles = lib.subtractLists publisherProfileNames (builtins.attrNames selected);
      unknownAccounts = lib.subtractLists (builtins.attrNames connection.clients) (
        builtins.attrValues selected
      );
    in
    if !types.validProfileClients selected then
      throw "vpn-client-profiles: ${ref.machine}/${ref.instanceId} clients must be a non-empty injective map of safe profile and account identities"
    else if unknownProfiles != [ ] then
      throw "vpn-client-profiles: provider ref selects undeclared publisher profiles: ${lib.concatStringsSep ", " unknownProfiles}"
    else if unknownAccounts != [ ] then
      throw "vpn-client-profiles: provider ref selects unknown accounts: ${lib.concatStringsSep ", " unknownAccounts}"
    else
      selected;
  publisherProfileOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = publisherDefaults.enable;
    };
    localMachineName = lib.mkOption {
      type = types.optionalSafeIdentityType;
      default = publisherDefaults.localMachineName;
    };
    configGatewayDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.configGatewayDomain;
      description = "Consumer gateway domain embedded into generated client templates.";
    };
    publicIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.publicIPv4;
      description = "Consumer public IPv4 embedded into generated client templates.";
    };
    edgeDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.edgeDomain;
      description = "Consumer edge domain embedded into generated client templates.";
    };
    clientDnsEndpoints = lib.mkOption {
      type = lib.types.nullOr types.clientDnsEndpointsType;
      default = publisherDefaults.clientDnsEndpoints;
      description = "Consumer-owned DNS-over-HTTPS endpoints; null preserves the edgeDomain/publicIPv4 endpoint.";
    };
    tailnetAdminDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = publisherDefaults.tailnetAdminDomains;
    };
    personalProxyDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = publisherDefaults.personalProxyDomains;
      description = "Consumer-owned domain suffixes routed by the selective profile.";
    };
    profiles = lib.mkOption {
      type = lib.types.listOf types.profileType;
      default = publisherDefaults.profiles;
    };
    providerRefs = lib.mkOption {
      type = lib.types.listOf types.providerRefType;
      default = publisherDefaults.providerRefs;
    };
    externalSubscriptions = lib.mkOption {
      type = types.externalSubscriptionsType;
      apply =
        sources:
        if builtins.all (name: types.safeIdentityType.check name) (builtins.attrNames sources) then
          sources
        else
          throw "vpn-client-profiles: external subscription IDs must be safe identities.";
      default = publisherDefaults.externalSubscriptions;
      description = "Profile-scoped external connections; subscription URLs are runtime secrets.";
    };
    profileLinks = lib.mkOption {
      type = lib.types.listOf types.profileLinkType;
      default = publisherDefaults.profileLinks;
    };
    linksPage = lib.mkOption {
      type = types.linksPageType;
      default = publisherDefaults.linksPage;
    };
  };
  interface = _: { options = publisherProfileOptions; };
  compile =
    {
      pkgs,
      settings,
      instanceName,
      exports,
      selectExports,
    }:
    let
      typedSettings =
        (lib.evalModules {
          modules = [
            (interface { })
            { config = settings; }
          ];
        }).config;
      publisher = typedSettings // {
        clientDnsEndpoints =
          if typedSettings.enable then
            types.normalizeClientDnsEndpoints typedSettings
          else
            typedSettings.clientDnsEndpoints;
      };
      active = publisher.enable;
      runtimeMachineName = publisher.localMachineName;
      inherit (publisher) providerRefs;
      publisherProfileNames = map (profile: profile.name) publisher.profiles;
      providerRefKeys = map (ref: "${ref.machine}/${ref.instanceId}") providerRefs;
      profileLinkNames = map (link: link.name) publisher.profileLinks;
      profilePathTokenSecretNames = map (profile: profile.pathTokenSecretName) publisher.profiles;
      ownDisplayLabels = map (
        ref: if ref.display == null then ref.machine else ref.display.label
      ) providerRefs;
      externalDisplayLabels = lib.mapAttrsToList (
        sourceId: source: if source.label == null then sourceId else source.label
      ) publisher.externalSubscriptions;
      providers =
        if !active then
          [ ]
        else
          map (
            ref:
            let
              provider = vpnExports.selectVpnProvider {
                providerInstanceId = ref.instanceId;
                providerMachine = ref.machine;
                consumerInstanceId = instanceName;
                inherit selectExports exports;
              };
            in
            provider
            // {
              profileClients = profileClientsFor publisherProfileNames ref provider;
              inherit (ref) display;
            }
          ) providerRefs;
      assertions = [
        {
          assertion = builtins.all (
            source: lib.subtractLists publisherProfileNames source.profileNames == [ ]
          ) (builtins.attrValues publisher.externalSubscriptions);
          message = "vpn-client-profiles: external subscriptions may reference only declared profiles.";
        }
        {
          assertion = builtins.all (label: !(builtins.elem label ownDisplayLabels)) externalDisplayLabels;
          message = "vpn-client-profiles: external subscription labels, including ID fallbacks, must differ from provider display labels and machine-name fallbacks.";
        }
        {
          assertion = !active || runtimeMachineName != "";
          message = "vpn-client-profiles: localMachineName is required when publishing is enabled.";
        }
        {
          assertion = !active || publisher.configGatewayDomain != null;
          message = "vpn-client-profiles: configGatewayDomain is required when publishing is enabled.";
        }
        {
          assertion = !active || publisher.publicIPv4 != null;
          message = "vpn-client-profiles: publicIPv4 is required when publishing is enabled.";
        }
        {
          assertion = !active || publisher.edgeDomain != null;
          message = "vpn-client-profiles: edgeDomain is required when publishing is enabled.";
        }
        {
          assertion =
            !active || builtins.deepSeq publisher.clientDnsEndpoints (publisher.clientDnsEndpoints != [ ]);
          message = "vpn-client-profiles: enabled publisher requires at least one valid client DNS endpoint.";
        }
        {
          assertion = !active || providerRefs != [ ];
          message = "vpn-client-profiles: enabled publisher requires explicit providerRefs.";
        }
        {
          assertion = !active || publisher.profiles != [ ];
          message = "vpn-client-profiles: enabled publisher requires explicit profiles.";
        }
        {
          assertion = publisherProfileNames == lib.unique publisherProfileNames;
          message = "vpn-client-profiles: profile names must be unique.";
        }
        {
          assertion = providerRefKeys == lib.unique providerRefKeys;
          message = "vpn-client-profiles: providerRefs must be unique by machine and instance.";
        }
        {
          assertion = profileLinkNames == lib.unique profileLinkNames;
          message = "vpn-client-profiles: profile link names must be unique.";
        }
        {
          assertion = profilePathTokenSecretNames == lib.unique profilePathTokenSecretNames;
          message = "vpn-client-profiles: each profile requires a distinct path-token secret.";
        }
        {
          assertion = lib.subtractLists publisherProfileNames profileLinkNames == [ ];
          message = "vpn-client-profiles: profile links may reference only declared profiles.";
        }
      ];
      errors = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
      validatedSettings = builtins.deepSeq typedSettings (
        if errors != [ ] then
          throw (lib.concatStringsSep "\n" errors)
        else
          builtins.deepSeq providers publisher
      );
    in
    {
      settings = validatedSettings;
      manifest =
        if !validatedSettings.enable then
          {
            schemaVersion = 1;
            assetCatalog = { };
            profiles = [ ];
          }
        else
          (import ./client-profiles.nix {
            inherit lib pkgs providers;
            settings = validatedSettings;
          }).manifest;
    };
in
{
  inherit interface compile;
}
