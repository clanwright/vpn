# Diagnose the failing layer

Use existing evidence, then test the smallest unresolved branch. Start with
server/process/port, clock, certificate/auth, quota, ordinary routing and DNS
checks so configuration errors are not mislabelled as censorship. Preserve a
working access path before changing firewall, routes or the only VPN endpoint.

## Symptom to discriminating test

| Observation | Plausible causes | Useful next comparison |
| --- | --- | --- |
| No mobile data, including several known allowed anchors | Outage, attach/APN/DNS fault, or broad restriction | Radio/data registration and address/route state; allowed anchors with DNS control; another SIM/network. Failed websites alone do not prove radio/L3 shutdown. |
| Allowed anchors work; ordinary destinations fail | Allowlist, resolver restriction, destination selection | Exact ingress IP, port, SNI/Host and provider/public DNS, recorded during the same restriction window. |
| TCP does not connect | Server/firewall, route or IP/CIDR/port denial | Server listener plus packet arrival; same IP/port from another network, and another controlled destination. |
| TCP connects; TLS fails | Clock/cert/auth, SNI, ALPN or fingerprint/path policy | Validate server independently; compare one TLS variable at a time and packet arrival at both ends. |
| Handshake/small page succeeds; bulk stalls | MTU/PMTUD, loss/congestion, proxy buffering, quotas or filtering | Sustained upload/download, size progression, same-IP ordinary HTTPS; capture before guessing a packet-count rule. |
| UDP is silent | Local firewall/NAT/server or UDP path policy | A known working UDP application/server from another network and a TCP control; silence from a nonresponding UDP port proves little. |
| Tunnel carries bytes; one app fails | DNS/routes/IPv6, remote service/exit rejection, app transport | App DNS, TCP/UDP/QUIC and egress compared with browser; see [clients.md](clients.md). |
| Works at home, fails on mobile | Different path, DNS, NAT/MTU, policy or allowlist | Same client/profile/server at nearby times across exact SIM/MVNO and home ISP. |

Inspect the final runtime configuration as well as its source: GUI merges,
profile importers and OS network services can replace DNS, routes, client
addresses or MTU. Compare before/after core versions and fixes that actually
shipped; see the scoped community cases in [tcp.md](tcp.md), [udp.md](udp.md)
and [clients.md](clients.md). When privacy requires full tunneling, any temporary
split-off or alternate-client control must preserve that intended protection.

Do not change IP, SNI, protocol, MTU and fingerprint together. A clean public
blocklist lookup means only no entry in that feed. Ping, a TCP connection, a
healthy server and a provider reputation do not establish usable VPN traffic.
For provider-side diagnostic rationale, see
[Selectel TSPU troubleshooting](https://docs.selectel.ru/en/dedicated/troubleshooting/tspu/).

## Allowlist and outage branch

Test multiple recently confirmed allowed services, ordinary controls and the
candidate ingress. Record exact SIM/operator/MVNO, approximate region, RAT,
time and resolver. MVNO branding does not identify every host-network policy.
Successful cached content is not a fresh connectivity result.

An SNI associated with an allowed service does not grant access to an arbitrary
IP. Test DNS bootstrap, IP/CIDR, TCP/UDP, port, SNI/Host and sustained transfer
separately. Browser-only allowlist tools cannot characterize arbitrary ports,
UDP or all SNI rules; [dpi-checkers](https://github.com/hyperion-cs/dpi-checkers/blob/main/README.md)
documents a browser CIDR check limitation when SNI is restricted.

A two-hop option is:

`client → tested admitted ingress → independent egress → destination`

This is an engineering option, not a validated universal bypass. It adds cost,
latency, another operator/trust boundary and another failure point. Both legs
must pass independently and end to end. A domestic VM, cloud brand or CDN
membership does not prove first-hop admission. Check provider-specific
[allocation/admission requirements](https://docs.selectel.ru/en/infrastructure/white-list/)
and exact live ingress reachability. It cannot repair a missing radio/L3 path;
for that state use a working alternative network and pre-staged instructions.

One long first-hop connection can still stall; many new first-hop connections
can trigger a suspected burst limit. Neither multiplexing nor chaining is an
automatic fix. For matching symptoms read the dated hypotheses in
[evidence.md](evidence.md), then compare connection reuse with separate flows.
Do not repeatedly hammer a frozen production path to rediscover a timeout.

## Acceptance proportional to the claim

For a config fix, verify parser/import compatibility, authenticated connection,
actual required applications, sustained bidirectional transfer and reconnect.
For a probing-resistance claim, also check unauthenticated/wrong-key behavior
on authorized endpoints against the exact implementation: intended silence,
rejection or fallback, no proxy access and no exposed management/stats. Include
AWG wrong-peer/key behavior and Hysteria wrong-auth/obfs behavior, not just
REALITY/Naive fallback. Normal Hysteria H3 and Salamander have different outer
responses. This tests resistance properties, not whether RKN actively probes.

Choose duration/volume sufficient to pass the observed failure point and real
use; a fixed universal speed threshold would misclassify mobile paths.

For censorship attribution, add appropriate controls: ordinary HTTPS at the same
destination, another Russian ISP, exact IP versus a controlled adjacent/prefix
comparison when available, reused versus new flows, bidirectional packet
captures and traces. Use a controlled endpoint rather than scanning a subnet.
For repeated QUIC/SNI experiments, avoid reusing a flow still affected by
residual filtering; the dated research in [evidence.md](evidence.md) explains
why an immediate benign retry can be a misleading negative control.
For resilience claims, repeat on each required ISP/SIM and after a network switch,
sleep/wake or restriction window. Test DNS/IPv6 and failure behavior separately.

A useful private result record:

- test time/timezone; approximate region, operator/MVNO and fixed/mobile/RAT;
- destination label with private IP/ASN mapping, port, SNI and resolver path;
- client/server core versions, OS, sanitized config revision and import path;
- TCP/TLS/auth outcomes; upload/download duration, bytes and stall/retry behavior;
- relevant IPv4/IPv6, DNS, application and control results;
- verdict: observed working, observed failing, inconclusive, or not tested;
- limitation, artifact location, next discriminating test and rollback result.

Do not publish raw captures, identifying location/IP metadata or profiles as
part of routine diagnosis. Network-measurement tools may upload by default:
[OONI documents default publication and opt-out](https://ooni.org/about/risks/).
Choose publication behavior deliberately before a run; reading public results
is different from authorizing collection/upload on the user's connection.
