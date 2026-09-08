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
  noAdguardEdge = evaluate { adguardIntegrationProvider = null; } true { };
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
  defaultServer = defaults.config.services.unbound.settings.server;
  ipv4Server = ipv4Only.config.services.unbound.settings.server;
  explicitServer = explicitIpv4.config.services.unbound.settings.server;
  explicitIpv6Server = explicitIpv6.config.services.unbound.settings.server;
  adguardUnit = defaults.config.systemd.services.adguardhome;
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
    && !(schemaAccepts { listen.port = 65536; });
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
  integrationContract =
    adguardUnit.wants == [ "unbound.service" ]
    && !(builtins.elem "unbound.service" adguardUnit.after)
    && !(builtins.elem "unbound.service" adguardUnit.requires)
    && !(noAdguardEdge.config.systemd.services ? adguardhome);
  effectiveOverrideRejected = builtins.all (value: value) effectiveOverrideResults;
  dnssecOverrideRejected = builtins.all (value: value) dnssecOverrideResults;
  includeOverrideRejected = builtins.all (value: value) includeOverrideResults;
  contract =
    schemaContract
    && defaultContract
    && ipv4Contract
    && integrationContract
    && effectiveOverrideRejected
    && dnssecOverrideRejected
    && includeOverrideRejected;
  generatedConfig = defaults.config.environment.etc."unbound/unbound.conf".source;
in
if contract then
  pkgs.runCommand "vpn-unbound-contracts"
    {
      nativeBuildInputs = [ unboundPackage ];
      passthru = {
        inherit
          contract
          defaultContract
          dnssecOverrideRejected
          effectiveOverrideRejected
          includeOverrideRejected
          integrationContract
          ipv4Contract
          schemaContract
          ;
      };
    }
    ''
      set -euo pipefail
      cp ${generatedConfig} generated-unbound.conf
      mkdir -p "$PWD/state"
      sed -i \
        -e '/auto-trust-anchor-file:/d' \
        -e "s|/var/lib/unbound|$PWD/state|g" \
        generated-unbound.conf
      unbound-checkconf generated-unbound.conf > unbound-checkconf.log 2>&1

      grep -Fq 'interface: 127.0.0.1' generated-unbound.conf
      grep -Fq 'interface: ::1' generated-unbound.conf
      grep -Fq 'interface-automatic: no' generated-unbound.conf
      grep -Fq 'access-control: 127.0.0.0/8 allow' generated-unbound.conf
      grep -Fq 'access-control: ::1/128 allow' generated-unbound.conf
      grep -Fq 'do-udp: yes' generated-unbound.conf
      grep -Fq 'do-tcp: yes' generated-unbound.conf
      grep -Fq 'edns-buffer-size: 1232' generated-unbound.conf
      grep -Fq 'module-config: "validator iterator"' generated-unbound.conf
      grep -Fq 'val-permissive-mode: no' generated-unbound.conf
      grep -Fq 'harden-dnssec-stripped: yes' generated-unbound.conf
      grep -Fq 'cache-min-ttl: 0' generated-unbound.conf
      grep -Fq 'serve-expired: yes' generated-unbound.conf
      grep -Fq 'serve-expired-ttl: 86400' generated-unbound.conf
      grep -Fq 'serve-expired-ttl-reset: no' generated-unbound.conf
      grep -Fq 'serve-expired-client-timeout: 1800' generated-unbound.conf
      grep -Fq 'serve-expired-reply-ttl: 30' generated-unbound.conf
      if grep -Fq 'forward-zone:' generated-unbound.conf; then
        echo "unbound contract unexpectedly generated an upstream forward-zone" >&2
        exit 1
      fi

      mkdir -p "$out"
      cp generated-unbound.conf "$out/generated-unbound.conf"
      cp unbound-checkconf.log "$out/unbound-checkconf.log"
    ''
else
  throw "Unbound schema, effective policy, IPv4-only, or integration contract failed: ${
    builtins.toJSON {
      inherit
        defaultContract
        dnssecOverrideRejected
        effectiveOverrideRejected
        includeOverrideRejected
        integrationContract
        ipv4Contract
        schemaContract
        ;
    }
  }"
