# Package authority

The domain supplies the exact application packages consumed by its service
modules and checks. Consumers do not replace them through overlays or internal
imports.

For `x86_64-linux`, the public package set contains `mihomo`, `mihomo-keygen`,
`sing-box`, `naiveproxy`, `amneziawg-go`, `amneziawg-tools`, `adguardhome` and
`unbound`. Mihomo, Mihomo keygen, Sing-box and the AmneziaWG packages come from
the domain's exact application-package input. AdGuard Home uses the domain's
pinned platform context. Unbound uses that context's systemd-enabled daemon
variant so the native NixOS `Type=notify` unit can report readiness. NaiveProxy
is the domain-owned manual binary package because the required package is
unavailable in the selected official package stream.

The removal condition for the manual NaiveProxy package is an official package
that preserves the required feature and passes the same domain and consumer
checks. Availability alone does not authorize a package-source change.

Runtime packages support `x86_64-linux`. Darwin is limited to developer and
evaluation tooling needed by existing checks.
