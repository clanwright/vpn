# Verify the Unbound source contract

Run the repository [verification gate](verify.md) and retain its logs and
summary. Acceptance covers forced Nix assertions for the stock systemd-enabled
package, loopback listeners and ACLs, host IPv6 policy, DNSSEC settings, bounded
stale settings and the integrated AdGuard dependency graph.

AdGuard may request Unbound startup with `Wants`; it must not wait for backend
readiness or require the backend to remain running. The consumer explicitly
binds AdGuard's primary upstream to the selected loopback address and port.

The project has no VM or real-machine tests. Do not execute Unbound,
unbound-checkconf, DNS probes, readiness listeners or synthetic DNS servers as
repository acceptance. The gate does not establish real `READY=1`, successful
trust-anchor refresh, DNSSEC response behavior or Internet recursion.

Complete repository verification before release or consumer adoption. Those are
separate owner actions. The consumer owns addresses, credentials, exposure,
monitoring and operational procedures. No deployment, resolver disruption,
state deletion, backup or restore is part of this verification.

Retain the currently deployed input revision as the rollback reference before a
separately authorized consumer update. Configuration rollback does not restore
or delete DNS state; there is no custom rollback coordinator.
