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
  evaluate =
    rawSettings: enableIPv6: extraModule:
    let
      settings = evalSettings rawSettings;
      instance = service.roles.recursive-backend.perInstance {
        inherit settings;
        instanceName = "fixture--unbound";
        machine.name = "fixture";
      };
      evaluated = lib.nixosSystem {
        inherit system;
        modules = [
          instance.nixosModule
          {
            boot.isContainer = true;
            networking = { inherit enableIPv6; };
            system.stateVersion = "26.11";
          }
          extraModule
        ];
      };
      inherit (evaluated) config;
    in
    {
      inherit config settings;
      assertionsPass = builtins.all (entry: entry.assertion) config.assertions;
    };
  defaults = evaluate { } true { };
  ipv4Only = evaluate { } false { };
  explicitIpv4 = evaluate { listen.hosts = [ "127.9.8.7" ]; } true { };
  explicitIpv6 = evaluate { listen.hosts = [ "::1" ]; } true { };
  explicitIpv6Conflict = evaluate { listen.hosts = [ "::1" ]; } false { };
  rejectsOverride = extraModule: !(evaluate { } true extraModule).assertionsPass;
  effectiveOverrideResults = map rejectsOverride [
    { services.unbound.package = lib.mkOverride 0 pkgs.hello; }
    { services.unbound.enableRootTrustAnchor = lib.mkOverride 0 false; }
    { services.unbound.checkconf = lib.mkOverride 0 false; }
    { services.unbound.settings.server.interface = lib.mkOverride 0 [ "0.0.0.0" ]; }
    { services.unbound.settings.server.port = lib.mkOverride 0 0; }
    { services.unbound.settings.server.access-control = lib.mkOverride 0 [ "0.0.0.0/0 allow" ]; }
    { services.unbound.settings.server.serve-expired = lib.mkOverride 0 false; }
  ];
  dnssecOverrideResults = map rejectsOverride [
    { services.unbound.settings.server.module-config = lib.mkOverride 0 ''"iterator"''; }
    { services.unbound.settings.server.val-permissive-mode = lib.mkOverride 0 true; }
    { services.unbound.settings.server.harden-dnssec-stripped = lib.mkOverride 0 false; }
    { services.unbound.settings.server.domain-insecure = lib.mkOverride 0 [ "example.invalid" ]; }
    { services.unbound.settings.server.trust-anchor = lib.mkOverride 0 [ "example.invalid" ]; }
    { services.unbound.settings.server.trust-anchor-file = lib.mkOverride 0 [ "/run/unbound/anchor" ]; }
    { services.unbound.settings.server.trusted-keys-file = lib.mkOverride 0 [ "/run/unbound/keys" ]; }
  ];
  includeOverrideResults = map rejectsOverride [
    { services.unbound.settings.include = "/run/unbound/override.conf"; }
    { services.unbound.settings.include-toplevel = "/run/unbound/override-toplevel.conf"; }
    { services.unbound.settings.server.include = "/run/unbound/override-server.conf"; }
    { services.unbound.settings.server.interface-automatic = lib.mkOverride 0 true; }
  ];
  zoneOverrideResults = map rejectsOverride [
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
  closedPolicyOverrideResults = map rejectsOverride [
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
    && ipv4Server.interface == [ "127.0.0.1" ]
    && ipv4Server.access-control == [ "127.0.0.0/8 allow" ]
    && ipv4Server.do-ip4
    && !ipv4Server.do-ip6
    && explicitIpv4.assertionsPass
    && explicitServer.interface == [ "127.9.8.7" ]
    && explicitServer.do-ip4
    && explicitServer.do-ip6
    && explicitIpv6.assertionsPass
    && explicitIpv6Server.interface == [ "::1" ]
    && explicitIpv6Server.do-ip4
    && explicitIpv6Server.do-ip6
    && !explicitIpv6Conflict.assertionsPass;
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
