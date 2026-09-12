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

The evaluation suite covers the nine stable module IDs, closed schemas,
negative security overrides, generated server and client configuration
structures, service isolation, package authority, secret/template wiring and
combined Clan composition. Publisher checks cover static log suppression,
publication cleanup/retry declarations, public-cache paths and readiness,
secret restart targets and consumer-owned integration. These are generated
configuration and script contracts, not execution of the runtime scripts.
Manifest checks reject missing or duplicate placeholder bindings, unsupported
decoders, unknown asset references and invalid publication phase order. The
runtime script is rendered from those phases; static guards also inspect the
resulting script. Separate consumer fixtures cover a disabled publisher, an
enabled publisher with minimal dependencies and complete composition.
Profile policy fixtures cover synthetic users, publishers and protocol
compatibility, including single-protocol profiles, manual-only selection,
three own DoH endpoints, protected UDP and IPv6 local exceptions. Asset checks
cover opaque canonical paths, legacy alias collisions and MRS validation before
cache replacement. AdGuard checks cover all four Safe Search/YouTube combinations
and unchanged private DNS routing and rewrites.
AnyTLS checks cover its separate stock sing-box service, TLS 1.3 policy,
runtime credentials, scoped ingress and process egress guard, plus both client
formats with AnyTLS-only and manual-only selection. UoT v2 relay, certificate
renewal and target-network availability remain consumer runtime acceptance.
The asset contracts check refresh-before-publication ordering, the complete
required-file guard after local asset synchronization, retention of cached
downloads on failure and retry declarations for recovery. Empty-cache and
upstream-outage behavior still require separate consumer runtime acceptance,
as does parsing the HaGeZi domain list with the pinned Mihomo version.
Each named test forces all its nested results and
rejects false booleans or non-boolean leaves before returning JSON. Focused and
full evaluation use that same success condition; the top-level `all` value
forces every named result.

Each run creates a unique ignored `.work/verification/<UTC-run-id>.<suffix>/`
directory. `scope.txt` records `full` or `test:<name>` so a focused
pass cannot be mistaken for the complete gate. Read `summary.tsv` for stage
status, duration and log paths. The adjacent logs contain the complete readable
output. Preserve that directory with review evidence.

`revision.txt` identifies the starting Git commit and `worktree-status.txt`
records pending paths without retaining a diff. `source-files.txt` lists the
filtered snapshot inputs using shell-quoted paths. `source.nar-hash` hashes
the actual evaluated snapshot, including file contents, executable bits and
symlink targets; `flake-lock.hash` separately hashes its lockfile. These hashes
identify uncommitted and untracked source changes as well as committed code.
They are written when the evaluation snapshot is prepared; a run that fails
during static checks has only its starting revision and worktree status.

A passing gate proves that the evaluated Nix contracts and static source checks
accepted the revision. It does not prove that application configuration
parsers accept generated files, packages can be built on Linux, systemd units
start, DNS answers or fallback behave at runtime, VPN authentication or relay
works, or any consumer machine adopted the change. Those runtime properties
remain unverified under the defined test boundary.

AWG and Hysteria2 startup guard failure scenarios and external acceptance are
listed in [VPN readiness](vpn-readiness.md). Their pure Nix contracts inspect
the generated guards; passing those contracts does not prove that the guards
execute correctly under systemd.
