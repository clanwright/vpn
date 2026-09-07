---
name: rkn-vpn-hardening
description: |
  Use for Russia-specific VPN/proxy censorship and detection work: RKN/TSPU/DPI,
  mobile whitelist or outage behavior, active probing, packet-count or TLS-burst
  freezes, protocol reachability, and client-side VPN detection. Also use for
  home-versus-mobile failures when censorship pressure is plausible. Do not use
  for ordinary VPN configuration ownership or monitoring without this threat model.
---

# RKN VPN Hardening

## Purpose

Assess VPN designs against current Russia-specific blocking and detection risks.
Treat "not detected" as risk reduction, never as a guarantee: RKN/TSPU
behavior is provider-, region-, transport-, app-, and date-dependent.

Apply this skill for advice, reviews, or implementation planning.

## Read on demand

Repository paths (`AGENTS.md` and `docs/...`) below are relative to the
repository root; `references/...` paths are relative to this skill directory.

Before changing this domain, read:

- `AGENTS.md`
- `docs/architecture.md` for domain and consumer ownership boundaries
- `docs/contracts.md` for public module interfaces
- `docs/package-authority.md` for exact package ownership
- `docs/operations/verify.md` for local verification and its limits
- The consumer's canonical documentation for selected protocols, exposure,
  DNS, routes, topology, monitoring, secret bindings, configuration and rollout
- `references/rkn-hardering-threat-model.md` for client-side threat model
- `references/rkn-vpn-best-practices.md` for evidence and mitigations
- `references/russia-2026-censorship.md` for dated context

## Workflow

1. Classify the task:
   - **Threat-model review:** read `references/rkn-hardering-threat-model.md`.
   - **Best practices:** read `references/rkn-vpn-best-practices.md`.
   - **Current context:** read `references/russia-2026-censorship.md`.
   - **Protocol/config choice:** read `docs/contracts.md` and the consumer's
     canonical configuration documentation.
   - **Whitelist/mobile blackout:** read the current context plus best practices
     before recommending protocol changes.
   - **Project implementation:** read the relevant project files and canonical
     docs before changing config.
2. Apply a freshness and evidence gate for current claims: recheck official
   releases plus current measurement/field sources; label claims as official,
   reproducible measurement, secondary report, or community observation with
   date and vantage.
3. Separate network-plane blocking from client-side detection: IP/CIDR and
   SNI policy, protocol/DPI, QUIC/UDP, DNS manipulation, active probes,
   packet-count or TLS-burst freezes versus Android `VpnService`, routes/DNS,
   TUN/MTU, local listeners, API exposure, app signatures, and GeoIP/RTT.
4. Prefer measurable changes. State the detector or failure mode reduced, what
   remains detectable, and which claims are not proven.
5. Preserve project invariants: declarative Git config, runtime-only secrets,
   stable public module contracts, and domain versus consumer ownership.

## Review Checklist

1. **Exit identity:** Is the public IP RU/non-RU, residential/hosting,
   proxy/VPN/Tor-flagged, or inconsistent across required checkers?
2. **Client detectability:** Does the client expose `TRANSPORT_VPN`, active
   `tun*`/`wg*`, low/nonstandard MTU, loopback DNS, local proxy listeners,
   Xray API, or installed VPN app signatures?
3. **Routing:** Is split routing intentional? Can an app bind to the underlying
   network and fetch a real IP? Are Russian services direct where required?
4. **DNS:** Are DNS requests routed consistently with traffic policy? Enforce
   router-side DNS where possible and avoid accidental loopback/private DNS on
   clients when detection surface matters.
5. **Protocol:** Resolve the selected protocols and defaults from evaluated
   consumer configuration and its canonical documentation; do not maintain a
   second portfolio in this skill. Verify each selected path on the exact target
   network instead of inferring reachability or probe behavior from configuration.
6. **Freeze hypotheses:** Treat numeric packet-count or TLS-burst signatures as
   dated hypotheses from the corresponding reference. Require exact path,
   second-ISP, pcap, sustained-transfer, and reused-versus-separate-flow
   controls before changing a default.
7. **Whitelist or blackout:** Distinguish whitelist filtering from complete
   radio/L3 shutdown. Validate IP/CIDR, port, protocol, SNI, provider-DNS path,
   and sustained transfer on the exact operator/MVNO/region/date.
8. **Operational resilience:** Maintain independent profiles/providers across
   tested paths, monitor reachability, rotate identifiers deliberately, and do
   not rely on a single VPS address.

## Output Style

Be concrete and adversarial. Map recommendations to a detector, block mode, or
project invariant; mark assumptions with date and source; say when a mitigation
helps only one plane; and provide file-level changes plus validation commands
for implementation tasks. Operator command sequences belong in
`docs/operations/*.md`.

## Sources To Recheck

Recheck current sources before making up-to-date claims. Consult the source
lists at the top of the relevant `references/` files instead of relying on
memory.
