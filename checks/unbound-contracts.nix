{
  inputs,
  pkgs,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  unboundPackage = self.packages.${system}.unbound;
  service = import ../clanServices/unbound/default.nix {
    unboundPackageFor = _: unboundPackage;
  };
  evalSettings =
    rawSettings:
    (lib.evalModules {
      modules = [
        (service.roles.recursive-backend.interface { inherit lib; })
        { config = rawSettings; }
      ];
    }).config;
  schemaAccepts =
    rawSettings: (builtins.tryEval (builtins.deepSeq (evalSettings rawSettings) true)).success;
  evaluateInstances =
    rawSettingsList: enableIPv6: extraModule:
    let
      settingsList = map evalSettings rawSettingsList;
      instances = lib.imap0 (
        index: settings:
        service.roles.recursive-backend.perInstance {
          inherit settings;
          instanceName = if index == 0 then "fixture--unbound" else "fixture--second-unbound";
          machine.name = "fixture";
        }
      ) settingsList;
      evaluated = lib.nixosSystem {
        inherit system;
        modules =
          lib.imap0 (
            index: instance:
            lib.setDefaultModuleLocation "unbound-fixture-owned-${toString index}" instance.nixosModule
          ) instances
          ++ [
            {
              nixpkgs.pkgs = inputs.nixpkgs.legacyPackages.${system};
              boot.isContainer = true;
              networking = { inherit enableIPv6; };
              system.stateVersion = "26.11";
            }
            extraModule
          ];
      };
      inherit (evaluated) config;
      ownedAssertions = lib.concatMap (definition: definition.value) (
        builtins.filter (
          definition: lib.hasPrefix "unbound-fixture-owned-" definition.file
        ) evaluated.options.assertions.definitionsWithLocations
      );
      ownedValues = map (entry: entry.assertion) ownedAssertions;
      nativeValues = map (entry: entry.assertion) config.assertions;
    in
    {
      inherit config ownedAssertions;
      settings = builtins.head settingsList;
      assertionsPass = builtins.deepSeq ownedValues (
        (!(builtins.any (settings: settings.enable) settingsList) || ownedAssertions != [ ])
        && builtins.all (value: value) ownedValues
      );
      nativeAssertionsPass = builtins.deepSeq nativeValues (builtins.all (value: value) nativeValues);
    };
  evaluate =
    rawSettings: enableIPv6: extraModule:
    evaluateInstances [ rawSettings ] enableIPv6 extraModule;
  defaults = evaluate { } true { };
  ipv4Only = evaluate { } false { };
  explicitIpv4 = evaluate { listen.hosts = [ "127.9.8.7" ]; } true { };
  explicitIpv6 = evaluate { listen.hosts = [ "::1" ]; } true { };
  explicitIpv6Conflict = evaluate { listen.hosts = [ "::1" ]; } false { };
  duplicateInstances = evaluateInstances [
    { }
    { }
  ] true { };
  activeWithDisabled = evaluateInstances [
    { }
    { enable = false; }
  ] true { };
  disabled = evaluate { enable = false; } true { };
  matchesMessage = predicate: entry: predicate entry.message;
  rejectsOverride =
    message: extraModule:
    let
      selected =
        builtins.filter (matchesMessage (value: value == message))
          (evaluate { } true extraModule).ownedAssertions;
    in
    assert builtins.length selected == 1;
    !(builtins.head selected).assertion;
  lifecycleOverrideResults =
    map
      (
        extraModule:
        let
          selected = builtins.filter (matchesMessage (
            value:
            value
            == "unbound: the active recursive backend must stay enabled without taking over the host resolver."
          )) (evaluate { } true extraModule).ownedAssertions;
        in
        assert builtins.length selected == 1;
        !(builtins.head selected).assertion
      )
      [
        { services.unbound.enable = lib.mkForce false; }
        { services.unbound.resolveLocalQueries = lib.mkForce true; }
      ];
  effectiveOverrideMessages = [
    "unbound: the runtime package must come from the VPN domain platform pin."
    "unbound: effective DNSSEC validation and the native managed root trust anchor must remain enabled."
    "unbound: include directives cannot bypass the effective loopback and DNSSEC policy."
    "unbound: effective interfaces must remain the configured nonempty loopback listener set."
    "unbound: the effective listener port must remain within 1-65535."
    "unbound: effective access control must allow only enabled loopback address families."
    "unbound: effective transport, EDNS, TTL, and bounded serve-expired policy must remain enabled."
  ];
  effectiveOverrideResults =
    lib.imap0
      (index: extraModule: rejectsOverride (builtins.elemAt effectiveOverrideMessages index) extraModule)
      [
        { services.unbound.package = lib.mkOverride 0 pkgs.hello; }
        { services.unbound.enableRootTrustAnchor = lib.mkOverride 0 false; }
        { services.unbound.checkconf = lib.mkOverride 0 false; }
        { services.unbound.settings.server.interface = lib.mkOverride 0 [ "0.0.0.0" ]; }
        { services.unbound.settings.server.port = lib.mkOverride 0 0; }
        { services.unbound.settings.server.access-control = lib.mkOverride 0 [ "0.0.0.0/0 allow" ]; }
        { services.unbound.settings.server.serve-expired = lib.mkOverride 0 false; }
      ];
  dnssecOverrideResults =
    map
      (rejectsOverride "unbound: effective DNSSEC validation and the native managed root trust anchor must remain enabled.")
      [
        { services.unbound.settings.server.module-config = lib.mkOverride 0 ''"iterator"''; }
        { services.unbound.settings.server.val-permissive-mode = lib.mkOverride 0 true; }
        { services.unbound.settings.server.harden-dnssec-stripped = lib.mkOverride 0 false; }
        { services.unbound.settings.server.domain-insecure = lib.mkOverride 0 [ "example.invalid" ]; }
        { services.unbound.settings.server.trust-anchor = lib.mkOverride 0 [ "example.invalid" ]; }
        { services.unbound.settings.server.trust-anchor-file = lib.mkOverride 0 [ "/run/unbound/anchor" ]; }
        { services.unbound.settings.server.trusted-keys-file = lib.mkOverride 0 [ "/run/unbound/keys" ]; }
      ];
  includeOverrideResults =
    lib.imap0
      (
        index: extraModule:
        rejectsOverride (
          if index < 3 then
            "unbound: include directives cannot bypass the effective loopback and DNSSEC policy."
          else
            "unbound: effective interfaces must remain the configured nonempty loopback listener set."
        ) extraModule
      )
      [
        { services.unbound.settings.include = "/run/unbound/override.conf"; }
        { services.unbound.settings.include-toplevel = "/run/unbound/override-toplevel.conf"; }
        { services.unbound.settings.server.include = "/run/unbound/override-server.conf"; }
        { services.unbound.settings.server.interface-automatic = lib.mkOverride 0 true; }
      ];
  zoneOverrideResults =
    map
      (rejectsOverride "unbound: freeform directives and remote control cannot replace the closed recursive backend policy.")
      [
        {
          services.unbound.settings.forward-zone = [
            {
              name = ".";
              forward-addr = [ "1.1.1.1" ];
            }
          ];
        }
        {
          services.unbound.settings.stub-zone = [
            {
              name = "example.invalid";
              stub-addr = [ "192.0.2.53" ];
            }
          ];
        }
        {
          services.unbound.settings.auth-zone = [
            {
              name = "example.invalid";
              zonefile = "/run/unbound/example.invalid.zone";
            }
          ];
        }
      ];
  closedPolicyOverrideResults =
    map
      (rejectsOverride "unbound: freeform directives and remote control cannot replace the closed recursive backend policy.")
      [
        { services.unbound.settings.server.local-zone = [ ''"example.invalid" redirect'' ]; }
        { services.unbound.settings.server.local-data = [ ''"example.invalid A 192.0.2.1"'' ]; }
        { services.unbound.settings.server.local-data-ptr = [ "192.0.2.1 example.invalid" ]; }
        {
          services.unbound.settings.rpz = [
            {
              name = "example.invalid";
              url = "https://example.invalid/rpz";
            }
          ];
        }
        { services.unbound.settings.remote-control.control-enable = lib.mkOverride 0 true; }
      ];
  duplicateGuards = builtins.filter (matchesMessage (
    value:
    value == "unbound: only one active instance may claim the native Unbound runtime per machine."
  )) duplicateInstances.ownedAssertions;
  duplicateInstancesRejected =
    builtins.length duplicateGuards == 2 && builtins.all (entry: !entry.assertion) duplicateGuards;
  explicitIpv6ConflictGuards = builtins.filter (matchesMessage (
    value: value == "unbound: listen.hosts explicitly enables ::1 while host IPv6 is disabled."
  )) explicitIpv6Conflict.ownedAssertions;
  explicitIpv6ConflictRejected =
    builtins.length explicitIpv6ConflictGuards == 1
    && !(builtins.head explicitIpv6ConflictGuards).assertion;
  defaultServer = defaults.config.services.unbound.settings.server;
  ipv4Server = ipv4Only.config.services.unbound.settings.server;
  explicitServer = explicitIpv4.config.services.unbound.settings.server;
  explicitIpv6Server = explicitIpv6.config.services.unbound.settings.server;
  schemaContract =
    defaults.settings.listen.hosts == null
    && defaults.settings.listen.port == 5335
    && schemaAccepts { listen.hosts = [ "127.0.0.1" ]; }
    && schemaAccepts {
      listen.hosts = [
        "127.255.0.1"
        "::1"
      ];
    }
    && schemaAccepts { listen.port = 1; }
    && schemaAccepts { listen.port = 65535; }
    && !(schemaAccepts { listen.hosts = [ ]; })
    && !(schemaAccepts { listen.hosts = [ "localhost" ]; })
    && !(schemaAccepts { listen.hosts = [ "0.0.0.0" ]; })
    && !(schemaAccepts { listen.hosts = [ "127.256.0.1" ]; })
    && !(schemaAccepts { listen.hosts = [ "127.00.0.1" ]; })
    && !(schemaAccepts { listen.hosts = [ "2001:db8::1" ]; })
    && !(schemaAccepts { listen.port = 0; })
    && !(schemaAccepts { listen.port = 65536; })
    && !(schemaAccepts { adguardIntegrationProvider = "dns-adguardhome"; });
  defaultContract =
    defaults.assertionsPass
    && defaults.nativeAssertionsPass
    && defaults.config.services.unbound.enable
    && !defaults.config.services.unbound.resolveLocalQueries
    && builtins.all (value: value) lifecycleOverrideResults
    && defaults.config.clanwright.dns.unbound.activeInstances == [ "fixture--unbound" ]
    && duplicateInstancesRejected
    && activeWithDisabled.assertionsPass
    && activeWithDisabled.nativeAssertionsPass
    && activeWithDisabled.config.clanwright.dns.unbound.activeInstances == [ "fixture--unbound" ]
    && disabled.assertionsPass
    && disabled.nativeAssertionsPass
    && disabled.config.clanwright.dns.unbound.activeInstances == [ ]
    && !disabled.config.services.unbound.enable
    &&
      defaultServer.interface == [
        "127.0.0.1"
        "::1"
      ]
    && !defaultServer.interface-automatic
    &&
      defaultServer.access-control == [
        "127.0.0.0/8 allow"
        "::1/128 allow"
      ]
    && defaultServer.port == 5335
    && defaultServer.do-ip4
    && defaultServer.do-ip6
    && defaultServer.do-udp
    && defaultServer.do-tcp
    && defaultServer.edns-buffer-size == 1232
    && defaultServer.auto-trust-anchor-file == "/var/lib/unbound/root.key"
    && defaultServer.module-config == ''"validator iterator"''
    && !defaultServer.val-permissive-mode
    && defaultServer.harden-dnssec-stripped
    && defaultServer.domain-insecure == [ ]
    && defaultServer.hide-identity
    && defaultServer.hide-version
    && defaultServer.qname-minimisation
    && !defaultServer.qname-minimisation-strict
    && defaultServer.prefetch
    && defaultServer.cache-min-ttl == 0
    && defaultServer.serve-expired
    && defaultServer.serve-expired-ttl == 86400
    && !defaultServer.serve-expired-ttl-reset
    && defaultServer.serve-expired-client-timeout == 1800
    && defaultServer.serve-expired-reply-ttl == 30
    && defaults.config.services.unbound.package == unboundPackage
    && defaults.config.services.unbound.checkconf
    && defaults.config.services.unbound.enableRootTrustAnchor
    && defaults.config.systemd.services.unbound.serviceConfig.Type == "notify";
  ipv4Contract =
    ipv4Only.assertionsPass
    && ipv4Only.nativeAssertionsPass
    && ipv4Server.interface == [ "127.0.0.1" ]
    && ipv4Server.access-control == [ "127.0.0.0/8 allow" ]
    && ipv4Server.do-ip4
    && !ipv4Server.do-ip6
    && explicitIpv4.assertionsPass
    && explicitIpv4.nativeAssertionsPass
    && explicitServer.interface == [ "127.9.8.7" ]
    && explicitServer.do-ip4
    && explicitServer.do-ip6
    && explicitIpv6.assertionsPass
    && explicitIpv6.nativeAssertionsPass
    && explicitIpv6Server.interface == [ "::1" ]
    && explicitIpv6Server.do-ip4
    && explicitIpv6Server.do-ip6
    && explicitIpv6ConflictRejected;
  integrationContract = !(defaults.config.systemd.services ? adguardhome);
  effectiveOverrideRejected = builtins.all (value: value) effectiveOverrideResults;
  dnssecOverrideRejected = builtins.all (value: value) dnssecOverrideResults;
  includeOverrideRejected = builtins.all (value: value) includeOverrideResults;
  zoneOverrideRejected = builtins.all (value: value) zoneOverrideResults;
  closedPolicyOverrideRejected = builtins.all (value: value) closedPolicyOverrideResults;
  contract =
    schemaContract
    && defaultContract
    && ipv4Contract
    && integrationContract
    && effectiveOverrideRejected
    && dnssecOverrideRejected
    && includeOverrideRejected
    && zoneOverrideRejected
    && closedPolicyOverrideRejected;
in
if !contract then
  throw "Unbound schema, effective policy, IPv4-only, or integration contract failed: ${
    builtins.toJSON {
      inherit
        defaultContract
        closedPolicyOverrideRejected
        dnssecOverrideRejected
        effectiveOverrideRejected
        includeOverrideRejected
        integrationContract
        ipv4Contract
        schemaContract
        zoneOverrideRejected
        ;
    }
  }"
else
  {
    all = true;
    inherit
      defaultContract
      closedPolicyOverrideRejected
      dnssecOverrideRejected
      effectiveOverrideRejected
      includeOverrideRejected
      integrationContract
      ipv4Contract
      schemaContract
      zoneOverrideRejected
      ;
  }
