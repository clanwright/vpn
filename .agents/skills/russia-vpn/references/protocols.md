# Choose and configure a path

Research baseline: 2026-09-07. These are conditional engineering candidates,
not a ranking established by a nationwide RU trial. For current availability,
read [evidence.md](evidence.md) and test the user's network. Prefer a maintained
implementation supported by all intended clients over an untested new feature.

## Selection matrix

| Candidate | Useful when | Main dependencies / what it does not fix |
| --- | --- | --- |
| VLESS + REALITY over RAW/TCP, optionally Vision where supported | A direct TCP endpoint is reachable; a relatively simple first candidate is wanted | Exact client/core support, target/SNI consistency; cannot rescue blocked IPs or absent first-hop access. |
| VLESS + XHTTP with REALITY for direct ingress, or TLS for a supported HTTP intermediary | HTTP transport behavior, separate upload/download, or intermediary compatibility solves a measured need | More mode/pooling/proxy interactions; HTTP request splitting does not necessarily create new TCP flows. |
| NaiveProxy over HTTPS/H2 | An independent TCP implementation using Chromium's networking and a real web front is practical | Matching padded proxy server, maintained client, domain/certificate/site operation; exit IP and post-handshake traffic remain observable. |
| AmneziaWG | UDP passes and low overhead/full IP tunneling matters | AWG generation and import compatibility; obfuscation does not defeat blanket UDP/IP denial. |
| Hysteria2 or TUIC | UDP/QUIC passes; performance or UDP application support matters | QUIC path MTU and client/server compatibility; neither is a TCP fallback. |
| Ordinary WireGuard, OpenVPN, IKEv2; basic Shadowsocks/Trojan/WS+TLS | Existing working setup, interoperability requirement, control or tested fallback | Encryption or TCP/443 alone is not browser impersonation. Retain if measured useful; do not claim either universally blocked or universally resistant. |

For a new censorship-resilient setup, test a supported TCP candidate first when
UDP availability is unknown; compare RAW/REALITY and Naive based on client and
hosting constraints. Add XHTTP for a concrete transport/intermediary need or a
controlled comparison. When resilience justifies the cost, retain a different
implementation on a different endpoint/provider, plus an optional UDP path.
Two profiles sharing one IP/ASN or one underlying UDP dependency are correlated
fallbacks. Avoid a forced multi-server portfolio for a small, already-working use.

A commercial service may reduce server maintenance; evaluate its actual client
mode/core, recovery/import path and trials on required operators, rather than
vendor rankings. Payment, website accessibility and a long server list do not
prove tunnel availability. Never recommend a paid plan solely from marketing.

## Version and configuration checkpoints

Inspect installed cores, not only GUI versions. Compare actual exported/imported
settings on every target OS. Current docs can track a pre-release and include
fields an installed stable build lacks. Do not upgrade every client to a
pre-release merely to match a document. Preserve a known-working profile.

Read only the implementation detail needed:

- [Baselines: WireGuard, OpenVPN, Trojan and Shadowsocks 2022](baselines.md).
- [TCP: REALITY/RAW, XHTTP and NaiveProxy](tcp.md).
- [UDP: AmneziaWG, Hysteria2 and TUIC](udp.md).
- [Additional and emerging: AnyTLS, TrustTunnel, ShadowTLS, mieru, AWG3,
  Mimic and Slipstream](emerging.md). This separates software maturity from
  evidence of Russian reachability.

## Alternatives with different limits

Read [alternatives.md](alternatives.md) when considering zapret/ByeDPI/GoodbyeDPI,
Tor transports, Conjure or DNS/relay/ICMP emergency channels. These have different
traffic coverage, trust and reachability dependencies; they are not substitutes
for an IP VPN merely because one blocked page opens.

For two-hop ingress, read [diagnostics.md](diagnostics.md): establish first-hop
admission and sustained transfer during the actual restriction before adding a
second server. A protocol or SNI name is not evidence of allowlist eligibility.
