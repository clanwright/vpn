# Package authority

The flake selects unmodified stock nixpkgs application packages for modules and
checks. Consumers cannot substitute packages through overlays or internal
imports. The package selection is defined in [flake.nix](../flake.nix), with
exact input revisions in [flake.lock](../flake.lock).

## Application inputs

| Input | Revision | Selected packages |
| --- | --- | --- |
| `apps-nixpkgs` | `c27cdad491a991b11ed731760aa2ef8db0cb0410` | Mihomo, Xray, AdGuard Home, dnsproxy, Unbound |
| `modern-apps-nixpkgs` | `f3afd85cd82edf71f2dea9b96dcda2d6a64f26f4` | sing-box, AmneziaWG Go and tools, Mieru |

`nixpkgs` supplies platform modules and developer tools. Selecting an application
from a separate input does not modify its derivation.

## Runtime package set

The public `packages.x86_64-linux` set contains nine applications:

| Attribute | Version | Selection |
| --- | --- | --- |
| `mihomo` | 1.19.30 | Stock `mihomo` |
| `xray` | 26.3.27 | Stock `xray` |
| `adguardhome` | 0.107.78 | Stock `adguardhome` |
| `dnsproxy` | 0.83.2 | Stock `dnsproxy` |
| `unbound` | 1.26.0 | Stock `unbound-with-systemd` |
| `sing-box` | 1.14.0 | Stock `sing-box` with Naive/Cronet support |
| `amneziawg-go` | 3.1.20260828 | Stock `amneziawg-go` |
| `amneziawg-tools` | 3.1.20260812 | Stock `amneziawg-tools` |
| `mieru` | 3.36.0 | Stock `mieru`; server entrypoint `bin/mita` |

These outputs must come from the NixOS cache; local overrides and custom binary
wrappers are prohibited. Cache availability is an external property, not a
result of the repository's pure evaluation gate.

The package authority contract checks the complete nine-application output
set against its stock source selections and exact versions. Service contracts
also reject substitution of those packages in the evaluated configuration.

Mieru 3.36.0 was explicitly accepted for initial support on 2026-09-12. Its
exact output `/nix/store/2pxyb640silgkmpbg3l61mhcayhj3yjh-mieru-3.36.0`
was present in the NixOS cache. Upstream 3.36.1 remains a follow-up package update
once a stock output is cached; no local build or package override is authorized.
The later release optimizes CPU usage and fixes an external SOCKS5 UDP egress
case; neither version supplies complete native destination filtering, so the
Mieru module provides service-scoped network guards.

## Caddy integration

NaiveProxy uses the consumer's Network-owned Caddy with forwardproxy and
ratelimit. The pinned Network input supplies the integration fixture; VPN does
not export a Caddy package. This is the sole allowed non-stock application
package. Stock Caddy lacks the required forwardproxy plugin.

The exception does not authorize a VPN-local override, a build or cache
publication. See [NaiveProxy operations](operations/naiveproxy.md) for integration
requirements.

## Platforms

Runtime support is `x86_64-linux`. The `aarch64-linux` and `aarch64-darwin` flake
outputs contain Mihomo, sing-box and developer tooling; their presence does not
extend runtime support.
