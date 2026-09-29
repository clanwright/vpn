# Package authority

The flake selects unmodified stock nixpkgs application packages for modules and
checks. Consumers cannot substitute packages through overlays or internal
imports. The package selection is defined in [flake.nix](../flake.nix), with
exact input revisions in [flake.lock](../flake.lock).

## Application inputs

| Input | Revision | Selected packages |
| --- | --- | --- |
| `apps-nixpkgs` | `8d5d270900d3fc75655ea2d9d248b234f6631439` | Mihomo, Xray, AdGuard Home, dnsproxy, Unbound |
| `modern-apps-nixpkgs` | `8d5d270900d3fc75655ea2d9d248b234f6631439` | sing-box, AmneziaWG Go and tools, Mieru |
| `trusttunnel-nixpkgs` | `8d5d270900d3fc75655ea2d9d248b234f6631439` | TrustTunnel endpoint |

`nixpkgs` supplies platform modules and developer tools. Selecting an application
from a separate input does not modify its derivation.

The root platform `nixpkgs` input also resolves to
`8d5d270900d3fc75655ea2d9d248b234f6631439`. The root `clan-core` input
is `c612dac4b2bfb5278b7c366f250044ddb5401bcb` and root `sops-nix` is
`5efb5a6f4f5ab192817d28557dd4d650fa14d866`. The Network v4.0.0 input
resolves to `2981962f1f590fae66c05c50a3d793825281de9e`; its own nested
input graph retains the revisions required for Network's exact Caddy package.
Network v4 requires the native NixOS ACME module's Lego 5 command and Lego 4
account-migration support, which the selected platform revision provides.

## Runtime package set

The public `packages.x86_64-linux` set contains ten applications:

| Attribute | Version | Selection |
| --- | --- | --- |
| `mihomo` | 1.19.31 | Stock `mihomo` |
| `xray` | 26.9.9 | Stock `xray` |
| `adguardhome` | 0.107.79 | Stock `adguardhome` |
| `dnsproxy` | 0.84.1 | Stock `dnsproxy` |
| `unbound` | 1.26.0 | Stock `unbound-with-systemd` |
| `sing-box` | 1.14.1 | Stock `sing-box` with Naive/Cronet support |
| `amneziawg-go` | 3.1.20260828 | Stock `amneziawg-go` |
| `amneziawg-tools` | 3.1.20260812 | Stock `amneziawg-tools` |
| `mieru` | 3.36.0 | Stock `mieru`; server entrypoint `bin/mita` |
| `trusttunnel-endpoint` | 1.1.0 | Stock `trusttunnel-endpoint` |

These outputs must come from the NixOS cache; local overrides and custom binary
wrappers are prohibited. On 2026-09-27 all ten exact `x86_64-linux` outputs at
this revision returned HTTP 200 from the NixOS cache; the path and status record
is retained in `.work/dependency-update/candidate-cache.tsv`. Cache availability
is an external property, not a result of the repository's pure evaluation gate.

The package authority contract checks the complete ten-application output
set against its stock source selections and exact versions. Service contracts
also reject substitution of those packages in the evaluated configuration.

Mieru 3.36.0 was explicitly accepted for initial support on 2026-09-12. The
selected revision still packages 3.36.0; upstream has released 3.38.0, but it
is not yet merged into the selected stock nixpkgs package. The 2026-09-27 cache
check confirmed the selected 3.36.0 output. Updating Mieru requires a reviewed
stock nixpkgs package and a cached exact output; no local build or override is
authorized. Native destination filtering remains incomplete, so the module
provides service-scoped network guards.

TrustTunnel 1.1.0 uses the same selected stock revision as the other applications.
Its exact output returned HTTP 200 from the NixOS cache on 2026-09-27. Upstream
1.1.0 fixes UDP idle-timeout socket cleanup and global
IPv6 classification; it does not establish that the open memory/panic and
reconnect reports are resolved. See [runtime acceptance](operations/trusttunnel.md).

As of 2026-09-27, upstream sing-box 1.14.2 and dnsproxy 0.85.0 are absent from
the selected nixpkgs revision; upstream Mieru 3.38.0 is not yet merged as a
stock package. Unbound 1.26.1 is available in nixpkgs staging, but its exact
outputs from staging and staging-26.05 returned HTTP 404 from the NixOS cache,
so this update retains 1.26.0. Xray 26.9.9 is marked prerelease upstream and is
the selected stock nixpkgs version.

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
