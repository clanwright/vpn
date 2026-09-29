# Evidence baseline — 29 September 2026

Read for current claims. No VPN traffic was tested from Russian networks for
this baseline, and several pages were read through a summarising fetcher: quote
numbers only after re-reading the original. Revisit living dashboards before a
later recommendation.

## Dated events, August–September 2026

| Event date and source | Class and vantage | Supported conclusion and limit |
| --- | --- | --- |
| 2026-08-04: [VirtualDC statement](https://news.vdc.ru/2026/08/04/o-massovoj-blokirovke-ip-adresov-tspurkn-oficzialnaya-pozicziya-kompanii/); Meduza 2026-08-05/19 | Hoster statement; media quoting VPN vendors | Large IP-blocking wave across several hosters, more than 20 VPN services; "entire subnets" per vendors. Mechanism and selection criteria unproven; vendors are interested parties. |
| First reported 2026-08-26: [net4people #657](https://github.com/net4people/bbs/issues/657); [Habr 1075272](https://habr.com/ru/articles/1075272/); NTC 23007 (Dom.ru SPb, 2026-09-19/20) | Community packet analysis (TTL probes), several wired ISPs | UDP DNS queries to public resolvers (8.8.8.8, 1.1.1.1) are DNAT-ed toward National DNS (NSDI) servers, returning substituted answers or NXDOMAIN; TCP DNS to the same resolver answered correctly. Major public DoH endpoints were reported blocked while Yandex worked. Carrier coverage not mapped; a self-selected Habr poll suggests it is broad. |
| 2026-09-21..28: [Amnezia #3192](https://github.com/amnezia-vpn/amnezia-client/issues/3192); NTC 4625 (posts 1662–1670); [Moscow Times RU](https://ru.themoscowtimes.com/2026/09/29/posle-viborov-v-dumu-v-rossii-nachalas-volna-blokirovok-vpn-a207251) and [Meduza](https://meduza.io/news/2026/09/29/v-rossii-posle-vyborov-usilili-ogranicheniya-protiv-vpn-servisov), 2026-09-29 | Self-selected user reports; external looking glasses; media quoting operators | After the 2026-09-18..20 Duma elections many self-hosted and commercial servers (REALITY, XHTTP, AWG 2.0/3.1) stopped: SYN or ping/SSH unanswered from Russian addresses while reachable from abroad; some reports name targeted IPs inside subnets with neighbours reachable. Moving hoster helped some users. No packet captures, operator/ASN time series or regulator comment. |
| 2026-09-25..28: [NTC 26076](https://ntc.rkn.quest/t/26076) | Single operator, tcpdump excerpt | New sessions to some foreign nodes stalled after about 1.4 KB of client upload, same with `security: none`. Points to destination/flow policy on that host, not a TLS fingerprint rule; ISPs not stated. |
| 2026-09-21: [Habr 1084862](https://habr.com/ru/articles/1084862/) (date low-confidence); NTC 25993 | Author observations, self-selected polls; [anti-malware.ru](https://www.anti-malware.ru/news/2026-09-22-111332/51489) retelling | Claims blocks follow scanning for exposed services (panels, SSH, impersonating certificates) and correlate with Censys visibility. Other posters saw no bans; the retelling states there is no independent confirmation. Correlation, not a probing test. |
| [Ateo status](https://freedomchecker.ateo.digital/status/), snapshot 2026-09-29 15:25 MSK; [methodology](https://freedomchecker.ateo.digital/methodology/) | Physical probes: fixed Rostelecom and Sibirskiy Medved; mobile MegaFon, MTS, Beeline (eSIMs); European Russia, Siberia, Far East | Tests purchased VPN products against named services every 4–6 h. At this snapshot 2 of 14 VPN products worked on MTS and Beeline (Far East) versus 12 of 14 on MegaFon and Rostelecom; target services are 5. **Tele2 and Yota are not covered.** Results are per product and service, not per protocol or mechanism. |
| [Selectel allowlist onboarding](https://docs.selectel.ru/en/infrastructure/white-list/), updated 2026-09-07; [TSPU troubleshooting](https://docs.selectel.ru/en/dedicated/troubleshooting/tspu/) | Provider documentation | Only legal entities or sole proprietors, for a Russian IP allocated exclusively to their service (dedicated, cloud servers, load balancers, Kubernetes qualify; floating/shared IPs, VDS, S3, CDN do not). ICMP/MTR/TCP can succeed while HTTPS, SSH, VPN or RDP transfers fail. Neither is a classifier or admission guarantee. |
| [net4people #603](https://github.com/net4people/bbs/issues/603), comment 2026-09-24; OONI `torsf` RU aggregates | One Russian client/proxy operator; crowdsourced probes | Snowflake success is time-varying: DTLS filtering was seen from 2026-03-30; by 2026-09-24 the reporter's client reached near 100% while Russian clients of his Russia-hosted proxy succeeded about 50–60%. OONI ok-share was 16–22% in Apr–Jul and about 31% in Aug–Sep. Cause unknown. |

## Mobile allowlists

Allowlist state varies more finely than "operator X":

- **SIM/account, not device:** in a Beeline family plan only the account
  owner's SIM was unrestricted; swapping SIMs swapped the restriction (NTC 16325,
  2026-07-23..24).
- **Radio zone:** a Ufa report (2026-08-02) describes packet sessions
  deactivated (no IP assigned) and LTE attach rejected in restricted zones, with
  a GSM-only/EDGE path unfiltered and an airplane-mode toggle needed after
  moving. One account; mechanics inferred from modem behaviour.
- **District and IP family:** at MTS St Petersburg, which Yandex
  load-balancer answered differed between IPv4 and IPv6 and between districts
  ([#650](https://github.com/net4people/bbs/issues/650), 2026-08-19).
- **Windows and partial passage:** MegaFon SPb CIDR-only windows of about a
  minute several times a day (2026-09-11); MTS UDP partly passed during an
  allowlist (2026-09-09). Single users each.
- **Admitted ranges churn:** Yandex-associated prefixes left the MTS list in May
  and other lists later; non-443 ports on admitted ranges were reported
  throttled (NTC 16325; [#516](https://github.com/net4people/bbs/issues/516)).
- **Regional scale:** Vigo data (July 2026): unrestricted mobile sessions about
  12% in Bryansk/Kursk/Belgorod, 49% in Moscow, above 70% in some Far East
  regions. Method unpublished.

The ministry discussed monitoring allowlisted subnets for VPN use (reported
2026-08-03 and 2026-08-31, proposal stage). No controlled test of a
Russian-ingress two-hop in a confirmed allowlist window exists; see
[hosting.md](hosting.md).

## QUIC SNI filtering — research with published packet captures

[FOCI 2026 paper](https://www.petsymposium.org/foci/2026/foci-2026-0010.pdf),
[artifacts](https://github.com/UPB-SysSec/RussiaQuicResults), discussed on
[2026-08-25](https://github.com/net4people/bbs/issues/654). Experiments were
**March–April 2026** from rented Moscow (AS50867), Saint Petersburg and
Novosibirsk (AS214822) hosts to Berlin — not mobile SIMs. TLS-blocked domains
were also blocked over QUIC v1 by SNI, only outbound; QUIC v2 was unaffected.
Filtering covered ports beyond 443 (in Moscow 22% of ports 1–1023 were
untouched); the same four-tuple stayed blocked for 420 seconds, with further
packets resetting the timer. QUIC and TLS devices sat at the same hop.
SNI-based QUIC filtering dates to no later than July 2023.

For a matching experiment, keep controls outside the residual state, inspect
the actual QUIC version and test end-to-end traffic. Do not hard-code 420
seconds as a recovery time elsewhere, and do not assume a tunnel can switch to
QUIC v2: no released Hysteria client dials v2 ([udp.md](udp.md)).

## Flow-level hypotheses worth testing, not adopting as defaults

**Payload freeze (l4-25, "16–20 KB"):** flows to restricted destinations stall
after a limited amount of data. [net4people #490](https://github.com/net4people/bbs/issues/490)
measured cuts from 14 to 34 KB (HTTP about 32–34 KB, HTTPS 25 KB or less,
February 2026); one hypothesis ties size to initial window × MSS. One
uncontrolled report has UDP cut at 20 packets (2026-08-15). Packet and byte
counts are not interchangeable. Compare ordinary HTTPS to the same destination,
a plain TCP upload without TLS, a second ISP, and reused versus genuinely
separate connections; splitting HTTP messages inside one TCP connection does
not create separate flows.

**Per-destination connection cap:** Russian reports summarised in
[Xray #6376](https://github.com/XTLS/Xray-core/issues/6376) (June–August) describe
about four concurrent TLS connections to one destination before a minutes-long
ban; reports disagree whether 3 or 6 is safe. Xray's XHTTP default is lowered
accordingly ([tcp.md](tcp.md)).

**TLS bursts:** the [June reproduction](https://habr.com/ru/articles/1044396/)
ties destination network and TLS fingerprint to more than three near-parallel
same-SNI handshakes (roughly 350–400 ms apart) inside about 60 seconds, followed
by roughly 120-second freezes. Use it only to build a bounded 1/2/3 versus 4+
comparison when symptoms match. Empty SNI is a diagnostic control, not a
recommended identity. Avoid aggressive retries during a freeze.

These pull in opposite directions (fresh flows may avoid a stall but trip a
cap or burst trigger): measure before changing connection pooling or
health-check concurrency.

## Venues and how to refresh

Search upstream release notes, measurement projects and operator evidence for
the actual symptom and date. Resolve conflicts by vantage and reproducibility,
not the newest headline. Keep software capability separate from successful RU
tests; a blocked vendor website does not show its tunnel fails.

Venue reliability, strongest first: net4people and NTC threads that state
vantage and controls; maintainer release notes and trackers; Habr posts read
with their correcting comments; 4PDA (client versions, weak on reachability);
Telegram channels (fastest, densest in resellers and scams). `ntc.rkn.quest`
mirrors the often-unreachable `ntc.party` and is not independent. net4people
plans to leave GitHub ([#637](https://github.com/net4people/bbs/issues/637));
check where it moved. Roskomsvoboda was dissolved on 2025-10-09. OONI
[Web Connectivity](https://ooni.org/nettest/web-connectivity/) and app tests
cover sites and apps, not VPN transports; "anomaly" is not confirmed blocking.

For a material claim, retain URL, event/test date, access date, source class,
operator/region, tool/core version, outcome, controls and missing data.

## What is not established

No independent measurement of the September waves, no controlled per-operator
comparison of VPN families, no packet-level study of CIDR versus SNI versus port
admission on allowlisted segments, no confirmation of active probing, and no
September test of which Russian apps refuse VPN users. 4PDA allowlist threads
and Telegram channels are unsurveyed. Positive single-path reports remain useful
trial evidence; these gaps are not proof that a protocol fails or that a
mechanism is absent.
