{ lib, ... }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/vpn-naiveproxy";
    description = "NaiveProxy Caddy add-on for one typed public-site claim";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.addon = {
    description = "Attach one generated NaiveProxy forward-proxy fragment to an existing public-site claim";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to generate and attach the NaiveProxy Caddy fragment.";
          };

          machineName = lib.mkOption {
            type = lib.types.str;
            description = "Short machine token used in the fragment and systemd unit names.";
          };

          selectedPublicSiteClaim = lib.mkOption {
            type = lib.types.str;
            description = "Existing Caddy claim that is explicitly marked publicSite.";
          };

          selectedPublicSiteEndpoint = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                domain = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Primary hostname of the selected public-site claim, for client exports only.";
                };
                publicIPv4 = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Public endpoint IPv4 used by clients, for client exports only.";
                };
                caddyBindIPv4 = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Caddy listener IPv4 of the selected public-site claim, for ownership validation only.";
                };
              };
            });
            default = { };
            description = "Non-owning endpoint metadata that must match the selected claim.";
          };

          passwordSecretNames = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                ibelyasov = lib.mkOption {
                  type = lib.types.str;
                  description = "SOPS secret name for the ibelyasov forward-proxy credential.";
                };
                bsv = lib.mkOption {
                  type = lib.types.str;
                  description = "SOPS secret name for the bsv forward-proxy credential.";
                };
                probe = lib.mkOption {
                  type = lib.types.str;
                  description = "SOPS secret name for the dedicated probe credential.";
                };
              };
            });
            description = "Exactly three machine-scoped SOPS names consumed by forward_proxy basic_auth.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName ? "naiveproxy",
        machine ? {
          name = null;
        },
        mkExports ? (value: value),
        ...
      }:
      let
        active = settings.enable;
        providerMachine =
          if machine ? name && machine.name != null && machine.name != "" then
            machine.name
          else
            builtins.head (lib.splitString "--" instanceName);
        selectedPublicSiteEndpoint =
          settings.selectedPublicSiteEndpoint or {
            domain = "";
            publicIPv4 = "";
            caddyBindIPv4 = "";
          };
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = {
            schemaVersion = 1;
            instanceId = instanceName;
            machine = providerMachine;
            role = "addon";
            protocol = "naiveproxy";
            enabled = true;
            endpoint = {
              inherit (selectedPublicSiteEndpoint) domain;
              ipv4 = selectedPublicSiteEndpoint.publicIPv4;
              port = 443;
              transport = "tcp";
            };
            transportMetadata = {
              protocol = "naiveproxy";
              tlsServerName = selectedPublicSiteEndpoint.domain;
              userNames = [
                "ibelyasov"
                "bsv"
                "probe"
              ];
              port = 443;
            };
            profileNames = [
              "ibelyasov"
              "bsv"
            ];
            secretNames = {
              password = settings.passwordSecretNames;
            };
          };
        });
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            fragmentPath = "/run/caddy-auth/naiveproxy-${settings.machineName}.caddy";
            serviceName = "naiveproxy-caddy-fragment-${settings.machineName}";
            secretNames = builtins.attrValues settings.passwordSecretNames;
            selectedClaim =
              let
                claims = ((config.networkCore or { }).caddy or { }).fragments or { };
              in
              if builtins.hasAttr settings.selectedPublicSiteClaim claims then
                claims.${settings.selectedPublicSiteClaim}
              else
                null;
            selectedClaimPrimaryListenAddress =
              if selectedClaim == null || (selectedClaim.listenAddresses or [ ]) == [ ] then
                null
              else
                builtins.head selectedClaim.listenAddresses;
            secretPath = name: lib.escapeShellArg config.sops.secrets.${name}.path;
            restartUnits = [
              "${serviceName}.service"
              "caddy.service"
            ];
          in
          {
            assertions = [
              {
                assertion = !settings.enable || settings.machineName != "";
                message = "naiveproxy: machineName must not be empty when enabled.";
              }
              {
                assertion = !settings.enable || settings.selectedPublicSiteClaim != "";
                message = "naiveproxy: selectedPublicSiteClaim must not be empty when enabled.";
              }
              {
                assertion =
                  !settings.enable
                  || (
                    selectedClaim != null
                    && selectedPublicSiteEndpoint.domain != ""
                    && selectedPublicSiteEndpoint.domain == selectedClaim.hostName
                    && selectedPublicSiteEndpoint.publicIPv4 != ""
                    && selectedPublicSiteEndpoint.caddyBindIPv4 != ""
                    && selectedClaimPrimaryListenAddress != null
                    && selectedPublicSiteEndpoint.caddyBindIPv4 == selectedClaimPrimaryListenAddress
                  );
                message = "naiveproxy: selectedPublicSiteEndpoint must match the selected public-site claim domain/listen address.";
              }
              {
                assertion = !settings.enable || builtins.all (name: name != "") secretNames;
                message = "naiveproxy: password secret names must not be empty when enabled.";
              }
              {
                assertion = !settings.enable || lib.length (lib.unique secretNames) == 3;
                message = "naiveproxy: ibelyasov, bsv and probe secret names must be distinct.";
              }
            ];
          }
          // lib.optionalAttrs settings.enable {
            systemd.services.${serviceName} = {
              description = "Generate NaiveProxy Caddy auth fragment for ${settings.machineName}";
              before = [ "caddy.service" ];
              requiredBy = [ "caddy.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = "root";
                Group = "root";
                UMask = "0027";
              };
              path = [ pkgs.coreutils ];
              script = ''
                set -euo pipefail

                read_secret() {
                  tr -d '\n' < "$1"
                }

                install -d -m 0750 -o root -g caddy /run/caddy-auth
                fragment_tmp="$(mktemp /run/caddy-auth/.naiveproxy-${settings.machineName}.caddy.XXXXXX)"

                printf 'forward_proxy {\n  basic_auth ibelyasov %s\n  basic_auth bsv %s\n  basic_auth probe %s\n  hide_ip\n  hide_via\n  ports 80 443\n  probe_resistance\n}\n' \
                  "$(read_secret ${secretPath settings.passwordSecretNames.ibelyasov})" \
                  "$(read_secret ${secretPath settings.passwordSecretNames.bsv})" \
                  "$(read_secret ${secretPath settings.passwordSecretNames.probe})" \
                  > "$fragment_tmp"

                install -m 0640 -o root -g caddy "$fragment_tmp" ${lib.escapeShellArg fragmentPath}
                rm -f "$fragment_tmp"
              '';
            };

            sops.secrets = lib.genAttrs secretNames (name: {
              path = "/run/secrets/${name}";
              owner = "root";
              group = "root";
              mode = "0400";
              inherit restartUnits;
            });

            networkCore.caddy.contributions = lib.optionalAttrs (selectedClaim != null) (
              lib.mapAttrs (
                claimName: claim:
                let
                  selectedListeners = selectedClaim.listenAddresses;
                  wildcard = addresses: addresses == [ ] || builtins.elem "0.0.0.0" addresses;
                  shared =
                    if wildcard claim.listenAddresses then
                      selectedListeners
                    else if wildcard selectedListeners then
                      claim.listenAddresses
                    else
                      lib.intersectLists claim.listenAddresses selectedListeners;
                  bothWildcard = wildcard claim.listenAddresses && wildcard selectedListeners;
                  listenerExpression = lib.concatMapStringsSep " || " (
                    address: ''{http.request.local.host} == "${address}"''
                  ) shared;
                  isSelected = claimName == settings.selectedPublicSiteClaim;
                  prelude =
                    if isSelected || bothWildcard then
                      "import ${fragmentPath}"
                    else if shared == [ ] then
                      ""
                    else
                      ''
                        @naive_proxy_connect {
                          method CONNECT
                          expression `${listenerExpression}`
                        }
                        route @naive_proxy_connect {
                          import ${fragmentPath}
                        }
                      '';
                in
                {
                  preRouteConfigFragments = lib.optional (prelude != "") prelude;
                  capabilities = lib.optional isSelected "forward-proxy";
                  siteAddress = if isSelected then ":443" else null;
                  requiresUnits = lib.optional isSelected "${serviceName}.service";
                  afterUnits = lib.optional isSelected "${serviceName}.service";
                }
              ) config.networkCore.caddy.fragments
            );
          };
      };
  };
}
