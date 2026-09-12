{
  inputs,
  pkgs,
  root ? ../.,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  mihomoPackage = self.packages.${system}.mihomo;
  service = import ../clanServices/mihomo-hysteria2/default.nix {
    inherit lib;
    mihomoPackageFor = _: mihomoPackage;
  };
  interface = service.roles.gateway.interface { inherit lib; };
  staticMasqueradeOutput = "/nix/store/00000000000000000000000000000000-hysteria-static-cover";
  staticMasqueradeRoot = "${staticMasqueradeOutput}/share/hysteria";
  baseSettings = {
    enable = true;
    listenIPv4 = "192.0.2.11";
    port = 443;
    serverName = "hysteria.example.invalid";
    users = [
      {
        name = "phone-android";
        passwordSecretName = "fixture/hysteria-phone-password";
      }
      {
        name = "macbook";
        passwordSecretName = "fixture/hysteria-macbook-password";
      }
    ];
    acmeCertName = "fixture";
    obfsPasswordSecretName = "fixture/hysteria-gecko-password";
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
    else
      value;
  evaluateWith =
    {
      rawSettings,
      useSystemdActivation,
      targetPkgs ? pkgs,
      activeInstances ? [ "fixture--hysteria2" ],
      firewallEnable ? true,
      firewallBackend ? "nftables",
      masqueradeRoot ? staticMasqueradeRoot,
    }:
    let
      settings = evalSettings rawSettings;
      secretNames = map (user: user.passwordSecretName) settings.users ++ [
        settings.obfsPasswordSecretName
      ];
      config = {
        sops = {
          inherit useSystemdActivation;
          placeholder = lib.genAttrs secretNames (name: "<SOPS:${name}:PLACEHOLDER>");
          templates."mihomo-hysteria2.json".path = "/run/secrets-rendered/mihomo-hysteria2.json";
        };
        networking.firewall = {
          enable = firewallEnable;
          backend = firewallBackend;
        };
        clanwright =
          (lib.evalModules {
            modules = [
              { inherit (definition) options; }
              {
                config.clanwright.vpn.hysteria2 = {
                  inherit activeInstances;
                }
                // lib.optionalAttrs (masqueradeRoot != null) { inherit masqueradeRoot; };
              }
            ];
          }).config.clanwright;
      };
      instance = service.roles.gateway.perInstance {
        inherit settings;
        instanceName = "fixture--hysteria2";
        machine.name = "fixture";
      };
      definition = instance.nixosModule {
        inherit config;
        pkgs = targetPkgs;
      };
      module = definition.config;
      template = unwrap (module.sops.templates."mihomo-hysteria2.json" or null);
      rendered = if template == null then null else builtins.fromJSON template.content;
      unit = unwrap (module.systemd.services.mihomo-hysteria2 or null);
    in
    {
      inherit
        instance
        module
        rendered
        settings
        template
        unit
        ;
      inherit (definition) options;
      assertionsPass = builtins.all (entry: entry.assertion) module.assertions;
    };
  evaluate =
    rawSettings: useSystemdActivation: evaluateWith { inherit rawSettings useSystemdActivation; };
  enabled = evaluate baseSettings true;
  paddedEndpoint = evaluate (
    baseSettings
    // {
      listenIPv4 = "1.2.16.255";
      port = 5;
    }
  ) true;
  inactiveMissingRoot = evaluateWith {
    rawSettings = baseSettings // {
      enable = false;
    };
    useSystemdActivation = true;
    activeInstances = [ ];
    masqueradeRoot = null;
  };
  activeMissingRootRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (evaluateWith {
          rawSettings = baseSettings;
          useSystemdActivation = true;
          masqueradeRoot = null;
        }).rendered
        true
    )).success;
  # Use the already available filtered source, never a fake store dependency
  # whose context could require realization during string operations.
  contextualMasqueradeRoot = builtins.appendContext "${toString ../.}/checks/fixtures" {
    ${toString ../.} = {
      path = true;
    };
  };
  contextualRoot = evaluateWith {
    rawSettings = baseSettings;
    useSystemdActivation = true;
    masqueradeRoot = contextualMasqueradeRoot;
  };
  activationScriptMode = evaluate baseSettings false;
  duplicateUsers = evaluate (
    baseSettings
    // {
      users = baseSettings.users ++ [ (builtins.head baseSettings.users) ];
    }
  ) true;
  sharedSecret = evaluate (
    baseSettings
    // {
      obfsPasswordSecretName = (builtins.head baseSettings.users).passwordSecretName;
    }
  ) true;
  armPkgs = pkgs // {
    stdenv = pkgs.stdenv // {
      hostPlatform = pkgs.stdenv.hostPlatform // {
        system = "aarch64-linux";
      };
    };
  };
  unsupportedPlatform = evaluateWith {
    rawSettings = baseSettings;
    useSystemdActivation = true;
    targetPkgs = armPkgs;
  };
  firewallDisabled = evaluateWith {
    rawSettings = baseSettings;
    useSystemdActivation = true;
    firewallEnable = false;
  };
  wrongFirewallBackend = evaluateWith {
    rawSettings = baseSettings;
    useSystemdActivation = true;
    firewallBackend = "iptables";
  };
  duplicateInstances = evaluateWith {
    rawSettings = baseSettings;
    useSystemdActivation = true;
    activeInstances = [
      "fixture--hysteria2"
      "fixture--second-hysteria2"
    ];
  };
  listener = builtins.head enabled.rendered.listeners;
  metadata = enabled.instance.exports.vpnProvider.transportMetadata;
  serviceConfig = enabled.unit.serviceConfig;
  postStart = enabled.unit.postStart;
  masqueradeRootOption = enabled.options.clanwright.vpn.hysteria2.masqueradeRoot;
  rootSchemaAccepts =
    value:
    (builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            { options.clanwright.vpn.hysteria2.masqueradeRoot = masqueradeRootOption; }
            { config.clanwright.vpn.hysteria2.masqueradeRoot = value; }
          ];
        }).config.clanwright.vpn.hysteria2.masqueradeRoot
        true
    )).success;
  mergedConsumer = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = [ "vpn-mihomo-hysteria2" ];
    includeNetwork = true;
  };
  mergedMachine = mergedConsumer.machine;
  mergedUnit = mergedMachine.systemd.services.mihomo-hysteria2;
  mergedTemplate = mergedMachine.sops.templates."mihomo-hysteria2.json";
  mergedListener = builtins.head (builtins.fromJSON mergedTemplate.content).listeners;
  disabledResults = {
    template = inactiveMissingRoot.template == null;
    unit = inactiveMissingRoot.unit == null;
    secrets = builtins.all (value: unwrap value == null) (
      builtins.attrValues inactiveMissingRoot.module.sops.secrets
    );
    exports = inactiveMissingRoot.instance.exports == { };
    acmeCerts = inactiveMissingRoot.module.security.acme.certs == { };
  };
  disabledContract = builtins.all (value: value) (builtins.attrValues disabledResults);
  readinessResults = {
    credentialDirectoryLinked =
      builtins.dirOf listener.certificate == builtins.dirOf listener."private-key"
      && serviceConfig.Environment == "SAFE_PATHS=${builtins.dirOf listener.certificate}";
    exactEndpoint = lib.hasInfix "expected_local=0B0200C0:01BB" postStart;
    paddedEndpoint = lib.hasInfix "expected_local=FF100201:0005" paddedEndpoint.unit.postStart;
    mainPidTable = lib.hasInfix ''/proc/"$MAINPID"/net/udp'' postStart;
    mainPidFds = lib.hasInfix ''/proc/"$MAINPID"/fd/*'' postStart;
    socketOwnership = lib.hasInfix ''"socket:[$inode]"'' postStart;
    localAddressMatch = lib.hasInfix "$local_address" postStart;
    unconnectedRemote = lib.hasInfix ''"$remote_address" != "00000000:0000"'' postStart;
    udpState = lib.hasInfix ''"$state" != "07"'' postStart;
    missingMainPid = lib.hasInfix ''-z "''${MAINPID:-}"'' postStart;
    safeInspectionFailure =
      lib.hasInfix "main process inspection unavailable" postStart
      && lib.hasInfix "2>/dev/null" postStart;
    boundedAttempts =
      lib.hasInfix "seq 1 15" postStart
      && lib.hasInfix "sleep 1" postStart
      && serviceConfig.TimeoutStartSec == "20s";
    failingActivation = lib.hasInfix "exit 1" postStart;
    noSocketUtility = !(lib.hasInfix "/bin/ss " postStart) && !(lib.hasInfix "iproute2" postStart);
    noSensitiveDiagnostics =
      !(lib.hasInfix "certificate.pem" postStart)
      && !(lib.hasInfix "private-key.pem" postStart)
      && !(lib.hasInfix "<SOPS:" postStart);
  };
  readinessContract = builtins.all (value: value) (builtins.attrValues readinessResults);
  schemaContract =
    schemaAccepts baseSettings
    && schemaAccepts (
      baseSettings
      // {
        users = map (user: user // { name = "device.${user.name}"; }) baseSettings.users;
      }
    )
    && !(masqueradeRootOption ? default)
    && activeMissingRootRejected
    && disabledContract
    && builtins.hasContext contextualRoot.template.content
    && !(schemaAccepts (baseSettings // { listenIPv4 = "0.0.0.0"; }))
    && !(schemaAccepts (baseSettings // { listenIPv4 = "0.0.0.0/0"; }))
    && !(schemaAccepts (baseSettings // { listenIPv4 = "192.0.2.999"; }))
    && !(schemaAccepts (baseSettings // { serverName = "invalid domain"; }))
    && !(schemaAccepts (baseSettings // { masqueradeUrl = "https://cover.example.invalid"; }))
    && rootSchemaAccepts staticMasqueradeOutput
    && rootSchemaAccepts staticMasqueradeRoot
    && !(rootSchemaAccepts "https://cover.example.invalid")
    && !(rootSchemaAccepts "http://cover.example.invalid")
    && !(rootSchemaAccepts "/srv/hysteria-static-cover")
    && !(rootSchemaAccepts "/nix/store")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share/bad path")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share?query")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share#fragment")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share%20encoded")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share/../secret")
    && !(rootSchemaAccepts "${staticMasqueradeOutput}/share/./site")
    && !(schemaAccepts (
      baseSettings
      // {
        users = [
          {
            name = "bad identity";
            passwordSecretName = "fixture/password";
          }
        ];
      }
    ))
    && !(schemaAccepts (baseSettings // { obfsPasswordSecretName = "../secret"; }))
    && !(schemaAccepts (baseSettings // { ignoreClientBandwidth = false; }))
    && !unsupportedPlatform.assertionsPass
    && !firewallDisabled.assertionsPass
    && !wrongFirewallBackend.assertionsPass
    && !duplicateInstances.assertionsPass
    && !duplicateUsers.assertionsPass
    && !sharedSecret.assertionsPass;
  configContract =
    enabled.assertionsPass
    && enabled.rendered.ipv6 == false
    && enabled.rendered."log-level" == "info"
    && builtins.length enabled.rendered.listeners == 1
    && listener.name == "hysteria2-in"
    && listener.type == "hysteria2"
    && listener.listen == baseSettings.listenIPv4
    && listener.port == 443
    && listener.masquerade == "file://${staticMasqueradeRoot}"
    && listener.alpn == [ "h3" ]
    && listener.obfs == "gecko"
    && listener."obfs-min-packet-size" == 512
    && listener."obfs-max-packet-size" == 1200
    && listener."ignore-client-bandwidth"
    && listener.certificate == "/run/credentials/mihomo-hysteria2.service/certificate.pem"
    && listener."private-key" == "/run/credentials/mihomo-hysteria2.service/private-key.pem"
    && listener.users.phone-android == "<SOPS:fixture/hysteria-phone-password:PLACEHOLDER>"
    && listener.users.macbook == "<SOPS:fixture/hysteria-macbook-password:PLACEHOLDER>"
    && listener."obfs-password" == "<SOPS:fixture/hysteria-gecko-password:PLACEHOLDER>"
    && builtins.all (field: !(builtins.hasAttr field listener)) [
      "up"
      "down"
      "ports"
      "hop-interval"
      "udp-mtu"
      "cwnd"
      "bbr-profile"
      "initial-stream-receive-window"
      "max-stream-receive-window"
      "initial-connection-receive-window"
      "max-connection-receive-window"
      "realm-opts"
      "ech-key"
      "mux-option"
    ];
  exportContract =
    enabled.instance.exports.vpnProvider.schemaVersion == 2
    &&
      enabled.instance.exports.vpnProvider.endpoint == {
        domain = "hysteria.example.invalid";
        ipv4 = "192.0.2.11";
        port = 443;
        transport = "udp";
      }
    &&
      metadata == {
        protocol = "hysteria2";
        sni = "hysteria.example.invalid";
        alpn = [ "h3" ];
        userNames = [
          "phone-android"
          "macbook"
        ];
        obfsName = "gecko";
        obfsMinPacketSize = 512;
        obfsMaxPacketSize = 1200;
        tlsVerify = true;
        credentialEncoding = "base64url";
      }
    &&
      enabled.instance.exports.vpnProvider.secretNames == {
        users = {
          phone-android = "fixture/hysteria-phone-password";
          macbook = "fixture/hysteria-macbook-password";
        };
        obfsPassword = "fixture/hysteria-gecko-password";
      };
  sandboxContract =
    serviceConfig.User == "mihomo-hysteria2"
    && serviceConfig.Group == "mihomo-hysteria2"
    && serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
    && serviceConfig.CapabilityBoundingSet == [ "CAP_NET_BIND_SERVICE" ]
    && serviceConfig.NoNewPrivileges
    && serviceConfig.PrivateDevices
    && serviceConfig.PrivateTmp
    && serviceConfig.ProtectSystem == "strict"
    && serviceConfig.ProtectHome == true
    &&
      serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ]
    && serviceConfig.Type == "exec"
    &&
      serviceConfig.LoadCredential == [
        "certificate.pem:/var/lib/acme/fixture/fullchain.pem"
        "private-key.pem:/var/lib/acme/fixture/key.pem"
      ]
    && lib.hasPrefix (lib.getExe mihomoPackage) serviceConfig.ExecStart
    && lib.hasInfix "-f /run/secrets-rendered/mihomo-hysteria2.json" serviceConfig.ExecStart
    && readinessContract
    &&
      enabled.unit.after == [
        "network-online.target"
        "sops-install-secrets.service"
      ]
    &&
      enabled.unit.wants == [
        "network-online.target"
        "sops-install-secrets.service"
      ]
    && !(enabled.unit ? requires)
    && activationScriptMode.unit.after == [ "network-online.target" ]
    && activationScriptMode.unit.wants == [ "network-online.target" ]
    && enabled.template.owner == "mihomo-hysteria2"
    && enabled.template.group == "mihomo-hysteria2"
    && enabled.template.mode == "0400"
    && enabled.template.restartUnits == [ "mihomo-hysteria2.service" ]
    &&
      (unwrap enabled.module.security.acme.certs.fixture.reloadServices) == [
        "mihomo-hysteria2.service"
      ];
  firewallContract =
    lib.hasInfix "ip daddr 192.0.2.11 udp dport 443 accept" (
      unwrap enabled.module.networking.firewall.extraInputRules
    )
    && !(enabled.module.networking.firewall ? allowedUDPPorts)
    && !(enabled.module.networking.firewall ? allowedTCPPorts);
  mergedUnitResults = {
    configuration = mergedConsumer.config.nixosConfigurations ? vpn-fixture;
    type = mergedUnit.serviceConfig.Type == "exec";
    user = mergedUnit.serviceConfig.User == "mihomo-hysteria2";
    credentials =
      mergedUnit.serviceConfig.LoadCredential == [
        "certificate.pem:/var/lib/acme/fixture/fullchain.pem"
        "private-key.pem:/var/lib/acme/fixture/key.pem"
      ];
    safePaths =
      builtins.dirOf mergedListener.certificate == builtins.dirOf mergedListener."private-key"
      &&
        mergedUnit.serviceConfig.Environment == "SAFE_PATHS=${builtins.dirOf mergedListener.certificate}";
    readinessEndpoint = lib.hasInfix "expected_local=0B0200C0:01BB" mergedUnit.postStart;
    readinessProcTable = lib.hasInfix ''/proc/"$MAINPID"/net/udp'' mergedUnit.postStart;
    readinessProcFds = lib.hasInfix ''/proc/"$MAINPID"/fd/*'' mergedUnit.postStart;
    readinessTimeout = mergedUnit.serviceConfig.TimeoutStartSec == "20s";
    groups = mergedMachine.users.users.mihomo-hysteria2.extraGroups == [ ];
    templateOwner = mergedTemplate.owner == "mihomo-hysteria2";
    templateRestart = mergedTemplate.restartUnits == [ "mihomo-hysteria2.service" ];
    gecko = mergedListener.obfs == "gecko";
    geckoMin = mergedListener."obfs-min-packet-size" == 512;
    geckoMax = mergedListener."obfs-max-packet-size" == 1200;
    masquerade = mergedListener.masquerade == "file://${staticMasqueradeRoot}";
    acmeRestart = builtins.elem "mihomo-hysteria2.service" mergedMachine.security.acme.certs.fixture.reloadServices;
    noSharedRuntime = !(mergedMachine.systemd.services ? mihomo-gateway);
  };
  mergedUnitContract = builtins.all (value: value) (builtins.attrValues mergedUnitResults);
  contract =
    schemaContract
    && configContract
    && exportContract
    && sandboxContract
    && firewallContract
    && mergedUnitContract;
in
if !contract then
  throw "Hysteria2 schema, Gecko config, export, sandbox, or firewall contract failed: ${
    builtins.toJSON {
      inherit
        configContract
        disabledContract
        disabledResults
        exportContract
        firewallContract
        mergedUnitContract
        mergedUnitResults
        readinessContract
        readinessResults
        sandboxContract
        schemaContract
        ;
    }
  }"
else
  {
    all = true;
    inherit
      configContract
      exportContract
      firewallContract
      mergedUnitContract
      readinessContract
      sandboxContract
      schemaContract
      ;
  }
