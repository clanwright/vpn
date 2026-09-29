# Client policy and app detection

Access, confidentiality and a service accepting the exit address are different
objectives; decide the traffic policy before changing DNS or routes. Android
details do not describe iOS, macOS or Windows. Checked 2026-09-29; re-check the
installed build. Hosting and credentials: [hosting.md](hosting.md).

## Routing and DNS decisions

| Requirement | Policy | Acceptance and tradeoff |
| --- | --- | --- |
| All intended traffic in the tunnel | Full tunnel, explicit DNS, both IP families; fail-closed if requested | Test disconnect/startup/reconnect and IPv6. "Connected" does not prove coverage. |
| Selected RU apps need the ordinary RU path | Narrow per-app/domain exclusions, if the user accepts | Direct traffic reveals the real path. Test those apps, dependencies, DNS, calls; never exclude all RU traffic by default. |
| Only a browser/app needs proxying | Application proxy | Other apps, DNS, UDP may bypass it; a SOCKS listener is not a full-device VPN. |
| Client cannot carry IPv6 | Block that path, or choose another client | No accidental direct IPv6 route; global IPv6 disable is not a universal first fix. |

DNS follows the same policy as traffic: endpoint bootstrap, split domains, application
DoH/private DNS, reconnect. DoH/DoT cannot fix an unreachable resolver. Avoid a bootstrap
loop where reaching the VPN needs DNS available only through it.

- In allowlist mode compare provider DNS with public resolvers over TCP/53 or
  DoT: UDP/53 to public resolvers may be intercepted (DNAT toward NSDI). Major
  public DoH endpoints were reported blocked while Yandex worked.
- With local DNS interception/fake-IP, test A/AAAA, direct domains, LAN names and
  required apps before changing mode. Loopback DNS alone is not a flaw; do not
  weaken DNS privacy to quiet an app heuristic.
- If a client GUI has a DNS/IPv6 toggle (Clash Verge Rev `dns.ipv6`), set it
  there: GUI settings outrank Merge/Script/profile overrides. Then read the
  generated runtime config and OS resolver. IPv6 failure in TUN shows as
  `no route to host` on direct IPv6.
- Android: without configured DNS the underlying-network DNS is used; an address
  family without a VPN route falls through; `allowBypass()` permits binding
  outside the VPN ([VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder)).
  Test both IP families, DNS, excluded apps, STUN/voice; an unexpected public
  address on a protected path is a leak, an intentionally direct call is not.
- Apple: coverage follows effective Network Extension routes, not a `utun` or a
  connected badge. [`includeAllNetworks`](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks)
  enforces stronger inclusion with OS-specific exceptions; verify on the target OS.
- Windows: verify the route table after connect and reconnect (metric, prefix
  specificity); VPN-profile filters and name-resolution policy differ from app
  exclusions ([profile options](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/vpn/vpn-profile-options)).

### Rule-set sources and design direction

Choose one direction: "proxy what is blocked" (blocked-lists) misses unlisted hosts and fails
in allowlist mode; "direct RU, proxy the rest" uses RU domain/IP sets. Pin source, format and
cadence; after each update test one direct RU and one proxied domain.

- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat): Xray `.dat`, rebuilt ~6 h; `ru-blocked`, `ru-blocked-all` (700k+ domains, use with care), `refilter`, antifilter, geoip `ru-whitelist` (mobile whitelist; allowlist mode).
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) `category-ru` for "direct RU"; [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) mihomo `.mrs` (`category-bank-ru`, `category-ecommerce-ru`, `category-ai-ru`, `ru`).
- [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains): "Russia inside/outside"; dnsmasq, sing-box (>=1.11), Xray dat, mihomo MRS. [Re-filter-lists](https://github.com/1andrevich/Re-filter-lists), antifilter.download: blocked-lists only.

sing-box ([deprecations](https://sing-box.sagernet.org/deprecated/)): use `.srs` rule-sets
(`geoip`/`geosite` gone in 1.12.0), no legacy DNS server formats (gone in 1.14.0), and the
`evaluate` action instead of legacy DNS-rule address filters (`ip_cidr`, `ip_is_private`
without `match_response`; gone in 1.16.0). Check the installed version.

## Client failure checks

Build/OS-scoped leads; read generated runtime state before any workaround.

- **Clash Verge Rev, macOS, DNS dead after sleep/wake ([#7593](https://github.com/clash-verge-rev/clash-verge-rev/issues/7593)):**
  read the OS resolver after wake; test a direct RU and a proxied domain. Clash Party 2.0.3+ lists a wake fix.
- **Clash Verge Rev, macOS TUN fails while proxy mode works ([#7633](https://github.com/clash-verge-rev/clash-verge-rev/issues/7633)):**
  with a LAN system DNS, macOS does not forward DNS to the core and TUN start rewrites it; read
  the resolver after TUN start before blaming another VPN.
- **AmneziaVPN, wrong routes or connected without traffic
  ([#3083](https://github.com/amnezia-vpn/amnezia-client/issues/3083),
  [#3080](https://github.com/amnezia-vpn/amnezia-client/issues/3080)):** use
  5.0.1.5+ ([#2937](https://github.com/amnezia-vpn/amnezia-client/issues/2937));
  compare imported input, saved profile, effective routes and interface address
  (a different address alone does not prove the config was ignored). On Windows
  keep CIDR exclusion lists small ([#3020](https://github.com/amnezia-vpn/amnezia-client/issues/3020))
  and validate excluded apps vs `/32` routes across reconnect
  ([#2932](https://github.com/amnezia-vpn/amnezia-client/issues/2932)).
- **AmneziaVPN Android per-app split ([#2457](https://github.com/amnezia-vpn/amnezia-client/issues/2457)):**
  an excluded app can bind to `tun0` (`curl --interface tun0`) and see the exit IP; SOCKS auth
  does not prevent it. Per-app exclusion does not hide the tunnel.

## Client security

- Clash Verge Rev on Windows: run 2.5.5+ ([GHSA-99qg-xv7m-jf4v](https://github.com/clash-verge-rev/clash-verge-rev/security/advisories/GHSA-99qg-xv7m-jf4v), service IPC privilege escalation, <= 2.5.4). Clash Party: run [2.0.3+](https://github.com/mihomo-party-org/clash-party/releases/tag/v2.0.3) (malicious `rule-providers` could execute commands).
- Treat imported subscriptions, rule-providers and scripts as untrusted: import
  only from a source you control and review them.

## Local proxy listeners

Any local app can probe a loopback SOCKS/HTTP inbound or Xray/Clash/sing-box API, learn the
exit IP and confirm a VPN (runetfreedom disclosure, 2026-04-07, secondary read). Check the
build's inbound authentication; disable unneeded listeners; keep a REST controller off or
authenticated. Authentication does not hide `TRANSPORT_VPN` or stop the `tun0` bind vector.

- Random credentials: Amnezia 4.8.15.4+/5.0.0.5+. Auth settings (default
  unverified, enable and check): Happ desktop 2.9.0+ and Android 3.18.0+, Karing
  1.2.16.1912+, Throne desktop 1.1.2+, FlClash 0.8.97+.
- No shipped fix: Hiddify ([hiddify-core #147](https://github.com/hiddify/hiddify-core/pull/147)),
  NekoBox; v2rayNG has a local-proxy off switch only in the 2.3.x prerelease line.
- Not assessed: sing-box apps, v2RayTun, Streisand, V2BOX, Shadowrocket;
  sing-box has a `package_name_regex` route rule for owner-based blocking.

## MTU and reliability

Start from the implementation default; derive MTU from path behavior only when symptoms
justify it. Small packets passing while large ones stall suggests PMTUD trouble, not DPI; test
both directions (offload distorts host captures). Never force 1500 for stealth or 1280
everywhere: a reliable smaller MTU beats a normal-looking one that black-holes traffic. QUIC
outer-packet needs: [protocols.md](protocols.md); path-failure tests:
[diagnostics.md](diagnostics.md). Check handover, sleep/wake, idle NAT expiry, routing loops.
Keepalive holds a NAT mapping and does not defeat IP blocking. Avoid retry storms.

## App-side VPN detection

Observers differ: the carrier sees destination IP/ASN, DNS, SNI/ALPN and flow shape; an
on-device app sees VPN APIs, proxy settings, interfaces, routes, listeners and installed VPN
apps; a remote service sees exit-IP reputation and session behavior. Changing the server
protocol changes no on-device signal; hiding local TUN state does not hide a foreign exit.

Russian apps were told to detect VPN use from 2026-04-15 (ministry order 2026-03-30, media;
sanction: loss of IT accreditation or the mobile whitelist). A ministry methodology
(authenticity confirmed by media) circulates as a [community-hosted copy](https://ntc.party/t/23842);
it models what apps may check, not what each app implements.

- **Staged design:** (1) server-side GeoIP/reputation; (2) device indicators: Android
  `NetworkCapabilities` (`TRANSPORT_VPN`, `IS_VPN`), iOS proxy settings, path monitor, interface
  names; (3) Windows/macOS/Linux connection enumeration, registry, virtual adapters.
- **Interface names:** `tun0`, `tun1`, `tap0`, `wg0`, `ppp0`, `ipsec`, `utun`. **Proxy ports:**
  SOCKS 1080, 9000, 5555, 16000-16100; HTTP 80, 443, 3128, 3127, 8000, 8080, 8081, 8888;
  transparent 4080, 7000/7044, 8082, 12345; Tor 9050, 9051, 9150. Use random non-listed ports
  plus authentication, or no listener.
- **Limits:** iOS access is restricted; router VPN, split tunneling and fast-rotating services
  are hard to catch; corporate VPN, antivirus, Docker/WSL2/Hyper-V and NAT cause false positives.

Measured behavior:

- RKS Global static analysis (30 popular RU Android apps, April 2026, not re-run): 30/30
  detected VPN, 7 (Wildberries, Ozon, 2GIS, RuStore, others) collected the installed
  VPN-client list. Assume apps can enumerate VPN clients.
- Which apps refuse or degrade service is unstable (April reports: Gosuslugi, Sber, T-Bank,
  VTB, Wildberries, Ozon, Yandex, VK, Max); test the specific app on the specific path.
- Signals that survive partial tunneling: `TRANSPORT_VPN` is visible even to excluded apps;
  VpnService `LinkProperties` DNS is visible to any app; whether local ports and interfaces
  are visible from a work profile or private space is conflicting evidence. Claim no
  Android 17 loopback or cross-profile restriction. `ACCESS_LOCAL_NETWORK` covers LAN ranges
  for apps targeting API 37.
- RU-direct routing removes only the server-side foreign-IP signal for those requests; it
  hides no `TRANSPORT_VPN`, interface or listener and reveals the real path.

| Countermeasure | Helps against | Does not help against |
| --- | --- | --- |
| Per-app split tunneling | Server-side IP checks for excluded apps | `TRANSPORT_VPN`, interfaces, local proxy, `tun0` bind |
| Router / travel router / second device | On-phone VpnService, `tun*`, localhost listeners; the only non-root way to remove them | Exit-IP reputation; the phone's mobile path away from that router; the installed VPN app |
| Work profile / Shelter / Island / private space | App-list enumeration, partly | Shared loopback and `tun0` (conflicting evidence); partly effective at best |
| [VPNHide](https://github.com/okhsunrog/vpnhide) 1.3.0 (root: kernel module, LSPosed, Zygisk) | Interface enumeration, bind-to-VPN-interface, `ip rule` | Root/integrity checks, timing detection (RKNHardering 2.11.0), GeoIP; adds its own surface. Configure the app you hide from, not the VPN app; one native backend |
| Disable/authenticate listeners; UID-scoped loopback block (root); entry/exit split | Localhost scans; exit-IP disclosure via a local proxy | Interface and capability signals; VPN presence |

No client-side measure defeats server-side signals, hardware attestation or new vendor rules.
Prefer supported routing and narrow per-app policy over root/hook concealment, and never
weaken tunnel security for a clean checker badge. VPNHide and router tunneling are untested
against the actual apps. What works now: [evidence.md](evidence.md).

## Interpreting RKNHardering and similar checkers

[RKNHardering](https://github.com/xtclovver/RKNHardering) ([v2.11.0](https://github.com/xtclovver/RKNHardering/releases/tag/v2.11.0))
is a local Android/path heuristic, not an RKN/TSPU specification; do not infer that RKN or any
app uses the same technique. Reproduce a verdict from the pinned build's rules and raw evidence;
carrier IMS/modem routes cause false positives. `NOT_DETECTED` means that run did not establish
detection; denied, unsupported, cancelled or failed checks are inconclusive. A timing anomaly
alone proves neither a tunnel nor carrier action.

## Store availability and fake apps

- Apple removed 20+ VPN/proxy clients (Streisand, V2Box, v2RayTun, Happ) from the Russian App
  Store at RKN demand (about 2026-03-27, media); check the store from the user's account region.
- A "free VPN" or lookalike from an unofficial source is a malware risk: the Ministry of
  Internal Affairs warned on [2026-05-26](https://ria.ru/20260526/mvd-2094734464.html) of apps
  carrying a banking trojan that intercepts SMS and push notifications. Install only from the
  developer's site, repository or store listing, verify the domain before paying, and review
  permissions (SMS, notifications, accessibility).
