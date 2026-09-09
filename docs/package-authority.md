# Package authority

The domain supplies the exact application packages consumed by its service
modules and checks. Consumers do not replace them through overlays or internal
imports.

Two named Nixpkgs inputs keep reviewed package families separate:

- `apps-nixpkgs` at `c27cdad491a991b11ed731760aa2ef8db0cb0410`
  supplies Mihomo 1.19.30, Xray 26.3.27, AdGuard Home 0.107.78 built with Go
  1.26.7, dnsproxy 0.83.2, and Unbound 1.26.0 with systemd support.
- `modern-apps-nixpkgs` at
  `f3afd85cd82edf71f2dea9b96dcda2d6a64f26f4` supplies sing-box 1.14.0 with
  the stock Naive/Cronet feature and the AmneziaWG 3.1 package family:
  `amneziawg-go` 3.1.20260828 and `amneziawg-tools` 3.1.20260812.

The split is intentional. The newer input contains dnsproxy 0.84.1, while the
accepted fallback design and source audit target 0.83.2. Importing the whole
newer package set would change that runtime without review.

For `x86_64-linux`, the public package set contains `mihomo`,
`xray`, `sing-box`, `amneziawg-go`, `amneziawg-tools`,
`adguardhome`, `dnsproxy`, and `unbound`. The obsolete Mihomo REALITY keygen
wrapper is removed; secret generation belongs to the consumer. The unused standalone
`naiveproxy` package is removed: the Naive server runs in Network's Caddy and
the client runs in the stock sing-box package.

The exact output paths for all eight application packages are present in
`cache.nixos.org`:

| Package | Cached output |
|---|---|
| AdGuard Home 0.107.78 | `/nix/store/khqalspdwbivh1jxszkas5c19a2133wy-adguardhome-0.107.78` |
| dnsproxy 0.83.2 | `/nix/store/0dng5ls5qqv13993p28v7448l3h0dpyc-dnsproxy-0.83.2` |
| Unbound 1.26.0 | `/nix/store/6396ha36mxdl1kilz9539ll06ighaqmd-unbound-1.26.0` |
| Mihomo 1.19.30 | `/nix/store/06sinlwrggajk6j7x2q01q4z59ind1s0-mihomo-1.19.30` |
| Xray 26.3.27 | `/nix/store/w9h9zkqpcrqa3h2nhhcd0w0h0hq0p7x6-xray-26.3.27` |
| AmneziaWG Go 3.1.20260828 | `/nix/store/3n5rkidh23m5x8d6qqzn2mgjcaazk48p-amneziawg-go-3.1.20260828` |
| AmneziaWG tools 3.1.20260812 | `/nix/store/dd28gg53ykjfa0c9i60x5wnwgi056719-amneziawg-tools-3.1.20260812` |
| sing-box 1.14.0 | `/nix/store/bcbfbiaxbsvh3qnsglcgnl2ab5wz0y18-sing-box-1.14.0` |

AdGuard Home 0.107.79 was not available as a stock package in the checked
official revisions. The retained 0.107.78 derivation already uses Go 1.26.7,
which includes the Go security fixes cited by the 0.107.79 release. DNS-over-QUIC
and DNS64 are disabled, so the identified remaining 0.107.79 gap is the blocked
EDNS reply compatibility fix, not an applicable confirmed security issue.

Network's Caddy 2.11.4 package with forwardproxy commit `d62c80d3dd2c` and the
ratelimit plugin is the sole approved non-stock application package. It remains
owned by the pinned Network input. Its exact output
`/nix/store/1z8ydds26sn7rpjd21q69xlykizhrhsp-caddy-2.11.4` was absent from all
four configured caches during the audit. Stock Caddy cannot replace it because
it lacks the required forwardproxy feature. This exception does not authorize a
VPN-local override, cache publication, or a build during source-only
verification.

Runtime packages support `x86_64-linux`. Darwin support is limited to developer
and evaluation tooling used by existing checks.
