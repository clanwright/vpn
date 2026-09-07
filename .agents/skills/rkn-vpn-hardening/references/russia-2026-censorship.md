# Russia 2026 RKN/TSPU Context

Use this file for current network-plane assumptions. Refreshed through **2026-08-16**. Re-browse for current operator, region, whitelist, incident, or protocol-prevalence claims.

## Evidence Policy

Label material claims by source class and observation date:

1. reproducible measurement with stated vantage;
2. official/provider technical documentation;
3. secondary or vendor incident report;
4. community observation.

Release notes prove software behavior, not RKN efficacy. A checker proves only the tested path. If current measurement is missing, keep the behavior as a dated hypothesis.

Current sources:

- `dpi-checkers` docs, `dpi-ch v0.11.0`, and current commits: `https://github.com/hyperion-cs/dpi-checkers/tree/main/ru/dpi-ch/docs`, `https://github.com/hyperion-cs/dpi-checkers/releases/tag/dpich-v0.11.0`, `https://github.com/hyperion-cs/dpi-checkers/commits/main`
- Selectel TSPU diagnostics, updated 2026-07-24: `https://docs.selectel.ru/en/dedicated/troubleshooting/tspu/`
- June TLS-burst report: `https://habr.com/ru/articles/1044396/`
- Historical l4-25 community report, opened 2025-06-27:
  `https://github.com/net4people/bbs/issues/490`
- August 4 outage reports, mechanism and scale unconfirmed: `https://meduza.io/feature/2026/08/04/nekotorye-servisy-soobschili-o-novoy-volne-blokirovok-vpn-v-rossii-ee-nazyvayut-odnoy-iz-krupneyshih-za-poslednee-vremya`, `https://www.securitylab.ru/news/575673.php`
- Ateo physical-probe status and methodology, checked 2026-08-16: `https://freedomchecker.ateo.digital/status/`, `https://freedomchecker.ateo.digital/methodology/`
- Selectel whitelist onboarding, updated 2026-07-28: `https://docs.selectel.ru/en/infrastructure/white-list/`
- `WhiteListCheck v0.5.3`: `https://github.com/dmitrystarosta/WhiteListCheck/releases/tag/v0.5.3`
- Archived single-vantage whitelist sample: `https://github.com/openlibrecommunity/twl`
- Live public blocklist feed: `https://github.com/runetfreedom/russia-blocked-geoip`

## Current Snapshot

- **Secondary reports, 2026-08-04:** multiple VPN services reported simultaneous IP/subnet outages. Public evidence did not establish a nationwide protocol block, exact operator matrix, or blocking mechanism.
- **Reproducible community measurement, checked 2026-08-16:** Ateo hardware probes showed strong operator/region variance across three macroregions and five operators. This is useful repeated measurement, not nationwide coverage or DPI attribution.
- **Secondary/community reports, July-August 2026:** partial filtering, whitelist mode, and complete mobile data/radio blackout all occurred. No tunnel can repair the last state.
- **Evidence gap, 2026-08-16:** no fresh independent July 16-August 16 campaign established current prevalence or exact thresholds for l4-25, the June TLS-burst detector, or Russian active probing.
- **Official tool release/commits, July-August 2026:** `dpi-ch v0.11.0` added Android arm64/Termux support; later commits added provider selection and whitelist-cache flushing. These improve reproducibility, not universality.

## Blocking Model

Classify failures by layer before choosing a protocol:

- **L3 IP/CIDR:** packets disappear before TLS. SNI, ECH, and application fragmentation cannot help.
- **DNS:** provider resolver constraints, poisoned/removed answers, or blocked public resolvers.
- **TLS/SNI:** ClientHello fingerprint, SNI, ALPN, connection timing, and server fallback behavior remain visible.
- **Protocol/DPI:** recognizable handshake or post-handshake flow shape.
- **Throttle/freeze:** TCP/TLS succeeds but sustained traffic stops or becomes unusable.
- **Whitelist:** the path may require both admitted IP/CIDR and acceptable L7 behavior.
- **Full blackout:** allowed anchors and ordinary data paths both fail; switch network rather than transport.

Do not infer one layer from another. A clean public blocklist lookup rules out only a hit in that feed, not dynamic DPI or operator-local policy. Successful ICMP, MTR, or TCP connect does not prove sustained SSH, HTTPS, VPN, or RDP; Selectel documents these split outcomes and recommends bidirectional traces and packet captures.

## l4-25

Historical community observations opened in 2025, later encoded by open
measurement tooling, describe a per-flow freeze around 25 packets in either
direction, often near 15-20 KB with typical packet sizes, on TCP and UDP. No
fresh July-August 2026 campaign established current prevalence or thresholds;
treat the numbers only as a dated reproduction signature.

Implications:

- HTTP/2 or application-message splitting inside one flow does not bypass a per-flow limit.
- XHTTP helps only if the selected mode/XMUX behavior creates separate flows.
- Restored throughput through multiple flows does not prove that a longer-lived destination/ASN/path policy cleared.
- SSH, sFTP, and RDP are not guaranteed exceptions.

Minimum attribution controls:

- plain HTTPS to the same destination;
- exact IP versus adjacent prefix/ASN where possible;
- another Russian ISP;
- reused versus deliberately separate flows;
- sustained bidirectional transfer, pcap, and MTR from both ends.

No published destination-policy TTL is known. Stopping a proxy listener reduces future detection surface but does not prove that an affected IP will recover.

## June TLS-Burst Hypothesis

A June 2026 community report described a chain involving destination-network suspicion, ClientHello fingerprint, and the fourth near-simultaneous TLS connection to one SNI, with roughly 350-400 ms spacing, a roughly 60-second counting window, and a roughly 120-second freeze. The initially reported 600-second escalation after changing fingerprints was later reported withdrawn. No fresh July-August campaign established current prevalence or exact thresholds.

Use these numbers only to reproduce the suspected mechanism:

- test controlled 1/2/3 versus 4+ same-SNI handshakes;
- pace normal startup, retries, health checks, and profile selection;
- compare fingerprints on the exact path rather than assuming Chrome/Safari/iOS is safest;
- wait out an observed freeze instead of churning fingerprints;
- use empty SNI only as a diagnostic control, never primary camouflage.

Xray `v26.7.28` reduced empty-XMUX `maxConnections` from 6 to 3, but this pre-release default is not a pacing mechanism and does not apply to this repository's Mihomo runtime.

## Mobile Whitelist And Blackout

First test several known allowed anchors plus ordinary and blocked controls:

- anchors and ordinary targets all fail -> likely full outage; change SIM/Wi-Fi/wired path;
- anchors pass but ordinary targets fail -> whitelist is plausible; continue per-ingress tests;
- mixed results -> record exact operator/MVNO, region/tower, timestamp, RAT, resolver, and target.

For each ingress test IP/CIDR, port, protocol family, SNI/Host, provider/public DNS, l4-25 progression, and sustained transfer. Enforcement may be SNI-only or combined IP/CIDR+SNI. Do not generalize UDP or port behavior from one SIM.

`WhiteListCheck v0.5.3` is a useful HTTPS mode classifier but does not measure CIDR, arbitrary SNI, ports, UDP, or resolver policy. The archived `twl` result is a dated single-SIM sample, not a live global whitelist.

An eligible provider submission may require an exclusively allocated Russian IP; shared, floating, CDN, or cloud membership is not proof of admission. Test the exact address after confirming ownership/submission state.

## Measurement Record

Preserve:

- source class and URL;
- observation timestamp;
- operator/MVNO, region, approximate tower/location, and RAT;
- direct/VPN state, resolver path, destination IP/ASN, SNI, port, and protocol;
- tool version, config/fingerprint, provider selector, and cache state;
- TCP/TLS result, packet progression, sustained transfer, pcap/MTR, and controls.

Without this metadata, state only a conditional recommendation.
