{
  inputs,
  pkgs,
  root,
  self,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  supportNames = [
    "edge-wildcard-certificate"
    "network-caddy"
    "network-certificates"
  ];
  serviceNames = builtins.filter (name: !(builtins.elem name supportNames)) (
    builtins.attrNames fixture.instances
  );
  consumer = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = serviceNames;
  };
  inherit (consumer) config machine;
  units = machine.systemd.services;
  generator = units.mihomo-gateway-config-generator;
  contract =
    builtins.attrNames config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ serviceNames)
    && builtins.length (builtins.attrNames config._services.allServices) == 10
    && builtins.length machine.networkCore.mihomo.vlessXhttp == 1
    && builtins.length machine.networkCore.mihomo.hysteria2 == 1
    && builtins.length machine.networkCore.mihomo.packages == 1
    && units ? mihomo-gateway
    && units ? mihomo-gateway-config-generator
    && lib.hasInfix "vless-in" generator.script
    && lib.hasInfix "hysteria2-in" generator.script
    && machine.sops.templates ? "naiveproxy-fixture.caddy"
    && machine.sops.templates."naiveproxy-fixture.caddy".reloadUnits == [ "caddy.service" ]
    && !(units ? naiveproxy-caddy-fragment-fixture)
    && !(units ? naiveproxy-caddy-refresh-fixture)
    && machine.services.adguardhome.enable
    && machine.services.unbound.enable
    && builtins.elem "unbound.service" units.adguardhome.wants
    && !(builtins.elem "unbound.service" units.adguardhome.after)
    && !(builtins.elem "unbound.service" units.adguardhome.requires)
    && machine.services.adguardhome.settings.dns.upstream_dns == [ "127.0.0.1:5335" ]
    && machine.networkCore.caddy.effectiveFragments ? fixture-site
    && builtins.elem "forward-proxy" machine.networkCore.caddy.effectiveFragments.fixture-site.capabilities;
in
if contract then
  pkgs.runCommand "vpn-combined-clan-fixture" { passthru = { inherit contract; }; } ''touch "$out"''
else
  throw "Combined external Clan fixture contract failed"
