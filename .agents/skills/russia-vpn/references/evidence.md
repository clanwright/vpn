# Evidence baseline — 7 September 2026

Read for current claims. Dates below distinguish publication/update from access;
all listed pages were inspected during the 2026-09-07 research and deeper community pass. Living dashboards
and documentation must be revisited for a later recommendation. No VPN traffic
was tested from Russian networks during this skill rebuild.

## What the evidence supports

| Source and date | Class and vantage | Supported conclusion and limit |
| --- | --- | --- |
| [Selectel TSPU troubleshooting](https://docs.selectel.ru/en/dedicated/troubleshooting/tspu/), updated 2026-08-27 | Hosting-provider technical/support documentation | ICMP, MTR and TCP connection may succeed while HTTPS, SSH, VPN or RDP transfers fail. IP, SNI, protocol and QUIC metadata can matter. Not a published classifier or nationwide measurement. |
| [Selectel allowlist onboarding](https://docs.selectel.ru/en/infrastructure/white-list/), updated 2026-09-01 | Provider operational documentation | Admission is service/IP-allocation dependent. Its process requires a Russian IP exclusively allocated to the service; listed shared/cloud/CDN products are unsuitable. This is one provider's eligibility guidance, not a packet-level specification or admission guarantee for any RU VPS. |
| [Ateo status](https://freedomchecker.ateo.digital/status/), snapshot 2026-09-07 19:30 MSK; [methodology](https://freedomchecker.ateo.digital/methodology/) | Physical fixed/mobile Russian probes; five operators, three macroregions | Contemporary named-service outcomes vary by operator. Tests repeat on roughly 4–6-hour cycles. Coverage is limited; service results do not isolate protocol, fingerprint, or blocking mechanism. Reopen the dashboard instead of copying a permanent winner list. |
| [dpi-checkers](https://github.com/hyperion-cs/dpi-checkers/blob/main/README.md); [dpi-ch v0.11.0](https://github.com/hyperion-cs/dpi-checkers/releases/tag/dpich-v0.11.0), 2026-07-29 | Community diagnostic implementation | Tools operationalize suspected transfer freezes and allowlisted IPv4 checks; this release adds Android arm64/Termux. Tool availability is not a new prevalence study; browser CIDR tests have SNI-filtering limitations. |
| [net4people #490](https://github.com/net4people/bbs/issues/490), opened 2025-06-27, subsequent community updates | Reported Russian path observations | Basis for the historical l4-25 hypothesis below. No fresh independent July–September campaign establishing threshold or coverage was located. |
| [TLS-burst reproduction](https://habr.com/ru/articles/1044396/), 2026-06-06, correction 2026-06-16 | Author's home-ISP tests against FirstVDS | Basis for the burst hypothesis below; not nationwide evidence. The author withdrew the earlier 600-second escalation claim. |
| [Snowflake DTLS report #603](https://github.com/net4people/bbs/issues/603), opened 2026-04-06 about behavior starting 2026-03-30 | User packet captures and maintainer analysis | Pion DTLS fingerprint filtering was observed; proxy implementation/update affected the outcome. Does not establish that all WebRTC or all Snowflake paths are blocked. |

**Evidence gap:** the research located September service measurements and
allowlist documentation, but no current controlled RU comparison of all candidate
VPN families, nor September validation of packet-count thresholds, TLS-burst
thresholds, active-probing prevalence, or general UDP throttling. Architecture
recommendations in [protocols.md](protocols.md) are engineering judgments to test.

## Additional primary findings from the deeper pass

**QUIC SNI filtering — research with published packet captures.**
[FOCI 2026 paper](https://www.petsymposium.org/foci/2026/foci-2026-0010.pdf),
[artifacts](https://github.com/UPB-SysSec/RussiaQuicResults), discussed on
[2026-08-25](https://github.com/net4people/bbs/issues/654).
Actual experiments were **March–April 2026**, from rented Moscow (AS50867),
Saint Petersburg and Novosibirsk (AS214822) endpoints to Germany—not mobile SIMs.
They observed QUIC v1 SNI-dependent drops and 420-second residual blocking of
the same IP/port four-tuple, with subsequent messages resetting the timer.
QUIC v2 was unaffected in those tests. Filtering extended beyond UDP/443;
Moscow had system-port exceptions and some domains behaved differently.
These findings do not validate a September VPN or every operator. For a matching
experiment, keep controls outside the observed residual state, inspect the actual
QUIC version and test end-to-end traffic. Do not hard-code 420 seconds as a
universal recovery time or assume changing to QUIC v2 is supported by the tunnel.

**MTS mixed-path report — 2026-08-19.**
[net4people #650](https://github.com/net4people/bbs/issues/650) describes three
MTS users: ordinary REALITY use worked for one, while another failed even outside
suspected allowlist periods. A community-listed Yandex prefix worked from
external test points but was **not tested during a confirmed mobile allowlist**.
During the suspected restriction, known allowed sites also failed. This leaves
outage/SIM/path causes unresolved; it does not prove either successful allowlist
bypass or a complete radio shutdown. A popular SNI and a CIDR-list entry are
candidate-selection inputs, not admission evidence.

**Settings and client reports:** read the dated tables in [tcp.md](tcp.md),
[udp.md](udp.md), [clients.md](clients.md) and [emerging.md](emerging.md) for
concrete incompatibilities and workarounds. Community issues can establish a
useful local failure class without establishing RKN involvement. A fix PR,
merged commit and shipped release are three distinct states.

## Historical mechanisms worth testing, not adopting as defaults

**l4-25:** reports describe a flow stalling around 25 packets in either direction,
often around 15–20 KB, and include TCP and UDP observations. Packet and byte
counts are not interchangeable. Compare ordinary HTTPS to the same destination,
a second ISP, and reused versus genuinely separate transport connections.
Splitting HTTP messages inside one TCP connection does not create separate flows.
Restored throughput over new flows does not show that IP/ASN policy has cleared.
There is no verified universal policy timeout. See [original thread](https://github.com/net4people/bbs/issues/490).

**TLS bursts:** the June reproduction associates destination network and TLS
fingerprint with more than three near-parallel same-SNI handshakes (roughly
350–400 ms spacing), a roughly 60-second window, and roughly 120-second freezes.
Use these only to construct a bounded 1/2/3 versus 4+ comparison when symptoms
match. Empty SNI is a diagnostic control, not a recommended identity. Neither
“three connections is always safe” nor “switching fingerprints unblocks it” is
established. Avoid aggressive retries during a freeze. See [report and correction](https://habr.com/ru/articles/1044396/).

These hypotheses can pull configuration in opposite directions: many fresh
flows may avoid a per-flow stall but worsen a burst trigger. Measure before
changing connection pooling or health-check concurrency.

## How to refresh this reference

Search the relevant upstream release/changelog, direct measurement project and
operator evidence for the actual symptom and date. Resolve conflicts by vantage
and reproducibility, not the newest headline. Keep software capability separate
from successful RU tests; a blocked vendor website is not proof its tunnel fails.
OONI [Web Connectivity](https://ooni.org/nettest/web-connectivity/) can help with
DNS/TCP/TLS/HTTP failures for tested sites, not arbitrary VPN interoperability.

For a material claim, retain URL, event/test date, access date, source class,
operator/region, tool/core version, observed outcome, controls and missing data.
Do not demand exhaustive measurements for every ordinary config explanation;
require the controls needed for the strength of the conclusion being made.


## Community search coverage and remaining gaps

The deeper pass used six separate scopes: TCP transports, UDP/AWG, network
filtering/allowlists, emerging protocols, client OS/routing, and DPI/Tor/emergency
alternatives. Russian and English queries covered GitHub issue/comment/release
history, net4people, NTC, firsthand Habr discussions and measurement papers;
August 1–September 7 was prioritized, with earlier unresolved or contradicted
findings traced when relevant.

Some NTC content was readable via `ntc.rkn.quest`; direct `ntc.party` access and
indexing were uneven. Treat mirror access as such, not independent corroboration.
Some GitHub comments and closed Telegram posts were unavailable. Category
activity dates, search-engine crawl dates and auto-updated “VPN today” rankings
were not treated as test dates. No comprehensive forum/Telegram archive was
searched, and this is not an exhaustive inventory of community knowledge.

The pass found September client-development evidence, including a September 5
CVR proposal, but no controlled September 1–7 RU head-to-head test establishing
an overall protocol winner. It also found no fresh August–September controlled
validation of l4-25/TLS-burst thresholds or active server probing. Positive
single-path reports remain useful trial evidence; these gaps are not proof that
a protocol fails or that a mechanism is absent.
