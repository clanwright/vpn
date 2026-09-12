{
  clanLib ? null,
  appsPkgsFor ? (_system: throw "vpn-client-profiles requires an explicit appsPkgsFor dependency"),
  mihomoPackageFor ? (
    _system: throw "vpn-client-profiles requires an explicit mihomoPackageFor dependency"
  ),
  lib,
  ...
}:
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
    secretPrefix = "";
    excludedProfileNames = [ "probe" ];
    tailnetAdminDomains = [ ];
    personalProxyDomains = [ ];
    profiles = [ ];
    providerRefs = [ ];
    profileLinks = [ ];
    linksPage = linksPageDefaults;
  };
  profileNamesFor =
    ref: provider:
    let
      selected = if ref.profileNames == [ ] then provider.profileNames else ref.profileNames;
      unknown = lib.subtractLists provider.profileNames selected;
    in
    if selected != lib.unique selected then
      throw "vpn-client-profiles: duplicate profileNames in ${ref.machine}/${ref.instanceId}"
    else if unknown != [ ] then
      throw "vpn-client-profiles: provider ref selects unknown profiles: ${lib.concatStringsSep ", " unknown}"
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
    secretPrefix = lib.mkOption {
      type = types.optionalSafeIdentityType;
      default = publisherDefaults.secretPrefix;
    };
    excludedProfileNames = lib.mkOption {
      type = lib.types.listOf types.safeIdentityType;
      default = publisherDefaults.excludedProfileNames;
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
    profileLinks = lib.mkOption {
      type = lib.types.listOf types.profileLinkType;
      default = publisherDefaults.profileLinks;
    };
    linksPage = lib.mkOption {
      type = types.linksPageType;
      default = publisherDefaults.linksPage;
    };
  };
in
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-client-profiles";
    description = "Typed Mihomo and Sing-box client profile publisher";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnPublisher" ];
  };
  roles.publisher = {
    description = "Publish client profiles from explicit non-secret provider exports";
    interface = _: { options = publisherProfileOptions; };
    perInstance =
      {
        settings,
        instanceName ? "vpn-client-profiles",
        exports ? { },
        mkExports ? (value: value),
        ...
      }:
      let
        publisherRaw =
          publisherDefaults // settings // { linksPage = linksPageDefaults // (settings.linksPage or { }); };
        publisher = publisherRaw // {
          clientDnsEndpoints =
            if publisherRaw.enable then
              types.normalizeClientDnsEndpoints publisherRaw
            else
              publisherRaw.clientDnsEndpoints;
        };
        providerRefs = publisher.providerRefs or [ ];
        active = publisher.enable;
        providerFor =
          ref:
          vpnExports.selectVpnProvider {
            providerInstanceId = ref.instanceId;
            providerMachine = ref.machine;
            inherit (ref) protocol;
            consumerInstanceId = instanceName;
            selectExports = if clanLib == null then null else clanLib.selectExports;
            inherit exports;
          };
        providers =
          if !active then
            [ ]
          else
            map (
              ref:
              let
                provider = providerFor ref;
              in
              provider
              // {
                profileNames = profileNamesFor ref provider;
              }
            ) providerRefs;
        runtimeMachineName = publisher.localMachineName;
        publisherProfileNames = map (profile: profile.name) publisher.profiles;
        providerRefKeys = map (ref: "${ref.machine}/${ref.instanceId}/${ref.protocol}") providerRefs;
        profileLinkNames = map (link: link.name) publisher.profileLinks;
        profileLinkSecretNames = map (link: link.pathTokenSecretName) publisher.profileLinks;
        publisherMetadata = {
          schemaVersion = 1;
          instanceId = instanceName;
          machine = runtimeMachineName;
          role = "publisher";
          enabled = active;
          accountDomain = publisher.configGatewayDomain;
          pagePath = publisher.linksPage.path;
          profileLinks = map (
            link: builtins.removeAttrs link [ "pathTokenSecretName" ]
          ) publisher.profileLinks;
        };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnPublisher = publisherMetadata;
        });
        nixosModule =
          { config, pkgs, ... }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            appsPkgs = appsPkgsFor system;
            mihomoPackage = mihomoPackageFor system;
            readerGroup = "vpn-client-profiles";
            runtimeBase = "/run/vpn-client-profiles/${runtimeMachineName}";
            profileRoot = "${runtimeBase}/published/current";
            linksRoot = "${profileRoot}/links";
            assetRoot = "/var/lib/vpn-client-profiles/${runtimeMachineName}/assets";
            statusPath = "/var/lib/vpn-client-profiles/${runtimeMachineName}/status.json";
            publicationService = "vpn-client-profiles-publish-${runtimeMachineName}";
            refreshService = "vpn-client-profiles-public-assets-${runtimeMachineName}";
            publicationUnit = "${publicationService}.service";
            refreshUnit = "${refreshService}.service";
            matcherSuffix = lib.replaceStrings [ "_" "-" "." ] [ "_u" "_h" "_d" ] instanceName;
            render = import ./client-profiles.nix {
              inherit lib pkgs providers;
              settings = publisher;
            };
            publicAssets = import ./public-assets.nix {
              inherit
                lib
                pkgs
                appsPkgs
                assetRoot
                statusPath
                readerGroup
                refreshService
                ;
              inherit (render) manifest;
            };
            publication = import ./runtime-publication.nix {
              inherit
                config
                lib
                pkgs
                mihomoPackage
                runtimeBase
                profileRoot
                readerGroup
                publicationService
                refreshUnit
                ;
              settings = publisher;
              inherit (render) manifest renderedProfiles;
              inherit (publicAssets) requiredAssetPaths localAssetSyncScript;
            };
            assetRoute = path: filename: contentType: ''
              handle ${path} {
                root * ${assetRoot}
                rewrite * /${filename}
                header Content-Type "${contentType}"
                header Cache-Control "public, max-age=3600"
                header Referrer-Policy "no-referrer"
                header X-Robots-Tag "noindex, nofollow, noarchive"
                header X-Content-Type-Options "nosniff"
                file_server
              }
            '';
            routeConfig = ''
              log_skip

              @vpn_client_profile_yaml_${matcherSuffix} path_regexp ^/[A-Za-z0-9_-]{32,128}/mihomo(-full)?\.yaml$
              handle @vpn_client_profile_yaml_${matcherSuffix} {
                root * ${profileRoot}/profiles
                header Content-Type "text/yaml; charset=utf-8"
                header Content-Disposition "attachment"
                header Cache-Control "no-store"
                header Referrer-Policy "no-referrer"
                header X-Robots-Tag "noindex, nofollow, noarchive"
                header X-Content-Type-Options "nosniff"
                file_server
              }

              @vpn_client_profile_json_${matcherSuffix} path_regexp ^/[A-Za-z0-9_-]{32,128}/profile\.json$
              handle @vpn_client_profile_json_${matcherSuffix} {
                root * ${profileRoot}/profiles
                header Content-Type "application/json; charset=utf-8"
                header Content-Disposition "attachment; filename=profile.json"
                header Profile-Title "Edge"
                header profile-update-interval "24"
                header Cache-Control "no-store"
                header Referrer-Policy "no-referrer"
                header X-Robots-Tag "noindex, nofollow, noarchive"
                header X-Content-Type-Options "nosniff"
                file_server
              }

              ${lib.concatMapStringsSep "\n" (
                asset:
                lib.concatMapStringsSep "\n" (path: assetRoute path asset.filename asset.contentType) (
                  [ asset.publicPath ] ++ asset.legacyPublicPaths
                )
              ) publicAssets.referencedAssets}
            '';
            integration = {
              schemaVersion = 1;
              inherit
                profileRoot
                assetRoot
                linksRoot
                routeConfig
                publicationUnit
                refreshUnit
                statusPath
                readerGroup
                ;
              inherit (publisher) configGatewayDomain;
            };
            configuredPublisherRoots = map (value: value.profileRoot) (
              builtins.attrValues config.clanwright.vpn.publishers
            );
            configuredGatewayDomains = map (value: lib.toLower value.configGatewayDomain) (
              builtins.attrValues config.clanwright.vpn.publishers
            );
          in
          {
            imports = [ ./integration.nix ];
            config = {
              clanwright.vpn = {
                publishers = lib.mkIf active { ${instanceName} = integration; };
                publisherRenders = lib.mkIf active {
                  ${instanceName} = publication.renderedProfiles;
                };
                publisherManifests = lib.mkIf active {
                  ${instanceName} = render.manifest;
                };
                publisherPublicationPhases = lib.mkIf active {
                  ${instanceName} = publication.publicationPhases;
                };
              };
              users.groups.${readerGroup} = lib.mkIf active { };
              assertions = [
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
                  assertion = !active || publisher.secretPrefix != "";
                  message = "vpn-client-profiles: secretPrefix is required when publishing is enabled.";
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
                  message = "vpn-client-profiles: providerRefs must be unique by machine, instance and protocol.";
                }
                {
                  assertion = profileLinkNames == lib.unique profileLinkNames;
                  message = "vpn-client-profiles: profile link names must be unique.";
                }
                {
                  assertion = profileLinkSecretNames == lib.unique profileLinkSecretNames;
                  message = "vpn-client-profiles: each profile link requires a distinct path-token secret.";
                }
                {
                  assertion = builtins.all (
                    link: link.pathTokenSecretName == "mihomo-client-${publisher.secretPrefix}-${link.name}-path-token"
                  ) publisher.profileLinks;
                  message = "vpn-client-profiles: each profile link must use the profile renderer path-token secret.";
                }
                {
                  assertion = lib.subtractLists publisherProfileNames profileLinkNames == [ ];
                  message = "vpn-client-profiles: profile links may reference only declared profiles.";
                }
                {
                  assertion = !active || mihomoPackage == appsPkgs.mihomo;
                  message = "vpn-client-profiles: Mihomo must be the exact repository-selected stock package.";
                }
                {
                  assertion = !active || appsPkgs ? sing-box;
                  message = "vpn-client-profiles: public assets require the selected stock sing-box package.";
                }
                {
                  assertion =
                    !active
                    || builtins.length (builtins.filter (root: root == profileRoot) configuredPublisherRoots) == 1;
                  message = "vpn-client-profiles: localMachineName must be unique for every active publisher on a machine.";
                }
                {
                  assertion =
                    !active
                    ||
                      builtins.length (
                        builtins.filter (
                          domain: domain == lib.toLower publisher.configGatewayDomain
                        ) configuredGatewayDomains
                      ) == 1;
                  message = "vpn-client-profiles: configGatewayDomain must be unique for every active publisher on a machine.";
                }
              ];
              sops.secrets = lib.mkIf active publication.sops.secrets;
              systemd = {
                tmpfiles.rules = lib.mkIf active (
                  publicAssets.systemd.tmpfiles.rules ++ publication.systemd.tmpfiles.rules
                );
                timers = lib.mkIf active publicAssets.systemd.timers;
                services = lib.mkIf active (publicAssets.systemd.services // publication.systemd.services);
              };
            };
          };
      };
  };
}
