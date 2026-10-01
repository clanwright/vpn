# Package authority

The flake selects unmodified stock nixpkgs application packages for modules and
checks. Consumers cannot substitute packages through overlays or internal
imports. The package selection is defined in [flake.nix](../flake.nix), with
exact input revisions in [flake.lock](../flake.lock).

AWG, Mieru, TrustTunnel and AnyTLS use explicit fixed application output paths and
version checks. Independent host `pkgs` aliases may differ without changing VPN
runtime. No VPN global package overlay or host-alias equality guard is required.
AWG directly adds its two required
stock packages to `environment.systemPackages`; Mieru and TrustTunnel guard
the effective `ExecStart` against their fixed package commands. AWG checks
inspect generated exact paths; they do not assert a new merged command guard.
AnyTLS explicitly selects native `services.sing-box.package` as stock 1.14.1;
its effective package, command, vendor provenance and security guards remain
mandatory. Independent host `pkgs.sing-box` is only a native option default,
not the AnyTLS runtime authority.

## Application inputs

| Input | Revision | Selection |
| --- | --- | --- |
| `nixpkgs` | `8d5d270900d3fc75655ea2d9d248b234f6631439` | Platform modules, developer tools and all ten stock applications |

All ten applications and the native platform use this single input. Exact
Clan, SOPS and Network revisions, including Network-owned nested package
inputs, are recorded in [flake.lock](../flake.lock). This keeps package
authority at its owning input rather than duplicating dependency pins in prose.

Clan owns its bundled native DataMesher dependency and NixOS module import.
VPN does not replace that module or override its dependency. Its native
`services.data-mesher.enable` default is false; the combined Clan fixture checks
that no DataMesher runtime is added and that the disabled module does not force
its package. The dependency follows Clan's existing nixpkgs, flake-parts and
treefmt inputs rather than introducing separate platform pins.

DataMesher is not a VPN runtime package or public module. Enabling Clan's mesh
service is separate consumer-owned composition and is outside VPN's stock
application package qualification and repository runtime support.

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
wrappers are prohibited. Cache availability is an external qualification, not
a result of pure evaluation. Retain exact-output cache evidence with release
artifacts as described in [release](operations/release.md).

The package authority contract checks the complete ten-application output set
against stock selections and exact versions. Effective service contracts reject
substitution of those runtime packages. Package changes require a reviewed stock
nixpkgs revision and cached exact output; they do not prove runtime compatibility.
Mieru’s service-scoped network guards complement its incomplete native
destination filtering. TrustTunnel’s memory, cleanup and reconnect acceptance is
defined in [its operations guide](operations/trusttunnel.md).

## Caddy integration

NaiveProxy uses Network-owned Caddy with forwardproxy and ratelimit. VPN does
not export a Caddy package. Native Caddy/ACME composition uses the public
Network API. Network remains the
sole specialized Caddy constructor; native host ACME and stock host Lego retain
authority. Dependency compatibility is qualified in
[verification](operations/verify.md#evidence-and-runtime-acceptance). This is the sole allowed non-stock application package. Stock
Caddy
lacks the required forwardproxy plugin.

The exception does not authorize a VPN-local override, a build or cache
publication. See [NaiveProxy operations](operations/naiveproxy.md) for integration
requirements.

## Platforms

Runtime support is `x86_64-linux`. The `aarch64-linux` and `aarch64-darwin` flake
outputs contain Mihomo, sing-box and developer tooling; their presence does not
extend runtime support.
