# Architecture

Clanwright VPN is one versioned domain containing seven independently selected
VPN and DNS bricks. Grouping them in one release keeps provider contracts,
profile rendering, DNS metadata and the exact application package set coherent;
it does not require a consumer to enable every brick.

## Ownership

The domain owns service implementation and defaults, the closed typed export
contracts, package closures and domain checks. Its flake exposes public Clan
modules, helper libraries, packages and checks without importing a consumer
repository or its inputs.

The consumer owns service placement and composition, machine facts, secret
values and runtime-path bindings, public and private exposure, certificates and
Caddy claims, operator procedures, monitoring/probe integrations and aggregate
cross-domain checks.

## Runtime shape

VLESS/REALITY with XHTTP runs in Xray. Hysteria2 runs in its own Mihomo service
with Gecko obfuscation. Their stable Clan module IDs retain the historical
Mihomo names; the services have independent configurations and lifecycles.

AmneziaWG is a separate userspace generation-3 UDP gateway with a runtime-only
header-protection key in addition to the individual WireGuard peer keys. NaiveProxy
remains one typed Caddy `forward_proxy` contribution attached to a consumer
selected public site claim.

The profile publisher consumes closed provider exports and renders the existing
Mihomo and Sing-box formats. AdGuard Home remains the local/tailnet DNS and DoH
front end, with loopback Unbound as its recursive backend. Exact domains,
listeners, rewrites and secret bindings come from the consumer composition.

The AdGuard role also owns a permanent loopback dnsproxy service through the
native NixOS module. It supplies the two reserve DNS tiers: parallel encrypted
providers, then plaintext only after encrypted exchange failures. AdGuard's
only fallback points to this service; Unbound remains its normal primary.
This adds no Clan module ID and no custom failover coordinator. It does not
switch VPN transports or provide a client bypass when AdGuard itself is down.

TCP performance tuning remains consumer owned. The audit does not introduce
incidental HTTP/3 changes to shared Caddy sites.

## Platforms

Runtime support is `x86_64-linux`. Darwin outputs exist only where current
developer and evaluation checks require them. Verification forces pure Nix
schema, contract and generated-configuration assertions, plus static source
hygiene. No application binaries, listeners, runtime tests, Linux builds,
external builders or tests on real machines are run. VM configurations and
VM-backed execution are prohibited throughout the project.
