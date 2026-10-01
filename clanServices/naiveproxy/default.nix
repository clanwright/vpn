{ lib, ... }:
let
  addressValidation = import ../../modules/contracts/address-validation.nix { inherit lib; };
  inherit (addressValidation) validIPv4;
  validDomain =
    value:
    addressValidation.validHostname value
    && lib.toLower value == value
    && lib.length (lib.splitString "." value) >= 2;
  identityPattern = "[A-Za-z0-9][A-Za-z0-9._-]{0,63}";
  secretNamePattern = "[A-Za-z0-9_][A-Za-z0-9_.+-]*(/[A-Za-z0-9_][A-Za-z0-9_.+-]*)*";
  validIdentity = value: builtins.match identityPattern value != null;
  validSecretName = value: builtins.match secretNamePattern value != null;
  parseCanonicalDecimal = value: builtins.match "(0|[1-9][0-9]{0,2})" value != null;
  validPrefix =
    maximum: value:
    parseCanonicalDecimal value && builtins.fromJSON value >= 0 && builtins.fromJSON value <= maximum;
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
    description = "NaiveProxy Caddy add-on for one existing native Caddy virtual host";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.addon = {
    description = "Attach one generated NaiveProxy forward-proxy fragment to an existing native Caddy virtual host";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to generate and attach the NaiveProxy Caddy fragment.";
          };

          domain = lib.mkOption {
            type = lib.types.addCheck lib.types.str validDomain;
            description = "Canonical hostname selecting the consumer-owned native Caddy virtual host.";
          };
          publicIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str (value: validIPv4 value && value != "0.0.0.0");
            description = "Advertised public endpoint IPv4 for clients; never used as the listener scope.";
          };
          bindIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str (value: validIPv4 value && value != "0.0.0.0");
            description = "Exact native Caddy listener IPv4 used to scope authenticated CONNECT on port 443.";
          };

          passwordSecretNames = lib.mkOption {
            type = passwordSecretNamesType;
            description = "Identity to machine-scoped SOPS secret-name map consumed by forward_proxy basic_auth.";
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
        instanceName,
        machine,
        mkExports ? (value: value),
        ...
      }:
      let
        active = settings.enable;
        providerMachine = machine.name;
        userNames = builtins.attrNames settings.passwordSecretNames;
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = {
            schemaVersion = 3;
            connection.naiveproxy = {
              endpoint = {
                hostname = settings.domain;
                ipv4 = settings.publicIPv4;
                port = 443;
              };
              clients = lib.mapAttrs (_: passwordSecret: {
                inherit passwordSecret;
              }) settings.passwordSecretNames;
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
            templateName = "naiveproxy-${providerMachine}.caddy";
            template = config.sops.templates.${templateName} or null;
            fragmentPath = config.sops.templates.${templateName}.path;
            caddyConfig = config.services.caddy;
            activeInstances = config.clanwright.vpn.naiveproxy.activeInstances;
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
            selectedHost = caddyConfig.virtualHosts.${settings.domain} or null;
            connectRoute = ''
              route {
                @naive_proxy_connect {
                  method CONNECT
                  expression `{http.request.local.host} == "${settings.bindIPv4}" && {http.request.local.port} == 443`
                }
                route @naive_proxy_connect {
                  import ${fragmentPath}
                }
              }
            '';
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
            imports = [ ./shared.nix ];

            config = lib.mkMerge [
              {
                clanwright.vpn.naiveproxy.activeInstances = lib.mkIf active [ instanceName ];

                assertions = [
                  {
                    assertion = !active || lib.length activeInstances == 1;
                    message = "naiveproxy: only one active instance may claim the machine-wide Caddy forward-proxy integration.";
                  }
                  {
                    assertion =
                      !settings.enable
                      || (
                        caddyConfig.enable
                        && caddyConfig.enableReload
                        && caddyConfig.adapter == "caddyfile"
                        && !caddyConfig.resume
                        && caddyConfig.httpsPort == 443
                      );
                    message = "naiveproxy: runtime credentials require native Caddyfile reload and resume disabled.";
                  }
                  {
                    assertion =
                      !active
                      || (
                        selectedHost != null
                        && selectedHost.forwardProxy
                        && selectedHost.hostName == ":443"
                        && selectedHost.listenAddresses == [ settings.bindIPv4 ]
                      );
                    message = "naiveproxy: the selected native Caddy host must have an existing owner and exactly the declared isolated IPv4 listener on port 443.";
                  }
                  {
                    assertion =
                      !active
                      || (
                        template != null
                        && builtins.all (
                          name:
                          let
                            secret = config.sops.secrets.${name} or null;
                          in
                          secret != null
                          && secret.path == "/run/secrets/${name}"
                          && secret.owner == "root"
                          && secret.group == "root"
                          && secret.mode == "0400"
                        ) secretNames
                        && template.content == fragmentContent
                        && template.owner == "root"
                        && template.group == caddyConfig.group
                        && template.mode == "0440"
                        && builtins.elem "caddy.service" template.reloadUnits
                      );
                    message = "naiveproxy: authenticated policy, SOPS credential permissions, and native Caddy reload bindings must remain guarded.";
                  }
                  {
                    assertion =
                      !active
                      || (
                        selectedHost != null
                        && template != null
                        && lib.hasInfix "persist_config off" caddyConfig.globalConfig
                        # Only the Boolean guard's regex needle loses context;
                        # both published and attached route strings retain it.
                        && lib.hasInfix (builtins.unsafeDiscardStringContext connectRoute) selectedHost.extraConfig
                        && config.clanwright.vpn.naiveproxy.connectRoute == connectRoute
                        && builtins.all (
                          unit:
                          builtins.elem unit config.systemd.services.caddy.after
                          && builtins.elem unit config.systemd.services.caddy.wants
                          && !(builtins.elem unit config.systemd.services.caddy.requires)
                        ) sopsUnits
                      );
                    message = "naiveproxy: selected authenticated CONNECT, in-memory credentials, and non-requiring SOPS startup dependencies must remain guarded.";
                  }
                ];
              }
              (lib.mkIf active {
                sops.templates.${templateName} = {
                  content = fragmentContent;
                  owner = "root";
                  inherit (caddyConfig) group;
                  mode = "0440";
                  reloadUnits = [ "caddy.service" ];
                };
                # Network's native Caddy policy keeps adapted credentials out of
                # autosave. The effective assertion below retains that boundary.

                sops.secrets = lib.genAttrs secretNames (name: {
                  path = "/run/secrets/${name}";
                  owner = "root";
                  group = "root";
                  mode = "0400";
                });

                clanwright.vpn.naiveproxy.connectRouteContent = connectRoute;
                services.caddy.virtualHosts.${settings.domain} = {
                  forwardProxy = true;
                  extraConfig = lib.mkBefore connectRoute;
                };
                systemd.services.caddy = {
                  after = sopsUnits;
                  wants = sopsUnits;
                };
              })
            ];
          };
      };
  };
}
