{
  inputs,
  pkgs,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  mieruPackage = self.packages.${system}.mieru;
  service = import ../clanServices/mieru/default.nix {
    inherit lib;
    mieruPackageFor = _: mieruPackage;
  };
  interface = service.roles.gateway.interface { inherit lib; };
  baseSettings = {
    enable = true;
    ingressIPv4 = "192.0.2.13";
    port = 443;
    users = [
      {
        name = "phone";
        passwordSecretName = "fixture/mieru-phone-password";
      }
      {
        name = "laptop";
        passwordSecretName = "fixture/mieru-laptop-password";
      }
    ];
    dnsResolverIPv4s = [
      "127.0.0.1"
      "9.9.9.9"
    ];
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
    mieru = mieruPackage;
  };
  baseConfigFor =
    settings: activeInstances:
    let
      names = map (user: user.passwordSecretName) settings.users;
    in
    {
      clanwright.vpn.mieru = { inherit activeInstances; };
      networking = {
        nameservers = settings.dnsResolverIPv4s;
        firewall = {
          enable = true;
          backend = "nftables";
        };
        nftables.enable = true;
      };
      sops = {
        useSystemdActivation = true;
        placeholder = lib.genAttrs names (name: "<SOPS:${name}:PLACEHOLDER>");
        secrets = lib.genAttrs names (name: {
          path = "/run/secrets/${name}";
        });
        templates."mita.json".path = "/run/secrets-rendered/mita.json";
      };
    };
  evaluateWith =
    {
      rawSettings,
      activeInstances ? [ "fixture--mieru" ],
      targetPkgs ? packagePkgs,
      mutateEffectiveConfig ? (value: value),
    }:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--mieru";
        machine.name = "fixture";
      };
      baseConfig = baseConfigFor settings activeInstances;
      bootstrap = instance.nixosModule {
        config = baseConfig;
        pkgs = targetPkgs;
      };
      bootstrapModule = bootstrap.config;
      effectiveConfig = mutateEffectiveConfig (
        baseConfig
        // {
          networking = baseConfig.networking // {
            nftables = baseConfig.networking.nftables // {
              tables.vpn_mieru_egress = unwrap bootstrapModule.networking.nftables.tables.vpn_mieru_egress;
            };
          };
          systemd.services.mita = unwrap bootstrapModule.systemd.services.mita;
        }
      );
      definition = instance.nixosModule {
        config = effectiveConfig;
        pkgs = targetPkgs;
      };
      module = definition.config;
      template = unwrap (module.sops.templates."mita.json" or null);
    in
    {
      inherit
        definition
        effectiveConfig
        instance
        module
        settings
        ;
      assertionsPass = builtins.all (entry: entry.assertion) module.assertions;
      rendered = if template == null then null else builtins.fromJSON template.content;
      table = unwrap (module.networking.nftables.tables.vpn_mieru_egress or null);
      inherit template;
      unit = unwrap module.systemd.services.mita;
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
      "fixture--mieru"
      "fixture--second-mieru"
    ];
  };
  noInstanceClaim = evaluateWith {
    rawSettings = baseSettings;
    activeInstances = [ ];
  };
  wrongNameservers = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        networking = config.networking // {
          nameservers = [ "1.1.1.1" ];
        };
      };
  };
  disabledNftables = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        networking = config.networking // {
          nftables = config.networking.nftables // {
            enable = false;
          };
        };
      };
  };
  weakenedGuard = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        networking = config.networking // {
          nftables = config.networking.nftables // {
            tables.vpn_mieru_egress = config.networking.nftables.tables.vpn_mieru_egress // {
              content = "chain output { type filter hook output priority filter; policy accept; }";
            };
          };
        };
      };
  };
  disabledGuardTable = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        networking = config.networking // {
          nftables = config.networking.nftables // {
            tables.vpn_mieru_egress = config.networking.nftables.tables.vpn_mieru_egress // {
              enable = false;
            };
          };
        };
      };
  };
  wrongIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        systemd.services.mita = config.systemd.services.mita // {
          serviceConfig = config.systemd.services.mita.serviceConfig // {
            User = "root";
          };
        };
      };
  };
  dynamicIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        systemd.services.mita = config.systemd.services.mita // {
          serviceConfig = config.systemd.services.mita.serviceConfig // {
            DynamicUser = true;
          };
        };
      };
  };
  wrongCommand = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      config
      // {
        systemd.services.mita = config.systemd.services.mita // {
          serviceConfig = config.systemd.services.mita.serviceConfig // {
            ExecStart = "/bin/false";
          };
        };
      };
  };
  wrongPackage = evaluateWith {
    rawSettings = baseSettings;
    targetPkgs = packagePkgs // {
      mieru = pkgs.hello;
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
  source = builtins.readFile ../clanServices/mieru/default.nix;
  disabledResults = {
    exports = disabled.instance.exports == { };
    assertions = disabled.module.assertions == [ ];
    users = disabled.module.users.groups == { } && disabled.module.users.users == { };
    secrets = disabled.module.sops.secrets == { };
    templates = disabled.module.sops.templates == { };
    tables = disabled.module.networking.nftables.tables == { };
    services = disabled.module.systemd.services == { };
    overlays = disabled.module.nixpkgs.overlays == [ ];
  };
  disabledContract = builtins.all (value: value) (builtins.attrValues disabledResults);
  schemaContract =
    schemaAccepts baseSettings
    && !(schemaAccepts (baseSettings // { ingressIPv4 = "0.0.0.0"; }))
    && !(schemaAccepts (baseSettings // { ingressIPv4 = "192.0.2.999"; }))
    && !(schemaAccepts (baseSettings // { dnsResolverIPv4s = [ ]; }))
    && !(schemaAccepts (
      baseSettings
      // {
        dnsResolverIPv4s = [
          "9.9.9.9"
          "9.9.9.9"
        ];
      }
    ))
    && !(schemaAccepts (baseSettings // { dnsResolverIPv4s = [ "dns.example.invalid" ]; }))
    && !(schemaAccepts (
      baseSettings
      // {
        users = [
          {
            name = "bad identity";
            passwordSecretName = "fixture/mieru-password";
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
    && !(schemaAccepts (baseSettings // { dnsUpstreamIPv4s = [ "9.9.9.9" ]; }))
    && !duplicateUsers.assertionsPass
    && !duplicateSecrets.assertionsPass
    && !noUsers.assertionsPass
    && !duplicateInstances.assertionsPass
    && !noInstanceClaim.assertionsPass
    && !wrongNameservers.assertionsPass
    && !disabledNftables.assertionsPass
    && !unsupportedPlatform.assertionsPass;
  configContract =
    enabled.assertionsPass
    &&
      enabled.rendered == {
        dns.dualStack = "ONLY_IPv4";
        loggingLevel = "INFO";
        portBindings = [
          {
            port = 443;
            protocol = "TCP";
          }
        ];
        users = [
          {
            allowLoopbackIP = false;
            allowPrivateIP = false;
            name = "phone";
            password = "<SOPS:fixture/mieru-phone-password:PLACEHOLDER>";
          }
          {
            allowLoopbackIP = false;
            allowPrivateIP = false;
            name = "laptop";
            password = "<SOPS:fixture/mieru-laptop-password:PLACEHOLDER>";
          }
        ];
      }
    && !(enabled.rendered ? trafficPattern)
    && !(enabled.rendered ? mtu)
    && !(enabled.rendered.dns ? servers)
    && !(enabled.rendered ? egress);
  exportContract =
    provider == {
      schemaVersion = 2;
      instanceId = "fixture--mieru";
      machine = "fixture";
      role = "gateway";
      protocol = "mieru";
      enabled = true;
      endpoint = {
        domain = null;
        ipv4 = "192.0.2.13";
        port = 443;
        transport = "tcp";
      };
      transportMetadata = {
        protocol = "mieru";
        userNames = [
          "phone"
          "laptop"
        ];
        credentialEncoding = "base64url";
      };
      profileNames = [
        "phone"
        "laptop"
      ];
      secretNames.users = {
        phone = "fixture/mieru-phone-password";
        laptop = "fixture/mieru-laptop-password";
      };
    };
  guardContract =
    enabled.table.enable
    && enabled.table.family == "inet"
    && lib.hasInfix "chain input_guard" tableContent
    && lib.hasInfix "type filter hook input priority -10" tableContent
    && lib.hasInfix "meta nfproto ipv6 tcp dport 443 drop" tableContent
    && lib.hasInfix "ip daddr != 192.0.2.13 tcp dport 443 drop" tableContent
    && lib.hasInfix ''meta skuid "mita" ct direction reply accept'' tableContent
    && lib.hasInfix "ip daddr { 127.0.0.1, 9.9.9.9 } udp dport 53 accept" tableContent
    && lib.hasInfix "ip daddr { 127.0.0.1, 9.9.9.9 } tcp dport 53 accept" tableContent
    && lib.hasInfix "100.64.0.0/10" tableContent
    && lib.hasInfix "169.254.0.0/16" tableContent
    && lib.hasInfix "224.0.0.0/4" tableContent
    && lib.hasInfix ''meta skuid "mita" ip6 daddr ::/0 drop'' tableContent
    && !weakenedGuard.assertionsPass
    && !disabledGuardTable.assertionsPass
    && lib.hasInfix "ip daddr 192.0.2.13 tcp dport 443 accept" (
      unwrap enabled.module.networking.firewall.extraInputRules
    )
    && !(enabled.module.networking.firewall ? allowedTCPPorts)
    && !(enabled.module.networking.firewall ? trustedInterfaces);
  runtimeContract =
    enabled.unit.serviceConfig.Type == "exec"
    && enabled.unit.serviceConfig.User == "mita"
    && enabled.unit.serviceConfig.Group == "mita"
    && !(enabled.unit.serviceConfig ? DynamicUser)
    && enabled.unit.serviceConfig.ExecStart == "${mieruPackage}/bin/mita run"
    && lib.hasPrefix "+" enabled.unit.serviceConfig.ExecStartPre
    &&
      enabled.unit.serviceConfig.Environment == [
        "MITA_CONFIG_JSON_FILE=/run/secrets-rendered/mita.json"
        "MITA_UDS_PATH=/run/mita/mita.sock"
        "MITA_LOG_NO_TIMESTAMP=true"
      ]
    && enabled.unit.serviceConfig.StateDirectory == "mita"
    && enabled.unit.serviceConfig.RuntimeDirectory == "mita"
    && enabled.unit.serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
    && highPort.unit.serviceConfig.AmbientCapabilities == [ ]
    && enabled.unit.requires == [ "nftables.service" ]
    && enabled.unit.bindsTo == [ "nftables.service" ]
    && enabled.unit.partOf == [ "nftables.service" ]
    && builtins.elem "nftables.service" enabled.unit.after
    && builtins.elem "sops-install-secrets.service" enabled.unit.after
    && lib.hasInfix "expected_tcp4=00000000:01BB" enabled.unit.postStart
    && lib.hasInfix "expected_tcp6=00000000000000000000000000000000:01BB" enabled.unit.postStart
    && lib.hasInfix ''/proc/"$MAINPID"/net/"$table"'' enabled.unit.postStart
    && lib.hasInfix ''/proc/"$MAINPID"/fd/*'' enabled.unit.postStart
    && lib.hasInfix ''"socket:[$inode]"'' enabled.unit.postStart
    && lib.hasInfix ''"$state" != "0A"'' enabled.unit.postStart
    && lib.hasInfix "seq 1 15" enabled.unit.postStart
    && lib.hasInfix "sleep 1" enabled.unit.postStart
    && lib.hasInfix "did not own the configured wildcard TCP listener" enabled.unit.postStart
    && enabled.template.owner == "mita"
    && enabled.template.group == "mita"
    && enabled.template.mode == "0400"
    && enabled.template.restartUnits == [ "mita.service" ]
    && builtins.all (
      secret:
      secret.owner == "root"
      && secret.group == "root"
      && secret.mode == "0400"
      && secret.restartUnits == [ "mita.service" ]
    ) (builtins.attrValues enabled.module.sops.secrets)
    && !wrongIdentity.assertionsPass
    && !dynamicIdentity.assertionsPass
    && !wrongCommand.assertionsPass
    && !wrongPackage.assertionsPass
    && lib.getVersion mieruPackage == "3.36.0";
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
    && runtimeContract
    && passwordGuardContract
    && disabledContract;
in
if !contract then
  throw "Mieru schema, export, runtime, nftables guard, or secret contract failed: ${
    builtins.toJSON {
      inherit
        configContract
        disabledContract
        disabledResults
        exportContract
        guardContract
        passwordGuardContract
        runtimeContract
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
      runtimeContract
      schemaContract
      ;
  }
