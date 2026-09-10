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
- `credentialContract`: the bcrypt placeholder stays in the root-only SOPS
  template and systemd credential wiring preserves the native unit;
- the disabled-role contract: no service, secret or exposure declarations;
- `negativeContract`: package substitution and unsafe overrides fail.

Evaluation must also force invalid upstream strings such as missing,
nonnumeric, zero and out-of-range ports. They must produce a failed module
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
6. Plain DNS includes loopback and only private addresses. UI and DoH Caddy
   fragments bind explicit addresses, check destination address and port 443,
   and Caddy verifies the HTTPS backend certificate with the configured SNI.
7. Query log is 7 days, statistics 90 days, IP anonymization is off, Safe
   Browsing is off, parental control and Safe Search remain on, and consumer
   `filtering.userRules` survive declarative rendering.

Do not inspect decrypted SOPS output or place a bcrypt value in an evaluation
argument or log. The contract test uses a placeholder and proves only that the
placeholder is wired into the generated configuration.

## Interpretation

A passing result proves the evaluated Nix data and assertions. It does not
prove process startup, parser acceptance, DNS answers, fallback timing,
certificate trust at runtime, network reachability, filtering downloads or
behavior on any ISP. These are inherent limits of the defined pure-evaluation
scope and must not be reported as verified.
