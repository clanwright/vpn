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
    caddyBindIPv4 = null;
    tailnetIPv4 = null;
    edgeDomain = null;
    acmeCertName = null;
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
    };
    publicIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.publicIPv4;
    };
    caddyBindIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.caddyBindIPv4;
    };
    tailnetIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.tailnetIPv4;
      description = "Tailnet IPv4 address for the dedicated profile listener.";
    };
    edgeDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.edgeDomain;
    };
    acmeCertName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = publisherDefaults.acmeCertName;
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
    interface = _: {
      options = publisherProfileOptions;
    };

    perInstance =
      {
        settings,
        instanceName ? "vpn-client-profiles",
        exports ? { },
        mkExports ? (value: value),
        ...
      }:
      let
        publisher =
          publisherDefaults
          // settings
          // {
            linksPage = linksPageDefaults // (settings.linksPage or { });
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
              provider // { profileNames = profileNamesFor ref provider; }
            ) providerRefs;
        runtimeMachineName = publisher.localMachineName;
        inherit (publisher) profiles;
        publisherProfileNames = map (profile: profile.name) profiles;
        providerRefKeys = map (ref: "${ref.machine}/${ref.instanceId}/${ref.protocol}") providerRefs;
        profileLinkNames = map (link: link.name) publisher.profileLinks;
        profileLinkSecretNames = map (link: link.pathTokenSecretName) publisher.profileLinks;
        publisherMetadata = {
          schemaVersion = 1;
          instanceId = instanceName;
          machine = publisher.localMachineName;
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
          {
            config,
            pkgs,
            ...
          }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            appsPkgs = appsPkgsFor system;
            mihomoPackage = mihomoPackageFor system;
            clientProfilesModule = import ./client-profiles.nix {
              inherit
                config
                appsPkgs
                lib
                mihomoPackage
                pkgs
                ;
              settings = publisher;
              inherit providers;
            };
            linksPageEnabled = active && publisher.linksPage.enable;
            linksServiceName = "vpn-client-profiles-links-${runtimeMachineName}";
            linkSecretDecls =
              lib.genAttrs (lib.unique (map (link: link.pathTokenSecretName) profileLinks))
                (_name: {
                  format = lib.mkDefault "binary";
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  restartUnits = [ "${linksServiceName}.service" ];
                });
            linksRoot = "/run/mihomo-client-config/${runtimeMachineName}/config-links";
            caddyBindIPv4 =
              if publisher.caddyBindIPv4 == null then publisher.publicIPv4 else publisher.caddyBindIPv4;
            inherit (publisher) profileLinks;
            profileLinkLine =
              link:
              let
                declared = config.sops.secrets.${link.pathTokenSecretName}.path;
                matchingProfiles = builtins.filter (
                  profile: profile.name == link.name
                ) clientProfilesModule.renderedProfiles;
                declaredProfile = if matchingProfiles == [ ] then null else builtins.head matchingProfiles;
                jsonLine =
                  if declaredProfile != null && declaredProfile.publishProfileJson then
                    ''printf '<li><a href="https://%s/%s/profile.json">%s (profile.json)</a></li>\n' ${lib.escapeShellArg link.accountDomain} "$token" ${lib.escapeShellArg link.label}''
                  else
                    "";
              in
              ''
                token="$(read_path_token ${lib.escapeShellArg declared})"
                token="$(printf '%s' "$token" | jq -sRr @uri)"
                printf '<li><a href="https://%s/%s/mihomo.yaml">%s (mihomo.yaml)</a></li>\n' ${lib.escapeShellArg link.accountDomain} "$token" ${lib.escapeShellArg link.label}
                printf '<li><a href="https://%s/%s/mihomo-full.yaml">%s (mihomo-full.yaml)</a></li>\n' ${lib.escapeShellArg link.accountDomain} "$token" ${lib.escapeShellArg link.label}
                ${jsonLine}
              '';
            linksPageFragment =
              if publisher.linksPage.tailnetOnly then
                ''
                  @vpn_client_profile_links {
                    path ${publisher.linksPage.path} ${publisher.linksPage.path}*
                  }
                  @wrong_listener_config_links {
                    expression `{http.request.local.host} != "${publisher.tailnetIPv4}"`
                    path ${publisher.linksPage.path} ${publisher.linksPage.path}*
                  }
                  handle @vpn_client_profile_links {
                    route {
                      respond @wrong_listener_config_links 404
                      root * ${linksRoot}
                      rewrite * /index.html
                      header Cache-Control "no-store"
                      file_server
                    }
                  }
                ''
              else
                ''
                  handle ${publisher.linksPage.path} {
                    root * ${linksRoot}
                    rewrite * /index.html
                    header Cache-Control "no-store"
                    file_server
                  }
                '';
            linksService = {
              description = "Render publisher-owned client profile links page";
              before = [ "caddy.service" ];
              requiredBy = [ "caddy.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = "root";
                Group = "root";
                UMask = "0027";
              };
              path = [
                pkgs.coreutils
                pkgs.jq
                pkgs.systemd
              ];
              script = ''
                set -euo pipefail
                read_secret() { tr -d '\r\n' < "$1"; }
                read_path_token() {
                  local value byte_count
                  value="$(cat "$1")"
                  byte_count="$(LC_ALL=C wc -c < "$1")"
                  byte_count="''${byte_count//[[:space:]]/}"
                  if [ "''${#value}" -ne "$byte_count" ]; then
                    printf 'Profile path token must not contain a trailing newline or NUL byte\n' >&2
                    exit 1
                  fi
                  if [[ ! "$value" =~ ^[A-Za-z0-9_-]{32,128}$ ]]; then
                    printf 'Profile path token must be 32-128 unpadded base64url characters\n' >&2
                    exit 1
                  fi
                  printf '%s' "$value"
                }
                install -d -m 0750 -o root -g caddy ${lib.escapeShellArg linksRoot}
                tmp="$(mktemp ${lib.escapeShellArg linksRoot}/.index.XXXXXX.html)"
                trap 'rm -f "$tmp"' EXIT
                {
                  printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head><body><h1>%s</h1><ul>\n' ${lib.escapeShellArg publisher.linksPage.title} ${lib.escapeShellArg publisher.linksPage.title}
                  ${lib.concatMapStringsSep "\n" profileLinkLine profileLinks}
                  printf '</ul></body></html>\n'
                } > "$tmp"
                install -o root -g caddy -m 0440 "$tmp" ${lib.escapeShellArg "${linksRoot}/index.html"}
                fragment="/run/caddy-auth/mihomo-client-links-${runtimeMachineName}.caddy"
                fragment_tmp="$(mktemp /run/caddy-auth/.mihomo-client-links.XXXXXX)"
                trap 'rm -f "$tmp" "$fragment_tmp"' EXIT
                printf '%s\n' ${lib.escapeShellArg linksPageFragment} > "$fragment_tmp"
                install -o root -g caddy -m 0640 "$fragment_tmp" "$fragment"
                ${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart caddy.service
              '';
            };
          in
          {
            _module.args.vpnClientProfileRender = clientProfilesModule.renderedProfiles;
            assertions = [
              {
                assertion = !active || publisher.localMachineName != "";
                message = "vpn-client-profiles: localMachineName is required when profile publishing is enabled.";
              }
              {
                assertion = !active || publisher.configGatewayDomain != null;
                message = "vpn-client-profiles: configGatewayDomain is required when profile publishing is enabled.";
              }
              {
                assertion = !active || publisher.publicIPv4 != null;
                message = "vpn-client-profiles: publicIPv4 is required when profile publishing is enabled.";
              }
              {
                assertion = !active || publisher.tailnetIPv4 != null;
                message = "vpn-client-profiles: tailnetIPv4 is required when profile publishing is active.";
              }
              {
                assertion = !active || publisher.edgeDomain != null;
                message = "vpn-client-profiles: edgeDomain is required when profile publishing is enabled.";
              }
              {
                assertion = !active || publisher.acmeCertName != null;
                message = "vpn-client-profiles: acmeCertName is required when profile publishing is enabled.";
              }
              {
                assertion = !active || publisher.secretPrefix != "";
                message = "vpn-client-profiles: secretPrefix is required when profile publishing is enabled.";
              }
              {
                assertion = !active || providerRefs != [ ];
                message = "vpn-client-profiles: enabled publisher requires explicit providerRefs.";
              }
              {
                assertion = !active || profiles != [ ];
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
                message = "vpn-client-profiles: each profile link must use the profile renderer's path-token secret.";
              }
              {
                assertion = lib.subtractLists publisherProfileNames profileLinkNames == [ ];
                message = "vpn-client-profiles: profile links may reference only declared profiles.";
              }
            ];
            sops.secrets = lib.mkIf active (
              lib.mkMerge [
                clientProfilesModule.sops.secrets
                (lib.mkIf linksPageEnabled linkSecretDecls)
              ]
            );
            systemd = {
              tmpfiles.rules = lib.mkIf active clientProfilesModule.systemd.tmpfiles.rules;
              timers = lib.mkIf active clientProfilesModule.systemd.timers;
              services = lib.mkIf active (
                {
                  caddy =
                    clientProfilesModule.systemd.services.caddy
                    // lib.optionalAttrs linksPageEnabled {
                      requires = (clientProfilesModule.systemd.services.caddy.requires or [ ]) ++ [
                        "${linksServiceName}.service"
                      ];
                      after = (clientProfilesModule.systemd.services.caddy.after or [ ]) ++ [
                        "${linksServiceName}.service"
                      ];
                    };
                  "mihomo-client-caddy-${runtimeMachineName}" =
                    clientProfilesModule.systemd.services."mihomo-client-caddy-${runtimeMachineName}";
                  "mihomo-client-hagezi-doh-${runtimeMachineName}" =
                    clientProfilesModule.systemd.services."mihomo-client-hagezi-doh-${runtimeMachineName}";
                  "mihomo-client-ruleset-mirror-${runtimeMachineName}" =
                    clientProfilesModule.systemd.services."mihomo-client-ruleset-mirror-${runtimeMachineName}";
                }
                // lib.optionalAttrs linksPageEnabled {
                  ${linksServiceName} = linksService;
                }
              );
            };
            networkCore =
              lib.optionalAttrs
                (
                  active
                  && publisher.tailnetIPv4 != null
                  && caddyBindIPv4 != null
                  && publisher.configGatewayDomain != null
                  && publisher.acmeCertName != null
                )
                {
                  caddy.fragments.${instanceName} = {
                    hostName = publisher.configGatewayDomain;
                    listenAddresses = [
                      caddyBindIPv4
                      publisher.tailnetIPv4
                    ];
                    useACMEHost = publisher.acmeCertName;
                    afterUnits = [
                      "tailscaled.service"
                      "tailscaled-autoconnect.service"
                    ];
                    wantsUnits = [
                      "tailscaled.service"
                      "tailscaled-autoconnect.service"
                    ];
                    logFile = "/var/log/caddy/mihomo-client-${runtimeMachineName}-access.log";
                    extraConfig = ''
                      bind ${caddyBindIPv4} ${publisher.tailnetIPv4}
                      tls /var/lib/acme/${publisher.acmeCertName}/fullchain.pem /var/lib/acme/${publisher.acmeCertName}/key.pem
                      import /run/caddy-auth/mihomo-client-${runtimeMachineName}.caddy
                      ${lib.optionalString linksPageEnabled "import /run/caddy-auth/mihomo-client-links-${runtimeMachineName}.caddy"}
                      handle {
                        respond 404
                      }
                    '';
                  };
                  acme.reloadServices.${publisher.acmeCertName} = [ "caddy.service" ];
                };
          };
      };
  };
}
