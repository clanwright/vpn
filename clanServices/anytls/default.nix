{
  lib,
  singBoxPackageFor ? (_system: throw "anytls requires an explicit singBoxPackageFor dependency"),
  ...
}:
let
  identities = import ../../modules/contracts/identities.nix { inherit lib; };
  inherit (import ../../modules/contracts/address-validation.nix { inherit lib; })
    validHostname
    validIPv4
    ;
  validBindIPv4 = value: validIPv4 value && value != "0.0.0.0";
  validDnsName = value: builtins.isString value && validDnsEndpointDomain (lib.toLower value);
  validDnsEndpointDomain =
    value:
    validHostname value
    && value == lib.toLower value
    && builtins.length (lib.splitString "." value) >= 2
    && !builtins.all (label: builtins.match "[0-9]+" label != null) (lib.splitString "." value);
  validHttpPath = value: builtins.match "/[A-Za-z0-9._~/-]*" value != null;
  ipv4ToInt =
    value:
    let
      octets = map builtins.fromJSON (lib.splitString "." value);
    in
    builtins.elemAt octets 0 * 16777216
    + builtins.elemAt octets 1 * 65536
    + builtins.elemAt octets 2 * 256
    + builtins.elemAt octets 3;
  pow2 = exponent: if exponent == 0 then 1 else 2 * pow2 (exponent - 1);
  deniedIPv4Networks = [
    {
      address = "0.0.0.0";
      prefixLength = 8;
    }
    {
      address = "10.0.0.0";
      prefixLength = 8;
    }
    {
      address = "100.64.0.0";
      prefixLength = 10;
    }
    {
      address = "127.0.0.0";
      prefixLength = 8;
    }
    {
      address = "169.254.0.0";
      prefixLength = 16;
    }
    {
      address = "172.16.0.0";
      prefixLength = 12;
    }
    {
      address = "192.0.0.0";
      prefixLength = 24;
    }
    {
      address = "192.0.2.0";
      prefixLength = 24;
    }
    {
      address = "192.88.99.0";
      prefixLength = 24;
    }
    {
      address = "192.168.0.0";
      prefixLength = 16;
    }
    {
      address = "198.18.0.0";
      prefixLength = 15;
    }
    {
      address = "198.51.100.0";
      prefixLength = 24;
    }
    {
      address = "203.0.113.0";
      prefixLength = 24;
    }
    {
      address = "224.0.0.0";
      prefixLength = 4;
    }
    {
      address = "240.0.0.0";
      prefixLength = 4;
    }
  ];
  publicOnlyDenyIPv4 = map (
    network: "${network.address}/${toString network.prefixLength}"
  ) deniedIPv4Networks;
  deniedIPv4 =
    value:
    let
      address = ipv4ToInt value;
    in
    builtins.any (
      network:
      let
        first = ipv4ToInt network.address;
        lastExclusive = first + pow2 (32 - network.prefixLength);
      in
      address >= first && address < lastExclusive
    ) deniedIPv4Networks;
  validPublicIPv4 = value: validIPv4 value && !deniedIPv4 value;
in
{
  _class = "clan.service";

  manifest = {
    name = "@clanwright/vpn-anytls";
    description = "Standalone sing-box AnyTLS TCP gateway with guarded process egress";
    readme = builtins.readFile ./README.md;
    exports.out = [ "vpnProvider" ];
  };

  roles.gateway = {
    description = "Public sing-box AnyTLS TCP gateway";

    interface =
      { lib, ... }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run the AnyTLS gateway.";
          };

          bindIPv4 = lib.mkOption {
            type = lib.types.addCheck lib.types.str validBindIPv4;
            description = "Consumer-owned public IPv4 used by the listener and destination-scoped ingress guard.";
          };

          domain = lib.mkOption {
            type = lib.types.addCheck lib.types.str validDnsName;
            description = "Consumer-owned TLS endpoint hostname exported to clients.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Direct AnyTLS TCP listener port.";
          };

          acmeCertName = lib.mkOption {
            type = identities.certificateKeyType;
            description = "Consumer-owned ACME certificate name under /var/lib/acme.";
          };

          users = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule (_: {
                options = {
                  name = lib.mkOption {
                    type = identities.safeIdentityType;
                    description = "Unique device identity exported to client profile generation.";
                  };
                  passwordSecretName = lib.mkOption {
                    type = identities.safeSecretNameType;
                    description = "Consumer-owned SOPS secret containing a nonempty unpadded base64url password.";
                  };
                };
              })
            );
            default = [ ];
            description = "Separately revocable runtime credentials, one per device.";
          };

          dnsEndpoint = lib.mkOption {
            type = lib.types.submodule (_: {
              options = {
                domain = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validDnsEndpointDomain;
                  description = "Consumer-owned canonical lowercase DoH hostname used for TLS identity and HTTP authority.";
                };
                ipv4 = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validPublicIPv4;
                  description = "Consumer-owned public numeric IPv4 bootstrap address for the DoH endpoint.";
                };
                port = lib.mkOption {
                  type = lib.types.port;
                  default = 443;
                  description = "HTTPS port of the DoH endpoint.";
                };
                path = lib.mkOption {
                  type = lib.types.addCheck lib.types.str validHttpPath;
                  default = "/dns-query";
                  description = "Absolute HTTP path of the DoH endpoint.";
                };
              };
            });
            description = "Single consumer-owned public DNS-over-HTTPS endpoint used by the AnyTLS process.";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName,
        mkExports ? (value: value),
        ...
      }:
      let
        active = settings.enable;
        profileNames = map (user: user.name) settings.users;
        userSecretNames = map (user: user.passwordSecretName) settings.users;
      in
      {
        exports = lib.optionalAttrs active (mkExports {
          vpnProvider = {
            schemaVersion = 3;
            connection.anytls = {
              endpoint = {
                hostname = settings.domain;
                ipv4 = settings.bindIPv4;
                inherit (settings) port;
              };
              clients = lib.listToAttrs (
                map (user: {
                  inherit (user) name;
                  value.passwordSecret = user.passwordSecretName;
                }) settings.users
              );
            };
          };
        });

        nixosModule =
          {
            config,
            modulesPath,
            options,
            pkgs,
            utils,
            ...
          }:
          let
            system =
              if pkgs ? stdenv && pkgs.stdenv ? hostPlatform && pkgs.stdenv.hostPlatform ? system then
                pkgs.stdenv.hostPlatform.system
              else
                builtins.currentSystem;
            singBoxPackage = singBoxPackageFor system;
            serviceName = "sing-box";
            serviceUnit = "${serviceName}.service";
            nftTableName = "vpn_anytls_egress";
            sopsUnits = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
            certificateSource = "/var/lib/acme/${settings.acmeCertName}/fullchain.pem";
            privateKeySource = "/var/lib/acme/${settings.acmeCertName}/key.pem";
            credentialDirectory = "/run/credentials/${serviceUnit}";
            certificatePath = "${credentialDirectory}/certificate.pem";
            privateKeyPath = "${credentialDirectory}/private-key.pem";
            passwordCredential = user: "password-${user.name}";
            passwordPath = user: "${credentialDirectory}/${passwordCredential user}";
            secretsPresent = builtins.all (secretName: config.sops.secrets ? ${secretName}) userSecretNames;
            distinctUserNames = lib.length (lib.unique profileNames) == lib.length profileNames;
            distinctSecretNames = lib.length (lib.unique userSecretNames) == lib.length userSecretNames;
            activeInstances = config.clanwright.vpn.anytls.activeInstances;
            deniedIPv4Set = lib.concatStringsSep ", " publicOnlyDenyIPv4;
            expectedNftContent = ''
              chain output {
                type filter hook output priority filter; policy accept;
                meta skuid "sing-box" ip saddr ${settings.bindIPv4} tcp sport ${toString settings.port} ct direction reply accept comment "anytls preserve listener replies"
                meta skuid "sing-box" ip daddr { ${deniedIPv4Set} } drop comment "anytls deny non-public IPv4 egress"
                meta skuid "sing-box" ip6 daddr ::/0 drop comment "anytls deny IPv6 egress"
              }
            '';
            expectedIngress = ''
              ip daddr ${settings.bindIPv4} tcp dport ${toString settings.port} accept comment "anytls destination-scoped ingress"
            '';
            expectedSettings = {
              log.level = "info";
              dns = {
                servers = [
                  {
                    type = "https";
                    tag = "own-adguard-doh";
                    server = settings.dnsEndpoint.ipv4;
                    server_port = settings.dnsEndpoint.port;
                    path = settings.dnsEndpoint.path;
                    tls = {
                      enabled = true;
                      server_name = settings.dnsEndpoint.domain;
                    };
                  }
                ];
                final = "own-adguard-doh";
                strategy = "ipv4_only";
              };
              inbounds = [
                {
                  type = "anytls";
                  tag = "anytls-in";
                  listen = settings.bindIPv4;
                  listen_port = settings.port;
                  users = map (user: {
                    inherit (user) name;
                    password._secret = passwordPath user;
                  }) settings.users;
                  tls = {
                    enabled = true;
                    server_name = settings.domain;
                    min_version = "1.3";
                    max_version = "1.3";
                    certificate_path = certificatePath;
                    key_path = privateKeyPath;
                  };
                }
              ];
              outbounds = [
                {
                  type = "direct";
                  tag = "direct";
                }
              ];
              route = {
                rules = [
                  {
                    inbound = [ "anytls-in" ];
                    action = "resolve";
                    server = "own-adguard-doh";
                    strategy = "ipv4_only";
                  }
                  {
                    inbound = [ "anytls-in" ];
                    ip_cidr = publicOnlyDenyIPv4;
                    action = "reject";
                  }
                  {
                    inbound = [ "anytls-in" ];
                    ip_is_private = true;
                    action = "reject";
                  }
                ];
                final = "direct";
                default_domain_resolver = {
                  server = "own-adguard-doh";
                  strategy = "ipv4_only";
                };
              };
            };
            passwordValidator = pkgs.writeShellScript "anytls-validate-passwords" (
              ''
                set -eu

                # Native -C reads every JSON in its runtime directory. Reject
                # another configuration before the native renderer installs ours.
                for config_file in /run/sing-box/*.json; do
                  if [ "$config_file" != /run/sing-box/config.json ] && [ -e "$config_file" ]; then
                    echo "anytls: the sing-box runtime configuration directory is exclusive" >&2
                    exit 1
                  fi
                done
              ''
              + lib.concatMapStringsSep "\n" (user: ''
                secret_path=${lib.escapeShellArg (passwordPath user)}
                byte_count="$(${pkgs.coreutils}/bin/wc -c < "$secret_path")"
                base64url_byte_count="$(LC_ALL=C ${pkgs.coreutils}/bin/tr -cd 'A-Za-z0-9_-' < "$secret_path" | ${pkgs.coreutils}/bin/wc -c)"
                if [ "$byte_count" -eq 0 ] || [ "$byte_count" -gt 64 ] || [ "$byte_count" -ne "$base64url_byte_count" ]; then
                  echo "anytls: a device password must be 1..64 raw unpadded base64url bytes" >&2
                  exit 1
                fi
              '') settings.users
            );
            bindCapabilities = lib.optional (settings.port < 1024) "CAP_NET_BIND_SERVICE";
            # The package unit grants more capabilities and supplies HUP reload.
            # Empty assignments reset those inherited directives in the drop-in.
            expectedLoadCredential = [
              "certificate.pem:${certificateSource}"
              "private-key.pem:${privateKeySource}"
            ]
            ++ map (
              user: "${passwordCredential user}:${config.sops.secrets.${user.passwordSecretName}.path}"
            ) settings.users;
            nativePreStart = pkgs.writeShellScript "sing-box-pre-start" ''
              ${utils.genJqSecretsReplacementSnippet expectedSettings "/run/sing-box/config.json"}
              chown --reference=/run/sing-box /run/sing-box/config.json
            '';
            hardening = {
              Type = "exec";
              ExecReload = [ "" ];
              UMask = "0077";
              AmbientCapabilities = [ "" ] ++ bindCapabilities;
              CapabilityBoundingSet = [ "" ] ++ bindCapabilities;
              LoadCredential = expectedLoadCredential;
              LockPersonality = true;
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              ProtectProc = "invisible";
              ProtectSystem = "strict";
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_UNIX"
              ];
              RestrictNamespaces = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              SystemCallArchitectures = "native";
            };
            expectedServiceConfig = hardening // {
              User = serviceName;
              Group = serviceName;
              ConfigurationDirectory = serviceName;
              StateDirectory = serviceName;
              StateDirectoryMode = "0700";
              RuntimeDirectory = serviceName;
              RuntimeDirectoryMode = "0700";
              WorkingDirectory = "/var/lib/sing-box";
              ExecStartPre = [
                "${passwordValidator}"
                "+${nativePreStart}"
              ];
              ExecStart = [
                ""
                "${lib.getExe singBoxPackage} -D \${STATE_DIRECTORY} -C \${RUNTIME_DIRECTORY} run"
              ];
            };
            unit = config.systemd.services.${serviceName};
            generatedUnit = config.systemd.units.${serviceUnit};
            # Trust pinned native NixOS package declarations and each service's
            # package authority. Consumer additions can introduce late vendor
            # drop-ins. This guards trusted declarative composition, without
            # inspecting unbuilt outputs or defending against hostile Nix code.
            nativePackageDefinitions = options.systemd.packages.definitionsWithLocations;
            nativeSystemdSource = "${toString modulesPath}/system/boot/systemd.nix";
            nativeSystemdTargets = [
              "systemd/system"
              "systemd/system.conf"
            ];
            nativeSystemdEntry =
              target:
              let
                definitions = builtins.filter (
                  definition: definition.value ? ${target}
                ) options.environment.etc.definitionsWithLocations;
              in
              definitions != [ ]
              && builtins.all (definition: definition.file == nativeSystemdSource) definitions
              && config.environment.etc ? ${target}
              && config.environment.etc.${target}.enable
              && config.environment.etc.${target}.target == target;
            managerDefaultEnvironment = config.systemd.settings.Manager.DefaultEnvironment or "";
            managerSettingsSafe = builtins.all (
              name:
              builtins.match "[A-Za-z][A-Za-z0-9]*" name != null
              && builtins.all (
                value:
                let
                  rendered = utils.systemdUtils.lib.toOption value;
                in
                !(lib.hasInfix "\n" rendered) && !(lib.hasInfix "\r" rendered)
              ) (lib.toList config.systemd.settings.Manager.${name})
            ) (builtins.attrNames config.systemd.settings.Manager);
            nativePath = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnused
              config.systemd.package
            ];
            expectedUnitConfig = {
              After = toString unit.after;
              BindsTo = toString unit.bindsTo;
              Description = "sing-box AnyTLS proxy gateway";
              PartOf = toString unit.partOf;
              Requires = toString unit.requires;
            }
            // lib.optionalAttrs (unit.wants != [ ]) {
              Wants = toString unit.wants;
            };
            namespacePath =
              value:
              builtins.any (path: lib.hasInfix path value) [
                "/run/sing-box"
                "/var/lib/sing-box"
                "/etc/sing-box"
                "/run/credentials/${serviceUnit}"
              ];
          in
          {
            imports = [ ./options.nix ];

            config = {
              clanwright.vpn.anytls.activeInstances = lib.mkIf active [ instanceName ];

              assertions = lib.optionals active [
                {
                  assertion = system == "x86_64-linux";
                  message = "anytls: runtime support is restricted to x86_64-linux.";
                }
                {
                  assertion = lib.getVersion singBoxPackage == "1.14.1";
                  message = "anytls: the injected stock sing-box package must be exactly version 1.14.1.";
                }
                {
                  assertion =
                    config.services.sing-box.enable
                    && config.services.sing-box.package == singBoxPackage
                    && config.services.sing-box.settings == expectedSettings;
                  message = "anytls: the native sing-box singleton must retain the exact package and exclusive AnyTLS settings.";
                }
                {
                  assertion =
                    builtins.elem singBoxPackage config.systemd.packages
                    && builtins.all (
                      definition: lib.hasPrefix "${toString modulesPath}/" definition.file
                    ) nativePackageDefinitions
                    && !(builtins.elem serviceUnit config.systemd.suppressedSystemUnits)
                    && builtins.all nativeSystemdEntry nativeSystemdTargets
                    && builtins.all (
                      name:
                      let
                        target = config.environment.etc.${name}.target;
                      in
                      target != "systemd"
                      && !(lib.hasPrefix "systemd/system.conf.d" target)
                      && (!(builtins.elem target nativeSystemdTargets) || name == target)
                    ) (builtins.attrNames config.environment.etc);
                  message = "anytls: stock sing-box and native systemd assembly must remain present; consumer package providers, suppression and directory replacement are unsupported.";
                }
                {
                  assertion = config.networking.firewall.enable;
                  message = "anytls: destination-scoped ingress requires the NixOS firewall.";
                }
                {
                  assertion = config.networking.firewall.backend == "nftables";
                  message = "anytls: ingress and process-scoped egress require the nftables firewall backend.";
                }
                {
                  assertion = config.networking.nftables.enable;
                  message = "anytls: the module-owned process egress guard requires networking.nftables.enable.";
                }
                {
                  assertion = lib.length activeInstances == 1;
                  message = "anytls: only one active instance may claim the singleton runtime per machine.";
                }
                {
                  assertion = settings.users != [ ];
                  message = "anytls: at least one per-device user is required.";
                }
                {
                  assertion = distinctUserNames;
                  message = "anytls: device identities must be unique.";
                }
                {
                  assertion = distinctSecretNames;
                  message = "anytls: every device must use a distinct SOPS password secret.";
                }
                {
                  assertion =
                    config.networking.nftables.tables ? ${nftTableName}
                    && config.networking.nftables.tables.${nftTableName}.family == "inet"
                    && config.networking.nftables.tables.${nftTableName}.enable
                    && config.networking.nftables.tables.${nftTableName}.content == expectedNftContent
                    && lib.hasInfix expectedIngress config.networking.firewall.extraInputRules;
                  message = "anytls: the module-owned ingress and process egress guard must not be removed or weakened.";
                }
                {
                  assertion = !(config.sops.templates ? "anytls.json") && !(config.sops.templates ? "sing-box.json");
                  message = "anytls: native sing-box owns runtime JSON rendering; competing SOPS templates are unsupported.";
                }
                {
                  assertion = builtins.all (
                    secretName:
                    config.sops.secrets ? ${secretName}
                    && config.sops.secrets.${secretName}.owner == "root"
                    && config.sops.secrets.${secretName}.group == "root"
                    && config.sops.secrets.${secretName}.mode == "0400"
                    && builtins.elem serviceUnit config.sops.secrets.${secretName}.restartUnits
                  ) userSecretNames;
                  message = "anytls: password secret permissions and restart bindings must remain guarded.";
                }
                {
                  assertion =
                    config.security.acme.certs ? ${settings.acmeCertName}
                    && builtins.elem serviceUnit config.security.acme.certs.${settings.acmeCertName}.reloadServices;
                  message = "anytls: ACME renewal must restart sing-box to refresh copied TLS credentials.";
                }
                {
                  assertion =
                    config.services.sing-box.enable
                    && config.systemd.services ? ${serviceName}
                    && secretsPresent
                    && unit.enable
                    && unit.wantedBy == [ "multi-user.target" ]
                    && unit.serviceConfig == expectedServiceConfig
                    && unit.unitConfig == expectedUnitConfig
                    && unit.path == nativePath
                    && managerSettingsSafe
                    && builtins.elem managerDefaultEnvironment [
                      ""
                      [ ]
                      [ "" ]
                    ]
                    && builtins.all (
                      name:
                      builtins.elem name [
                        "LOCALE_ARCHIVE"
                        "TZDIR"
                      ]
                    ) (builtins.attrNames config.systemd.globalEnvironment)
                    &&
                      unit.environment == {
                        PATH = "${lib.makeBinPath nativePath}:${lib.makeSearchPathOutput "bin" "sbin" nativePath}";
                      }
                    && unit.preStart == ""
                    && unit.postStart == ""
                    && unit.script == ""
                    && unit.reload == ""
                    && !unit.reloadIfChanged
                    && unit.restartIfChanged
                    &&
                      unit.requires == [
                        "network-online.target"
                        "nftables.service"
                      ]
                    && unit.bindsTo == [ "nftables.service" ]
                    && unit.partOf == [ "nftables.service" ]
                    && builtins.elem "nftables.service" unit.after
                    && builtins.all (name: builtins.elem name unit.after && builtins.elem name unit.wants) sopsUnits;
                  message = "anytls: the native unit identity, execution, credentials, hardening, restart and firewall lifecycle must remain guarded.";
                }
                {
                  assertion =
                    config.services.sing-box.enable
                    && secretsPresent
                    && config.systemd.services ? ${serviceName}
                    && config.systemd.units ? ${serviceUnit}
                    && config.users.users ? ${serviceName}
                    && config.users.groups ? ${serviceName}
                    && generatedUnit.enable
                    && generatedUnit.text == (utils.systemdUtils.lib.serviceToUnit unit).text
                    && generatedUnit.unit == utils.systemdUtils.lib.makeUnit serviceUnit generatedUnit
                    && generatedUnit.wantedBy == unit.wantedBy
                    && unit.aliases == [ ]
                    && generatedUnit.aliases == [ ]
                    && builtins.all (name: !(builtins.elem serviceUnit config.systemd.units.${name}.aliases)) (
                      builtins.attrNames config.systemd.units
                    )
                    && generatedUnit.overrideStrategy == "asDropinIfExists"
                    && !(config.systemd.services ? anytls)
                    && builtins.all (name: name == serviceName || !(lib.hasPrefix "sing-box" name)) (
                      builtins.attrNames config.systemd.services
                    )
                    && builtins.all (name: name == serviceUnit || !(lib.hasPrefix "sing-box" name)) (
                      builtins.attrNames config.systemd.units
                    )
                    && builtins.all (
                      name:
                      name == serviceName || (config.systemd.services.${name}.serviceConfig.User or null) != serviceName
                    ) (builtins.attrNames config.systemd.services)
                    && builtins.all (
                      name:
                      let
                        target = config.environment.etc.${name}.target;
                      in
                      !(lib.hasPrefix "sing-box" target) && !(lib.hasPrefix "systemd/system/sing-box" target)
                    ) (builtins.attrNames config.environment.etc)
                    && !(builtins.any namespacePath config.systemd.tmpfiles.rules)
                    && !(builtins.any namespacePath (
                      lib.concatMap builtins.attrNames (builtins.attrValues config.systemd.tmpfiles.settings)
                    ))
                    && config.users.users.${serviceName}.isSystemUser
                    && config.users.users.${serviceName}.enable
                    && config.users.users.${serviceName}.name == serviceName
                    && !config.users.users.${serviceName}.isNormalUser
                    && config.users.users.${serviceName}.group == serviceName
                    && config.users.users.${serviceName}.home == "/var/lib/sing-box"
                    && config.users.users.${serviceName}.uid == null
                    && config.users.users.${serviceName}.extraGroups == [ ]
                    && config.users.groups.${serviceName}.gid == null
                    && config.users.groups.${serviceName}.name == serviceName
                    && config.users.groups.${serviceName}.members == [ ]
                    && builtins.all (name: !(builtins.elem serviceName config.users.groups.${name}.members)) (
                      builtins.attrNames config.users.groups
                    )
                    && builtins.all (
                      name:
                      name == serviceName
                      || (
                        config.users.users.${name}.group != serviceName
                        && config.users.users.${name}.name != serviceName
                        && !(builtins.elem serviceName config.users.users.${name}.extraGroups)
                      )
                    ) (builtins.attrNames config.users.users)
                    && builtins.all (name: name == serviceName || config.users.groups.${name}.name != serviceName) (
                      builtins.attrNames config.users.groups
                    );
                  message = "anytls: native sing-box unit, UID, directories and configuration namespace are exclusively owned by this singleton.";
                }
              ];

              services.sing-box = lib.mkIf active {
                enable = true;
                package = singBoxPackage;
                settings = expectedSettings;
              };

              sops.secrets = lib.optionalAttrs active (
                lib.genAttrs userSecretNames (_: {
                  owner = "root";
                  group = "root";
                  mode = "0400";
                  restartUnits = [ serviceUnit ];
                })
              );

              networking = {
                firewall.extraInputRules = lib.mkIf active (lib.mkAfter expectedIngress);
                nftables = {
                  # Pure nft syntax checks have no target user database.
                  preCheckRuleset = lib.mkIf active (
                    lib.mkAfter ''
                      sed 's/meta skuid "sing-box"/meta skuid 0/g' -i ruleset.conf
                    ''
                  );
                  tables = lib.optionalAttrs active {
                    ${nftTableName} = {
                      enable = true;
                      family = "inet";
                      content = expectedNftContent;
                    };
                  };
                };
              };

              security.acme.certs = lib.optionalAttrs active {
                ${settings.acmeCertName}.reloadServices = [ serviceUnit ];
              };

              systemd.services = lib.optionalAttrs active {
                ${serviceName} = {
                  description = "sing-box AnyTLS proxy gateway";
                  after = [
                    "network-online.target"
                    "nftables.service"
                  ]
                  ++ sopsUnits;
                  wants = sopsUnits;
                  requires = [ "nftables.service" ];
                  bindsTo = [ "nftables.service" ];
                  partOf = [ "nftables.service" ];
                  # sing-box 1.14.1 propagates AnyTLS ListenTCP failure through
                  # Inbound.Start -> Box.Start -> run(). Native restart handles
                  # that failure; a separate /proc listener supervisor is redundant.
                  serviceConfig = hardening // {
                    ExecStartPre = lib.mkBefore [ "${passwordValidator}" ];
                  };
                };
              };
            };
          };
      };
  };
}
