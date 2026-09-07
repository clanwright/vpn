# Client policy and app detection

Access, confidentiality and a service accepting the exit address are different
objectives. Decide the intended traffic policy before changing DNS or routes.
This reference applies across clients; Android details below are platform-specific
and must not be assumed to describe iOS, macOS or Windows API visibility.

## Routing and DNS decisions

| Requirement | Reasonable policy | Acceptance and tradeoff |
| --- | --- | --- |
| All intended traffic must use the tunnel | Full tunnel, explicit DNS and both IP families; deliberate fail-closed behavior if requested | Test disconnect/startup/reconnect and IPv6. “Connected” does not prove every app or protocol is covered. |
| Selected Russian apps require the ordinary RU path | Narrow per-app/domain exclusions, if acceptable to the user | Direct traffic reveals the underlying path. Test those apps, dependencies, DNS and calls; do not exclude all RU traffic as an unexamined default. |
| Only a browser/app needs proxying | Application proxy when that scope suffices | Other apps, DNS or UDP may bypass it; a SOCKS listener is not a full-device VPN. |
| Client cannot support IPv6 through the chosen tunnel | Explicitly block/disable the unsupported path within scope, or choose a supported client | Do not leave an accidental direct IPv6 route; disabling IPv6 globally is not a universal first fix. |

DNS must implement the same intended policy as traffic, including endpoint
bootstrap, split domains, application DoH/private DNS and reconnect behavior.
DoH/DoT encryption cannot fix an unreachable resolver or guarantee censorship
resistance. Avoid a bootstrap loop where reaching the VPN requires DNS only
available through that VPN. In allowlist mode compare provider DNS with public
resolvers rather than assuming a globally reachable public service.

Local DNS interception/fake-IP modes can change app compatibility and route
matching. Inspect the actual client's handling and test A/AAAA, direct domains,
LAN names and required apps before changing mode. Loopback DNS alone is not a
security flaw or proof of censorship. Do not weaken DNS privacy just to make
an app heuristic report fewer signals.

Android has non-obvious defaults: without configured DNS, underlying-network
DNS is used; permitting an address family without an appropriate VPN route can
let it fall through. `allowBypass()` explicitly permits binding outside the
VPN. Check effective behavior instead of assuming the GUI switch implements
full coverage. [VpnService.Builder API](https://developer.android.com/reference/android/net/VpnService.Builder).

For troubleshooting Android include both IP families and DNS, direct/excluded
apps and STUN/voice where relevant. An intentionally direct call is policy,
not automatically a leak; an unexpected public address on a protected path is.

Apple Network Extension routing is controlled by the effective tunnel routes
and protocol settings; do not infer coverage from an assigned `utun` interface
or a connected badge. Apple's [`includeAllNetworks`](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks)
can enforce stronger inclusion, with platform availability and system-traffic
exceptions that must be checked for the target OS. Keep Apple routing claims
within the supported Network Extension model rather than promising arbitrary
per-process visibility. See [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic).

On Windows, distinguish the VPN profile's traffic filters, routes and name
resolution policy from application-level exclusions. Verify the effective
route table after connect and reconnect, including route metric and prefix
specificity; an exclusion control can still produce conflicting routes. See
[Windows VPN profile options](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/vpn/vpn-profile-options).

## High-value client failure checks

Checked 2026-09-07. Dates below identify the report or proposed change, not a
new independent test. Treat each as a build/OS-scoped reproduction lead; inspect
later fixes and the actual runtime state before applying a workaround:

- Clash Verge Rev 2.5.2 on macOS 15.3.1 reportedly left OS-restored DNS in
  place after sleep/wake (2026-07-25) ([#7593](https://github.com/clash-verge-rev/clash-verge-rev/issues/7593)).
  Test resolver state and protected/direct traffic after wake, handover and
  reconnect. A later report on macOS 26.4 ARM found proxy mode working while
  TUN failed, with Tailscale present as a confounder
  ([#7633](https://github.com/clash-verge-rev/clash-verge-rev/issues/7633));
  treat the competing network extension as a confounder, not a proven cause.
- Clash Verge Rev final-config processing has had reported DNS side effects
  (2026-08-04)
  ([PR #7684](https://github.com/clash-verge-rev/clash-verge-rev/pull/7684)).
  Inspect the generated configuration, not only the source profile. A 2026-09-05 proposed
  change preserves explicit `dns.ipv6: false` in generated TUN configuration
  ([PR #7864](https://github.com/clash-verge-rev/clash-verge-rev/pull/7864));
  merge status and release inclusion were not verified for either pull request.
- AmneziaVPN 5.0.1.5 on macOS Tahoe 26.6 ARM reportedly assigned the gateway
  address to `utun` instead of the client address (2026-08-28), while 4.8.21 worked
  ([#3083](https://github.com/amnezia-vpn/amnezia-client/issues/3083)).
  Compare effective interface addresses, routes and reachability across the
  exact builds. On iPadOS 26.6.1, another report described connected status
  without traffic across several protocols while an alternative app worked
  ([#3080](https://github.com/amnezia-vpn/amnezia-client/issues/3080));
  attribution remains unresolved, so retain server, profile and OS controls.
- Imported-route normalization can silently change policy: AmneziaVPN was
  reported to rewrite an imported `/20` to `/32` (2026-08-04; macOS path,
  exact build not established here)
  ([#2937](https://github.com/amnezia-vpn/amnezia-client/issues/2937)).
  Compare imported input, saved profile and effective routes. On Windows 11 with
  Amnezia 5.0.0.5, excluded-app routing reportedly conflicted via
  `/32` routes ([#2932](https://github.com/amnezia-vpn/amnezia-client/issues/2932));
  validate both excluded and protected apps, including reconnect.
- Very large route sets can be a client performance problem: a 2026-08-22
  Windows 11 / Amnezia 4.8.15.4 AWG2 report observed slowdown with about 12,840 routes
  ([#3020](https://github.com/amnezia-vpn/amnezia-client/issues/3020)).
  Measure connect time and route installation instead of assuming protocol or
  server failure.
- On Android, a 2026-04-07 report described an internal localhost SOCKS
  listener accessible to excluded apps without authentication (exact build not
  established here), with per-process authentication proposed separately
  ([#2452](https://github.com/amnezia-vpn/amnezia-client/issues/2452),
  [PR #2453](https://github.com/amnezia-vpn/amnezia-client/pull/2453)).
  Confirm the listener, reachability and authentication in the exact installed
  build; proposal or merge status alone does not prove release inclusion.

## MTU and reliability

Use the implementation default as a starting point, then derive MTU from actual
encapsulation/path behavior when symptoms justify it. Small packets passing
while large packets stall may be PMTUD trouble, not a DPI signature. Test both
directions; offload can distort packet sizes/counts in host captures. Do not
force 1500 for stealth or blindly set 1280 for every tunnel. A reliable smaller
MTU is preferable to a “normal-looking” value that black-holes traffic. QUIC's
outer packet requirements are in [protocols.md](protocols.md).

Check network handover, sleep/wake, idle NAT expiry and routing loops. Keepalive
can preserve a NAT mapping at a bandwidth/battery cost; it does not defeat IP
blocking. Avoid retry storms and simultaneous racing of every profile.

## Who can see what

| Observer | Typical evidence | What tunnel camouflage cannot remove |
| --- | --- | --- |
| Carrier/network observer | Destination IP/ASN, DNS where visible, handshake/ALPN/SNI where visible, UDP/TCP and flow timing/size | The physical path and endpoint identity; TLS camouflage is limited to particular signals. |
| App on the device | Available VPN APIs, proxy settings, interfaces/routes, accessible local listeners, permitted package/path queries | Local OS VPN state merely by changing the server protocol. API access varies by OS, permissions and build. |
| Remote service | Exit IP/ASN reputation, account/session/location and request behavior | A datacenter/foreign exit merely by hiding local TUN state. |

Android exposes VPN network capabilities; package visibility and filesystem
access are constrained, so do not promise every app can enumerate everything.
Use the exact app/OS evidence.
[NetworkCapabilities](https://developer.android.com/reference/android/net/NetworkCapabilities),
[package visibility](https://developer.android.com/training/package-visibility).

Close unneeded control APIs and proxy listeners. Binding a management API to
loopback limits remote exposure, but local apps may still reach it; require
appropriate authentication. A listening port alone is weaker evidence than a
confirmed proxy or unauthenticated management API. Keep remote administration
separate from the public tunnel surface.

Off-device/router tunneling can remove the phone's active local VPN service and
TUN surface when it uses ordinary LAN routing. It does not remove an installed
VPN app, alter remote exit reputation or make carrier-side traffic invisible.
It also does not solve the phone's mobile path while away from that router.

Root/hook concealment adds another failure and integrity-detection surface;
do not make it the default remedy. Prefer supported routing and narrow
application policy that meets the user’s actual need. Never weaken tunnel
security solely to obtain a clean checker badge.

## Interpreting RKNHardering and similar checkers

[RKNHardering](https://github.com/xtclovver/RKNHardering) is a local Android/path
heuristic implementation, not an RKN/TSPU specification. Research found
[v2.11.0](https://github.com/xtclovver/RKNHardering/releases/tag/v2.11.0),
released 2026-07-26. Its history includes false-positive fixes; inspect the
pinned build's rule and raw participant evidence when reproducing a verdict.

`NOT_DETECTED` means that run's matrix did not establish detection. Permission
denied, unsupported, cancelled or failed checks are inconclusive. Interface
names, MTU, RTT and modem/IMS routes need context; a generic heuristic is not a
confirmed active tunnel. Do not infer that RKN deployed the same technique.

For VPNHide interface-index/tail or hook-timing investigations, re-read the
matching upstream implementation; do not turn release-specific constants, beta
status or verdict matrices into permanent general VPN policy. A timing anomaly alone is not proof
of a tunnel or carrier action.
