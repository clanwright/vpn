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

VLESS/REALITY with XHTTP and Hysteria2 are independent Clan selections that
contribute fragments to one `mihomo-gateway.service`. The runtime accepts at
most one active fragment of each protocol per machine, so both transports share
one process and configuration failure domain.

AmneziaWG remains a separate UDP gateway. Its first release retains the
existing AWG2-compatible parameter set and package-family validation. NaiveProxy
remains one typed Caddy `forward_proxy` contribution attached to a consumer
selected public site claim.

The profile publisher consumes closed provider exports and renders the existing
Mihomo and Sing-box formats. AdGuard Home remains the local/tailnet DNS and DoH
front end, with loopback Unbound as its recursive backend. Exact domains,
listeners, rewrites and secret bindings come from the consumer composition.

TCP performance tuning remains consumer owned and is tracked as future work.
The first release changes no HTTP/3 setting or transport behavior.

## Platforms

Runtime support is `x86_64-linux`. Darwin outputs exist only where current
developer and evaluation checks require them. Verification uses native Nix
evaluation and Linux builds; the repository does not add QEMU or synthetic
NixOS VM tests.
