# Additional and emerging protocols

Checked 2026-09-29. No controlled operator matrix exists for any candidate here;
Russian-efficacy evidence is anecdotal (single-author NTC posts, no captures), and
software maturity differs from censorship efficacy. Use [diagnostics.md](diagnostics.md)
for comparable tests, keep the known working profile, and check the implementation's
schema and client support before generating a config. AmneziaWG 3/3.1 lives in
[udp.md](udp.md); read it before blaming DPI for an AWG failure.

Connection count and TLS-library fingerprint can matter as much as the protocol.
One secondary-sourced report (a blog post and a Tor team meeting note) describes a
TSPU trigger on the rustls ClientHello and on more than 3 parallel TLS connections
to one SNI within ~60 s (first seen June 2026). Treat it as a hypothesis when a
many-connection design stalls.

## AnyTLS: TLS/TCP session and padding alternative

**Consider it** for a maintained TLS proxy with session reuse and padding. It diversifies
software, not destination IP/ASN dependencies, and is not an allowlist solution.

**Configuration:** start with supported TLS/SNI and default padding/session values
; do not copy a preset with five idle connections. Use
sing-box 1.14.2+ or Mihomo 1.19.31+: older clients sent identifying name/version
metadata, so check the installed core's default. Mihomo excludes AnyTLS+REALITY.
anytls-go `-dr` disables reuse; use it only as a controlled stall comparison.
[sing-box AnyTLS](https://sing-box.sagernet.org/configuration/outbound/anytls/),
[metadata note](https://sing-box.sagernet.org/manual/misc/anytls-client-metadata/),
[Mihomo](https://wiki.metacubex.one/en/config/proxies/anytls/),
[protocol](https://github.com/anytls/anytls-go/blob/main/docs/protocol.md).

**Status:** trial where clients support it; no RU comparative measurement. Reuse can
still stall per flow.

## TrustTunnel: HTTP-based full-device candidate

**Consider it** for TCP/UDP/ICMP carriage with TUN or SOCKS and split routing/DNS
("indistinguishable" is a vendor claim). [Project](https://github.com/TrustTunnel/TrustTunnel).

**Configuration:** for a TCP trial set client `upstream_protocol: http2`; HTTP/3 is a
separate UDP-dependent trial. Verify endpoint TLS identity, client authentication,
DNS and TUN routes (SOCKS mode does not cover every application), connection limits
and endpoint access controls.
[Client](https://github.com/TrustTunnel/TrustTunnelClient/blob/master/trusttunnel/README.md),
[endpoint](https://github.com/TrustTunnel/TrustTunnel/blob/master/CONFIGURATION.md).

- Use endpoint 1.1.0+. With `allow_private_network_connections=false`, a loopback or
  private reverse-proxy origin works from 1.1.0; earlier endpoints wrongly blocked
  it. Client traffic to private networks stays forbidden.
- `per_client_metrics` (off by default) exposes usernames and client IPs: protect it.
- Use client 1.1.7+ (1.1.5 changed the config:
  `VpnUpstreamSessionRecoverySettings::attempts`, no infinite retry). Read the
  [changelog](https://github.com/TrustTunnel/TrustTunnel/blob/master/CHANGELOG.md)
  first; do not assume CLI/GUI parity.
- Soak-test for [#140](https://github.com/TrustTunnel/TrustTunnel/issues/140) memory
  growth (cause unconfirmed), [#144](https://github.com/TrustTunnel/TrustTunnel/issues/144)
  drop without reconnect (open), and
  [#153](https://github.com/TrustTunnel/TrustTunnel/issues/153) UDP-over-H2 at
  3–12 Mbit/s against ~133 Mbit/s for TCP on OpenWrt armv7: measure UDP
  applications separately.

**RU evidence (NTC anecdotes, no captures):** on Megafon mobile the QUIC variant failed
while HTTP/2 worked (2026-06-01), and TrustTunnel-over-HTTPS, NaiveProxy and some
XHTTP modes held only ~2 Mbit/s (2026-07-19, region unstated) while the same configs
were fine on Beeline mobile. Try HTTP/2 first there, but test. An app detecting the
client does not show a carrier blocks the transport.

## ShadowTLS v3: wrapper requiring an encrypted backend

**Consider it** to reuse a real TLS handshake, then carry an encrypted proxy
(Shadowsocks, Snell) on the same TCP connection. It adds no payload encryption and
needs a compatible backend on both ends.
[Protocol v3](https://github.com/ihciah/shadow-tls/blob/master/docs/protocol-v3-en.md).

**Configuration:** use v3 consistently with strict mode and a tested TLS 1.3
handshake target; do not disable strictness to hide a target mismatch. Bind the
backend to localhost, since public direct access defeats the wrapper. Verify
fallback and backend authentication separately.
[How to run](https://github.com/ihciah/shadow-tls/wiki/How-to-Run).

**Status:** upstream is dormant (last release v0.2.25, 2023-12-13); prefer clients that
bundle it. One NTC anecdote (2026-09-05, Megafon): bare Snell detected, ShadowTLS+Snell
working. A well-known decoy cannot hide the VPS address, exit identity or flow shape.

## Snell: watchlist

Native in sing-box 1.14.0+ and Mihomo; evidence is the one Megafon anecdote above.
Its thread reports 10–15 parallel TCP flows per browsing burst: test it
ShadowTLS-wrapped and watch connection counts.

## mieru: non-TLS transport diversity

**Consider it** for a dedicated encrypted TCP/UDP proxy with padding and
multiplexing, no domain or TLS front-site requirement; upstream generally recommends
TCP. It gives DPI a distinct wire protocol and is not HTTPS impersonation.
[Project](https://github.com/enfein/mieru/blob/main/README.md),
[protocol](https://github.com/enfein/mieru/blob/main/docs/protocol.md).

**Configuration:** match `mieru` client and `mita` server profiles; try TCP first;
validate padding fields against the installed version. SOCKS is not full-device/UDP coverage.

**Security check:** through v3.38.0 the SOCKS5 server selects no-authentication
whenever the client offers it, even with credentials configured
([PR #316](https://github.com/enfein/mieru/pull/316), merged 2026-09-28, not in a
tagged release). Bind any credentialed SOCKS5 listener to loopback or firewall it,
and update once a tagged release includes the fix.

**Status:** RU efficacy anecdotal (a [maintainer discussion](https://github.com/enfein/mieru/discussions/263)
without operator, region or throughput; one NTC post ranks it second to Snell).
Upstream's [traffic-pattern analysis](https://github.com/enfein/mieru/blob/main/docs/traffic-pattern.md)
puts body expansion at ~1.15x–2x: a shaping tradeoff, not an evasion promise.

## Sudoku: implementation-specific entropy shaping

**Consider it** as a Mihomo standalone encrypted proxy with selectable AEAD, padding
ratios, byte-layout tables, multiplexing and HTTP mask options. Sudoku_ASCII, Mihomo
and Xray modes are different implementations: validate the fields (`aead-method`,
`padding-*`, `table-type`, `multiplex`, `httpmask.*`) against the installed build.
Keep `aead-method` as `chacha20-poly1305` or `aes-128-gcm`; `none` removes
confidentiality and integrity. Upgrade both ends together. On Xray
`unknown config id`, check config syntax first.
[Mihomo schema](https://wiki.metacubex.one/en/config/proxies/sudoku/).
No RU efficacy evidence: a version-pinned trial beside a working profile.

## Samizdat: watchlist only

[Samizdat](https://github.com/getlantern/samizdat) (TCP/TLS/HTTP2 with probe fallback,
padding, ClientHello fragmentation) has only v0.0.x releases and project-authored
Russian-resilience claims. Track it; do not deploy.

## Hysteria Mimic: Linux/root outer-packet experiment

**Consider it** to replace the outer UDP presentation with fake TCP headers via
eBPF/XDP (a separate `mimic` executable managed by Hysteria) while keeping QUIC
inside. It is not ordinary Hysteria2, Salamander, or a real TCP transport.

**Configuration:** both ends need Linux, root, the executable and compatible `mimic`
settings; use Hysteria 2.12.2+. Check `interface`, `xdpMode` (`native` or `skb`) and
`path`; treat raw `extraArgs` as implementation-specific. It disables UDP
segmentation offload, can reduce throughput, cannot coexist with port hopping, and
ordinary Hysteria clients cannot use that listener.
[Mimic guide](https://v2.hysteria.network/docs/advanced/Mimic/).

**Status:** no RU field result; phone clients lack support, and fake TCP is not a
whitelist admission mechanism. Test the actual outer path, not just UDP/443. Other
Hysteria2 topics: [udp.md](udp.md).

## Slipstream: emergency DNS-carried TCP service

**Consider it** only where a resolver path remains: a local TCP forwarder to a
configured service, not a full IP VPN. Rust port:
[slipstream-rust](https://github.com/Mygod/slipstream-rust); DNS-tunnel ecosystem and
UDP/53 interception: [alternatives.md](alternatives.md).

**Configuration:** needs an owned domain with correct NS/A delegation, a forwarded
TCP service and selected recursive resolvers. Test each resolver's behavior,
throughput and limits; direct server port 53 removes the recursive-relay advantage.
DNS carriage means polling, size/rate and latency limits, and high-volume
subdomains can be classified.
[Usage](https://endpositive.github.io/slipstream/usage.html),
[protocol](https://endpositive.github.io/slipstream/protocol.html).

**RU evidence (NTC, April–May 2026, per vantage, no controls):** Tele2 St Petersburg
worked via the operator resolver (11.1 Mbit/s down); MTS Moscow was poor (100–200
kbit/s, sessions tearing after ~10 min); Tele2 Siberia mobile passed ~2 KB then nothing.
All predate the UDP/53 interception, so none validates a public-resolver path; use
operator, NSDI or Yandex resolvers, or TCP/DoH.
