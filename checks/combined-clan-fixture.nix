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
    && units ? naiveproxy-caddy-fragment-fixture
    && machine.services.adguardhome.enable
    && machine.services.unbound.enable
    && builtins.elem "unbound.service" units.adguardhome.after
    && builtins.elem "unbound.service" units.adguardhome.requires
    && machine.networkCore.caddy.effectiveFragments ? fixture-site
    && builtins.elem "forward-proxy" machine.networkCore.caddy.effectiveFragments.fixture-site.capabilities;
in
if contract then
  pkgs.runCommand "vpn-combined-clan-fixture" { passthru = { inherit contract; }; } ''touch "$out"''
else
  throw "Combined external Clan fixture contract failed"
