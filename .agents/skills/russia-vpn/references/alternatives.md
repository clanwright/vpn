# DPI tools and emergency alternatives

Checked 2026-09-29. These solve different problems from a full-device VPN. No
controlled Russian multi-operator trial covers them; evidence is upstream artifacts
and community reports (mostly NTC, single authors). Use it to design a trial, not to
claim a working path.

## zapret2, ByeDPI and GoodbyeDPI

Check TCP connection and destination reachability with the tool disabled: if the
IP/port path already fails, desync presets cannot restore a denied destination. Once
the path works, isolate the handshake/request that fails before searching strategies,
and inspect capture/filter scope, hostlists, bootstrap DNS and firewall/VPN
interaction. A strategy for one domain/transport need not fit another; retain a
known-working build. Do not stack packet interceptors or disable firewall/AV
protections as a permanent workaround. These tools give no foreign exit or
full-device confidentiality.

- **zapret2:** programmable packet manipulation, not an exit-IP provider. The
  [official project](https://github.com/bol-van/zapret2) governs syntax; verify
  OS/build (macOS excluded; [zapret1 is EOL](https://github.com/bol-van/zapret)).
  Current [v1.0.5.2](https://github.com/bol-van/zapret2/releases/tag/v1.0.5.2)
  (2026-09-15). No preset is a global RU default.
- **Fake-based presets:** NTC zapret2 reports (~2026-09-10 to 09-12, several regions, no
  captures) say many "fake with TTL fooling" strategies stopped working, `tcp_ts`
  fooling still worked for one Volga user, and a fake SNI must match the real SNI's
  length. Treat any fake-based preset older than 2026-09-10 as stale and rerun
  blockcheck2 on the user's path.
- **Bundles and lookalike repos:** use only sources named by zapret2 upstream; do not
  recommend "РАБОЧИЙ ZAPRET"-style repos with dated titles (unreviewed, probably
  star-farmed). The [Flowseal bundle](https://github.com/Flowseal/zapret-discord-youtube) is a third-party,
  unreviewed bundle of EOL zapret1 binaries: prefer upstream zapret2.
- **ByeDPI:** upstream quiet since 2025-09 (v0.17.3); the Android front-end
  [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) is active. An
  [MGTS report](https://github.com/hufrea/byedpi/issues/401) favors domain-specific
  strategies over one global strategy: test each intended domain. One NTC anecdote
  (2026-09): Psiphon behind ByeDPI as upstream SOCKS reached ~1 Mbit/s.
- **GoodbyeDPI:** [Windows/WinDivert tool](https://github.com/ValdikSS/GoodbyeDPI), no release
  since 2024-09. Its `-q` blocks QUIC, pushing applications to TCP; that does not
  show UDP became reachable.

## Tor transports

[Official bridge guidance](https://support.torproject.org/little-t-tor/circumvention/using-bridges/)
covers obfs4, meek, Snowflake and WebTunnel. Bridge lines and Snowflake discovery are
different dependencies; test bootstrap and the required application, not whether a
bridge address opens. Tor Browser is not full-device VPN coverage.

- **Bridge-user counts** (Tor metrics, country=ru; estimates, not success rates):
  obfs4 ~40–50k, Snowflake ~14–20k, WebTunnel ~20–24k, flat June–September 2026; not
  a ranking.
- **Snowflake:** [net4people #603](https://github.com/net4people/bbs/issues/603)
  (2026-09-24 update, one author) reports near-100% client success with default lines
  but only ~50–60% for Russian clients reaching his Russia-hosted proxy, typically
  stalling after the second ClientHello: uneven per vantage and client location.

## DNS-carried paths

DNS tunnels are emergency channels: far slower than a VPN, and they do not repair an
unavailable first hop. **UDP/53 queries to public resolvers (8.8.8.8, 8.8.4.4
and similar) are DNAT-ed toward the NSDI resolver by the TSPU**
([net4people #657](https://github.com/net4people/bbs/issues/657), opened 2026-08-26,
which is not a known start date; NTC, Dom.ru St Petersburg wired, 2026-09-19; several
ISPs; TTL probes show DNAT at the TSPU for DNS-shaped packets only). TCP/53 worked.
DoH depends on the endpoint: major public DoH endpoints were reported blocked; Yandex
worked.

- Point tests at the operator resolver, NSDI or Yandex resolvers, or a TCP path; a
  public-resolver UDP test is invalid. April–May DNS-tunnel results (see
  [emerging.md](emerging.md)) predate the interception and are not comparable. Record
  resolver, transport, operator and date per result.
- **Slipstream family:** see [emerging.md](emerging.md). Other Russian-community
  names: SlipNet (Android client), VayDNS, NoizDNS, MasterDnsVPN; check release and
  issue history before use.
- [iodine](https://github.com/yarrick/iodine): needs delegated DNS; IPv4 and unencrypted, so add an authenticated
  encrypted layer. [dnstt](https://www.bamsoftware.com/software/dnstt/protocol.html): encrypted
  channel over DNS; DoH adds a reachable-service dependency, not immunity.
- Resolver reachability does not show it carries the needed query sizes or rate. ICMP
  tunneling has no validated design here.

## WebRTC, SFU and TURN relays

Tunnels through call platforms are fragile: they depend on the carrier's allowlist
scope, the platform owner's tolerance and a platform account that can be banned. Use
them as an emergency allowlist-scope option, not a fallback. No controlled test or
ban rate exists; READMEs are author claims.

- **whitelist-bypass** ([v0.4.4](https://github.com/kulikov0/whitelist-bypass/releases)):
  headless Pion tunnel (DC or VP8 video) via VK Call, Telemost, WB Stream, DION,
  Bitrix. Author-listed gaps ([net4people #618](https://github.com/net4people/bbs/issues/618)):
  ML-classifier detectability unmeasured, AEAD key derived from the join link. A
  Telemost run from a Paris VPS reset mid-transfer (0 of 8 10 MB downloads); try a
  smaller `--vp8-batch`. olcRTC is effectively EoL: start no new deployment on it.
- **vk-turn-proxy family** (Turnable, lionheart, clients): DTLS/SRTP over VK/WB TURN
  carrying WireGuard, Hysteria or VLESS. Expect VK captcha requirements, VK-side
  shaping (NTC, 2026-08-16: DTLS relay ~60–80 kbit/s single peer, ~300–400 kbit/s
  with 5 peers; an SRTP mode faster) and filtered WireGuard replies.
- **Whitelisted-cloud fronting** (Yandex Cloud, Timeweb, Selectel or CDN with xhttp) is
  a parallel approach; NTC anecdotes (2026-09) expect abuse controls and report
  whitelisted Yandex Cloud IPs harder to obtain.

Allowlist scope differs by segment and IP family (an MTS-only report saw Yandex over
IPv6 but not IPv4 in St Petersburg, [net4people #650](https://github.com/net4people/bbs/issues/650)):
test the actual carrier and segment first; see [diagnostics.md](diagnostics.md).
