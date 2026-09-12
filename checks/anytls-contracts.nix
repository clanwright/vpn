{
  inputs,
  pkgs,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  singBoxPackage = self.packages.${system}.sing-box;
  service = import ../clanServices/anytls/default.nix {
    inherit lib;
    singBoxPackageFor = _: singBoxPackage;
  };
  interface = service.roles.gateway.interface { inherit lib; };
  baseSettings = {
    enable = true;
    bindIPv4 = "192.0.2.14";
    domain = "anytls.example.invalid";
    port = 443;
    acmeCertName = "anytls-example";
    users = [
      {
        name = "phone";
        passwordSecretName = "fixture/anytls-phone-password";
      }
      {
        name = "laptop";
        passwordSecretName = "fixture/anytls-laptop-password";
      }
    ];
    dnsEndpoint = {
      domain = "dns.example.invalid";
      ipv4 = "93.184.216.34";
    };
  };
  evalSettings =
    value:
    (lib.evalModules {
      modules = [
        interface
        { config = value; }
      ];
    }).config;
  schemaAccepts = value: (builtins.tryEval (builtins.deepSeq (evalSettings value) true)).success;
  unwrap =
    value:
    if builtins.isAttrs value && (value._type or null) == "if" then
      if value.condition then unwrap value.content else null
    else if builtins.isAttrs value && (value._type or null) == "order" then
      unwrap value.content
    else if builtins.isAttrs value && (value._type or null) == "override" then
      unwrap value.content
    else
      value;
  packagePkgs = pkgs // {
    sing-box = singBoxPackage;
  };
  baseConfigFor =
    settings: activeInstances:
    let
      names = map (user: user.passwordSecretName) settings.users;
    in
    {
      clanwright.vpn.anytls = { inherit activeInstances; };
      networking = {
        nameservers = [ "127.0.0.53" ];
        firewall = {
          enable = true;
          backend = "nftables";
        };
        nftables.enable = true;
      };
      security.acme.certs.${settings.acmeCertName}.reloadServices = [ ];
      sops = {
        useSystemdActivation = true;
        placeholder = lib.genAttrs names (name: "<SOPS:${name}:PLACEHOLDER>");
        secrets = lib.genAttrs names (name: {
          path = "/run/secrets/${name}";
          restartUnits = [ "profile-publisher.service" ];
        });
        templates."anytls.json" = {
          path = "/run/secrets-rendered/anytls.json";
          restartUnits = [ "profile-publisher.service" ];
        };
      };
    };
  evaluateWith =
    {
      rawSettings,
      activeInstances ? [ "fixture--anytls" ],
      targetPkgs ? packagePkgs,
      mutateEffectiveConfig ? (value: value),
    }:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--anytls";
        machine.name = "fixture";
      };
      baseConfig = baseConfigFor settings activeInstances;
      bootstrap = instance.nixosModule {
        config = baseConfig;
        pkgs = targetPkgs;
      };
      bootstrapModule = bootstrap.config;
      mergeSecret =
        name:
        baseConfig.sops.secrets.${name}
        // (unwrap bootstrapModule.sops.secrets.${name})
        // {
          restartUnits =
            baseConfig.sops.secrets.${name}.restartUnits
            ++ (unwrap bootstrapModule.sops.secrets.${name}).restartUnits;
        };
      effectiveConfig = mutateEffectiveConfig (
        baseConfig
        // {
          networking = baseConfig.networking // {
            nftables = baseConfig.networking.nftables // {
              tables.vpn_anytls_egress = unwrap bootstrapModule.networking.nftables.tables.vpn_anytls_egress;
            };
          };
          security.acme.certs.${settings.acmeCertName}.reloadServices =
            unwrap
              bootstrapModule.security.acme.certs.${settings.acmeCertName}.reloadServices;
          sops = baseConfig.sops // {
            secrets = lib.genAttrs (map (user: user.passwordSecretName) settings.users) mergeSecret;
            templates."anytls.json" =
              baseConfig.sops.templates."anytls.json"
              // (unwrap bootstrapModule.sops.templates."anytls.json")
              // {
                restartUnits =
                  baseConfig.sops.templates."anytls.json".restartUnits
                  ++ (unwrap bootstrapModule.sops.templates."anytls.json").restartUnits;
              };
          };
          systemd.services.anytls = unwrap bootstrapModule.systemd.services.anytls;
        }
      );
      definition = instance.nixosModule {
        config = effectiveConfig;
        pkgs = targetPkgs;
      };
      module = definition.config;
      template = unwrap (module.sops.templates."anytls.json" or null);
    in
    {
      inherit
        definition
        effectiveConfig
        instance
        module
        settings
        template
        ;
      assertionsPass = builtins.all (entry: entry.assertion) module.assertions;
      rendered = if template == null then null else builtins.fromJSON template.content;
      table = unwrap (module.networking.nftables.tables.vpn_anytls_egress or null);
      unit = unwrap module.systemd.services.anytls;
    };
  enabled = evaluateWith { rawSettings = baseSettings; };
  disabled = evaluateWith {
    rawSettings = baseSettings // {
      enable = false;
    };
    activeInstances = [ ];
  };
  duplicateUsers = evaluateWith {
    rawSettings = baseSettings // {
      users = baseSettings.users ++ [ (builtins.head baseSettings.users) ];
    };
  };
  duplicateSecrets = evaluateWith {
    rawSettings = baseSettings // {
      users = [
        (builtins.head baseSettings.users)
        (
          (builtins.elemAt baseSettings.users 1)
          // {
            inherit (builtins.head baseSettings.users) passwordSecretName;
          }
        )
      ];
    };
  };
  noUsers = evaluateWith {
    rawSettings = baseSettings // {
      users = [ ];
    };
  };
  duplicateInstances = evaluateWith {
    rawSettings = baseSettings;
    activeInstances = [
      "fixture--anytls"
      "fixture--second-anytls"
    ];
  };
  noInstanceClaim = evaluateWith {
    rawSettings = baseSettings;
    activeInstances = [ ];
  };
  alternateNameservers = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { networking.nameservers = [ "10.0.0.53" ]; };
  };
  disabledNftables = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig = config: lib.recursiveUpdate config { networking.nftables.enable = false; };
  };
  weakenedGuard = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        networking.nftables.tables.vpn_anytls_egress.content =
          "chain output { type filter hook output priority filter; policy accept; }";
      };
  };
  disabledGuardTable = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { networking.nftables.tables.vpn_anytls_egress.enable = false; };
  };
  wrongIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { systemd.services.anytls.serviceConfig.User = "root"; };
  };
  dynamicIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { systemd.services.anytls.serviceConfig.DynamicUser = true; };
  };
  wrongCommand = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { systemd.services.anytls.serviceConfig.ExecStart = "/bin/false"; };
  };
  wrongCredentials = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { systemd.services.anytls.serviceConfig.LoadCredential = [ ]; };
  };
  wrongTemplate = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { sops.templates."anytls.json".content = "{}"; };
  };
  wrongRouteOrder = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      let
        rendered = builtins.fromJSON config.sops.templates."anytls.json".content;
        rules = rendered.route.rules;
      in
      lib.recursiveUpdate config {
        sops.templates."anytls.json".content = builtins.toJSON (
          rendered
          // {
            route = rendered.route // {
              rules = [
                (builtins.elemAt rules 1)
                (builtins.elemAt rules 0)
                (builtins.elemAt rules 2)
              ];
            };
          }
        );
      };
  };
  missingCidrReject = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      let
        rendered = builtins.fromJSON config.sops.templates."anytls.json".content;
      in
      lib.recursiveUpdate config {
        sops.templates."anytls.json".content = builtins.toJSON (
          rendered
          // {
            route = rendered.route // {
              rules = [
                (builtins.elemAt rendered.route.rules 0)
                (builtins.elemAt rendered.route.rules 2)
              ];
            };
          }
        );
      };
  };
  missingSecretRestart = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        sops.secrets."fixture/anytls-phone-password".restartUnits = [ "profile-publisher.service" ];
      };
  };
  missingAcmeReload = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { security.acme.certs.anytls-example.reloadServices = [ ]; };
  };
  wrongPackage = evaluateWith {
    rawSettings = baseSettings;
    targetPkgs = packagePkgs // {
      sing-box = pkgs.hello;
    };
  };
  armPkgs = packagePkgs // {
    stdenv = packagePkgs.stdenv // {
      hostPlatform = packagePkgs.stdenv.hostPlatform // {
        system = "aarch64-linux";
      };
    };
  };
  unsupportedPlatform = evaluateWith {
    rawSettings = baseSettings;
    targetPkgs = armPkgs;
  };
  highPort = evaluateWith {
    rawSettings = baseSettings // {
      port = 8443;
    };
  };
  provider = enabled.instance.exports.vpnProvider;
  tableContent = enabled.table.content;
  source = builtins.readFile ../clanServices/anytls/default.nix;
  disabledResults = {
    exports = disabled.instance.exports == { };
    assertions = disabled.module.assertions == [ ];
    users = disabled.module.users.groups == { } && disabled.module.users.users == { };
    secrets = disabled.module.sops.secrets == { };
    templates = disabled.module.sops.templates == { };
    tables = disabled.module.networking.nftables.tables == { };
    services = disabled.module.systemd.services == { };
    acme = disabled.module.security.acme.certs == { };
    overlays = disabled.module.nixpkgs.overlays == [ ];
  };
  disabledContract = builtins.all (value: value) (builtins.attrValues disabledResults);
  schemaContract =
    schemaAccepts baseSettings
    && schemaAccepts (
      baseSettings
      // {
        users = map (user: user // { name = "device.${user.name}"; }) baseSettings.users;
      }
    )
    && schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          port = 8443;
          path = "/private-dns-query";
        };
      }
    )
    && !(schemaAccepts (baseSettings // { bindIPv4 = "0.0.0.0"; }))
    && !(schemaAccepts (baseSettings // { bindIPv4 = "192.0.2.999"; }))
    && !(schemaAccepts (baseSettings // { domain = "localhost"; }))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          domain = "DNS.example.invalid";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          domain = "localhost";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "10.0.0.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "100.64.0.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "127.0.0.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "169.254.1.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "192.0.2.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "224.0.0.53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          ipv4 = "2001:db8::53";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          path = "dns-query";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          headers.Host = "dns.example.invalid";
        };
      }
    ))
    && !(schemaAccepts (baseSettings // { dnsResolverIPv4s = [ "9.9.9.9" ]; }))
    && !(schemaAccepts (
      baseSettings
      // {
        users = [
          {
            name = "bad identity";
            passwordSecretName = "fixture/anytls";
          }
        ];
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        users = [
          {
            name = "phone";
            passwordSecretName = "../secret";
          }
        ];
      }
    ))
    && !(schemaAccepts (baseSettings // { serverName = "other.example.invalid"; }))
    && !duplicateUsers.assertionsPass
    && !duplicateSecrets.assertionsPass
    && !noUsers.assertionsPass
    && !duplicateInstances.assertionsPass
    && !noInstanceClaim.assertionsPass
    && alternateNameservers.assertionsPass
    && !disabledNftables.assertionsPass
    && !unsupportedPlatform.assertionsPass;
  configContract =
    enabled.assertionsPass
    &&
      enabled.rendered == {
        log.level = "info";
        dns = {
          servers = [
            {
              type = "https";
              tag = "own-adguard-doh";
              server = "93.184.216.34";
              server_port = 443;
              path = "/dns-query";
              tls = {
                enabled = true;
                server_name = "dns.example.invalid";
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
            listen = "192.0.2.14";
            listen_port = 443;
            users = [
              {
                name = "phone";
                password = "<SOPS:fixture/anytls-phone-password:PLACEHOLDER>";
              }
              {
                name = "laptop";
                password = "<SOPS:fixture/anytls-laptop-password:PLACEHOLDER>";
              }
            ];
            tls = {
              enabled = true;
              server_name = "anytls.example.invalid";
              min_version = "1.3";
              max_version = "1.3";
              certificate_path = "/run/credentials/anytls.service/certificate.pem";
              key_path = "/run/credentials/anytls.service/private-key.pem";
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
              ip_cidr = [
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
              ];
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
      }
    && !(builtins.head enabled.rendered.inbounds ? padding_scheme)
    && !(builtins.head enabled.rendered.inbounds ? idle_session_timeout)
    && !(builtins.head enabled.rendered.inbounds ? idle_session_check_interval)
    && !(builtins.head enabled.rendered.inbounds ? min_idle_session)
    && !(enabled.rendered ? experimental)
    && !(builtins.head enabled.rendered.dns.servers ? headers)
    && !((builtins.head enabled.rendered.dns.servers).tls ? insecure)
    && !(enabled.module.networking ? nameservers);
  routeRules = enabled.rendered.route.rules;
  routeGuardContract =
    lib.length routeRules == 3
    &&
      builtins.elemAt routeRules 0 == {
        inbound = [ "anytls-in" ];
        action = "resolve";
        server = "own-adguard-doh";
        strategy = "ipv4_only";
      }
    &&
      builtins.elemAt routeRules 1 == {
        inbound = [ "anytls-in" ];
        ip_cidr = [
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
        ];
        action = "reject";
      }
    &&
      builtins.elemAt routeRules 2 == {
        inbound = [ "anytls-in" ];
        ip_is_private = true;
        action = "reject";
      }
    && !wrongRouteOrder.assertionsPass
    && !missingCidrReject.assertionsPass;
  exportContract =
    provider == {
      schemaVersion = 2;
      instanceId = "fixture--anytls";
      machine = "fixture";
      role = "gateway";
      protocol = "anytls";
      enabled = true;
      endpoint = {
        domain = "anytls.example.invalid";
        ipv4 = "192.0.2.14";
        port = 443;
        transport = "tcp";
      };
      transportMetadata = {
        protocol = "anytls";
        tlsServerName = "anytls.example.invalid";
        userNames = [
          "phone"
          "laptop"
        ];
        tlsVerify = true;
        tlsMinVersion = "1.3";
        credentialEncoding = "base64url";
      };
      profileNames = [
        "phone"
        "laptop"
      ];
      secretNames.users = {
        phone = "fixture/anytls-phone-password";
        laptop = "fixture/anytls-laptop-password";
      };
    };
  guardContract =
    enabled.table.enable
    && enabled.table.family == "inet"
    && !(lib.hasInfix "chain input_guard" tableContent)
    && !(lib.hasInfix "ip daddr !=" tableContent)
    && lib.hasInfix ''meta skuid "anytls" ip saddr 192.0.2.14 tcp sport 443 ct direction reply accept'' tableContent
    && !(lib.hasInfix ''meta skuid "anytls" ct direction reply accept'' tableContent)
    && !(lib.hasInfix "udp dport 53 accept" tableContent)
    && !(lib.hasInfix "tcp dport 53 accept" tableContent)
    && lib.hasInfix "100.64.0.0/10" tableContent
    && lib.hasInfix "169.254.0.0/16" tableContent
    && lib.hasInfix "224.0.0.0/4" tableContent
    && lib.hasInfix ''meta skuid "anytls" ip6 daddr ::/0 drop'' tableContent
    && !weakenedGuard.assertionsPass
    && !disabledGuardTable.assertionsPass
    && lib.hasInfix "ip daddr 192.0.2.14 tcp dport 443 accept" (
      unwrap enabled.module.networking.firewall.extraInputRules
    )
    && !(enabled.module.networking.firewall ? allowedTCPPorts)
    && !(enabled.module.networking.firewall ? trustedInterfaces);
  runtimeResults = {
    identity =
      enabled.unit.serviceConfig.Type == "exec"
      && enabled.unit.serviceConfig.User == "anytls"
      && enabled.unit.serviceConfig.Group == "anytls"
      && !(enabled.unit.serviceConfig ? DynamicUser);
    command =
      enabled.unit.serviceConfig.ExecStart
      == "${lib.getExe singBoxPackage} run -c /run/secrets-rendered/anytls.json"
      && lib.hasPrefix "+" enabled.unit.serviceConfig.ExecStartPre;
    credentials =
      enabled.unit.serviceConfig.LoadCredential == [
        "certificate.pem:/var/lib/acme/anytls-example/fullchain.pem"
        "private-key.pem:/var/lib/acme/anytls-example/key.pem"
      ];
    directories =
      enabled.unit.serviceConfig.StateDirectory == "anytls"
      && enabled.unit.serviceConfig.RuntimeDirectory == "anytls";
    capabilities =
      enabled.unit.serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
      && highPort.unit.serviceConfig.AmbientCapabilities == [ ];
    addressFamilies =
      enabled.unit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_UNIX"
      ];
    ordering =
      enabled.unit.requires == [ "nftables.service" ]
      && enabled.unit.bindsTo == [ "nftables.service" ]
      && enabled.unit.partOf == [ "nftables.service" ]
      && builtins.elem "nftables.service" enabled.unit.after
      && builtins.elem "sops-install-secrets.service" enabled.unit.after;
    readiness =
      lib.hasInfix "expected_local=0E0200C0:01BB" enabled.unit.postStart
      && lib.hasInfix ''/proc/"$MAINPID"/net/tcp'' enabled.unit.postStart
      && !(lib.hasInfix "/net/tcp6" enabled.unit.postStart)
      && lib.hasInfix ''/proc/"$MAINPID"/fd/*'' enabled.unit.postStart
      && lib.hasInfix ''"socket:[$inode]"'' enabled.unit.postStart
      && lib.hasInfix ''"$state" != "0A"'' enabled.unit.postStart;
    template =
      enabled.template.owner == "anytls"
      && enabled.template.group == "anytls"
      && enabled.template.mode == "0400"
      && builtins.elem "anytls.service" enabled.template.restartUnits
      &&
        builtins.elem "profile-publisher.service"
          enabled.effectiveConfig.sops.templates."anytls.json".restartUnits;
    secrets =
      builtins.all (
        secret:
        secret.owner == "root"
        && secret.group == "root"
        && secret.mode == "0400"
        && builtins.elem "anytls.service" secret.restartUnits
      ) (builtins.attrValues enabled.module.sops.secrets)
      && builtins.all (secret: builtins.elem "profile-publisher.service" secret.restartUnits) (
        builtins.attrValues enabled.effectiveConfig.sops.secrets
      );
    acme = builtins.elem "anytls.service" enabled.module.security.acme.certs.anytls-example.reloadServices;
    negativeOverrides =
      !wrongIdentity.assertionsPass
      && !dynamicIdentity.assertionsPass
      && !wrongCommand.assertionsPass
      && !wrongCredentials.assertionsPass
      && !wrongTemplate.assertionsPass
      && !wrongRouteOrder.assertionsPass
      && !missingCidrReject.assertionsPass
      && !missingSecretRestart.assertionsPass
      && !missingAcmeReload.assertionsPass
      && !wrongPackage.assertionsPass;
    version = lib.getVersion singBoxPackage == "1.14.0";
  };
  runtimeContract = builtins.all (value: value) (builtins.attrValues runtimeResults);
  passwordGuardContract =
    lib.hasInfix "byte_count" source
    && lib.hasInfix "base64url_byte_count" source
    && lib.hasInfix ''"$byte_count" -gt 64'' source
    && lib.hasInfix "tr -cd 'A-Za-z0-9_-'" source
    && !(lib.hasInfix "tr -d '\\n'" source)
    && !(lib.hasInfix "echo \"$password\"" source);
  contract =
    schemaContract
    && configContract
    && exportContract
    && guardContract
    && routeGuardContract
    && runtimeContract
    && passwordGuardContract
    && disabledContract;
in
if !contract then
  throw "AnyTLS schema, export, config, runtime, nftables guard, or secret contract failed: ${
    builtins.toJSON {
      inherit
        configContract
        disabledContract
        disabledResults
        exportContract
        guardContract
        passwordGuardContract
        routeGuardContract
        runtimeContract
        runtimeResults
        schemaContract
        ;
    }
  }"
else
  {
    all = true;
    inherit
      configContract
      disabledContract
      exportContract
      guardContract
      passwordGuardContract
      routeGuardContract
      runtimeContract
      schemaContract
      ;
  }
