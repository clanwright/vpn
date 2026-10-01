---
status: accepted
---

# Retire asset path aliases

The publisher already uses 15 canonical assets with stable opaque/hash paths.
The historical guarantee for previously issued profiles has ended; external
client use is unknown. The owner accepted retirement of exactly the 11 audited
`/assets/v1/catalog/<name>` aliases recorded in the
[public VPN finding](https://github.com/clanwright/vpn/issues/15#issuecomment-5911502739),
removing that compatibility surface while preserving canonical publication.

## Decision

Retire only these catalog aliases:

- `secure-dns.txt`
- `segments.txt`
- `filters.srs`
- `ru_blocked_and_geoblocked_domains.srs`
- `ru_blocked_asn_ips.srs`
- `refilter_blocked_domains.srs`
- `refilter_blocked_ips.srs`
- `ru_blocked_and_geoblocked_domains.mrs`
- `ru_blocked_asn_ips.mrs`
- `refilter_blocked_domains.mrs`
- `refilter_blocked_ips.mrs`

Preserve all 15 canonical assets and their opaque/hash paths, both tokenized
profile endpoints, the private links page, native host aliases, all nine public
module IDs and current client/DNS modes. Host aliases are not asset path aliases.

## Consequences

After future consumer adoption, old profiles using retired aliases may lose
asset refresh. That consequence is accepted despite unknown external client
usage. New canonical profiles keep their existing paths and behavior; this
source decision does not authorize adoption, release or deployment. Affected
source checks, publisher harness and independent review must qualify the changed
source; earlier PASS evidence does not cover alias retirement.

This accepted record is immutable. Future changes require a new ADR.
