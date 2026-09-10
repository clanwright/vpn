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
4. AdGuard's 10-second outer timeout exceeds both 3-second dnsproxy stages plus
   the asserted margin. AdGuard and Unbound are the only cache layers; only
   Unbound may serve stale data.
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
