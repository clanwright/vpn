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
    rawSettings:
    (lib.evalModules {
      modules = [
        (service.roles.gateway.interface { inherit lib; })
        { config = rawSettings; }
      ];
    }).config;
  schemaAccepts =
    rawSettings: (builtins.tryEval (builtins.deepSeq (evalSettings rawSettings) true)).success;
  sopsModule = inputs.clan-core.inputs.sops-nix.nixosModules.sops;
  evaluateInstances =
    rawSettingsList: extraModule:
    let
      settingsList = map evalSettings rawSettingsList;
      instances = lib.imap0 (
        index: settings:
        service.roles.gateway.perInstance {
          inherit settings;
          instanceName = if index == 0 then "fixture--anytls" else "fixture--second-anytls";
          machine.name = "fixture";
        }
      ) settingsList;
      allSettings = builtins.head settingsList;
      evaluated = lib.nixosSystem {
        inherit system;
        modules =
          lib.imap0 (
            index: instance:
            lib.setDefaultModuleLocation "anytls-fixture-owned-${toString index}" instance.nixosModule
          ) instances
          ++ [
            sopsModule
            {
              boot.isContainer = true;
              system.stateVersion = "26.11";
              networking = {
                nameservers = [ "127.0.0.53" ];
                firewall = {
                  enable = true;
                  backend = "nftables";
                };
                nftables.enable = true;
              };
              security.acme = {
                acceptTerms = true;
                defaults.email = "fixture@example.invalid";
                certs.${allSettings.acmeCertName} = {
                  inherit (allSettings) domain;
                  webroot = "/var/lib/acme/acme-challenge";
                };
              };
              sops = {
                useSystemdActivation = true;
                validateSopsFiles = false;
                defaultSopsFile = builtins.toFile "anytls-fixture-sops.yaml" "fixture: synthetic\n";
                age.keyFile = "/run/fixture/age-key";
                secrets =
                  lib.genAttrs
                    (lib.concatMap (settings: map (user: user.passwordSecretName) settings.users) settingsList)
                    (_: {
                      restartUnits = [ "profile-publisher.service" ];
                    });
              };
            }
            extraModule
          ];
      };
      inherit (evaluated) config;
      # Diagnostic messages are lazy and some native messages reference data
      # available only on failure. Select our assertion definitions by source,
      # then force booleans without touching successful native diagnostics.
      anytlsAssertions = lib.concatMap (definition: definition.value) (
        builtins.filter (
          definition: lib.hasPrefix "anytls-fixture-owned-" definition.file
        ) evaluated.options.assertions.definitionsWithLocations
      );
      assertionValues = map (entry: entry.assertion) anytlsAssertions;
      nativeAssertionValues = map (entry: entry.assertion) config.assertions;
    in
    {
      inherit config instances anytlsAssertions;
      inherit (evaluated) pkgs;
      settings = allSettings;
      assertionsPass = builtins.deepSeq assertionValues (
        (!(builtins.any (settings: settings.enable) settingsList) || anytlsAssertions != [ ])
        && builtins.all (value: value) assertionValues
      );
      nativeAssertionsPass = builtins.deepSeq nativeAssertionValues (
        builtins.all (value: value) nativeAssertionValues
      );
    };
  evaluate = rawSettings: extraModule: evaluateInstances [ rawSettings ] extraModule;
  enabled = evaluate baseSettings { };
  disabled = evaluate (baseSettings // { enable = false; }) { };
  highPort = evaluate (baseSettings // { port = 8443; }) { };
  alternateNameservers = evaluate baseSettings {
    networking.nameservers = lib.mkForce [ "10.0.0.53" ];
  };
  withoutSystemdActivation = evaluate baseSettings {
    sops.useSystemdActivation = lib.mkForce false;
  };
  unrelatedNativePackages = evaluate baseSettings {
    services.dbus.enable = true;
    services.caddy = {
      enable = true;
      virtualHosts."http://localhost:8080".extraConfig = "respond fixture";
    };
    systemd.settings.Manager.LogLevel = "info";
    systemd.managerEnvironment.FIXTURE_ONLY = "ordinary";
  };
  foreignSingBoxAlias = evaluate baseSettings {
    nixpkgs.overlays = lib.mkAfter [ (_final: _prev: { sing-box = pkgs.hello; }) ];
  };
  duplicateInstances = evaluateInstances [ baseSettings baseSettings ] { };
  # Two active modules also conflict at native unique package options. Prove
  # our intended singleton assertion without forcing those unrelated values.
  duplicateSingletonAssertions = builtins.filter (
    entry:
    entry.message == "anytls: only one active instance may claim the singleton runtime per machine."
  ) duplicateInstances.anytlsAssertions;
  duplicateSingletonValues = map (entry: entry.assertion) duplicateSingletonAssertions;
  duplicateSingletonRejected = builtins.deepSeq duplicateSingletonValues (
    lib.length duplicateInstances.config.clanwright.vpn.anytls.activeInstances == 2
    && lib.length duplicateSingletonValues == 2
    && builtins.all (value: !value) duplicateSingletonValues
  );
  duplicateNativePackageRejected =
    !(builtins.tryEval (
      builtins.deepSeq duplicateInstances.config.services.sing-box.package.drvPath true
    )).success;
  activeWithDisabled = evaluateInstances [
    baseSettings
    (baseSettings // { enable = false; })
  ] { };
  duplicateUsers = evaluate (
    baseSettings // { users = baseSettings.users ++ [ (builtins.head baseSettings.users) ]; }
  ) { };
  duplicateSecrets = evaluate (
    baseSettings
    // {
      users = [
        (builtins.head baseSettings.users)
        (
          (builtins.elemAt baseSettings.users 1)
          // {
            inherit (builtins.head baseSettings.users) passwordSecretName;
          }
        )
      ];
    }
  ) { };
  noUsers = evaluate (baseSettings // { users = [ ]; }) { };
  accepts =
    extraModule:
    let
      evaluated = evaluate baseSettings extraModule;
      result = builtins.tryEval (builtins.deepSeq evaluated.assertionsPass evaluated.assertionsPass);
    in
    result.success && result.value;
  guardMessages = {
    architecture = "anytls: runtime support is restricted to x86_64-linux.";
    settings = "anytls: the native sing-box singleton must retain the exact package and exclusive AnyTLS settings.";
    assembly = "anytls: stock sing-box and native systemd assembly must remain present; consumer package providers, suppression and directory replacement are unsupported.";
    firewall = "anytls: destination-scoped ingress requires the NixOS firewall.";
    backend = "anytls: ingress and process-scoped egress require the nftables firewall backend.";
    nftables = "anytls: the module-owned process egress guard requires networking.nftables.enable.";
    singleton = "anytls: only one active instance may claim the singleton runtime per machine.";
    users = "anytls: device identities must be unique.";
    secrets = "anytls: every device must use a distinct SOPS password secret.";
    nonempty = "anytls: at least one per-device user is required.";
    egress = "anytls: the module-owned ingress and process egress guard must not be removed or weakened.";
    renderer = "anytls: native sing-box owns runtime JSON rendering; competing SOPS templates are unsupported.";
    credentials = "anytls: password secret permissions and restart bindings must remain guarded.";
    renewal = "anytls: ACME renewal must restart sing-box to refresh copied TLS credentials.";
    unit = "anytls: the native unit identity, execution, credentials, hardening, restart and firewall lifecycle must remain guarded.";
    namespace = "anytls: native sing-box unit, UID, directories and configuration namespace are exclusively owned by this singleton.";
  };
  assertionFails =
    evaluated: message:
    let
      matching = builtins.filter (entry: entry.message == message) evaluated.anytlsAssertions;
    in
    lib.length matching == 1 && (builtins.head matching).assertion == false;
  rejectsFor = message: extraModule: assertionFails (evaluate baseSettings extraModule) message;
  actual = enabled.config;
  nativeDisabled = evaluate baseSettings { services.sing-box.enable = lib.mkForce false; };
  missingPassword = evaluate baseSettings {
    sops.secrets = lib.mkForce (
      builtins.removeAttrs actual.sops.secrets [ "fixture/anytls-phone-password" ]
    );
  };
  unrelatedAssertionControls = {
    successfulNativeMessageStaysLazy = accepts {
      assertions = [
        {
          assertion = true;
          message = throw "successful native messages must remain lazy";
        }
      ];
    };
    unrelatedNativeFailureDoesNotProveOurRejection = accepts {
      assertions = [
        {
          assertion = false;
          message = "synthetic unrelated native failure";
        }
      ];
    };
    unrelatedNativeFailureDoesNotProveNamedRejection =
      !(rejectsFor guardMessages.settings {
        assertions = [
          {
            assertion = false;
            message = "unrelated native fixture failure";
          }
        ];
      });
  };
  rendered = actual.services.sing-box.settings;
  unit = actual.systemd.services.sing-box;
  unitText = actual.systemd.units."sing-box.service".text;
  table = actual.networking.nftables.tables.vpn_anytls_egress;
  source = builtins.readFile ../clanServices/anytls/default.nix;
  deniedCidrs = [
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
  expectedRendered = {
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
            password._secret = "/run/credentials/sing-box.service/password-phone";
          }
          {
            name = "laptop";
            password._secret = "/run/credentials/sing-box.service/password-laptop";
          }
        ];
        tls = {
          enabled = true;
          server_name = "anytls.example.invalid";
          min_version = "1.3";
          max_version = "1.3";
          certificate_path = "/run/credentials/sing-box.service/certificate.pem";
          key_path = "/run/credentials/sing-box.service/private-key.pem";
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
          ip_cidr = deniedCidrs;
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
  schemaResults = {
    valid = schemaAccepts baseSettings;
    dottedDeviceIdentity = schemaAccepts (
      baseSettings
      // {
        users = map (user: user // { name = "device.${user.name}"; }) baseSettings.users;
      }
    );
    longCertificateKey = schemaAccepts (
      baseSettings
      // {
        acmeCertName = "${lib.concatStrings (lib.replicate 63 "a")}.${lib.concatStrings (lib.replicate 63 "b")}.example.invalid";
      }
    );
    certificateBounds =
      !(schemaAccepts (baseSettings // { acmeCertName = "*.example.invalid"; }))
      && !(schemaAccepts (baseSettings // { acmeCertName = lib.concatStrings (lib.replicate 254 "a"); }))
      && !(schemaAccepts (
        baseSettings
        // {
          users = [
            {
              name = lib.concatStrings (lib.replicate 65 "a");
              passwordSecretName = "fixture/password";
            }
          ];
        }
      ));
    customDohPath = schemaAccepts (
      baseSettings
      // {
        dnsEndpoint = baseSettings.dnsEndpoint // {
          port = 8443;
          path = "/private-dns-query";
        };
      }
    );
    malformedInputsRejected = builtins.all (settings: !(schemaAccepts settings)) [
      (baseSettings // { bindIPv4 = "0.0.0.0"; })
      (baseSettings // { bindIPv4 = "192.0.2.999"; })
      (baseSettings // { domain = "localhost"; })
      (baseSettings // { domain = "a..example.invalid"; })
      (baseSettings // { domain = "a.-bad.example.invalid"; })
      (baseSettings // { serverName = "other.example.invalid"; })
      (baseSettings // { dnsResolverIPv4s = [ "9.9.9.9" ]; })
      (
        baseSettings
        // {
          users = [
            {
              name = "bad identity";
              passwordSecretName = "fixture/anytls";
            }
          ];
        }
      )
      (
        baseSettings
        // {
          users = [
            {
              name = "phone";
              passwordSecretName = "../secret";
            }
          ];
        }
      )
    ];
    privateAndReservedDohRejected =
      builtins.all
        (
          ipv4:
          !(schemaAccepts (
            baseSettings
            // {
              dnsEndpoint = baseSettings.dnsEndpoint // {
                inherit ipv4;
              };
            }
          ))
        )
        [
          "0.0.0.53"
          "10.0.0.53"
          "100.64.0.53"
          "127.0.0.53"
          "169.254.1.53"
          "172.16.0.53"
          "192.0.0.53"
          "192.0.2.53"
          "192.88.99.53"
          "192.168.0.53"
          "198.18.0.53"
          "198.51.100.53"
          "203.0.113.53"
          "224.0.0.53"
          "240.0.0.53"
          "2001:db8::53"
        ];
    dohIdentityAndPathRejected =
      builtins.all (dnsEndpoint: !(schemaAccepts (baseSettings // { inherit dnsEndpoint; })))
        [
          (baseSettings.dnsEndpoint // { domain = "DNS.example.invalid"; })
          (baseSettings.dnsEndpoint // { domain = "localhost"; })
          (baseSettings.dnsEndpoint // { domain = "dns..example.invalid"; })
          (baseSettings.dnsEndpoint // { domain = "192.0.2.53"; })
          (baseSettings.dnsEndpoint // { domain = "999.001.2.53"; })
          (baseSettings.dnsEndpoint // { path = "dns-query"; })
          (baseSettings.dnsEndpoint // { headers.Host = "dns.example.invalid"; })
        ];
  };
  schemaContract = builtins.all (value: value) (builtins.attrValues schemaResults);
  disabledResults = {
    exports = (builtins.head disabled.instances).exports == { };
    assertions = disabled.anytlsAssertions == [ ];
    singleton = disabled.config.clanwright.vpn.anytls.activeInstances == [ ];
    services =
      !disabled.config.services.sing-box.enable
      && !(disabled.config.systemd.services ? sing-box)
      && !(disabled.config.systemd.services ? anytls);
    users = !(disabled.config.users.users ? sing-box) && !(disabled.config.users.groups ? sing-box);
    secrets = builtins.all (secret: !(builtins.elem "sing-box.service" secret.restartUnits)) (
      builtins.attrValues disabled.config.sops.secrets
    );
    templates =
      !(disabled.config.sops.templates ? "anytls.json")
      && !(disabled.config.sops.templates ? "sing-box.json");
    tables = !(disabled.config.networking.nftables.tables ? vpn_anytls_egress);
    acme =
      !(builtins.elem "sing-box.service" disabled.config.security.acme.certs.anytls-example.reloadServices);
    overlays = disabled.config.nixpkgs.overlays == [ ];
  };
  disabledContract = builtins.all (value: value) (builtins.attrValues disabledResults);
  singletonContract =
    enabled.assertionsPass
    && duplicateSingletonRejected
    && duplicateNativePackageRejected
    && activeWithDisabled.assertionsPass
    && activeWithDisabled.config.clanwright.vpn.anytls.activeInstances == [ "fixture--anytls" ]
    && activeWithDisabled.nativeAssertionsPass
    && assertionFails duplicateUsers guardMessages.users
    && assertionFails duplicateSecrets guardMessages.secrets
    && assertionFails noUsers guardMessages.nonempty
    && rejectsFor guardMessages.singleton { clanwright.vpn.anytls.activeInstances = lib.mkForce [ ]; };
  configContract =
    rendered == expectedRendered
    && alternateNameservers.assertionsPass
    && alternateNameservers.config.services.sing-box.settings == rendered
    && actual.networking.nameservers == [ "127.0.0.53" ]
    && actual.services.sing-box.enable
    && actual.services.sing-box.package == singBoxPackage;
  exportContract =
    (builtins.head enabled.instances).exports.vpnProvider == {
      schemaVersion = 3;
      connection.anytls = {
        endpoint = {
          hostname = "anytls.example.invalid";
          ipv4 = "192.0.2.14";
          port = 443;
        };
        clients = {
          phone.passwordSecret = "fixture/anytls-phone-password";
          laptop.passwordSecret = "fixture/anytls-laptop-password";
        };
      };
    };
  guardResults = {
    shape = table.enable && table.family == "inet";
    listenerReplies =
      lib.hasInfix ''meta skuid "sing-box" ip saddr 192.0.2.14 tcp sport 443 ct direction reply accept'' table.content
      && !(lib.hasInfix ''meta skuid "sing-box" ct direction reply accept'' table.content);
    fullDeniedSet = builtins.all (cidr: lib.hasInfix cidr table.content) deniedCidrs;
    ipv6 = lib.hasInfix ''meta skuid "sing-box" ip6 daddr ::/0 drop'' table.content;
    noDnsOrBroadIngressExceptions =
      !(lib.hasInfix "udp dport 53 accept" table.content)
      && !(lib.hasInfix "tcp dport 53 accept" table.content)
      && !(lib.hasInfix "chain input_guard" table.content)
      && !(lib.hasInfix "ip daddr !=" table.content)
      && lib.hasInfix "ip daddr 192.0.2.14 tcp dport 443 accept" actual.networking.firewall.extraInputRules
      && !(builtins.elem 443 actual.networking.firewall.allowedTCPPorts)
      && actual.networking.firewall.allowedTCPPorts == disabled.config.networking.firewall.allowedTCPPorts
      && actual.networking.firewall.allowedUDPPorts == disabled.config.networking.firewall.allowedUDPPorts
      &&
        actual.networking.firewall.trustedInterfaces
        == disabled.config.networking.firewall.trustedInterfaces
      && disabled.config.networking.firewall.trustedInterfaces == [ "lo" ];
    effectiveGuardOverridesRejected =
      rejectsFor guardMessages.firewall { networking.firewall.enable = lib.mkForce false; }
      && rejectsFor guardMessages.backend { networking.firewall.backend = lib.mkForce "iptables"; }
      && rejectsFor guardMessages.nftables { networking.nftables.enable = lib.mkForce false; }
      && builtins.all (rejectsFor guardMessages.egress) [
        { networking.firewall.extraInputRules = lib.mkForce ""; }
        { networking.nftables.tables.vpn_anytls_egress.enable = lib.mkForce false; }
        {
          networking.nftables.tables = lib.mkForce (
            builtins.removeAttrs actual.networking.nftables.tables [ "vpn_anytls_egress" ]
          );
        }
        {
          networking.nftables.tables.vpn_anytls_egress.content =
            lib.mkForce "chain output { type filter hook output priority filter; policy accept; }";
        }
      ];
  };
  guardContract = builtins.all (value: value) (builtins.attrValues guardResults);
  routeGuardContract =
    rendered.route.rules == expectedRendered.route.rules
    && builtins.all (rejectsFor guardMessages.settings) [
      { services.sing-box.settings.route.rules = lib.mkForce (lib.reverseList rendered.route.rules); }
      {
        services.sing-box.settings.route.rules = lib.mkForce [
          (builtins.head rendered.route.rules)
          (builtins.elemAt rendered.route.rules 2)
        ];
      }
      {
        services.sing-box.settings.route.rules = [
          {
            action = "route";
            outbound = "direct";
          }
        ];
      }
    ];
  runtimeResults = {
    nativeLifecycle =
      unit.serviceConfig.User == "sing-box"
      && unit.serviceConfig.Group == "sing-box"
      && !(unit.serviceConfig ? DynamicUser)
      && unit.serviceConfig.Type == "exec"
      && unit.serviceConfig.ConfigurationDirectory == "sing-box"
      && unit.serviceConfig.RuntimeDirectory == "sing-box"
      && unit.serviceConfig.RuntimeDirectoryMode == "0700"
      && unit.serviceConfig.StateDirectory == "sing-box"
      && unit.serviceConfig.StateDirectoryMode == "0700"
      && unit.serviceConfig.WorkingDirectory == "/var/lib/sing-box"
      && actual.users.users.sing-box.isSystemUser;
    command =
      unit.serviceConfig.ExecStart == [
        ""
        "${lib.getExe singBoxPackage} -D \${STATE_DIRECTORY} -C \${RUNTIME_DIRECTORY} run"
      ]
      && lib.length unit.serviceConfig.ExecStartPre == 2
      && !(lib.hasPrefix "+" (builtins.head unit.serviceConfig.ExecStartPre))
      && lib.hasPrefix "+" (builtins.elemAt unit.serviceConfig.ExecStartPre 1)
      && unit.preStart == ""
      && unit.postStart == "";
    credentials =
      unit.serviceConfig.LoadCredential == [
        "certificate.pem:/var/lib/acme/anytls-example/fullchain.pem"
        "private-key.pem:/var/lib/acme/anytls-example/key.pem"
        "password-phone:/run/secrets/fixture/anytls-phone-password"
        "password-laptop:/run/secrets/fixture/anytls-laptop-password"
      ];
    restartRefreshesCredentials =
      unit.serviceConfig.ExecReload == [ "" ]
      && lib.hasInfix "ExecReload=\n" unitText
      && unit.reload == ""
      && !unit.reloadIfChanged
      && builtins.elem "sing-box.service" actual.security.acme.certs.anytls-example.reloadServices;
    capabilityReset =
      unit.serviceConfig.AmbientCapabilities == [
        ""
        "CAP_NET_BIND_SERVICE"
      ]
      &&
        unit.serviceConfig.CapabilityBoundingSet == [
          ""
          "CAP_NET_BIND_SERVICE"
        ]
      && highPort.config.systemd.services.sing-box.serviceConfig.AmbientCapabilities == [ "" ]
      && highPort.config.systemd.services.sing-box.serviceConfig.CapabilityBoundingSet == [ "" ]
      && lib.hasInfix "AmbientCapabilities=\n" unitText
      && lib.hasInfix "CapabilityBoundingSet=\n" unitText;
    addressFamilies =
      unit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_UNIX"
      ];
    ordering =
      builtins.elem "network-online.target" unit.requires
      && builtins.elem "nftables.service" unit.requires
      && unit.bindsTo == [ "nftables.service" ]
      && unit.partOf == [ "nftables.service" ]
      && builtins.elem "nftables.service" unit.after
      && builtins.elem "sops-install-secrets.service" unit.after
      && builtins.elem "sops-install-secrets.service" unit.wants;
    secrets = builtins.all (
      secret:
      secret.owner == "root"
      && secret.group == "root"
      && secret.mode == "0400"
      && builtins.elem "sing-box.service" secret.restartUnits
      && builtins.elem "profile-publisher.service" secret.restartUnits
    ) (builtins.attrValues actual.sops.secrets);
    noCustomRenderer =
      !(actual.sops.templates ? "anytls.json")
      && !(actual.systemd.services ? anytls)
      && !(lib.hasInfix "sops.placeholder" source)
      && !(lib.hasInfix ''/proc/"$MAINPID"'' source);
    version = lib.getVersion singBoxPackage == "1.14.1";
  };
  runtimeContract = builtins.all (value: value) (builtins.attrValues runtimeResults);
  effectiveOverrideResults = {
    nativeAssembly = builtins.all (rejectsFor guardMessages.assembly) [
      { systemd.packages = lib.mkForce [ ]; }
      {
        systemd.packages = [
          (pkgs.writeTextDir "lib/systemd/system/sing-box.service.d/zz-fixture.conf" "[Service]\nExecReload=/bin/kill -HUP $MAINPID\nAmbientCapabilities=CAP_NET_ADMIN\n")
        ];
      }
      { systemd.suppressedSystemUnits = [ "sing-box.service" ]; }
      {
        environment.etc."systemd/system".source = lib.mkForce (
          pkgs.writeTextDir "sing-box.service" "[Service]\nExecStart=/bin/false\n"
        );
      }
      { environment.etc."systemd/system".enable = lib.mkForce false; }
      { environment.etc."systemd/system".target = lib.mkForce "systemd/other"; }
      {
        environment.etc.fixture-unit-directory = {
          target = "systemd/system";
          source = pkgs.writeTextDir "sing-box.service" "[Service]\nExecStart=/bin/false\n";
        };
      }
      {
        environment.etc."systemd/system.conf".text =
          lib.mkForce "[Manager]\nDefaultEnvironment=BASH_ENV=/run/fixture/override.sh\n";
      }
      { environment.etc."systemd/system.conf".enable = lib.mkForce false; }
      { environment.etc."systemd/system.conf".target = lib.mkForce "systemd/other.conf"; }
      {
        environment.etc."systemd/system.conf.d/override.conf".text =
          "[Manager]\nDefaultEnvironment=BASH_ENV=/run/fixture/override.sh\n";
      }
      {
        environment.etc.fixture-manager = {
          target = "systemd/system.conf";
          text = "[Manager]\nDefaultEnvironment=BASH_ENV=/run/fixture/override.sh\n";
        };
      }
    ];
    nativePins =
      foreignSingBoxAlias.pkgs.sing-box == pkgs.hello
      && foreignSingBoxAlias.assertionsPass
      && foreignSingBoxAlias.nativeAssertionsPass
      && foreignSingBoxAlias.config.services.sing-box.package == singBoxPackage
      &&
        foreignSingBoxAlias.config.systemd.services.sing-box.serviceConfig.ExecStart == [
          ""
          "${lib.getExe singBoxPackage} -D \${STATE_DIRECTORY} -C \${RUNTIME_DIRECTORY} run"
        ]
      && builtins.elem singBoxPackage foreignSingBoxAlias.config.systemd.packages
      && enabled.config.nixpkgs.overlays == [ ]
      && lib.length foreignSingBoxAlias.config.nixpkgs.overlays == 1
      && rejectsFor guardMessages.architecture { nixpkgs.hostPlatform = lib.mkForce "aarch64-linux"; };
    nativeSettings =
      assertionFails nativeDisabled guardMessages.settings
      && builtins.all (rejectsFor guardMessages.settings) [
        { services.sing-box.package = lib.mkForce pkgs.hello; }
        { services.sing-box.settings = lib.mkForce { }; }
        { services.sing-box.settings.log.level = lib.mkForce "debug"; }
        {
          services.sing-box.settings.inbounds = [
            {
              type = "mixed";
              listen_port = 1080;
            }
          ];
        }
        { services.sing-box.settings.experimental.clash_api.external_controller = "127.0.0.1:9090"; }
        { services.sing-box.settings.network_namespaces = [ { name = "shared"; } ]; }
      ];
    unitAndIdentity =
      assertionFails missingPassword guardMessages.unit
      && builtins.all (rejectsFor guardMessages.unit) [
        { systemd.services.sing-box.enable = lib.mkForce false; }
        { systemd.services.sing-box.wantedBy = lib.mkForce [ ]; }
        { systemd.services.sing-box.serviceConfig.User = lib.mkForce "root"; }
        { systemd.services.sing-box.serviceConfig.DynamicUser = true; }
        {
          systemd.services.sing-box.serviceConfig.ExecStart = lib.mkForce [
            ""
            "/bin/false"
          ];
        }
        { systemd.services.sing-box.serviceConfig.ExecStartPre = lib.mkForce [ ]; }
        { systemd.services.sing-box.serviceConfig.LoadCredential = lib.mkForce [ ]; }
        { systemd.services.sing-box.serviceConfig.ExecReload = lib.mkForce [ "/bin/kill -HUP $MAINPID" ]; }
        { systemd.services.sing-box.serviceConfig.CapabilityBoundingSet = lib.mkForce [ "CAP_NET_ADMIN" ]; }
        { systemd.services.sing-box.serviceConfig.RuntimeDirectory = lib.mkForce "shared"; }
        {
          systemd.services.sing-box.serviceConfig.RestrictAddressFamilies = lib.mkForce [
            "AF_INET"
            "AF_INET6"
          ];
        }
        { systemd.services.sing-box.requires = lib.mkForce [ "network-online.target" ]; }
        { systemd.services.sing-box.bindsTo = lib.mkForce [ ]; }
        { systemd.services.sing-box.unitConfig.Requires = lib.mkForce "network-online.target"; }
        { systemd.services.sing-box.environment.BASH_ENV = "/run/fixture/override.sh"; }
        { systemd.globalEnvironment.BASH_ENV = "/run/fixture/override.sh"; }
        { systemd.settings.Manager.DefaultEnvironment = "BASH_ENV=/run/fixture/override.sh"; }
        { systemd.settings.Manager.DefaultEnvironment = [ "BASH_ENV=/run/fixture/override.sh" ]; }
        { systemd.settings.Manager."DefaultEnvironment " = "BASH_ENV=/run/fixture/override.sh"; }
        {
          systemd.settings.Manager.LogLevel = "info\nDefaultEnvironment=BASH_ENV=/run/fixture/override.sh";
        }
        {
          systemd.settings.Manager.LogLevel = [
            "info\rDefaultEnvironment=BASH_ENV=/run/fixture/override.sh"
          ];
        }
        {
          systemd.managerEnvironment.FIXTURE_ONLY = "ordinary\nDefaultEnvironment=BASH_ENV=/run/fixture/override.sh";
        }
        { systemd.services.sing-box.reload = "echo synthetic"; }
        { systemd.services = lib.mkForce (builtins.removeAttrs actual.systemd.services [ "sing-box" ]); }
      ];
    identity =
      assertionFails nativeDisabled guardMessages.namespace
      && builtins.all (rejectsFor guardMessages.namespace) [
        { users.users = lib.mkForce (builtins.removeAttrs actual.users.users [ "sing-box" ]); }
        { users.groups = lib.mkForce (builtins.removeAttrs actual.users.groups [ "sing-box" ]); }
        { users.users.sing-box.uid = 0; }
        { users.groups.sing-box.gid = 0; }
        { users.users.sing-box.enable = lib.mkForce false; }
        { users.users.sing-box.name = lib.mkForce "fixture-other"; }
        { users.groups.sing-box.name = lib.mkForce "fixture-other"; }
        { systemd.units."sing-box.service".unit = lib.mkForce pkgs.hello; }
        { systemd.units = lib.mkForce (builtins.removeAttrs actual.systemd.units [ "sing-box.service" ]); }
        {
          systemd.units."sing-box.service".text =
            lib.mkForce "[Service]\nExecReload=/bin/kill -HUP $MAINPID\n";
        }
        {
          users.users.sing-box.extraGroups = [ "fixture-readers" ];
          users.groups.fixture-readers = { };
        }
        { users.groups.fixture-readers.members = [ "sing-box" ]; }
        { users.groups.fixture-reader.name = "sing-box"; }
        {
          users.users.fixture-alias = {
            isSystemUser = true;
            group = "nogroup";
            name = "sing-box";
          };
        }
        {
          users.users.fixture-reader = {
            isSystemUser = true;
            group = "sing-box";
          };
        }
        {
          users.users.fixture-supplementary-reader = {
            isSystemUser = true;
            group = "nogroup";
            extraGroups = [ "sing-box" ];
          };
        }
      ];
    namespace = builtins.all (rejectsFor guardMessages.namespace) [
      {
        systemd.services.fixture-alias = {
          aliases = [ "sing-box.service" ];
          serviceConfig.ExecStart = "/bin/false";
        };
      }
      { systemd.services.sing-box.aliases = [ "fixture-anytls.service" ]; }
      {
        systemd.services."sing-box@fixture" = {
          serviceConfig.ExecStart = "/bin/false";
        };
      }
      {
        systemd.services.other.serviceConfig = {
          User = "sing-box";
          ExecStart = "/bin/false";
        };
      }
      { environment.etc."sing-box/extra.json".text = "{}"; }
      {
        environment.etc."systemd/system/sing-box.service.d/extra.conf".text =
          "[Service]\nExecReload=/bin/false\n";
      }
      { systemd.tmpfiles.rules = [ "f /run/sing-box/extra.json 0600 sing-box sing-box - {}" ]; }
      { systemd.tmpfiles.settings.fixture."/run/sing-box/extra.json".f.argument = "{}"; }
    ];
    renderer = builtins.all (rejectsFor guardMessages.renderer) [
      { sops.templates."anytls.json".content = "{}"; }
    ];
    secrets =
      assertionFails missingPassword guardMessages.credentials
      && builtins.all (rejectsFor guardMessages.credentials) [
        {
          sops.secrets."fixture/anytls-phone-password".restartUnits = lib.mkForce [
            "profile-publisher.service"
          ];
        }
        { sops.secrets."fixture/anytls-phone-password".owner = lib.mkForce "sing-box"; }
        { sops.secrets."fixture/anytls-phone-password".mode = lib.mkForce "0440"; }
      ];
    renewal = builtins.all (rejectsFor guardMessages.renewal) [
      { security.acme.certs.anytls-example.reloadServices = lib.mkForce [ ]; }
      {
        security.acme.certs = lib.mkForce (
          builtins.removeAttrs actual.security.acme.certs [ "anytls-example" ]
        );
      }
    ];
  };
  effectiveOverrideContract = builtins.all (value: value) (
    builtins.attrValues effectiveOverrideResults
  );
  passwordValidatorSourceHygiene =
    lib.hasInfix "byte_count" source
    && lib.hasInfix "base64url_byte_count" source
    && lib.hasInfix ''"$byte_count" -gt 64'' source
    && lib.hasInfix "tr -cd 'A-Za-z0-9_-'" source
    && !(lib.hasInfix "tr -d '\\n'" source)
    && !(lib.hasInfix "echo \"$password\"" source)
    && lib.hasInfix "for config_file in /run/sing-box/*.json" source;
  results = {
    inherit
      schemaContract
      disabledContract
      singletonContract
      configContract
      exportContract
      guardContract
      routeGuardContract
      runtimeContract
      effectiveOverrideContract
      passwordValidatorSourceHygiene
      ;
    nativeAssertions = enabled.nativeAssertionsPass && highPort.nativeAssertionsPass;
    nativeWithoutSopsActivation =
      withoutSystemdActivation.assertionsPass && withoutSystemdActivation.nativeAssertionsPass;
    unrelatedNativeContributorsPreserved =
      unrelatedNativePackages.assertionsPass
      && unrelatedNativePackages.nativeAssertionsPass
      && builtins.elem unrelatedNativePackages.config.services.caddy.package unrelatedNativePackages.config.systemd.packages;
    assertionSelectionContract = builtins.all (value: value) (
      builtins.attrValues unrelatedAssertionControls
    );
    emptyManagerEnvironmentAccepted = accepts { systemd.settings.Manager.DefaultEnvironment = [ ]; };
  };
  contract = builtins.deepSeq results (builtins.all (value: value) (builtins.attrValues results));
in
if !contract then
  throw "AnyTLS native schema, export, config, unit, namespace, nftables or secret contract failed: ${
    builtins.toJSON {
      enabledFailureMessages = map (entry: entry.message) (
        builtins.filter (entry: !entry.assertion) enabled.anytlsAssertions
      );
      inherit
        results
        schemaResults
        disabledResults
        guardResults
        runtimeResults
        effectiveOverrideResults
        ;
    }
  }"
else
  results // { all = true; }
