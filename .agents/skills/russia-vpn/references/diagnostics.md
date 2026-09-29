# Diagnose the failing layer

Use existing evidence, then test the smallest unresolved branch. Check
server/process/port, clock, certificate/auth, quota, routing and DNS first so
configuration errors are not mislabelled as censorship. Preserve a working
access path before changing firewall, routes or the only VPN endpoint.

## Symptom to discriminating test

| Observation | Plausible causes | Useful next comparison |
| --- | --- | --- |
| No mobile data, including several known allowed anchors | Outage, attach/APN/DNS fault, or zone-level restriction | Whether an IP/packet session is assigned; LTE attach versus fallback to UMTS/GSM (one Ufa report found EDGE unfiltered); airplane toggle after moving; a second SIM of the same operator and plan at the same place, since restrictions followed the SIM/account in Beeline reports. Failed websites alone do not prove radio/L3 shutdown. |
| Allowed anchors work; ordinary destinations fail | Allowlist, resolver restriction, destination selection | Exact ingress IP, port, SNI/Host, IP family and resolver path, recorded during the same restriction window. |
| Many services fail at once; the server answers from abroad but not from Russian networks (ping, SYN, SSH) | IP or subnet block of the exit, hoster incident, or server outage | The exact IP from a Russian and a foreign vantage; a neighbour address in the same subnet and an address at another hoster. Complaint counts do not locate the cause. Protocol or AWG tuning cannot fix this branch; see [hosting.md](hosting.md). |
| TCP does not connect | Server/firewall, route or IP/CIDR/port denial | Server listener plus packet arrival; same IP/port from another network, and another controlled destination. |
| Failure starts right after a server or panel upgrade (REALITY "verification failed", no server log) | Core interoperability: Xray ≥26.9.8 rejects ClientHellos without ML-KEM | An Xray client with a supported fingerprint against the same server, or the previous server core. Not censorship; see [tcp.md](tcp.md). |
| TCP connects; TLS fails | Clock/cert/auth, SNI, ALPN or fingerprint/path policy | Validate server independently; compare one TLS variable at a time and packet arrival at both ends. Add a plain TCP upload without TLS to the same IP/port: an identical stall points to destination/flow policy, not the TLS fingerprint. |
| Public resolver answers look wrong or NXDOMAIN | UDP/53 interception toward NSDI, blocked DoH endpoint, local DNS policy | The same query over UDP/53, TCP/53 and DoT/DoH to the same resolver; record which path answered. See [evidence.md](evidence.md). |
| Handshake/small page succeeds; bulk stalls | MTU/PMTUD, loss/congestion, proxy buffering, quotas or filtering | Sustained upload/download, size progression, same-IP ordinary HTTPS; capture before guessing a packet-count rule. |
| UDP is silent | Local firewall/NAT/server or UDP path policy | A known working UDP application/server from another network and a TCP control; silence from a nonresponding UDP port proves little. |
| Tunnel carries bytes; one app fails | DNS/routes/IPv6, remote service/exit rejection, app transport | App DNS, TCP/UDP/QUIC and egress compared with browser; see [clients.md](clients.md). |
| Works at home, fails on mobile | Different path, DNS, NAT/MTU, policy or allowlist | Same client/profile/server at nearby times across exact SIM/MVNO and home ISP. |
| TUN mode degrades the whole mobile link after minutes; proxy mode works | DNS inside TUN, reconnect/sniffing connection storms, carrier limits | Same server in system-proxy versus TUN mode with minimal traffic; count flows and DNS queries. One unresolved Beeline report ([#663](https://github.com/net4people/bbs/issues/663)); not evidence that TUN is detected. |

Inspect the final runtime configuration as well as its source: GUI merges,
profile importers and OS network services can replace DNS, routes, client
addresses or MTU. Compare core versions and fixes that actually shipped; see
[tcp.md](tcp.md), [udp.md](udp.md) and [clients.md](clients.md). When privacy
requires full tunneling, any split-off or alternate-client control must
preserve that protection.

Change one variable at a time (IP, SNI, protocol, MTU, fingerprint). A clean
public blocklist lookup means only no entry in that feed. Ping, a TCP
connection, a healthy server and provider reputation do not establish usable
VPN traffic ([Selectel TSPU troubleshooting](https://docs.selectel.ru/en/dedicated/troubleshooting/tspu/)).

## Allowlist and outage branch

Test several recently confirmed allowed services, ordinary controls and the
candidate ingress. Record exact SIM/operator/MVNO and plan, region, RAT, IP
family, time and resolver. MVNO branding does not identify every host-network
policy; a roaming guest operator can apply its own restriction. Cached content
is not a fresh connectivity result. Allowlist state changes by district, IP
family and within minutes (short CIDR-only windows were reported), so compare
candidates inside the same window. Public UDP DNS may be intercepted; use
TCP/53 or DoT as the resolver control.

An SNI of an allowed service does not grant access to an arbitrary IP. Test DNS
bootstrap, IP/CIDR, TCP/UDP, port, SNI/Host and sustained transfer separately.
Browser-only allowlist tools cannot characterize arbitrary ports, UDP or all
SNI rules; [dpi-checkers](https://github.com/hyperion-cs/dpi-checkers/blob/main/README.md)
has a per-provider DNS-hijacking test, and its browser CIDR check is limited
when SNI is restricted.

Two-hop option: `client → tested admitted ingress → independent egress →
destination`. It is an engineering option, not a validated bypass, and adds
cost, latency, another trust boundary and another failure point. Both legs must
pass independently and end to end. A domestic VM, cloud brand or CDN membership
does not prove first-hop admission; admitted ranges churn, and non-443 ports on
them were reported throttled. Check provider admission rules and exact live
ingress reachability ([hosting.md](hosting.md)). It cannot repair a missing
radio/L3 path; for that use a working alternative network and pre-staged
instructions.

One long first-hop connection can still stall; many new ones can trigger a
suspected burst limit. Neither multiplexing nor chaining is an automatic fix.
For matching symptoms read the hypotheses in [evidence.md](evidence.md) and
compare connection reuse with separate flows. Do not hammer a frozen production
path to rediscover a timeout.

## Acceptance proportional to the claim

For a config fix, verify import compatibility, authenticated connection, the
required applications, sustained bidirectional transfer and reconnect. For a
probing-resistance claim, also check wrong-key/unauthenticated behavior against
the exact implementation: intended silence, rejection or fallback, no proxy
access, no exposed management/stats. Cover AWG wrong-peer/key and Hysteria
wrong-auth/obfs, not just REALITY/Naive fallback; normal Hysteria H3 and
Salamander have different outer responses. This tests resistance properties,
not whether RKN actively probes.

Choose duration and volume that pass the observed failure point and real use;
a fixed speed threshold misclassifies mobile paths. For censorship attribution,
add controls: ordinary HTTPS at the same destination, another Russian ISP,
exact IP versus a controlled adjacent/prefix comparison when available, reused
versus new flows, bidirectional packet captures and traces. Use a controlled
endpoint rather than scanning a subnet. For repeated QUIC/SNI experiments,
avoid reusing a flow still under residual filtering; an immediate benign retry
is a misleading negative control ([evidence.md](evidence.md)).
For resilience claims, repeat on each required ISP/SIM and after a network switch,
sleep/wake or restriction window. Test DNS/IPv6 and failure behavior separately.

Private result record:

- time/timezone; approximate region, operator/MVNO, fixed/mobile/RAT;
- destination label (private IP/ASN mapping), port, SNI, resolver path;
- client/server core versions, OS, sanitized config revision, import path;
- TCP/TLS/auth outcomes; transfer duration, bytes, stall/retry behavior;
- IPv4/IPv6, DNS, application and control results;
- verdict (observed working, observed failing, inconclusive, not tested),
  limitation, artifact location, next test and rollback result.

Do not publish raw captures, location/IP metadata or profiles. Measurement
tools may upload by default ([OONI publication and opt-out](https://ooni.org/about/risks/)):
choose publication behavior before a run; reading public results does not
authorize collection or upload on the user's connection.
