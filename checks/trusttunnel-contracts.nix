{
  inputs,
  pkgs,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  trustTunnelPackage = self.packages.${system}.trusttunnel-endpoint;
  service = import ../clanServices/trusttunnel/default.nix {
    inherit lib;
    trustTunnelPackageFor = _: trustTunnelPackage;
  };
  interface = service.roles.gateway.interface { inherit lib; };
  baseSettings = {
    enable = true;
    bindIPv4 = "192.0.2.15";
    domain = "trusttunnel.example.invalid";
    port = 443;
    acmeCertName = "trusttunnel-example";
    users = [
      {
        name = "phone";
        passwordSecretName = "fixture/trusttunnel-phone-password";
      }
      {
        name = "laptop";
        passwordSecretName = "fixture/trusttunnel-laptop-password";
      }
    ];
    dnsResolverIPv4s = [
      "127.0.0.1"
      "192.0.2.53"
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
    trusttunnel-endpoint = trustTunnelPackage;
  };
  baseConfigFor =
    settings: activeInstances:
    let
      names = map (user: user.passwordSecretName) settings.users;
    in
    {
      clanwright.vpn.trusttunnel = { inherit activeInstances; };
      networking = {
        nameservers = settings.dnsResolverIPv4s;
        firewall = {
          enable = true;
          backend = "nftables";
          extraInputRules = "";
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
        templates."trusttunnel.toml" = {
          path = "/run/secrets-rendered/trusttunnel.toml";
          restartUnits = [ "profile-publisher.service" ];
        };
      };
    };
  evaluateWith =
    {
      rawSettings,
      activeInstances ? [ "fixture--trusttunnel" ],
      targetPkgs ? packagePkgs,
      mutateEffectiveConfig ? (value: value),
    }:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--trusttunnel";
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
            firewall = baseConfig.networking.firewall // {
              extraInputRules = unwrap bootstrapModule.networking.firewall.extraInputRules;
            };
            nftables = baseConfig.networking.nftables // {
              tables.vpn_trusttunnel_egress = unwrap bootstrapModule.networking.nftables.tables.vpn_trusttunnel_egress;
            };
          };
          security.acme.certs.${settings.acmeCertName}.reloadServices =
            unwrap
              bootstrapModule.security.acme.certs.${settings.acmeCertName}.reloadServices;
          sops = baseConfig.sops // {
            secrets = lib.genAttrs (map (user: user.passwordSecretName) settings.users) mergeSecret;
            templates."trusttunnel.toml" =
              baseConfig.sops.templates."trusttunnel.toml"
              // (unwrap bootstrapModule.sops.templates."trusttunnel.toml")
              // {
                restartUnits =
                  baseConfig.sops.templates."trusttunnel.toml".restartUnits
                  ++ (unwrap bootstrapModule.sops.templates."trusttunnel.toml").restartUnits;
              };
          };
          systemd.services.trusttunnel = unwrap bootstrapModule.systemd.services.trusttunnel;
        }
      );
      definition = instance.nixosModule {
        config = effectiveConfig;
        pkgs = targetPkgs;
      };
      module = definition.config;
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
      table = unwrap (module.networking.nftables.tables.vpn_trusttunnel_egress or null);
      template = unwrap (module.sops.templates."trusttunnel.toml" or null);
      unit = unwrap module.systemd.services.trusttunnel;
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
  noResolvers = evaluateWith {
    rawSettings = baseSettings // {
      dnsResolverIPv4s = [ ];
    };
  };
  duplicateResolvers = evaluateWith {
    rawSettings = baseSettings // {
      dnsResolverIPv4s = [
        "127.0.0.1"
        "127.0.0.1"
      ];
    };
  };
  duplicateInstances = evaluateWith {
    rawSettings = baseSettings;
    activeInstances = [
      "fixture--trusttunnel"
      "fixture--second-trusttunnel"
    ];
  };
  noInstanceClaim = evaluateWith {
    rawSettings = baseSettings;
    activeInstances = [ ];
  };
  wrongNameservers = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { networking.nameservers = [ "1.1.1.1" ]; };
  };
  weakenedGuard = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        networking.nftables.tables.vpn_trusttunnel_egress.content =
          "chain output { type filter hook output priority filter; policy accept; }";
      };
  };
  disabledGuard = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { networking.nftables.tables.vpn_trusttunnel_egress.enable = false; };
  };
  weakenedIngress = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { networking.firewall.extraInputRules = ""; };
  };
  wrongIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { systemd.services.trusttunnel.serviceConfig.User = "root"; };
  };
  dynamicIdentity = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { systemd.services.trusttunnel.serviceConfig.DynamicUser = true; };
  };
  wrongCommand = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { systemd.services.trusttunnel.serviceConfig.ExecStart = "/bin/false"; };
  };
  wrongCredentials = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { systemd.services.trusttunnel.serviceConfig.LoadCredential = [ ]; };
  };
  staleCredentialReload = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        systemd.services.trusttunnel.serviceConfig.ExecReload = "/bin/kill -HUP $MAINPID";
      };
  };
  wrongCapabilities = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        systemd.services.trusttunnel.serviceConfig.CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      };
  };
  enabledIPv6 = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        systemd.services.trusttunnel.serviceConfig.RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
  };
  unboundFirewallLifecycle = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { systemd.services.trusttunnel.bindsTo = [ ]; };
  };
  wrongTemplate = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config: lib.recursiveUpdate config { sops.templates."trusttunnel.toml".content = ""; };
  };
  missingSecretRestart = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config {
        sops.secrets."fixture/trusttunnel-phone-password".restartUnits = [ "profile-publisher.service" ];
      };
  };
  missingAcmeRestart = evaluateWith {
    rawSettings = baseSettings;
    mutateEffectiveConfig =
      config:
      lib.recursiveUpdate config { security.acme.certs.trusttunnel-example.reloadServices = [ ]; };
  };
  wrongPackage = evaluateWith {
    rawSettings = baseSettings;
    targetPkgs = packagePkgs // {
      trusttunnel-endpoint = pkgs.hello;
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
  templateContent = enabled.template.content;
  source = builtins.readFile ../clanServices/trusttunnel/default.nix;
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
    && !(schemaAccepts (baseSettings // { bindIPv4 = "0.0.0.0"; }))
    && !(schemaAccepts (baseSettings // { bindIPv4 = "192.0.2.999"; }))
    && !(schemaAccepts (baseSettings // { domain = "localhost"; }))
    && !(schemaAccepts (baseSettings // { dnsResolverIPv4s = [ "2001:db8::53" ]; }))
    && !(schemaAccepts (baseSettings // { quic = false; }))
    && !(schemaAccepts (
      baseSettings
      // {
        users = [
          {
            name = "bad identity";
            passwordSecretName = "fixture/trusttunnel";
          }
        ];
      }
    ))
    && !duplicateUsers.assertionsPass
    && !duplicateSecrets.assertionsPass
    && !noUsers.assertionsPass
    && !noResolvers.assertionsPass
    && !duplicateResolvers.assertionsPass
    && !duplicateInstances.assertionsPass
    && !noInstanceClaim.assertionsPass
    && !wrongNameservers.assertionsPass
    && !unsupportedPlatform.assertionsPass;
  exportContract =
    provider == {
      schemaVersion = 2;
      instanceId = "fixture--trusttunnel";
      machine = "fixture";
      role = "gateway";
      protocol = "trusttunnel";
      enabled = true;
      endpoint = {
        domain = "trusttunnel.example.invalid";
        ipv4 = "192.0.2.15";
        port = 443;
        transport = "tcp";
      };
      transportMetadata = {
        protocol = "trusttunnel";
        userNames = [
          "phone"
          "laptop"
        ];
        tlsServerName = "trusttunnel.example.invalid";
        tlsVerify = true;
        credentialEncoding = "base64url";
        upstreamProtocol = "http2";
      };
      profileNames = [
        "phone"
        "laptop"
      ];
      secretNames.users = {
        phone = "fixture/trusttunnel-phone-password";
        laptop = "fixture/trusttunnel-laptop-password";
      };
    };
  configContract =
    enabled.assertionsPass
    && lib.hasInfix "credentials_file = \"\${credentialsConfigPath}\"" source
    && lib.hasInfix "ipv6_available = false" source
    && lib.hasInfix "allow_private_network_connections = false" source
    && lib.hasInfix "auth_failure_status_code = 404" source
    && lib.hasInfix "non_connect_auth_failure_status_code = 404" source
    && lib.hasInfix "[listen_protocols.http2]" source
    && lib.hasInfix ''password = "<SOPS:fixture/trusttunnel-phone-password:PLACEHOLDER>"'' templateContent
    && !(lib.hasInfix "max_http2_conns" templateContent)
    && !(lib.hasInfix "listen_protocols.http1" source)
    && !(lib.hasInfix "listen_protocols.quic" source)
    && !(lib.hasInfix "[icmp]" source)
    && !(lib.hasInfix "rules_file" source)
    && !(lib.hasInfix "[metrics]" source)
    && !(lib.hasInfix "[reverse_proxy]" source);
  guardContract =
    enabled.table.enable
    && enabled.table.family == "inet"
    && lib.hasInfix ''meta skuid "trusttunnel" ip saddr 192.0.2.15 tcp sport 443 ct direction reply accept'' tableContent
    && lib.hasInfix "ip daddr { 127.0.0.1, 192.0.2.53 } udp dport 53 accept" tableContent
    && lib.hasInfix "ip daddr { 127.0.0.1, 192.0.2.53 } tcp dport 53 accept" tableContent
    && lib.hasInfix "100.64.0.0/10" tableContent
    && lib.hasInfix "169.254.0.0/16" tableContent
    && lib.hasInfix ''meta skuid "trusttunnel" ip6 daddr ::/0 drop'' tableContent
    && lib.hasInfix "ip daddr 192.0.2.15 tcp dport 443 accept" enabled.effectiveConfig.networking.firewall.extraInputRules
    && !weakenedGuard.assertionsPass
    && !disabledGuard.assertionsPass
    && !weakenedIngress.assertionsPass;
  runtimeContract =
    enabled.unit.serviceConfig.Type == "exec"
    && enabled.unit.serviceConfig.User == "trusttunnel"
    && enabled.unit.serviceConfig.Group == "trusttunnel"
    && !(enabled.unit.serviceConfig ? DynamicUser)
    && !(enabled.unit.serviceConfig ? ExecReload)
    && lib.hasPrefix "${trustTunnelPackage}/bin/trusttunnel_endpoint --loglvl info " enabled.unit.serviceConfig.ExecStart
    && lib.hasSuffix "trusttunnel-hosts.toml" enabled.unit.serviceConfig.ExecStart
    && !(lib.hasInfix "--logfile" enabled.unit.serviceConfig.ExecStart)
    && !(lib.hasInfix "--sentry_dsn" enabled.unit.serviceConfig.ExecStart)
    && !(lib.hasInfix "--client_config" enabled.unit.serviceConfig.ExecStart)
    && lib.hasPrefix "+" enabled.unit.serviceConfig.ExecStartPre
    &&
      enabled.unit.serviceConfig.LoadCredential == [
        "certificate.pem:/var/lib/acme/trusttunnel-example/fullchain.pem"
        "private-key.pem:/var/lib/acme/trusttunnel-example/key.pem"
      ]
    && enabled.unit.serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
    && enabled.unit.serviceConfig.CapabilityBoundingSet == [ "CAP_NET_BIND_SERVICE" ]
    && highPort.unit.serviceConfig.AmbientCapabilities == [ ]
    && highPort.unit.serviceConfig.CapabilityBoundingSet == [ ]
    &&
      enabled.unit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_UNIX"
      ]
    && enabled.unit.requires == [ "nftables.service" ]
    && enabled.unit.bindsTo == [ "nftables.service" ]
    && enabled.unit.partOf == [ "nftables.service" ]
    && lib.hasInfix "/proc/\"$MAINPID\"/net/tcp" enabled.unit.postStart
    && lib.hasInfix ''"socket:[$inode]"'' enabled.unit.postStart
    && !wrongIdentity.assertionsPass
    && !dynamicIdentity.assertionsPass
    && !wrongCommand.assertionsPass
    && !wrongCredentials.assertionsPass
    && !staleCredentialReload.assertionsPass
    && !wrongCapabilities.assertionsPass
    && !enabledIPv6.assertionsPass
    && !unboundFirewallLifecycle.assertionsPass
    && !wrongTemplate.assertionsPass
    && !missingSecretRestart.assertionsPass
    && !missingAcmeRestart.assertionsPass
    && !wrongPackage.assertionsPass
    && lib.getVersion trustTunnelPackage == "1.1.0";
  passwordGuardContract =
    lib.hasInfix "byte_count" source
    && lib.hasInfix "base64url_byte_count" source
    && lib.hasInfix ''"$byte_count" -gt 64'' source
    && lib.hasInfix "tr -cd 'A-Za-z0-9_-'" source
    && !(lib.hasInfix "tr -d '\\n'" source)
    && !(lib.hasInfix "echo \"$password\"" source);
  contract =
    schemaContract
    && exportContract
    && configContract
    && guardContract
    && runtimeContract
    && passwordGuardContract
    && disabledContract;
in
if !contract then
  throw "TrustTunnel schema, export, configuration, runtime, nftables, or secret contract failed: ${
    builtins.toJSON {
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
