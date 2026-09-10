{
  combined,
  fixture,
  lib,
}:
let
  supportNames = [
    "edge-wildcard-certificate"
    "network-caddy"
    "network-certificates"
  ];
  serviceNames = builtins.filter (name: !(builtins.elem name supportNames)) (
    builtins.attrNames fixture.instances
  );
  inherit (combined) config machine;
  units = machine.systemd.services;
  adguardTemplateNames = builtins.filter (lib.hasSuffix "-adguardhome.yaml") (
    builtins.attrNames machine.sops.templates
  );
  adguardTemplate = machine.sops.templates.${builtins.head adguardTemplateNames};
  adguardSettings = builtins.fromJSON adguardTemplate.content;
  contract =
    builtins.attrNames config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ serviceNames)
    && builtins.length (builtins.attrNames config._services.allServices) == 10
    && machine.services.xray.enable
    && units ? xray
    && units ? mihomo-hysteria2
    && machine.sops.templates ? "mihomo-hysteria2.json"
    && !((machine.networkCore.mihomo or { }) ? vlessXhttp)
    && !((machine.networkCore.mihomo or { }) ? hysteria2)
    && !(units ? mihomo-gateway)
    && machine.sops.templates ? "naiveproxy-vpn-fixture.caddy"
    && machine.sops.templates."naiveproxy-vpn-fixture.caddy".reloadUnits == [ "caddy.service" ]
    && !(units ? naiveproxy-caddy-fragment-fixture)
    && !(units ? naiveproxy-caddy-refresh-fixture)
    && machine.services.adguardhome.enable
    && machine.services.adguardhome.settings == null
    && machine.services.dnsproxy.enable
    && builtins.length adguardTemplateNames == 1
    && adguardTemplate.restartUnits == [ "adguardhome.service" ]
    && machine.services.unbound.enable
    && builtins.elem "unbound.service" units.adguardhome.wants
    && !(builtins.elem "unbound.service" units.adguardhome.after)
    && !(builtins.elem "unbound.service" units.adguardhome.requires)
    && adguardSettings.dns.upstream_dns == [ "127.0.0.1:5335" ]
    && adguardSettings.dns.fallback_dns == [ "127.0.0.1:5336" ]
    && machine.services.dnsproxy.settings.listen-addrs == [ "127.0.0.1" ]
    && machine.networkCore.caddy.effectiveFragments ? fixture-site
    && builtins.elem "forward-proxy" machine.networkCore.caddy.effectiveFragments.fixture-site.capabilities;
in
if !contract then
  throw "Combined external Clan fixture contract failed"
else
  {
    all = true;
    inherit contract;
  }
