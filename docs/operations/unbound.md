# Accept an Unbound candidate

Run the repository verification procedure in [verify.md](verify.md) and retain
its stage logs and timings. VM configurations and VM-based tests are prohibited.
Native-process checks exercise the exported Linux binary using local DNS
fixtures; they do not prove activation of a real machine or Internet recursion.

## Repository acceptance

Verify that the exported package and the native service use the same exact
systemd-enabled Unbound build. Check the generated configuration with that
build's parser, invalid listener/port assertions, IPv4-only behavior and the
real `READY=1` notification. Record DNSSEC valid/bogus responses, UDP/TCP,
negative answers, fresh/stale behavior and recovery from local fixture failures.

The integrated AdGuard service must have a soft start dependency only: starting
AdGuard may request Unbound, but it must not wait for backend readiness or stop
because the backend failed. An evaluation check of unit dependencies is source
evidence, not a real systemd failure test.

## Later consumer acceptance

All VPN audits must finish before release and consumer adoption. The following
checks belong to that later, explicitly authorized work on existing machines.

1. Confirm the installed package, effective loopback listeners and access-control
   rules, host IPv6 policy, system time and outbound UDP/TCP 53 connectivity.
   DNSSEC authenticates signed data; recursive authoritative queries are normally
   unencrypted and leave from the server. Do not infer client DNS routing from
   the location of this backend alone.
2. Verify initial trust-anchor creation and refresh, and startup with an existing
   anchor during a temporary upstream outage. A usable existing anchor and a
   missing or corrupt anchor are different cases. A readiness notification alone
   does not establish successful DNSSEC validation.
3. Check real signed valid and bogus answers, unsigned names, NXDOMAIN and TCP
   fallback. DNSSEC failure must not be accepted as validated data through a
   different resolver. Never disable certificate or DNSSEC validation to pass.
4. Confirm the explicit AdGuard primary is this local backend. Stop/fail Unbound
   only within the authorized test scope; verify AdGuard remains available.
   Full encrypted/plaintext fallback and bootstrap behavior belong to the
   separate AdGuard audit and require their own acceptance.
5. Measure cold-cache latency, stale limits, negative caching and return to fresh
   data. The initial stale settings are defaults to assess, not established
   performance targets for every server or network.

## Recovery and evidence

Retain the previous consumer generation and VPN input revision before an
approved activation. Package/configuration rollback does not justify deleting
the trust anchor or other runtime state. No custom rollback coordinator is
provided. If rollback to an older version restores a known security issue,
record that tradeoff and keep it temporary.

Keep machine addresses, detailed traffic evidence and any private diagnostic
artifacts in the consumer. Report repository checks, machine acceptance and
client-network results separately; record unperformed checks explicitly.
