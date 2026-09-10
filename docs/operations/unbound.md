# Verify the Unbound source contract

Run the repository [verification gate](verify.md) and retain its logs and
summary. Acceptance covers forced Nix assertions for the stock systemd-enabled
package, loopback listeners and ACLs, host IPv6 policy, DNSSEC settings, bounded
stale settings and absence of implicit AdGuard composition.

The consumer may request Unbound startup from AdGuard with `Wants`; this does
not require waiting for backend readiness or keeping the backend running.
The consumer also binds AdGuard's primary upstream to the selected loopback
address and port. The Unbound role adds no AdGuard dependency edge.

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
