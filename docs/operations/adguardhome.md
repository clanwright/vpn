# Verify the AdGuard Home source contract

This runbook covers repository evaluation only. It does not activate a machine,
read or change a secret, contact a DNS provider, or run AdGuard Home, dnsproxy,
configuration parsers or a VM.

## Consumer filtering policy

The library defaults do not contain personal filtering policy. Define required
rules in the consumer resolver role settings. The typed input is the canonical
owner. Changing filtering policy or adopting a new repository revision in a
consumer requires separate authorization.

## Targeted evaluation

From the repository root, force the complete AdGuard result:

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh adguardhome-contracts
```

The result must contain true values for:

- `schemaContract`: the typed interface is closed and rejects invalid types;
- `effectiveContract`: the generated AdGuard attrset keeps the selected
  listeners, primary/fallback paths, TLS, cache, filters and retention;
- `cascadeContract`: dnsproxy uses the three static-address DoH stamps in
  parallel, then the three plaintext addresses, with no bootstrap or cache;
- `privateSchemaContract`: the new option types are closed;
- `privateAssertionContract`: invalid private zones, endpoints, rewrites and
  conflicting user rules are rejected;
- `privateDnsContract`: conditional lines occur in both AdGuard upstream lists,
  native rewrites and DS guards are generated, and user-rule ordering is fixed;
- `filteringDisabledContract`: a declarative protection pause changes only
  `protection_enabled`;
- `privateDisabledContract`: private settings do not weaken disabled-role cleanup;
- `credentialContract`: the bcrypt placeholder stays in the root-only SOPS
  template and systemd credential wiring preserves the native unit;
- the disabled-role contract: no service, secret or exposure declarations;
- `negativeContract`: package substitution and unsafe overrides fail.

Evaluation must also force invalid upstream strings such as missing,
nonnumeric, zero and out-of-range ports, and invalid private-zone/rewrite cases:
empty or duplicate groups and names, public or looping resolvers,
public answers, uncovered targets, wildcard/chained/cyclic aliases, and
`dnsrewrite`, `badfilter` or `important` user-rule modifiers. They must produce
a failed module
assertion instead of aborting JSON parsing.

The stamp checks decode the configured base64url payloads and check their
length-prefixed fields and complete consumption. They also reject the malformed
Quad9 hostname length that previously escaped string-equality checks. These
checks do not execute dnsproxy or establish fallback availability at runtime.

## Complete repository gate

Before any release work, run the common gate:

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh
```

The gate is defined in [verify.md](verify.md). It performs static hygiene and
pure Nix evaluation with builders disabled. Preserve the generated
`.work/verification/<UTC-run-id>.<suffix>/summary.tsv` and referenced logs as the
review evidence.

## Inspect the generated contract

The evaluated configuration must show these source properties:

1. The AdGuard package is stock 0.107.78 from the domain pin and dnsproxy is
   stock 0.83.2. Consumer package overrides are rejected.
2. AdGuard has one loopback Unbound primary and one loopback dnsproxy fallback.
   It has no `Requires` or ordering edge to Unbound.
3. dnsproxy has a 3-second exchange timeout, static connect IP plus TLS identity
   for every encrypted provider, `insecure=false`, and plaintext only in its
   fallback pool.
4. The relationship between AdGuard's per-upstream timeout and the dnsproxy
   stages satisfies the module's timeout contract. AdGuard and Unbound are the
   only cache layers; only Unbound may serve stale data.
5. An enabled role forces auth, root-only secret/template metadata,
   `settings=null`, `LoadCredential`, direct `install -m 600` and the exact
   package's `--check-config` command. The native ExecStart, DynamicUser,
   StateDirectory and sandbox remain owned by the NixOS module.
6. Plain DNS includes loopback and only private addresses. The role exposes typed
   UI/DoH backend metadata and consumes explicit certificate file bindings. It
   declares no Network claims, firewall exposure, ACME or Tailscale dependencies.
   The consumer integration fixture binds explicit frontend addresses and verifies
   the HTTPS backend certificate with the exported SNI.
7. Query log is 7 days, statistics 90 days, IP anonymization is off, Safe
   Browsing is off, parental control and Safe Search remain on, and consumer
   `filtering.userRules` survive declarative rendering.
8. Every private zone has numeric private resolver endpoints in conditional
   lines in both `upstream_dns` and `fallback_dns`. Generated
   `@@||<zone>^$important,dnsrewrite` followed by `@@||<zone>^$important`
   precede consumer rules. Native typed rewrites retain priority and remain enabled, and
   `filtering.enable` changes only `protection_enabled`.
9. Private-zone DS names are guarded through `dns.blocked_hosts`; other qtypes,
   including the HTTPS record type, retain the conditional route. These are
   generated-data properties, not proof of live protocol responses or resolver behavior.

Do not inspect decrypted SOPS output or place a bcrypt value in an evaluation
argument or log. The contract test uses a placeholder and proves only that the
placeholder is wired into the generated configuration.

## Consumer runtime acceptance specification

Clanwright owns the isolated runtime harness, deployment integration and
monitoring for this contract. This repository neither implements nor runs that
harness. The consumer must use controlled synthetic names and resolver fixtures,
without querying real private zones, changing provider or DNS state, or using a
live machine as repository verification. Record the exact AdGuard Home,
embedded dnsproxy, standalone dnsproxy and Unbound versions for every run.

Derive scenario deadlines and permitted scheduling overhead from the
[module README](../../clanServices/adguardhome/README.md) timeout contract;
record both the configured bounds and the measured monotonic elapsed time. Do
not infer a total deadline by simply adding nominal stage timeouts. For every A
and AAAA query, capture the final reply's answer content, rcode and elapsed time
separately from the ordered, timestamped upstream-attempt evidence. The attempt
trace must show which primary, encrypted reserve and plaintext reserve endpoints
were contacted; the final reply alone cannot prove the selected path.

Run these public-name scenarios with deterministic fixture answers:

1. An AdGuard query with a silent Unbound primary advances to an encrypted
   reserve; the trace contains the primary attempt before the reserve attempt.
2. In that silent-primary case, a successful encrypted reserve returns its A and
   AAAA fixture answers within the applicable bound and without a plaintext
   attempt.
3. Silent encrypted reserves advance to plaintext, whose successful fixture
   answer is returned within the applicable bound.
4. With Unbound silent but loopback dnsproxy answering, all silent encrypted and
   plaintext public upstreams produce SERVFAIL within the module contract's
   functioning-fallback bound (`2A + 5F + M`, 48 seconds at defaults).
5. With both Unbound and loopback dnsproxy silent, AdGuard returns SERVFAIL
   within the silent-failure budget (`B`, 65 seconds at defaults).
6. After restoring the primary, new queries return the primary fixture answer and
   no longer attempt a reserve path.

Run encrypted-reserve timing once with a cold DoH client and again with an
already initialized DoH client. Use a fresh fixture qname for the warm-client
case so DNS caching cannot hide connection reuse or retry behavior.

Exercise a UDP fixture reply with TC set and verify the subsequent TCP exchange
separately. Record that path and full latency with filtering helpers enabled
outside the compact silent-path bounds; neither is covered by the timeout
formula above.

For each path, run a cold-cache query, an immediate cached repeat, a concurrent
duplicate pair and a query after the relevant TTL boundary. Attribute
deduplication only when concurrent identical queries share an upstream exchange;
do not treat an AdGuard or Unbound cache hit as deduplication. Prove that AdGuard
does not serve optimistic stale data, that only Unbound can supply an intentionally
configured stale fixture, and that enabled filtering is applied to both fresh and
cached replies. Repeat the filtering observations with the declarative protection
pause and show the documented preservation of native rewrites rather than assuming
all filtering behavior is disabled.

Exercise valid negative replies independently for both address families:

- NXDOMAIN is returned unchanged and does not trigger the public reserve path;
- NODATA preserves NOERROR with an empty answer and does not trigger the public
  reserve path;
- SERVFAIL from the Unbound primary is returned unchanged with no dnsproxy
  attempt; a valid SERVFAIL from an encrypted reserve is likewise not
  reclassified as an exchange error that advances to plaintext.

Finally, use synthetic private zones and resolvers to prove that A, AAAA and
HTTPS queries use only their conditional private route, including resolver
failure and recovery. Verify typed IP and CNAME rewrites, the DS privacy guard's
immediate TCP REFUSED and silent UDP behavior as distinct outcomes, and absence
of private-name attempts at Unbound, encrypted public or plaintext public
endpoints. Repeat with filtering enabled,
with a permitted consumer rule, and with a controlled conflicting remote-filter
fixture: private exclusions and typed rewrites must retain their documented
ordering, while a more-specific important remote block may block the reply but
must not cause public forwarding. Keep the attempt trace, final replies, fixture
definitions, version record and timing table together as the consumer acceptance
evidence.

## Interpretation

A passing result proves the evaluated Nix data and assertions. It does not
prove process startup, parser acceptance, DNS answers, fallback timing,
certificate trust at runtime, network reachability, filtering downloads or
behavior on any ISP. These are inherent limits of the defined pure-evaluation
scope and must not be reported as verified.

In particular, the checks do not prove that a private resolver avoids public
recursion, that DS over TCP returns REFUSED or over UDP drops, or that
timeouts retry exactly as expected. Validate those properties only in the
consumer's separately authorized runtime acceptance.

The source checks also do not prove that enabled remote filter feeds contain no
more-specific important block for a private name. Review that consumer-chosen
content when private-name availability matters; such a block does not cause
fallback to the public resolver path.
