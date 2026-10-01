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
  publisherCompiler = import ./publisher.nix { inherit lib; };
in
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-client-profiles";
    description = "Typed Mihomo and Sing-box client profile publisher";
    readme = builtins.readFile ./README.md;
  };
  roles.publisher = {
    description = "Publish client profiles from explicit non-secret provider exports";
    inherit (publisherCompiler) interface;
    perInstance =
      {
        settings,
        instanceName,
        exports ? { },
        ...
      }:
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            compiled = publisherCompiler.compile {
              inherit
                pkgs
                settings
                instanceName
                exports
                ;
              selectExports = if clanLib == null then null else clanLib.selectExports;
            };
            publisher = compiled.settings;
            active = publisher.enable;
            runtimeMachineName = publisher.localMachineName;
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
              inherit (compiled) manifest;
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
              inherit (compiled) manifest;
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
            logConfig = ''
              log_skip
            '';
            routeConfig = ''
              route {
                @vpn_client_profile_site_${matcherSuffix} host ${publisher.configGatewayDomain}
                route @vpn_client_profile_site_${matcherSuffix} {
                  @vpn_client_profile_yaml_${matcherSuffix} path_regexp ^/[A-Za-z0-9_-]{32,128}/mihomo\.yaml$
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
                    asset: assetRoute asset.publicPath asset.filename asset.contentType
                  ) publicAssets.referencedAssets}
                }
              }
            '';
            integration = {
              schemaVersion = 2;
              inherit
                profileRoot
                assetRoot
                linksRoot
                logConfig
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
              clanwright.vpn.publishers = lib.mkIf active { ${instanceName} = integration; };
              users.groups.${readerGroup} = lib.mkIf active { };
              assertions = [
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
