# Package authority

The flake selects unmodified stock nixpkgs application packages for modules and
checks. Consumers cannot substitute packages through overlays or internal
imports. The package selection is defined in [flake.nix](../flake.nix), with
exact input revisions in [flake.lock](../flake.lock).

## Application inputs

| Input | Revision | Selected packages |
| --- | --- | --- |
| `apps-nixpkgs` | `c27cdad491a991b11ed731760aa2ef8db0cb0410` | Mihomo, Xray, AdGuard Home, dnsproxy, Unbound |
| `modern-apps-nixpkgs` | `f3afd85cd82edf71f2dea9b96dcda2d6a64f26f4` | sing-box, AmneziaWG Go and tools |

`nixpkgs` supplies platform modules and developer tools. Selecting an application
from a separate input does not modify its derivation.

## Runtime package set

The public `packages.x86_64-linux` set contains eight applications:

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

These outputs must come from the NixOS cache; local overrides and custom binary
wrappers are prohibited. Cache availability is an external property, not a
result of the repository's pure evaluation gate.

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
