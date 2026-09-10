# Verify the repository

Repository acceptance is limited to pure Nix evaluation and static source
hygiene. The gate does not build packages or checks and does not execute VPN,
DNS, parser, key-management, service or listener binaries. Python, virtual
machines, VM-backed runners and tests on deployed machines are prohibited.

Run the complete local gate from the repository root:

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh
```

To run the same static gate and one named evaluation contract through the same
filtered snapshot path, pass its result name:

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh adguardhome-contracts
```

The outer command uses the already-cached development shell in offline mode
with builders disabled. The script itself never enters another shell or
installs tools. It executes two stages:

1. `static`: diff whitespace, Nix formatting, Statix, Deadnix and redacted
   Gitleaks checks.
2. `evaluation`: flake evaluation, public module and package-name evaluation,
   then a forced JSON evaluation of `evaluationTests.x86_64-linux` with
   offline mode, builders disabled, zero build jobs and import-from-derivation
   disabled.

Evaluation uses a temporary source snapshot outside the repository containing
only tracked and non-ignored untracked files. The snapshot excludes `.git`,
`.work`, environment files and common secret, private-key or certificate
extensions before Nix copies the source into its store. The script removes the
snapshot on exit.

The evaluation suite covers the seven stable module IDs, closed schemas,
negative security overrides, generated server and client configuration
structures, service isolation, package authority, secret/template wiring and
combined Clan composition. Each named test forces all its nested results and
rejects false booleans or non-boolean leaves before returning JSON. Focused and
full evaluation use that same success condition; the top-level `all` value
forces every named result.

Each run creates a unique ignored `.work/verification/<UTC-run-id>.<suffix>/`
directory. `scope.txt` records `full` or `test:<name>` so a focused
pass cannot be mistaken for the complete gate. Read `summary.tsv` for stage
status, duration and log paths. The adjacent logs contain the complete readable
output. Preserve that directory with review evidence.

A passing gate proves that the evaluated Nix contracts and static source checks
accepted the revision. It does not prove that application configuration
parsers accept generated files, packages can be built on Linux, systemd units
start, DNS answers or fallback behave at runtime, VPN authentication or relay
works, or any consumer machine adopted the change. Those runtime properties
remain unverified under the defined test boundary.
