# RKN VPN Best Practices

Use this file for implementation and review heuristics. Current selected
protocols and exposure live in the consumer configuration and canonical docs;
operator procedures belong in the owning repository's `docs/operations/`. Use
`russia-2026-censorship.md` for current network evidence and
`rkn-hardering-threat-model.md` for Android/app detection.

Network measurement/provider sources are centralized at the top of
`russia-2026-censorship.md`. This file does not keep a second copy of those
lists.

## Portfolio-independent posture

- Resolve the selected protocol portfolio from evaluated configuration,
  and the consumer's canonical docs; do not keep another current list here.
- Maintain independent paths across the failure modes that matter, and treat any
  selected UDP path as usable only after validation on the exact target network.
- Design for graceful degradation, not invisibility.
- Separate reachability, endpoint confirmation/probing, and client/app detection.
- Route Russian direct-sensitive apps direct when they must see a Russian residential/mobile path.
- Treat releases and camouflage features as hypotheses until measured on the target operator/path.

## Diagnose Before Changing Protocol

Classify the failure first:

| Observation                          | First interpretation               | Next check                     |
| ------------------------------------ | ---------------------------------- | ------------------------------ |
| no allowed anchors or data path      | radio/L3 blackout                  | another SIM, Wi-Fi, wired path |
| destination IP never connects        | IP/CIDR/port/path issue            | exact-IP controls, another ISP |
| TCP connects, TLS resets             | SNI/ALPN/fingerprint/fallback      | controlled TLS variants        |
| TLS/HTTP succeeds, transfer freezes  | l4-25 or path throttling           | pcap, sustained flow controls  |
| fourth same-SNI connect freezes      | June TLS-burst hypothesis          | paced 1/2/3 versus 4+ test     |
| UDP silent                           | UDP/QUIC unavailable               | keep TCP baseline              |
| provider DNS works, public DNS fails | resolver constraint                | provider-DNS-aware design      |
| works at home, fails on mobile       | operator/region/whitelist variance | exact SIM/MVNO/tower tests     |

Do not change SNI, certificate, protocol, and destination simultaneously; that destroys attribution.

## Endpoint And Ingress

- Prefer TCP/443 for browser-like paths and UDP/443 only where UDP passes.
- Present a valid certificate and plausible web behavior to unauthorized visitors.
- Verify probe behavior:
  - NaiveProxy `probe_resistance`/fallback;
  - REALITY fallback/dest behavior;
  - exact AmneziaWG wrong-key/unauthenticated response.
- Keep admin panels, stats, Xray/sing-box APIs, and dashboards off the public VPN surface; use loopback/tailnet or a separate management path.
- Use one credential/peer/profile per device. Never log or commit private keys, UUIDs, credentials, short IDs, or live profile URLs.
- Keep public health checks and clients from racing multiple TLS sessions to the same SNI.

Before choosing an endpoint, test the exact IP rather than provider reputation:

- current public blocklist hit/no-hit;
- prefix/ASN/organization and neighboring-address controls;
- reachability from required Russian operators;
- sustained plain HTTPS, not only ping/connect;
- SNI/dest and certificate plausibility from server and client vantage;
- provider ToS and operational ownership.

A clean public feed means only “no hit in that feed.” A popular cloud, domestic ASN, or shared/CDN address is not automatically reachable or whitelist-eligible.

## Whitelist And Two-Hop Design

Whitelist mode is a reachability problem before a protocol problem.

For each candidate ingress validate:

- exact SIM/operator/MVNO, region/tower, date, and RAT;
- IP/CIDR and port;
- TCP/UDP/ICMP separately;
- SNI/Host and TLS fingerprint;
- provider/public DNS path;
- l4-25 progression and sustained bidirectional transfer.

If an admitted ingress exists but foreign egress does not, a two-hop design may be justified:

```text
client -> tested RU/whitelisted ingress -> foreign egress -> internet
```

Keep credentials, management surfaces, failure domains, and logs separate. Route Russian apps direct. Do not infer that a cloud VM is admitted because the provider's consumer services are.

Complete radio/L3 shutdown is not whitelist mode and cannot be fixed by a tunnel. Pre-stage alternate SIM/Wi-Fi/wired access and offline instructions.

## Routing And DNS

- Prefer explicit split routing for mixed RU/non-RU use.
- Handle IPv6 deliberately: route it consistently or disable it; never leave an accidental bypass.
- Keep DNS on the same policy path as traffic.
- On LAN, enforce DNS at the router when project policy permits.
- On Android, loopback DNS, replaced public DNS, odd routes, and split-tunnel shape are detectable.
- Avoid unauthenticated localhost proxy listeners and public management APIs.
- Test STUN/voice/call paths separately; they can reveal another IP/path.

## Client-Side Risk Reduction

Router-level proxying can remove Android `TRANSPORT_VPN` and VPN-package signals from the phone, but not network-plane fingerprints, foreign GeoIP, DNS/routing mistakes, or service-side checks.

When a local client is required:

- disable unneeded mixed/SOCKS/HTTP listeners and Xray/sing-box/Clash APIs;
- avoid unusual low MTU and unnecessary interface/route artifacts;
- keep one consistent IPv4/IPv6/DNS policy;
- expect apps to compare VPN APIs, packages, routes, DNS, localhost ports, STUN, GeoIP/ASN, SIM/cell/Wi-Fi location, and RTT;
- treat hook/root concealment as another detectable surface.

See `rkn-hardering-threat-model.md` for the versioned behavior currently
documented by this skill.

## Experimental And Emergency Paths

Do not promote these into the base set without a separate spike:

| Path                  | Classification                            | Minimum acceptance evidence                                          |
| --------------------- | ----------------------------------------- | -------------------------------------------------------------------- |
| XICMP/ICMP tunnel     | privileged emergency path                 | exact ICMP reachability, abuse risk, pcap, sustained transfer        |
| DNS tunnel            | emergency when resolver is the only plane | provider resolver, rate limits, loss/latency/MTU, sustained transfer |
| API Gateway/WebSocket | provider-specific bridge                  | frame/idle limits, reorder/half-close, bans/ToS, rollback            |
| TURN/SFU/WebRTC       | service-specific research                 | relay permission, DataChannel/VP8 behavior, pacing, IPv6, ToS        |
| Hysteria Mimic        | Linux/root/eBPF experiment, still UDP     | both-end compatibility, operator UDP, pcap, throughput               |
| FPS/carrier-TLS       | beta/research                             | carrier profile, pcap size/timing, active probes, mobile UX          |

This table is a dated policy classification, not current implementation
evidence. Locate and recheck the primary upstream or research source for a row
before relying on its implementation details or promoting it.

## Operations

- Record each profile's role: primary TCP, secondary TCP, UDP, emergency.
- Track tests by home ISP, SIM/operator/MVNO, region, date, and tool/config version.
- Keep independent providers/transports; do not chain otherwise independent
  edge paths by default.
- Rotate credentials deliberately, not every deploy.
- Monitor connect, TLS, sustained transfer, TLS-burst behavior, UDP availability, public IP/ASN, and DNS path without printing secrets.
- Preserve test outputs, pcaps, traces, and exact tool versions.
- Keep config declarative and use the project's owning skills before implementation or deploy.

## Evidence Checklist

Before saying a design works, record:

- source class and observation date;
- exact operator/MVNO, region, network type, destination IP/ASN, and SNI;
- DNS resolver/path;
- TCP connect and TLS handshake;
- controlled same-SNI burst behavior;
- UDP/443 result;
- sustained bidirectional transfer and packet/flow behavior;
- plain-HTTPS same-destination control, adjacent prefix/ASN control where possible, second Russian ISP, bidirectional pcap/MTR;
- IPv4/IPv6 public IP from RU and non-RU checks;
- local listeners/APIs/routes/DNS/TUN state;
- direct Russian-app and blocked-resource behavior;
- STUN/voice path where relevant.

If a check is missing, state the recommendation as conditional.
