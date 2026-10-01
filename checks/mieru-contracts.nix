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
  nativeEvaluate = import ./lib/provider-evaluation.nix { inherit inputs; };
  evaluateWith =
    {
      rawSettings,
      activeInstances ? [ "fixture--mieru" ],
      targetSystem ? "x86_64-linux",
      extraModule ? { },
    }:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--mieru";
      };
      result = nativeEvaluate {
        inherit instance settings;
        prefix = "mieru";
        system = targetSystem;

        extraModule = {
          imports = [ extraModule ];
          clanwright.vpn.mieru.activeInstances = lib.mkForce activeInstances;
        };
      };
      inherit (result) module;
      template = module.sops.templates."mita.json" or null;
    in
    result
    // {
      inherit instance settings template;
      table = module.networking.nftables.tables.vpn_mieru_egress or null;
      unit = module.systemd.services.mita or null;
      rendered = if template == null then null else builtins.fromJSON template.content;
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
    extraModule = {
      networking.nameservers = lib.mkForce [ "1.1.1.1" ];
    };
  };
  disabledNftables = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.nftables.enable = lib.mkForce false;
    };
  };
  weakenedGuard = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.nftables.tables.vpn_mieru_egress.content =
        lib.mkForce "chain output { type filter hook output priority filter; policy accept; }";
    };
  };
  disabledGuardTable = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      networking.nftables.tables.vpn_mieru_egress.enable = lib.mkForce false;
    };
  };
  wrongIdentity = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.mita.serviceConfig.User = lib.mkForce "root";
    };
  };
  dynamicIdentity = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.mita.serviceConfig.DynamicUser = lib.mkForce true;
    };
  };
  wrongCommand = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      systemd.services.mita.serviceConfig.ExecStart = lib.mkForce "/bin/false";
    };
  };
  foreignHostAlias = evaluateWith {
    rawSettings = baseSettings;
    extraModule = {
      nixpkgs.overlays = [ (_final: _prev: { mieru = pkgs.hello; }) ];
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
  dportsIn =
    text:
    lib.unique (
      map builtins.head (builtins.filter builtins.isList (builtins.split "dport ([0-9]+)" text))
    );
  source = builtins.readFile ../clanServices/mieru/default.nix;
  disabledResults = {
    exports = disabled.instance.exports == { };
    assertions = disabled.assertions == [ ];
    users = !(disabled.module.users.groups ? mita) && !(disabled.module.users.users ? mita);
    secrets = disabled.module.sops.secrets == { };
    templates = disabled.module.sops.templates == { };
    tables = !(disabled.module.networking.nftables.tables ? vpn_mieru_egress);
    services = !(disabled.module.systemd.services ? mita);
    overlays = disabled.module.nixpkgs.overlays == [ ];
  };
  disabledContract =
    disabled.nativeAssertionsPass && builtins.all (value: value) (builtins.attrValues disabledResults);
  schemaContract =
    schemaAccepts baseSettings
    && schemaAccepts (
      baseSettings
      // {
        users = map (user: user // { name = "device.${user.name}"; }) baseSettings.users;
      }
    )
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
    && duplicateUsers.rejects "device identities must be unique."
    && duplicateSecrets.rejects "every device must use a distinct SOPS password secret."
    && noUsers.rejects "at least one per-device user is required."
    && duplicateInstances.rejects "only one active instance may claim the upstream singleton mita runtime per machine."
    && noInstanceClaim.rejects "only one active instance may claim the upstream singleton mita runtime per machine."
    && wrongNameservers.rejects "networking.nameservers must exactly equal dnsResolverIPv4s because stock mita uses the system resolver."
    && disabledNftables.rejects "the module-owned process egress guard requires networking.nftables.enable."
    && unsupportedPlatform.rejects "runtime support is restricted to x86_64-linux.";
  configContract =
    enabled.assertionsPass
    && enabled.nativeAssertionsPass
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
            password = enabled.module.sops.placeholder."fixture/mieru-phone-password";
          }
          {
            allowLoopbackIP = false;
            allowPrivateIP = false;
            name = "laptop";
            password = enabled.module.sops.placeholder."fixture/mieru-laptop-password";
          }
        ];
      }
    && !(enabled.rendered ? trafficPattern)
    && !(enabled.rendered ? mtu)
    && !(enabled.rendered.dns ? servers)
    && !(enabled.rendered ? egress);
  exportContract =
    provider == {
      schemaVersion = 3;
      connection.mieru = {
        endpoint = {
          ipv4 = "192.0.2.13";
          port = 443;
        };
        clients = {
          phone.passwordSecret = "fixture/mieru-phone-password";
          laptop.passwordSecret = "fixture/mieru-laptop-password";
        };
      };
    };
  guardResults = {
    enabledTable = enabled.table.enable;
    inetFamily = enabled.table.family == "inet";
    inputChain = lib.hasInfix "chain input_guard" tableContent;
    inputPriority = lib.hasInfix "type filter hook input priority -10" tableContent;
    ipv6IngressDenial = lib.hasInfix "meta nfproto ipv6 tcp dport 443 drop" tableContent;
    otherIPv4IngressDenial = lib.hasInfix "ip daddr != 192.0.2.13 tcp dport 443 drop" tableContent;
    repliesPreserved = lib.hasInfix ''meta skuid "mita" ct direction reply accept'' tableContent;
    udpResolvers = lib.hasInfix "ip daddr { 127.0.0.1, 9.9.9.9 } udp dport 53 accept" tableContent;
    tcpResolvers = lib.hasInfix "ip daddr { 127.0.0.1, 9.9.9.9 } tcp dport 53 accept" tableContent;
    cgnatDenial = lib.hasInfix "100.64.0.0/10" tableContent;
    linkLocalDenial = lib.hasInfix "169.254.0.0/16" tableContent;
    multicastDenial = lib.hasInfix "224.0.0.0/4" tableContent;
    ipv6EgressDenial = lib.hasInfix ''meta skuid "mita" ip6 daddr ::/0 drop'' tableContent;
    weakenedGuardRejected = weakenedGuard.rejects "the module-owned ingress and process egress guard must not be removed or weakened.";
    disabledTableRejected = disabledGuardTable.rejects "the module-owned ingress and process egress guard must not be removed or weakened.";
    destinationScopedIngress = lib.hasInfix "ip daddr 192.0.2.13 tcp dport 443 accept" enabled.module.networking.firewall.extraInputRules;
    noWildcardIngressPort = enabled.module.networking.firewall.allowedTCPPorts == [ ];
    nativeLoopbackDefault = enabled.module.networking.firewall.trustedInterfaces == [ "lo" ];
    highPortAssertions = highPort.assertionsPass;
    highPortNativeAssertions = highPort.nativeAssertionsPass;
    highPortTablePorts =
      dportsIn highPort.table.content == [
        "8443"
        "53"
      ];
    highPortIngressPort = dportsIn highPort.module.networking.firewall.extraInputRules == [ "8443" ];
  };
  guardContract = builtins.deepSeq guardResults (
    builtins.all (value: value) (builtins.attrValues guardResults)
  );
  hostAliasResults = {
    aliasActuallyDiffers =
      foreignHostAlias.pkgs.mieru == pkgs.hello && foreignHostAlias.pkgs.mieru != mieruPackage;
    inherit (foreignHostAlias) assertionsPass nativeAssertionsPass;
    fixedExecStart = foreignHostAlias.unit.serviceConfig.ExecStart == "${mieruPackage}/bin/mita run";
    unchangedExecStart =
      foreignHostAlias.unit.serviceConfig.ExecStart == enabled.unit.serviceConfig.ExecStart;
    fixedRestartTrigger = foreignHostAlias.unit.restartTriggers == [ mieruPackage ];
    noOwnedOverlay = enabled.module.nixpkgs.overlays == [ ];
  };
  hostAliasContract = builtins.deepSeq hostAliasResults (
    builtins.all (value: value) (builtins.attrValues hostAliasResults)
  );
  runtimeContract =
    enabled.unit.serviceConfig.Type == "exec"
    && enabled.unit.serviceConfig.User == "mita"
    && enabled.unit.serviceConfig.Group == "mita"
    && !(enabled.unit.serviceConfig ? DynamicUser)
    && enabled.unit.serviceConfig.ExecStart == "${mieruPackage}/bin/mita run"
    && lib.hasPrefix "+" enabled.unit.serviceConfig.ExecStartPre
    &&
      enabled.unit.serviceConfig.Environment == [
        "MITA_CONFIG_JSON_FILE=${enabled.template.path}"
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
    && wrongIdentity.rejects "mita identity, command, credential validation, and runtime paths must remain guarded."
    && dynamicIdentity.rejects "mita identity, command, credential validation, and runtime paths must remain guarded."
    && wrongCommand.rejects "mita identity, command, credential validation, and runtime paths must remain guarded."
    && lib.getVersion mieruPackage == "3.36.0";
  passwordValidatorSourceHygiene =
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
    && hostAliasContract
    && runtimeContract
    && passwordValidatorSourceHygiene
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
        guardResults
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
      guardResults
      hostAliasContract
      hostAliasResults
      passwordValidatorSourceHygiene
      runtimeContract
      schemaContract
      ;
  }
