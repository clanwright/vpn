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
  nativeEvaluate = import ./lib/provider-evaluation.nix { inherit inputs; };
  evaluateWith =
    {
      rawSettings,
      activeInstances ? [ "fixture--trusttunnel" ],
      targetSystem ? "x86_64-linux",
      extraModule ? { },
    }:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--trusttunnel";
      };
      result = nativeEvaluate {
        inherit instance settings;
        prefix = "trusttunnel";
        system = targetSystem;
        baseModule = {
          security.acme = {
            acceptTerms = true;
            defaults.email = "fixture@example.invalid";
            certs.${settings.acmeCertName} = {
              inherit (settings) domain;
              webroot = "/var/lib/acme/acme-challenge";
            };
          };
          sops.secrets = lib.genAttrs (map (user: user.passwordSecretName) settings.users) (_: {
            restartUnits = [ "profile-publisher.service" ];
          });
          sops.templates."trusttunnel.toml".restartUnits = [ "profile-publisher.service" ];
        };

        extraModule = {
          imports = [ extraModule ];
          clanwright.vpn.trusttunnel.activeInstances = lib.mkForce activeInstances;
        };
      };
      inherit (result) module;
      template = module.sops.templates."trusttunnel.toml" or null;
    in
    result
    // {
      inherit instance settings template;
      table = module.networking.nftables.tables.vpn_trusttunnel_egress or null;
      unit = module.systemd.services.trusttunnel or null;

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
    extraModule = {
      networking.nameservers = lib.mkForce [ "1.1.1.1" ];
    };
  };
  weakenedGuard = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.nftables.tables.vpn_trusttunnel_egress.content =
        lib.mkForce "chain output { type filter hook output priority filter; policy accept; }";
    };
  };
  disabledGuard = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.nftables.tables.vpn_trusttunnel_egress.enable = lib.mkForce false;
    };
  };
  weakenedIngress = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.firewall.extraInputRules = lib.mkForce "";
    };
  };
  wrongIdentity = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.User = lib.mkForce "root";
    };
  };
  dynamicIdentity = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.DynamicUser = lib.mkForce true;
    };
  };
  wrongCommand = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.ExecStart = lib.mkForce "/bin/false";
    };
  };
  wrongCredentials = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.LoadCredential = lib.mkForce [ ];
    };
  };
  staleCredentialReload = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.ExecReload = lib.mkForce "/bin/kill -HUP $MAINPID";
    };
  };
  wrongCapabilities = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.CapabilityBoundingSet = lib.mkForce [ "CAP_NET_RAW" ];
    };
  };
  enabledIPv6 = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.serviceConfig.RestrictAddressFamilies = lib.mkForce [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };
  unboundFirewallLifecycle = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.trusttunnel.bindsTo = lib.mkForce [ ];
    };
  };
  wrongTemplate = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      sops.templates."trusttunnel.toml".content = lib.mkForce "";
    };
  };
  missingSecretRestart = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      sops.secrets."fixture/trusttunnel-phone-password".restartUnits = lib.mkForce [
        "profile-publisher.service"
      ];
    };
  };
  missingAcmeRestart = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      security.acme.certs.trusttunnel-example.reloadServices = lib.mkForce [ ];
    };
  };
  foreignHostAlias = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      nixpkgs.overlays = [ (_final: _prev: { trusttunnel-endpoint = pkgs.hello; }) ];
    };
  };
  unsupportedPlatform = evaluateWith {
    rawSettings = baseSettings;
    targetSystem = "aarch64-linux";
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
    assertions = disabled.assertions == [ ];
    users =
      !(disabled.module.users.groups ? trusttunnel) && !(disabled.module.users.users ? trusttunnel);
    secrets = disabled.module.sops.secrets == { };
    templates = disabled.module.sops.templates == { };
    tables = !(disabled.module.networking.nftables.tables ? vpn_trusttunnel_egress);
    services = !(disabled.module.systemd.services ? trusttunnel);
    acme = disabled.module.security.acme.certs == { };
    overlays = disabled.module.nixpkgs.overlays == [ ];
  };
  disabledContract =
    disabled.nativeAssertionsPass && builtins.all (value: value) (builtins.attrValues disabledResults);
  schemaContract =
    schemaAccepts baseSettings
    && schemaAccepts (
      baseSettings
      // {
        acmeCertName = "${lib.concatStrings (lib.replicate 63 "a")}.example.invalid";
      }
    )
    && !(schemaAccepts (baseSettings // { acmeCertName = "*.example.invalid"; }))
    && !(schemaAccepts (baseSettings // { bindIPv4 = "0.0.0.0"; }))
    && !(schemaAccepts (baseSettings // { bindIPv4 = "192.0.2.999"; }))
    && !(schemaAccepts (baseSettings // { domain = "localhost"; }))
    && schemaAccepts (baseSettings // { domain = "TrustTunnel.Example.INVALID"; })
    && builtins.all (domain: !(schemaAccepts (baseSettings // { inherit domain; }))) [
      "a..b"
      "a.-b"
      "a.b-"
      "${lib.concatStrings (lib.replicate 64 "a")}.example"
      (lib.concatStringsSep "." (lib.replicate 4 (lib.concatStrings (lib.replicate 63 "a"))))
    ]
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
    && duplicateUsers.rejects "users and their SOPS password secrets must be nonempty and unique."
    && duplicateSecrets.rejects "users and their SOPS password secrets must be nonempty and unique."
    && noUsers.rejects "users and their SOPS password secrets must be nonempty and unique."
    && noResolvers.rejects "consumer resolver IPv4 addresses must be nonempty and unique."
    && duplicateResolvers.rejects "consumer resolver IPv4 addresses must be nonempty and unique."
    && duplicateInstances.rejects "only one active instance may claim the singleton runtime per machine."
    && noInstanceClaim.rejects "only one active instance may claim the singleton runtime per machine."
    && wrongNameservers.rejects "networking.nameservers must exactly match dnsResolverIPv4s."
    && unsupportedPlatform.rejects "runtime support is restricted to x86_64-linux.";
  exportContract =
    provider == {
      schemaVersion = 3;
      connection.trusttunnel = {
        endpoint = {
          hostname = "trusttunnel.example.invalid";
          ipv4 = "192.0.2.15";
          port = 443;
        };
        clients = {
          phone.passwordSecret = "fixture/trusttunnel-phone-password";
          laptop.passwordSecret = "fixture/trusttunnel-laptop-password";
        };
      };
    };
  configContract =
    enabled.assertionsPass
    && enabled.nativeAssertionsPass
    && lib.hasInfix "credentials_file = \"\${credentialsConfigPath}\"" source
    && lib.hasInfix "ipv6_available = false" source
    && lib.hasInfix "allow_private_network_connections = false" source
    && lib.hasInfix "auth_failure_status_code = 404" source
    && lib.hasInfix "non_connect_auth_failure_status_code = 404" source
    && lib.hasInfix "[listen_protocols.http2]" source
    && lib.hasInfix ''password = "${enabled.module.sops.placeholder."fixture/trusttunnel-phone-password"}"'' templateContent
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
    && lib.hasInfix "ip daddr 192.0.2.15 tcp dport 443 accept" enabled.module.networking.firewall.extraInputRules
    && weakenedGuard.rejects "ingress and process egress guards must not be removed or weakened."
    && disabledGuard.rejects "ingress and process egress guards must not be removed or weakened."
    && weakenedIngress.rejects "ingress and process egress guards must not be removed or weakened.";
  hostAliasResults = {
    aliasActuallyDiffers =
      foreignHostAlias.pkgs.trusttunnel-endpoint == pkgs.hello
      && foreignHostAlias.pkgs.trusttunnel-endpoint != trustTunnelPackage;
    inherit (foreignHostAlias) assertionsPass nativeAssertionsPass;
    fixedExecStart = lib.hasPrefix "${trustTunnelPackage}/bin/trusttunnel_endpoint --loglvl info " foreignHostAlias.unit.serviceConfig.ExecStart;
    unchangedExecStart =
      foreignHostAlias.unit.serviceConfig.ExecStart == enabled.unit.serviceConfig.ExecStart;
    fixedRestartTrigger = foreignHostAlias.unit.restartTriggers == [ trustTunnelPackage ];
    noOwnedOverlay = enabled.module.nixpkgs.overlays == [ ];
  };
  hostAliasContract = builtins.deepSeq hostAliasResults (
    builtins.all (value: value) (builtins.attrValues hostAliasResults)
  );
  runtimeContract =
    highPort.assertionsPass
    && highPort.nativeAssertionsPass
    && enabled.unit.serviceConfig.Type == "exec"
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
    && wrongIdentity.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && dynamicIdentity.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && wrongCommand.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && wrongCredentials.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && staleCredentialReload.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && wrongCapabilities.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && enabledIPv6.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && unboundFirewallLifecycle.rejects "service lifecycle, command, credentials, capabilities, and IPv4-only sandbox must remain guarded."
    && wrongTemplate.rejects "credential template, permissions, and restart binding must remain guarded."
    && missingSecretRestart.rejects "password secret permissions and restart bindings must remain guarded."
    && missingAcmeRestart.rejects "ACME renewal must restart the service so LoadCredential copies are refreshed."
    && lib.getVersion trustTunnelPackage == "1.1.0";
  passwordValidatorSourceHygiene =
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
    && hostAliasContract
    && runtimeContract
    && passwordValidatorSourceHygiene
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
        hostAliasContract
        hostAliasResults
        passwordValidatorSourceHygiene
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
      hostAliasContract
      hostAliasResults
      passwordValidatorSourceHygiene
      runtimeContract
      schemaContract
      ;
  }
