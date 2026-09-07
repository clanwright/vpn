# RKNHardering Client-Side Threat Model

Canonical interpretation of `xtclovver/RKNHardering`, refreshed on 2026-08-16
against release `v2.11.0`. Use it for Android/app detection questions, not as
evidence of what an operator or TSPU observed on the network.

Primary sources:

- project and release: `https://github.com/xtclovver/RKNHardering`,
  `https://github.com/xtclovver/RKNHardering/releases/tag/v2.11.0`
- VPNHide native-oracle commit:
  `https://github.com/xtclovver/RKNHardering/commit/0bce612ebba6b199af5cd43a24b2d4b8db08515b`
- VPNHide timing-beta commit:
  `https://github.com/xtclovver/RKNHardering/commit/266a6bad9eeddfca9e077195ee1ffbe17361dc10`
- Android VPN and network APIs:
  `https://developer.android.com/develop/connectivity/vpn`,
  `https://developer.android.com/reference/android/net/NetworkCapabilities`
- Android 17 changes and local-network permission:
  `https://developer.android.com/about/versions/17/release-notes`,
  `https://developer.android.com/privacy-and-security/local-network-permission`
- Android ECH/network security configuration:
  `https://developer.android.com/privacy-and-security/security-config`

After the 2026-07-26 release, only the same-day `6014117` documentation-test
maintenance commit was found through this 2026-08-16 refresh; no later
behavior-bearing detector change was found.

## Scope Boundary

RKNHardering is an app-level heuristic model. It combines Android APIs, local
process/kernel observations, active localhost probes, public-IP/path checks, and
location evidence. Its result does not prove:

- that RKN/TSPU uses the same detector;
- that the carrier recognized the tunnel protocol;
- that a clean or unavailable check means no VPN exists;
- that a local concealment inconsistency caused a network block.

Keep network-plane evidence in `russia-2026-censorship.md` and client-plane
evidence here.

## Signal Map

| Surface          | Examples                                                                         | Interpretation                                             |
| ---------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Android direct   | `TRANSPORT_VPN`, missing `NOT_VPN`, `VpnTransportInfo`, system/per-network proxy | strongest ordinary local evidence                          |
| App/package      | known VPN/proxy packages, declared `VpnService`                                  | app presence/capability; not proof of active traffic alone |
| Network shape    | `tun*`/`wg*`/IPsec interfaces, routes, MTU, DNS replacement, `dumpsys`           | indirect evidence; false-positive guards matter            |
| Local listeners  | SOCKS/HTTP proxy ports, Xray gRPC API, Clash-compatible REST API                 | active confirmation can become hard evidence               |
| Path divergence  | direct versus VPN/underlying IP, IPv4/IPv6 mismatch, STUN/call transport         | split, leak, or cross-channel evidence                     |
| Geo/location     | foreign/hosting/proxy GeoIP plus Russian SIM/cell/Wi-Fi/location                 | strong combined app-level pattern                          |
| Native integrity | sysfs/netlink/proc/routes/socket probes, hooks/root signs                        | concealment/tampering or kernel-view evidence              |
| Noisy heuristics | RTT, PMTU, jitter, emulator/isolation                                            | review evidence only unless combined by a defined rule     |

## Direct And Indirect Checks

Direct checks include Android `NetworkCapabilities` (`TRANSPORT_VPN`, `IS_VPN`,
`VpnTransportInfo`), proxy properties, default and per-network proxy
configuration, installed package signatures, and apps that declare
`VpnService.SERVICE_INTERFACE`.

Indirect checks include:

- active tunnel-like interfaces and routes, including split routing;
- unusual tunnel MTU and public host routes;
- loopback/replaced DNS and divergence from the underlying network;
- `/proc/net/*` listeners, `dumpsys vpn_management`, and running `VpnService`;
- native `getifaddrs`, netlink, sysfs, IPv4/IPv6 route, socket-binding, PMTU,
  MSS, timing, backpressure, and GSO observations.

Do not strip interpretation guards. Common modem interfaces, kernel-local/link
routes, ordinary IPsec/IMS behavior, and noisy timing/PMTU observations are not
equivalent to a confirmed VPN.

## Active Local Probes

When enabled, the app can:

- scan loopback for SOCKS5 and HTTP CONNECT proxies;
- confirm that a proxy exit differs from the direct public IP;
- call Xray's local gRPC API and enumerate outbound details;
- query Clash/mihomo/sing-box-compatible control APIs;
- test weak proxy authentication and unauthenticated UDP association;
- bind requests to a non-VPN underlying Android network;
- compare HTTP(S), IPv4/IPv6, STUN, call-transport, and local-proxy paths.

The runner also exposes optional domain-reachability, ICMP-spoofing, and
CDN-edge probes. Preserve their raw status; none attributes a carrier mechanism
by itself.

An open port alone can be review evidence. A confirmed management API,
authentication bypass, gateway leak, or underlying-network bypass can become a
hard verdict signal. Keep management APIs closed or strongly protected and do
not expose unnecessary localhost proxy listeners.

## GeoIP, Location, And Cross-Channel Evidence

The app retains public IP, country, ASN/organization, hosting, proxy/VPN/Tor,
and provider-consensus evidence. It can compare Russian and non-Russian IP
services, active and underlying networks, IPv4 and IPv6, STUN, CDN traces, SIM
MCC/MNC, cell/Wi-Fi location, and roaming state.

Important consequences:

- a plausible TLS transport does not hide a foreign datacenter exit;
- Russian location plus foreign GeoIP is stronger than either signal alone;
- IPv6, STUN, or an excluded app can reveal a different path from normal web
  traffic;
- blocking one public-IP page does not remove system or cross-channel evidence.

Route Russian apps directly when they must see a Russian exit. A Russian ingress
with a foreign second hop helps only if those apps are excluded from the foreign
egress path.

## VPNHide Changes In `v2.11.0`

### Native concealment oracles

The release added ordinary unprivileged socket/ioctl consistency probes:

- `vpnhide_ifindex_oracle`: a candidate name yields a stable interface index,
  but reverse index-to-name lookup reports the interface missing;
- `vpnhide_ifconf_tail_vpn`: bytes beyond the reported `SIOCGIFCONF` length
  contain a plausible tunnel-like name.

These are concealment inconsistencies, not carrier evidence and not proof of a
currently active VPN. The name matcher is intentionally broad, including
synthetic `ifN` candidates. A generic stale tail is medium review evidence.
Socket/ioctl errors, unsupported paths, and empty results are not clean proof.

### Hook-timing beta

The opt-in ARM64 beta compares libc calls with raw syscall, netlink, and
`/proc` paths over paired warmups and repeated samples. A positive needs both a
stable timing anomaly and a semantic mismatch. Timing-only, semantic-only,
unsupported, unavailable, truncated, or cancelled results are inconclusive.

`BETA_HOOK_TIMING` is MEDIUM `HOOK_OR_TAMPERING`, review-only, and excluded from
hard-verdict/quorum logic. It models local process/kernel integrity, not RKN.

## Verdict Semantics

Hard conditions include `SPLIT_TUNNEL_BYPASS`, `XRAY_API`, `CLASH_API`,
`PROXY_AUTH_BYPASS`, `VPN_GATEWAY_LEAK`, `VPN_NETWORK_BINDING`, and Russian
location combined with a foreign-GeoIP signal.

The general matrix combines:

- `geoMatrixHit`: foreign GeoIP evidence;
- `directMatrixHit`: direct network-capability or system-proxy evidence;
- `indirectMatrixHit`: interface, route, DNS, listener, indirect capability, or
  high-confidence native evidence.

The key interpretation is conservative:

| Evidence combination                      | Result                                               |
| ----------------------------------------- | ---------------------------------------------------- |
| none                                      | `NOT_DETECTED` for this run, not proof of absence    |
| geo only                                  | `NEEDS_REVIEW`                                       |
| direct only or indirect only, without geo | `NOT_DETECTED` for this matrix, not proof of absence |
| direct + indirect without geo             | `NEEDS_REVIEW`                                       |
| geo combined with direct or indirect      | normally `DETECTED`                                  |
| medium/noisy/beta evidence                | can raise review, not create a hard verdict alone    |

The VPNHide index/tail high-confidence rows can feed the native evidence path;
the generic stale-tail and timing-beta rows remain review-only. Preserve the
structured rule code and participant evidence when reporting a verdict.
Among opt-in beta checks, only the documented Binder-service and TUN-fd kernel
queries can become standalone hard evidence after two stable samples; do not
extend that rule to timing beta or other beta rows.

Exact provider lists, scan ports, concurrency, and timeout constants are
implementation details, not policy. Inspect the pinned app source when
reproducing a specific checker instead of copying them into this reference.

## Android 17 Boundaries

- Cross-profile loopback is blocked by default; same-profile loopback is not.
  Do not claim this removes localhost scanners.
- Target SDK 37+ local-network permission can make LAN probes unavailable.
  Permission denial means unavailable, not clean; the official docs do not say
  that all loopback access is covered.
- ECH can hide SNI from network observers when client, library, and server
  support it. It does not hide `VpnService`, interfaces, routes, DNS, listeners,
  packages, GeoIP/ASN, IPv6, STUN, or CDN/path evidence.

## Mitigation Priorities

1. Router/off-device proxying removes the phone's local `VpnService` and tunnel
   interface when the phone uses ordinary LAN routing.
2. Close management APIs and unnecessary proxy listeners; require authentication
   where a listener must exist.
3. Avoid unusual TUN MTU, loopback DNS, route artifacts, and accidental IPv6 or
   STUN divergence.
4. Use per-app/direct routing for Russian apps rather than expecting protocol
   camouflage to hide a foreign exit.
5. If using root/hooking concealment, keep libc, raw syscall, netlink, proc,
   Binder, and socket views consistent; the concealment layer is itself a signal.

Router-level routing reduces local Android evidence but does not hide endpoint
IP/ASN, DNS, TLS/QUIC behavior, traffic shape, or carrier-side policy. Client and
network hardening must be evaluated separately.
