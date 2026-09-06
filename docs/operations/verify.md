# Verify a candidate

Run the complete local gate from the repository root:

```bash
scripts/verify.sh
```

The script enters the pinned development shell once and executes four stages:

1. `static`: diff whitespace, Nix formatting, Statix, Deadnix and redacted
   Gitleaks checks.
2. `flake-eval`: `x86_64-linux` flake evaluation and public module, check and
   package attribute evaluation.
3. `linux-checks`: domain contracts, combined Clan fixture, client render smoke
   and AmneziaWG key consistency builds.
4. `owned-packages`: builds Mihomo, Mihomo keygen, Sing-box, NaiveProxy,
   AmneziaWG Go, AmneziaWG tools, AdGuard Home and Unbound.

Each run creates an ignored `.work/verification/<UTC-run-id>/` directory. Read
`summary.tsv` for stage status, duration, log path and whole-run duration; the
adjacent stage logs contain complete readable output. Preserve that directory
with review evidence.

A passing gate proves the candidate source, public surface and Linux build set.
It does not prove consumer adoption, machine activation, endpoint reachability,
provider/DNS state or secret correctness.
