# Choose and configure a path

Checked 2026-09-29. These are conditional candidates, not a ranking from a nationwide RU trial. Read
[evidence.md](evidence.md) for current availability and test the user's network. Prefer a maintained
implementation supported by all intended clients over an untested new feature.

## Selection matrix

| Candidate | Useful when | Dependencies / what it does not fix |
| --- | --- | --- |
| VLESS + REALITY over RAW/TCP, optionally Vision | A direct TCP endpoint is reachable; a simple first candidate is wanted | Choose server core and client set together (Xray >=26.9.8 rejects ClientHellos without ML-KEM; several non-Xray clients fail, see [tcp.md](tcp.md)); target/SNI consistency; cannot rescue blocked IPs or absent first-hop access |
| VLESS + XHTTP with REALITY (direct) or TLS (HTTP intermediary) | HTTP transport behavior, separate upload/download or intermediary compatibility solves a measured need | More mode/pooling/proxy interactions; request splitting does not necessarily create new TCP flows |
| NaiveProxy over HTTPS/H2 | An independent TCP implementation on Chromium networking with a real web front is practical | Padded proxy server, maintained client, domain/certificate/site operation; exit IP and post-handshake traffic stay observable |
| AmneziaWG | UDP passes; low overhead or full IP tunneling matters | AWG generation, engine pair, import compatibility; review installer-generated shared constants ([udp.md](udp.md)); does not defeat blanket UDP/IP denial |
| Hysteria2 or TUIC | UDP/QUIC passes; performance or UDP apps matter | QUIC path MTU, client/server compatibility; a QUIC v1 Initial with a blocked SNI is exposed to SNI filtering ([evidence.md](evidence.md)); not a TCP fallback |
| Plain WireGuard, OpenVPN, IKEv2; basic Shadowsocks/Trojan/WS+TLS | Working setup, interoperability requirement, control or tested fallback | Encryption or TCP/443 alone is not browser impersonation; keep if measured useful; claim neither universally blocked nor universally resistant |

For a new setup, test a supported TCP candidate first when UDP availability is unknown; choose between
RAW/REALITY and Naive by client and hosting constraints. Add XHTTP for a concrete transport or
intermediary need, or a controlled comparison. When resilience justifies the cost, keep a different
implementation on a different endpoint/provider, plus an optional UDP path. Profiles sharing one
IP/ASN or one UDP dependency are correlated fallbacks.

Exit hosting is its own failure domain: whole foreign IPs and subnets can be unreachable from Russian
networks regardless of protocol (seen September 2026). Put the fallback on another hoster/ASN, and
read [hosting.md](hosting.md) for hosting, Russian ingress, subscription credentials and evaluating a
commercial or reseller service. Payment, website access and a long server list do not prove tunnel
availability; never recommend a paid plan from marketing alone.

## Version and configuration checkpoints

Inspect installed cores, not only GUI versions, and compare exported/imported settings on every
target OS. Docs can track a pre-release and describe fields an installed stable build lacks; do not
upgrade clients to match a document. Preserve a known-working profile. Server upgrades break clients
too: panels bundle cores (3x-ui 3.8.x ships Xray 26.9.9) and every Xray tag after v26.3.27 is flagged
pre-release. Pin the server core; upgrade only after the intended clients pass against it.

Read only the detail needed:

- [Baselines: WireGuard, OpenVPN, Trojan, Shadowsocks 2022](baselines.md)
- [TCP: REALITY/RAW, XHTTP, NaiveProxy](tcp.md)
- [UDP: AmneziaWG, Hysteria2, TUIC](udp.md)
- [Emerging: AnyTLS, TrustTunnel, ShadowTLS, Snell, mieru, Sudoku, Samizdat, Hysteria Mimic,
  Slipstream](emerging.md); separates software maturity from evidence of Russian reachability.
- [Alternatives](alternatives.md): zapret/ByeDPI/GoodbyeDPI, Tor transports, Conjure, WebRTC/TURN
  relays, DNS/ICMP emergency channels. They differ in traffic coverage, trust and reachability; one
  opening blocked page does not make them substitutes for an IP VPN.

For two-hop ingress, read [hosting.md](hosting.md) and [diagnostics.md](diagnostics.md): establish
first-hop admission and sustained transfer during the actual restriction before adding a second
server. A protocol or SNI name is not evidence of allowlist eligibility.
