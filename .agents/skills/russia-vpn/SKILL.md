---
name: russia-vpn
description: >-
  Choose, configure, and troubleshoot VPNs and proxies for use in Russia under
  RKN/TSPU censorship. Covers home and mobile networks, allowlists and outages,
  DPI and probing resistance, and app-side VPN detection. Use for Russia-specific
  resilience questions, not routine VPN administration without this context.
---

# VPN for Russia

Help the user obtain a working, maintainable connection under their actual
network conditions. This is a universal methodology: no required distribution,
configuration framework, hosting provider, or protocol portfolio.

## Establish the decision

Use available configuration and results first. Ask only for missing information
that changes the recommendation: target ISP/SIM/MVNO and region, home/mobile
path, client OS and core versions, symptoms, and whether the priority is access,
all-traffic confidentiality, latency, or compatibility with Russian services.
Do not request credentials or live subscription/profile URLs.

Separate three questions: can the carrier carry the tunnel; can an app identify
a local VPN; will a service accept the exit IP/account/location? Solving one does
not solve the others. A failed connection alone does not attribute a block to RKN.

## Read the relevant reference

- **Choose a design or configure a protocol:** [protocols.md](references/protocols.md).
  Compare conditional candidates, then inspect the installed client/server core,
  effective sanitized config and current upstream syntax before writing a patch.
- **Connection fails, stalls, or differs by network; mobile allowlist/outage:**
  [diagnostics.md](references/diagnostics.md). Start with the smallest test that
  distinguishes censorship from server, DNS, routing, MTU, or application failure.
- **App detects VPN; DNS, IPv6, split routing or privacy tradeoffs:**
  [clients.md](references/clients.md).
- **What works now, RKN/TSPU claims, numeric blocking signatures:**
  [evidence.md](references/evidence.md). Consult this alongside the relevant mode
  whenever the answer depends on current Russian blocking behavior.

## Evidence discipline

For time-sensitive advice, browse primary upstream documentation/releases and
current Russian measurements. Record access date separately from event or test
date. Official software support proves compatibility, not Russian reachability;
a vendor outage report or single-SIM success is not nationwide protocol evidence.
Prefer explicit operator/region/version results over marketing rankings.
Community reports can justify a conditional starting configuration without a
nationwide trial. Read the original post and later corrections, distinguish a
client bug from a blocking claim, and check whether a proposed fix actually
shipped. Do not turn a workaround that changed several variables into a causal
rule, or an unresolved single-build issue into a universal protocol defect.

The research baseline is **2026-09-07**; it is not an expiry-free prescription.
When fresh measurements are unavailable, give a conditional recommendation and
state the missing test. Do not fill gaps with remembered release numbers or
promises of an undetectable/always-working VPN. Preserve inaccessible sources as
unverified rather than upgrading search snippets into evidence.

## Produce a usable result

For selection, recommend a primary candidate and a fallback with a meaningfully
different failure domain; explain the operating cost and dependencies. Do not
force extra servers on a user whose tested single path meets their need.

For configuration, give the minimal version-specific changes, why each helps,
what it cannot fix, and a verification/rollback plan. Keep certificate and peer
authentication intact. Prefer a separately revocable credential/peer per device
where the implementation supports it; otherwise explain the shared-credential
revocation tradeoff. Keep credential values out of logs and committed profiles.
Avoid random tuning, automatic credential/IP rotation,
or replacing several independent settings at once.

For diagnosis, report observed facts, leading alternatives, the discriminating
test, and its result or remaining limitation. “Works” requires application-level
use and sustained transfer on the intended path, not only a green handshake.

Respect the user's authorized scope. Read-only research does not authorize
provider, DNS, deploy, routing/firewall, credential, or measurement-publication
changes. Keep secrets out of outputs; treat packet captures and exact client
location/address metadata as private diagnostic artifacts. If working inside a
repository, follow its local ownership and operator-runbook rules; this skill
adds no repository-specific deployment process.
