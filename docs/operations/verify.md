# Verify the repository

The main repository gate uses pure Nix evaluation and static source
hygiene. It does not build packages or checks and does not execute VPN,
DNS, parser, key-management, service or listener binaries. Python, virtual
machines, VM-backed runners and tests on deployed machines are prohibited.

A separate publisher regression harness is the narrow execution exception.
It runs the generated publication shell with synthetic credentials and real
local jq in an isolated temporary directory. Privileged ownership operations
are stubbed; the JSON fixture does not invoke VPN parsers. It provides evidence
about interpolation and temporary-file cleanup, not systemd, production permissions, client parser
acceptance or deployed publication. It uses no real secrets or network and
does not extend the main gate's execution boundary.

The same harness invokes `scripts/test-subscriptions-runtime.sh` for external
subscription import. It uses synthetic Xray profiles and a stubbed HTTP client,
clock and privileged filesystem commands. It checks extraction, per-client
composition, profile scope, Auto/manual membership, cache invalidation and
expiry without contacting a subscription or running VPN parsers. Its timeout
stub does not prove elapsed-time enforcement on Linux. Neither harness proves
systemd readiness, client compatibility, upstream availability or deployed
secret handling.

Run it separately with local Bash, Nix and jq available:

```bash
bash scripts/test-publisher-runtime.sh
```

The harness evaluates the real publisher generator offline with builders
disabled, then checks JSON credential substitution and cleanup after injected
allocation, permission-setup and jq failures. It also checks that publication
writes no files into its working directory. Ownership and read-only temporary
file modes are adapted for an unprivileged test process, and the Linux-only
`mv -T` option is adapted for the local filesystem tools. These adaptations do
not verify production permissions or replacement semantics. Cleanup checks
assume filesystem deletion succeeds; they do not cover forced termination or
filesystem failures that prevent unlinking files.

Run the complete local gate from the repository root:

```bash
nix shell --offline --inputs-from . --max-jobs 0 --builders '' nixpkgs#deadnix nixpkgs#gitleaks nixpkgs#nixfmt nixpkgs#statix --command scripts/verify.sh
```

To run the same static gate and one named evaluation contract through the same
filtered snapshot path, pass its result name:

```bash
nix shell --offline --inputs-from . --max-jobs 0 --builders '' nixpkgs#deadnix nixpkgs#gitleaks nixpkgs#nixfmt nixpkgs#statix --command scripts/verify.sh adguardhome-contracts
```

The outer command selects the four already-cached check tools from the pinned
`nixpkgs` input in offline mode with builders disabled. It does not build a
development-shell derivation. The script itself never enters another shell or
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
AdGuard timeout checks cover typed defaults, a nondefault profile and rejected
retry-budget boundaries for silent upstreams. They check generated timeouts and
their arithmetic relationship, not elapsed client time or runtime fallback;
the [consumer scenarios](adguardhome.md#consumer-runtime-acceptance-specification)
remain owned by Clanwright.
AnyTLS checks cover its separate stock sing-box service, TLS 1.3 policy,
runtime credentials, scoped ingress and process egress guard, plus both client
formats with AnyTLS-only and manual-only selection. UoT v2 relay, certificate
renewal and target-network availability remain consumer runtime acceptance.
TrustTunnel checks cover the stock 1.1.0 package, standalone H2-only listener,
runtime TOML credentials and certificate bindings, native private-destination
denial, IPv4-only process restrictions and DNS-scoped guard exceptions. Provider
and profile contracts cover its closed export schema, Mihomo TCP/UDP selection,
single-protocol and manual-only cases, and exclusion from sing-box. Runtime TOML
parsing, HTTP 404 authentication compatibility, TLS renewal, UDP cleanup,
memory bounds and reconnect remain separate consumer acceptance.
The asset contracts check refresh-before-publication ordering, the complete
required-file guard after local asset synchronization, retention of cached
downloads on failure and retry declarations for recovery. Empty-cache and
upstream-outage behavior still require separate consumer runtime acceptance,
as does parsing the HaGeZi domain list with the pinned Mihomo version.
Each named test forces all its nested results and
rejects false booleans or non-boolean leaves before returning JSON. Focused and
full evaluation use that same success condition; the top-level `all` value
forces every named result.

Domain regression ownership is exercised by these named evaluation results:

| Result | Coverage |
| --- | --- |
| `client-render-contracts` | Provider/profile compatibility, client configuration structures, DNS/routing policy, excluded-profile nonpublication and missing-input rejection. |
| `publisher-manifest-contracts` | Artifact bindings, required assets and publication phase ordering; combined composition checks also inspect generated cleanup and revocation guards. |
| `adguardhome-contracts` | Selected DNS configuration and DoH stamp structure, including malformed, truncated and appended-payload fixtures. |
| `awg-contracts` | Generated scoped ingress, forwarding and SNAT rules, including NAT-disabled configuration. |
| `naiveproxy-contracts` | Generated authentication and CONNECT routing configuration. |
| `xray-contracts` | Public provider exports and direct/loopback listener configuration. |

These checks belong to this repository; consumers need not duplicate its
renderers or generated rule text. Stamp structure checks do not run dnsproxy's
parser, and generated firewall/authentication rules do not establish successful
packet forwarding or authenticated CONNECT.

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

AWG startup guard failure scenarios and external acceptance are listed in
[VPN readiness](vpn-readiness.md). Its pure Nix contracts inspect
the generated guards; passing those contracts does not prove that the guards
execute correctly under systemd.
