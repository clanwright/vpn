# Package authority

The domain supplies the exact application packages consumed by its service
modules and checks. Consumers do not replace them through overlays or internal
imports.

For `x86_64-linux`, the public package set contains `mihomo`, `mihomo-keygen`,
`sing-box`, `naiveproxy`, `amneziawg-go`, `amneziawg-tools`, `adguardhome` and
`unbound`. Mihomo, Mihomo keygen and the AmneziaWG packages come from
the domain's exact application-package input. Sing-box is pinned to the official
1.14.0 Linux amd64 archive with its adjacent `libcronet.so`; the Naive backend
requires this runtime, not only a parser accepting the outbound type. Its ELF
dependencies are patched for NixOS and checked during installation. AdGuard Home uses the domain's
pinned platform context. Unbound 1.26.0 uses the stock `unbound-with-systemd`
package from the existing locked application-package input. It retains systemd
support so the native NixOS `Type=notify` unit can report readiness; no custom
source override or separate package recipe is needed. The same exact derivation
is exported and injected into the service. NaiveProxy
is the domain-owned manual binary package because the required package is
unavailable in the selected official package stream.

The removal condition for the manual NaiveProxy package is an official package
that preserves the required feature and passes the same domain and consumer
checks. Availability alone does not authorize a package-source change.

Runtime packages support `x86_64-linux`. Darwin is limited to developer and
evaluation tooling needed by existing checks.

For the September 2026 Naive candidate, the Network-owned Caddy 2.11.4 and
klzgrad/forwardproxy commit `d62c80d3dd2c` remain unchanged, as does the standalone
NaiveProxy client 150.0.7871.63-1. The latest forwardproxy release tag names the
same source commit; changing that label would not update the implementation.
