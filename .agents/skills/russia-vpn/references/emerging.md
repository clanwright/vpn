# Additional and emerging protocols

Checked 2026-09-07. “Worth testing” below is engineering judgment based on
implementation properties. No controlled August–September RU operator matrix
was found for these candidates. A released feature can still have immature
client support; software maturity and censorship efficacy are separate axes.
Use [diagnostics.md](diagnostics.md) for comparable tests and retain the known
working profile. Avoid generating a deployable config before checking the exact
implementation's schema and client support.

## AnyTLS — TLS/TCP session and padding alternative

**Why consider it:** session reuse and configurable early-write padding give a
maintained alternative TLS proxy design. That diversifies software behavior,
not destination IP/ASN dependencies. It is not itself a complete TLS identity
or an automatic allowlist solution.

**Configuration:** start with supported TLS/SNI and the implementation's default
padding/session strategy. In sing-box, the researched defaults were
`idle_session_check_interval: 30s`, `idle_session_timeout: 30s` and
`min_idle_session: 0`; do not set five idle connections from a copied preset.
[sing-box AnyTLS configuration](https://sing-box.sagernet.org/configuration/outbound/anytls/).

Server `paddingScheme` affects early writes; match protocol support before
customizing it. anytls-go v0.0.13 (2026-06-27) added `-dr` to disable reuse, but
upstream says reuse was not shown problematic. Disable it only as a controlled
stall comparison, not a permanent anti-RKN rule.
[Protocol](https://github.com/anytls/anytls-go/blob/main/docs/protocol.md),
[release](https://github.com/anytls/anytls-go/releases/tag/v0.0.13).

**Pitfalls:** older clients sent identifying name/version metadata. Verify the
installed behavior; sing-box 1.13.16/1.14-beta.5 and Mihomo 1.19.30 changed the
default. Do not add unsupported AnyTLS+REALITY: Mihomo explicitly excludes it.
TLS/ShadowTLS choices require their own compatible chain.
[Metadata note](https://sing-box.sagernet.org/manual/misc/anytls-client-metadata/),
[Mihomo support](https://wiki.metacubex.one/en/config/proxies/anytls/).

The upstream [2026-08-03 metadata clarification](https://github.com/anytls/anytls-go/commit/fd6167a)
says `client` is inside the encrypted connection, so a passive network observer
cannot read it. The proxy operator can read it and apply rejection policy, but
the self-declared value is not a reliable client identifier. Separately,
[issue #46](https://github.com/anytls/anytls-go/issues/46) found that an endpoint
padding update leaked through a process-global default; the issue is closed, but
the report does not identify a fixed release or establish the behavior of every
AnyTLS client. Check the exact implementation and release before relying on
per-endpoint padding isolation.

**Status:** useful trial where clients support it; no strong current RU
comparative measurement located. Session reuse can still meet a per-flow stall,
and extra connections can meet a burst trigger.

## TrustTunnel — HTTP-based full-device candidate

**Why consider it:** the implementation carries TCP/UDP/ICMP, supports TUN or
SOCKS use and provides split routing/DNS configuration. Its official HTTP/2
path offers another TCP-based option. “Indistinguishable” is a vendor assertion,
not a measured guarantee.
[Project](https://github.com/TrustTunnel/TrustTunnel).

**Configuration:** for a TCP trial choose client `upstream_protocol: http2`;
HTTP/3 is a separate UDP-dependent trial. Verify endpoint TLS identity, client
authentication, DNS and TUN routes; a SOCKS mode does not cover every device
application. Inspect HTTP connection limits and endpoint access controls.
[Client configuration](https://github.com/TrustTunnel/TrustTunnelClient/blob/master/trusttunnel/README.md),
[endpoint configuration](https://github.com/TrustTunnel/TrustTunnel/blob/master/CONFIGURATION.md).

**Pitfalls/status:** check the exact current OS/client release instead of assuming
CLI and GUI parity. The endpoint changelog includes a private-network restriction
bypass fix, making version/security review part of adoption. No current same-path
RU efficacy comparison was located. A user's report that an app detects it is
not evidence the carrier blocks its transport.
[Changelog](https://github.com/TrustTunnel/TrustTunnel/blob/master/CHANGELOG.md).

Recent endpoint reports reinforce the need for a bounded soak test. A July 18
[Android 1.1.1 / endpoint 1.0.33 report](https://github.com/TrustTunnel/TrustTunnel/issues/134)
observed an ECH handshake timeout, but was closed without a confirmed cause. An
August 3 [1 GiB server report](https://github.com/TrustTunnel/TrustTunnel/issues/140)
recorded memory growth and a separate HTTP/2 panic without proving one root
cause. An August 22 [drop/no-reconnect report](https://github.com/TrustTunnel/TrustTunnel/issues/144)
contains no ISP evidence. These are useful failure checks, not Russian blocking
measurements or proof that all endpoint versions share the failures.

## ShadowTLS v3 — a wrapper requiring an encrypted backend

**Why consider it:** reuses a real TLS handshake then transfers to an encrypted
proxy over the same TCP connection. It is a composable alternative, not new
payload encryption. It needs a separate compatible encrypted backend, such as
Shadowsocks, on both ends.
[Protocol v3](https://github.com/ihciah/shadow-tls/blob/master/docs/protocol-v3-en.md).

**Configuration:** use v3 consistently and keep strict mode with a tested TLS
1.3 handshake target. Non-strict TLS 1.2 support changes hijack resistance;
do not disable strictness to hide a target mismatch. Bind the backend privately;
public direct access defeats the wrapper. Verify normal fallback and encrypted
backend authentication separately.
[How to run](https://github.com/ihciah/shadow-tls/wiki/How-to-Run),
[project](https://github.com/ihciah/shadow-tls/blob/master/README.md).

**Status:** established implementation pattern worth a compatible test profile;
no current controlled RU comparison found. A famous decoy cannot hide the VPS
address, service-side exit identity or sustained-flow shape.

## mieru — non-TLS transport diversity

**Why consider it:** dedicated encrypted TCP/UDP proxy with padding and multiplexing,
without the domain/TLS front-site requirement. Upstream generally recommends
TCP. This avoids reliance on a TLS camouflage target but gives DPI a distinct
wire protocol; it is not HTTPS impersonation.
[Project](https://github.com/enfein/mieru/blob/main/README.md),
[protocol](https://github.com/enfein/mieru/blob/main/docs/protocol.md).

**Configuration:** use compatible `mieru` client/`mita` server profiles; prefer a
TCP trial first, match authentication and transport/port settings, and validate
new padding fields against the installed version. Client ecosystem support
varies; verify OS/plugin availability before choosing it for mixed devices.
Do not equate a running SOCKS service with full-device/UDP coverage.

**Status:** an active diversity candidate; RU efficacy remains anecdotal. In the
[maintainer discussion](https://github.com/enfein/mieru/discussions/263), June–July
2026 users reported success and an allowlist limitation, without operator,
region, throughput or packet controls. That warrants a trial, not a winner label.

The July 29 [v3.35.0 release](https://github.com/enfein/mieru/releases/tag/v3.35.0)
added low-entropy modes. Upstream's controlled
[traffic-pattern analysis](https://github.com/enfein/mieru/blob/main/docs/traffic-pattern.md)
puts full-chunk body expansion at about 1.15x–2x, depending on mode, and states
that metadata, nonces, authentication tags and some control traffic remain high
entropy. Treat this as a measurable shaping tradeoff, not a promise of evasion.
The older [China report #54](https://github.com/enfein/mieru/issues/54) does not
establish current behavior in Russia.

## Sudoku — implementation-specific entropy shaping

**Why consider it:** current Mihomo documents a standalone encrypted proxy with
selectable AEAD, padding ratios, byte-layout tables, multiplexing and HTTP mask
options. Those are the current fields to validate against the installed build:
`key`, `aead-method`, `padding-min`, `padding-max`, `table-type`, optional custom
tables, `multiplex`, `httpmask.*` and `enable-pure-downlink`.
Keep `aead-method` as `chacha20-poly1305` or `aes-128-gcm`; `none` disables
AEAD protection and must not be used for traffic that requires confidentiality
and integrity.
[Current Mihomo schema](https://wiki.metacubex.one/en/config/proxies/sudoku/).

**Pitfalls/status:** the older Sudoku_ASCII project and newer Mihomo/Xray modes
are different implementations. Do not generalize old no-Android or sub-30%
throughput claims to current clients. A May 7
[Xray finalmask report](https://github.com/XTLS/Xray-core/issues/6088) showed an
`unknown config id` startup failure after moving from 25.10.15 to 26.3.27; it is
a version/configuration compatibility report, not transport or RU efficacy
evidence. Keep Sudoku a version-pinned trial beside a known-working profile.

## Samizdat — watchlist only

The [Samizdat repository](https://github.com/getlantern/samizdat) describes a
TCP/TLS/HTTP2 design with active-probe fallback, multiplexing, padding, jitter
and fragmentation. As of this check it has no published releases and its broad
Russian-resilience claims are project-authored; no primary Russian operator
measurements were validated. Track it for releases and independent same-path
tests rather than promoting it to a deployment candidate.

## AmneziaWG 3 — header protection, with import risks

**Why consider it:** extends AWG header concealment. It still needs its underlying
path; it is not evidence that blanket UDP denial or allowlists are bypassed.

**Configuration:** `HeaderProtectionKey` must match both peers; its documented
nonce requirement makes all `S1`–`S4` at least 12. New content-padding and timing
ranges introduce more version-specific parameters. Export/import round trips
must preserve them, and the server engine/module must implement them.
[AWG configuration](https://github.com/amnezia-vpn/amneziawg-go#configuration).
Use the ordinary compatibility checklist in [udp.md](udp.md) as well.

**Status:** AWG3 support is a released client feature, but exact builds/importers
still matter. [Client release 5.0.0.5](https://github.com/amnezia-vpn/amnezia-client/releases/tag/5.0.0.5)
mentions support; an [August import report](https://github.com/amnezia-vpn/amnezia-client/issues/2942)
describes dropped fields. These are implementation reports, not proof of failure
on every client. Controlled August issues report
[handshake without traffic](https://github.com/amnezia-vpn/amnezia-client/issues/3043)
and [an imported MTU mismatch](https://github.com/amnezia-vpn/amnezia-client/issues/3064).
Check these failure classes before blaming DPI or switching protocols.

## Hysteria Mimic — Linux/root outer-packet experiment

**Why consider it:** Hysteria can manage a separate `mimic` executable that uses
eBPF/XDP to replace the outer UDP presentation with fake TCP headers, while
retaining QUIC internally. Do not conflate this with ordinary Hysteria2 UDP,
Salamander, or a real TCP transport with ordinary TCP semantics.

**Configuration:** both ends need Linux, root, the executable and compatible
`mimic` settings. Check `interface`, `xdpMode` (`native` or `skb`) and executable
`path`; treat raw `extraArgs` as implementation-specific. It disables UDP
segmentation offload, can reduce throughput, cannot coexist with port hopping,
and does not serve ordinary Hysteria clients in that mode.
[Official Mimic guide](https://v2.hysteria.network/docs/advanced/Mimic/).

**Status:** released integration with a narrow deployment envelope; no credible
RU field result located. A Linux lab or separately authorized router setup is
plausible; native phone clients do not inherit support. Fake TCP is not a
whitelist admission mechanism. Test the actual outer path, not just UDP/443.

## Slipstream — emergency DNS-carried TCP service

**Why consider it:** a real experimental implementation carrying data through DNS
resolvers, potentially useful where the resolver path remains. It is a local
TCP forwarder to a configured service, not a turnkey full IP VPN.

**Configuration:** requires an owned domain with correct NS/A delegation to the
server, a forwarded TCP service, and selected recursive resolvers. Test each
resolver's behavior, throughput and limits; direct server port 53 removes the
recursive-relay advantage. Bootstrap/delegation are real infrastructure changes.
[Usage](https://endpositive.github.io/slipstream/usage.html).

**Limits/status:** v0.1.1 was released 2026-04-12. Modified QUIC data encoded in
DNS queries/TXT replies incurs polling, size/rate and latency constraints, and
high-volume subdomains can be classified or blocked. No primary Russian
operator validation was found. Keep it an emergency experiment with measured
service usefulness, not a substitute for a healthy primary path.
[Release](https://github.com/EndPositive/slipstream/releases/tag/v0.1.1),
[protocol](https://endpositive.github.io/slipstream/protocol.html).
