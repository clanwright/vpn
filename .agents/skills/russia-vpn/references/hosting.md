# Hosting, subscriptions and commercial services

Read when choosing who operates the path, where the exit or Russian ingress
lives, how credentials are distributed, or whether a paid service is worth
trying. Protocols: [protocols.md](protocols.md); tests: [diagnostics.md](diagnostics.md).

## Who operates the path

| Path owner | What the user controls | Main risks to state |
| --- | --- | --- |
| Self-hosted server | Keys, exit IP, core versions, per-device credentials | Hoster account/IP loss, operator time, panel/core upgrade breakage. |
| Commercial service | Client choice at most | Unknown logging, shared exit IPs, closed clients, payment path, vendor lock-in. |
| Reseller or Telegram-bot shop | Nothing beyond the subscription | Unknown upstream nodes and logging; can vanish after payment. Many shops are white-label bots on one panel. |
| Public config lists | Nothing | Shared credentials among strangers; untrusted transit. Emergency use only, never for accounts or sensitive traffic. |

Ask which class applies before recommending; revocation, evidence and trust
differ by class even with an identical protocol.

## Foreign exit hosting

Blocking acts on exact IPs, whole prefixes and ASNs, and differs per operator:

- A February 2026 author-run scan from one Rostelecom north-west vantage listed
  391 restricted ASNs (Hetzner, DigitalOcean, OVH, AWS, Cloudflare, Akamai,
  Oracle among them; [Habr 997088](https://habr.com/ru/articles/997088/)). One
  vantage and date: a provider name is a hypothesis for the user's own path.
- 2026-09-21..28: many self-hosted servers stopped answering ping and SSH from
  Russian addresses while reachable from abroad; some users recovered by moving
  hoster, others lost a new IP within a day. Self-selected reports and media
  testimony, not measurements; see [evidence.md](evidence.md).

Design consequences:

- Test the exact exit IP from a Russian vantage before and after deployment;
  a new IP in the same /24 or the same hoster is a correlated fallback.
- Keep a fallback on a different hoster/ASN, and preserve a working path before
  moving the primary.
- Expose only the tunnel listener on the public address; keep SSH, panels,
  stats and APIs restricted to management sources. This is ordinary hygiene;
  the claim that TSPU blocks after scanning such services (Habr 1084862, date
  low-confidence) is unverified and its Censys-visibility causality disputed.
- Avoid packing many users onto one address: one vendor says detection scores
  volume and users per IP (Amnezia, 2026-08); not a measured threshold.

Hoster-side pressure is a separate failure domain: Aeza told customers in
December 2025 to remove VPN servers after a regulator list; Russian hosters
(RUVDS, Beget, NTX) prohibit VPN in their terms
([Teplitsa, 2026-05, updated 2026-07-11](https://te-st.org/2026/05/12/hostingrules/)).
The second anti-fraud package (Duma, 2026-06-10) has a hosting provision;
sources conflict on its effective date (September 2026 versus 2027-03-01). Do
not place a confidentiality-critical exit under Russian jurisdiction.

## Russian ingress and two-hop

`client → Russian ingress → foreign exit` is used for mobile allowlists and to
keep the exit address away from app-side disclosure. It is an engineering
option, not a validated bypass:

- Allowlist admission is per provider, IP pool and operator. VK Cloud reportedly
  stopped issuing admitted IPs and revoked some without notice (one IP lasted
  about 3.5 months); a January 2026 report says clouds were told to separate
  admitted pools. Do not assume Yandex Cloud IPs are always admitted. Selectel
  accepts only legal entities for addresses allocated exclusively to their
  service ([allocation requirements](https://docs.selectel.ru/en/infrastructure/white-list/)).
- A hosting-industry figure (June 2026) said RU→foreign cascades are targeted,
  and the ministry discussed monitoring allowlisted subnets for VPN use
  (August, proposal stage). Both are statements, not measurements; plan for the
  ingress to be the less durable leg.
- [net4people #650](https://github.com/net4people/bbs/issues/650) (2026-08-19..09-01)
  has no verified recipe for Beeline, MegaFon or T2 in a confirmed allowlist
  window; MTS results varied by number segment, location and IP family.
- Russian CDN fronting of XHTTP has provider filters and account bans
  ([tcp.md](tcp.md)).
- The ingress is under Russian jurisdiction and sees client addresses. Keep
  authentication and encryption end to end to the exit; pre-stage a replacement
  ingress and a subscription update path.

## Subscriptions and credentials

- A subscription URL is a bearer credential: whoever holds it imports every
  outbound. Keep it out of logs, screenshots, repositories and chats; revoke the
  user when it leaks.
- Give each device its own panel user/UUID/peer so one device can be revoked.
  Remnawave's HWID limit is a client-declared header (race advisory in backend
  ≤2.7.4, fixed 2.7.5; relay tools defeat it): anti-resale policy, not device
  identity.
- Panels older than 3x-ui 3.8.5 (2026-09-16) link the built-in profile page from
  subscription responses; review what the subscription endpoint exposes.
- Share links can drop client-specific options. On Mihomo ≥1.19.31 a link
  carrying `support-x25519mlkem768=true` transfers the REALITY ML-KEM option;
  links without it and older cores default to off ([tcp.md](tcp.md)). Check the
  imported runtime config.
- Pause automatic subscription updates while migrating servers until the new
  profile is verified.
- Panels bundle cores. Record and pin panel and core versions per server;
  upgrade only after the intended clients pass, because a panel upgrade can
  upgrade the server core and break clients (3x-ui 3.8.x requires Xray 26.9.9,
  whose REALITY gate rejects several non-Xray clients).

## Evaluating a commercial service

No independent reachability test of commercial providers was found for 2026.
Ranking sites with tracking links, single-vendor "I tested them all" posts and a vendor's own allowlist test are marketing. Vendor prices cluster at
about 100–800 RUB/month (vendor pages only). Check instead:

1. Client mode and core exposed to the user; can an independent client replace it.
2. Separate credential per device and a revocation path.
3. More than one independent exit, ingress hoster and protocol family.
4. Whether ingress is domestic infrastructure (trust and legal boundary).
5. A trial or refund on the user's own operator and SIM.
6. Payment path; avoid long prepayment (bank-side VPN payment blocking was
   anticipated in April 2026, start unconfirmed).
7. Official domain and app source: counterfeit sites dominate search, and the
   Ministry of Internal Affairs warned (2026-05-26) about "free VPN" apps
   carrying banking trojans.

Services registered with RKN must apply the Russian blocklist, so they are not
circumvention paths; treat any domestically operated or regulator-tolerated
service as a logging endpoint. Providers report Western brands work rarely;
Mullvad says most of its servers are blocked from Russia
([Mullvad](https://mullvad.net/en/help/connecting-to-mullvad-vpn-from-restrictive-locations)).

Legal context, only when asked: using a VPN is not itself penalised; VPN
advertising and deliberate searching for "extremist" material are fined; a paid
foreign-traffic tier was reported ordered after the elections (2026-09-23,
anonymous sources), not verified as enacted.
