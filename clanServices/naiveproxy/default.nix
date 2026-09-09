{ lib, ... }:
let
  identityPattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,63}";
  secretNamePattern = "[A-Za-z0-9_][A-Za-z0-9_.+-]*(/[A-Za-z0-9_][A-Za-z0-9_.+-]*)*";
  validIdentity = value: builtins.match identityPattern value != null;
  validSecretName = value: builtins.match secretNamePattern value != null;
  parseCanonicalDecimal = value: builtins.match "(0|[1-9][0-9]{0,2})" value != null;
  validPrefix =
    maximum: value:
    parseCanonicalDecimal value && builtins.fromJSON value >= 0 && builtins.fromJSON value <= maximum;
  validIPv4 =
    value:
    let
      octets = lib.splitString "." value;
    in
    lib.length octets == 4
    && builtins.all (
      octet: parseCanonicalDecimal octet && builtins.fromJSON octet >= 0 && builtins.fromJSON octet <= 255
    ) octets;
  validIPv6 =
    value:
    let
      compressedParts = lib.splitString "::" value;
      compressed = lib.length compressedParts == 2;
      hextets = lib.concatMap (
        part: if part == "" then [ ] else lib.splitString ":" part
      ) compressedParts;
      validHextet = hextet: builtins.match "[0-9A-Fa-f]{1,4}" hextet != null;
    in
    value != ""
    && lib.length compressedParts <= 2
    && builtins.all validHextet hextets
    && (if compressed then lib.length hextets < 8 else lib.length hextets == 8);
  validAclAddress =
    value:
    let
      parts = lib.splitString "/" value;
      address = builtins.head parts;
      hasPrefix = lib.length parts == 2;
      ipv6 = lib.hasInfix ":" address;
      addressValid = if ipv6 then validIPv6 address else validIPv4 address;
      prefixValid = !hasPrefix || validPrefix (if ipv6 then 128 else 32) (builtins.elemAt parts 1);
    in
    lib.length parts <= 2 && addressValid && prefixValid;
  passwordSecretNamesType = lib.types.addCheck (lib.types.attrsOf lib.types.str) (
    value:
    value != { }
    && builtins.all validIdentity (builtins.attrNames value)
    && builtins.all validSecretName (builtins.attrValues value)
    && lib.length (lib.unique (builtins.attrValues value)) == lib.length (builtins.attrValues value)
  );
in
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
            type = lib.types.addCheck lib.types.str validIdentity;
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
                  type = lib.types.addCheck lib.types.str (value: value == "" || validIPv4 value);
                  default = "";
                  description = "Public endpoint IPv4 used by clients, for client exports only.";
                };
                caddyBindIPv4 = lib.mkOption {
                  type = lib.types.addCheck lib.types.str (value: value == "" || validIPv4 value);
                  default = "";
                  description = "Caddy listener IPv4 of the selected public-site claim, for ownership validation only.";
                };
              };
            });
            default = { };
            description = "Non-owning endpoint metadata that must match the selected claim.";
          };

          passwordSecretNames = lib.mkOption {
            type = passwordSecretNamesType;
            description = "Identity to machine-scoped SOPS secret-name map consumed by forward_proxy basic_auth.";
          };

          probeUserName = lib.mkOption {
            type = lib.types.addCheck lib.types.str validIdentity;
            default = "probe";
            description = "Identity reserved for health probes and excluded from ordinary device profiles.";
          };

          additionalDeny = lib.mkOption {
            type = lib.types.listOf (lib.types.addCheck lib.types.str validAclAddress);
            default = [ ];
            description = "Additional consumer-owned IPv4/IPv6 addresses or CIDRs denied before public Internet access is allowed.";
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
        userNames = builtins.attrNames settings.passwordSecretNames;
        profileNames = builtins.filter (name: name != settings.probeUserName) userNames;
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
              inherit userNames;
              port = 443;
            };
            inherit profileNames;
            secretNames = {
              password = settings.passwordSecretNames;
            };
          };
        });
        nixosModule =
          {
            config,
            lib,
            ...
          }:
          let
            templateName = "naiveproxy-${settings.machineName}.caddy";
            fragmentPath = config.sops.templates.${templateName}.path;
            caddyConfig = config.services.caddy;
            secretNames = builtins.attrValues settings.passwordSecretNames;
            publicOnlyDeny = [
              "0.0.0.0/8"
              "10.0.0.0/8"
              "100.64.0.0/10"
              "127.0.0.0/8"
              "169.254.0.0/16"
              "172.16.0.0/12"
              "192.0.0.0/24"
              "192.0.2.0/24"
              "192.88.99.0/24"
              "192.168.0.0/16"
              "198.18.0.0/15"
              "198.51.100.0/24"
              "203.0.113.0/24"
              "224.0.0.0/4"
              "240.0.0.0/4"
              "::/128"
              "::1/128"
              "64:ff9b:1::/48"
              "100::/64"
              "100:0:0:1::/64"
              "2001::/32"
              "2001:10::/28"
              "2001:20::/28"
              "2001:2::/48"
              "2001:db8::/32"
              "2002::/16"
              "3fff::/20"
              "5f00::/16"
              "fc00::/7"
              "fe80::/10"
              "ff00::/8"
            ];
            denySubjects = lib.unique (publicOnlyDeny ++ settings.additionalDeny);
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
            basicAuthLines = lib.concatMapStringsSep "\n" (
              identity:
              "  basic_auth ${identity} ${config.sops.placeholder.${settings.passwordSecretNames.${identity}}}"
            ) userNames;
            fragmentContent = ''
              forward_proxy {
              ${basicAuthLines}
                hide_ip
                hide_via
                acl {
                  deny ${lib.concatStringsSep " " denySubjects}
                  allow all
                }
                probe_resistance
              }
            '';
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
          in
          {
            assertions = [
              {
                assertion =
                  !settings.enable
                  || (caddyConfig.enableReload && caddyConfig.adapter == "caddyfile" && !caddyConfig.resume);
                message = "naiveproxy: runtime credentials require native Caddyfile reload and resume disabled.";
              }
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
                  !settings.enable || builtins.hasAttr settings.probeUserName settings.passwordSecretNames;
                message = "naiveproxy: probeUserName must name an identity in passwordSecretNames.";
              }
              {
                assertion = !settings.enable || profileNames != [ ];
                message = "naiveproxy: at least one non-probe device identity is required.";
              }
              {
                assertion =
                  !settings.enable
                  || (
                    selectedClaim != null
                    && (selectedClaim.publicSite or false)
                    && selectedPublicSiteEndpoint.domain != ""
                    && selectedPublicSiteEndpoint.domain == selectedClaim.hostName
                    && selectedPublicSiteEndpoint.publicIPv4 != ""
                    && selectedPublicSiteEndpoint.caddyBindIPv4 != ""
                    && selectedPublicSiteEndpoint.caddyBindIPv4 != "0.0.0.0"
                    && selectedClaimPrimaryListenAddress != null
                    && selectedClaim.listenAddresses == [ selectedPublicSiteEndpoint.caddyBindIPv4 ]
                  );
                message = "naiveproxy: selected claim must be publicSite and have exactly the declared domain and isolated Caddy listener.";
              }
            ];
          }
          // lib.optionalAttrs settings.enable {
            sops.templates.${templateName} = {
              content = fragmentContent;
              owner = "root";
              inherit (caddyConfig) group;
              mode = "0440";
              reloadUnits = [ "caddy.service" ];
            };
            # Adapted config contains reversible auth material. Keep it in /run
            # and memory; Caddy's default autosave must not persist credentials.
            services.caddy.globalConfig = lib.mkAfter ''
              persist_config off
            '';

            sops.secrets = lib.genAttrs secretNames (name: {
              path = "/run/secrets/${name}";
              owner = "root";
              group = "root";
              mode = "0400";
            });

            networkCore.caddy.contributions = lib.optionalAttrs (selectedClaim != null) (
              lib.mapAttrs (
                claimName: claim:
                let
                  isSelected = claimName == settings.selectedPublicSiteClaim;
                  wildcard = addresses: addresses == [ ] || builtins.elem "0.0.0.0" addresses;
                  sharesSelectedListener =
                    !isSelected
                    && (
                      wildcard claim.listenAddresses
                      || builtins.elem selectedPublicSiteEndpoint.caddyBindIPv4 claim.listenAddresses
                    );
                  siblingConnectRoute = ''
                    @naive_proxy_connect {
                      method CONNECT
                      expression `{http.request.local.host} == "${selectedPublicSiteEndpoint.caddyBindIPv4}" && {http.request.local.port} == "443"`
                    }
                    route @naive_proxy_connect {
                      import ${fragmentPath}
                    }
                  '';
                in
                {
                  preRouteConfigFragments =
                    lib.optional isSelected "import ${fragmentPath}"
                    ++ lib.optional sharesSelectedListener siblingConnectRoute;
                  capabilities = lib.optional isSelected "forward-proxy";
                  siteAddress = if isSelected then ":443" else null;
                  wantsUnits = lib.optionals isSelected sopsUnits;
                  afterUnits = lib.optionals isSelected sopsUnits;
                }
              ) config.networkCore.caddy.fragments
            );
          };
      };
  };
}
