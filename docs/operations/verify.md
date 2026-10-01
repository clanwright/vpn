# Verify the repository

The repository gate checks static source hygiene and forces pure Nix contracts.
It disables builders, build jobs and import-from-derivation. It does not build
Linux outputs, execute application binaries or parsers, start services, open
listeners or test deployed machines. Python, virtual machines and VM runners
are prohibited.

## Local gate

Run the complete gate from the repository root with the cached tools:

```bash
nix shell --offline --inputs-from . --max-jobs 0 --builders '' --option allow-import-from-derivation false nixpkgs#deadnix nixpkgs#gitleaks nixpkgs#nixfmt nixpkgs#statix --command scripts/verify.sh
```

For one named evaluation result, append its name:

```bash
nix shell --offline --inputs-from . --max-jobs 0 --builders '' --option allow-import-from-derivation false nixpkgs#deadnix nixpkgs#gitleaks nixpkgs#nixfmt nixpkgs#statix --command scripts/verify.sh adguardhome-contracts
```

A focused pass is not the complete gate. The script uses the same filtered source
snapshot and static stage for both:

1. `static`: diff whitespace, Nix formatting, Statix, Deadnix and redacted Gitleaks.
2. `evaluation`: public module IDs, package names and forced
   `evaluationTests.x86_64-linux` results in one offline JSON evaluation.

Gitleaks retains its standard detection rules and excludes only the root
`.work/` evidence directory through native configuration. Active files, including
hidden configuration and untracked source, remain in the scan.

The nonempty named inventory rejects false booleans, non-boolean leaves and empty
containers. Each named result forces its nested assertions; the top-level `all`
forces every result. The flake's evaluation inventory is authoritative.

Evaluation snapshots contain tracked and non-ignored untracked source files,
excluding `.git`, `.work`, environment files and common secret, private-key and
certificate extensions. The temporary snapshot is removed on exit. The runner
never installs tools or enters another shell.

## Contract coverage

Checks share the production schemas and private publisher compiler. They cover
nine stable module IDs, schema 3 provider tags, explicit account maps, negative
security overrides, generated server/client structures, native service isolation,
exact package authority, secret wiring and combined Clan composition. Compiler
variants avoid repeated full composition; retained composition fixtures cover
actual units, restart targets and exposure wiring.

The domain suite also checks Clan's bundled native DataMesher source identity
and dependency follows, native option provenance, its disabled default in the
combined fixture and absence of runtime contributions. A throwing package value
checks that disabled import does not require package evaluation. Upstream
DataMesher package outputs and checks are not executed or built by this gate.

| Result | Domain regression coverage |
| --- | --- |
| `client-render-contracts` | Provider/profile compatibility, DNS/routing, client structures and missing-input rejection. |
| `publisher-manifest-contracts` | Asset references, structural bindings and publication manifest. |
| `adguardhome-contracts` | DNS/private rewrites, timeout arithmetic, filtering combinations and DoH stamp structure. |
| `awg-contracts` | Scoped ingress, forwarding and SNAT, including NAT-disabled configuration. |
| `naiveproxy-contracts` | Full authenticated CONNECT fragment, ACLs, listener guards and native attachment. |
| `xray-contracts` | Public exports and direct/loopback listener configuration. |

Additional forced contracts cover native AnyTLS package, identity, environment,
credentials and vendor-declaration guards; TrustTunnel H2/IPv4 restrictions;
publisher cleanup, readiness, retries, required assets, 15 canonical paths and
retirement of exactly 11 path aliases. Native systemd declaration origins and
package authority are trusted inputs; evaluation does not inspect unbuilt vendor
outputs or prove final unit assembly. Password validator source hygiene is
lexical and does not execute the validator.

Production and checks use the same internal schema 1 artifact manifest
(`schemaVersion`, `assetCatalog`, `profiles`). The generated publication shell
has a fixed sequence; there is no configurable phase graph or NixOS manifest
projection. Source assertions inspect withdrawal, cleanup and exposure order.
See [contracts](../contracts.md) for public behavior and the module pages for
settings; consumers need not duplicate generated rule text or renderers.

## Synthetic publisher harness

This is the narrow execution exception. It runs generated publication shell
with synthetic credentials and real local jq/filesystem tools in an isolated
temporary directory. VPN parsers, HTTP fetching, clocks and privileged ownership
operations are stubbed. It uses no real secrets or network.

```bash
bash scripts/test-publisher-runtime.sh
```

The harness evaluates the generator offline with builders disabled and invokes
`scripts/test-subscriptions-runtime.sh`. It checks structural substitution,
allocation/permission/jq failure cleanup, no writes to the working directory,
external Xray extraction, per-node skip diagnostics, names and collisions,
profile selection, cache invalidation and expiry, and 1024-node uniqueness.
The integrated slow-fetch fixture inspects the exposed `profile.json`: own
publication precedes fetch, accepted siblings remain and expired siblings are
withdrawn. Injected publication failures check global withdrawal and cleanup,
including omission of synthetic secrets from logs.

Unprivileged ownership and file modes, plus adaptation of Linux `mv -T`, do not
prove production permissions or replacement semantics. Deletion-failure and
forced-termination cleanup are outside the harness. Synthetic clocks and timeout
stubs do not prove Linux elapsed-time enforcement or a hard deadline for the
`65 * sourceCount + 30` TTL holdback. Client parsers and actual upstream
availability remain outside its evidence.

## Retained artifacts

Each gate creates a unique ignored `.work/verification/<UTC-run-id>.<suffix>/`:

| Artifact | Meaning |
| --- | --- |
| `scope.txt` | `full` or `test:<name>`. |
| `summary.tsv` and stage logs | Status, durations and complete readable output. |
| `revision.txt`, `worktree-status.txt` | Starting commit and pending paths, without a retained diff. |
| `source-files.txt`, `source.nar-hash` | Filtered source inventory and exact evaluated snapshot hash. |
| `flake-lock.hash` | Snapshot root lockfile hash. |

Source and lock hashes are written when evaluation prepares its snapshot; a
static-stage failure retains only earlier metadata. The NAR hash identifies
contents, executable bits and symlink targets, including uncommitted source.
The synthetic harness retains pass/fail logs and wall-clock performance in
`.work/publisher-runtime/<UTC-run-id>.<suffix>/`. Preserve evidence directories.

The runner also supports explicit ephemeral Network qualification through
`--network-candidate` with an existing direct nonsymlink store directory.
It uses an override and `--no-write-lock-file`; root-pin failure cannot be
reported as override success or hidden behind an adapter. Override identity,
computed NAR hash and shell-quoted arguments are retained in
`input-metadata.tsv` and `flake-override-arguments.txt`. The root lockfile hash
still describes the root lock, not the effective override graph. Ephemeral
qualification does not adopt a producer input.

## Evidence and runtime acceptance

Static/pure acceptance, the synthetic publisher harness and independent review
qualify repository source. A release, permanent consumer input adoption and
runtime acceptance are separate operations. Network owns the compatible native
Caddy/ACME API, specialized package and producer publication; a released producer
must supply that API before the consumer can adopt this source.

Network-owned ordinary synthetic controls qualify generic Caddy authentication,
ACLs, listener/Host behavior, cover GET, TLS and logging contexts. They do not
execute VPN's actual exported policy. VPN's exact-source pure composition must
check the complete context-bearing authenticated CONNECT fragment, runtime
import, named canonical/alias attachments and single root attachment, schema 2
publisher fragments and fixed package/startup declarations. Optional consumer
use of Access's public `lib.tailscaleReadyGate { pkgs; ipv4; interface; }` has
separate qualification in ignored artifacts; it is not a shipped VPN root/lock
input or mandatory fixture edge. When selected, it attaches to ordinary native
Caddy `ExecStartPre` under the consuming UID/sandbox with Access package authority;
there is no reload hook, watcher, privileged prefix or CLI override.

The following consumer observations are **PREDEPLOY / NOT OBSERVED** by these
repository checks:

- Final assembled systemd units/vendor drop-ins, actual same-host startup and
  journal behavior, including native Tailscale interface/address readiness.
- Actual cancellation, forced stop, cgroup/process lifetime and stop-before-delete
  ordering; cleanup under interruption, resource/socket bounds, root-peer
  interference and private file-descriptor access/inheritance. Generated guards
  and the synthetic harness do not prove these consuming-manager properties.
- Native credential substitution, permissions and certificate-copy refresh on
  ACME reload/restart; actual TLS/SNI and authenticated CONNECT routing.
- Authentication, TCP/UDP relay, parser/client compatibility and availability on
  intended networks, including reconnect, idle and sustained traffic.
- Token privacy in returned HTTP errors and every logging sink; access-log
  suppression alone does not establish this.
- DNS answers, private-resolution closure and elapsed fallback/failover behavior;
  source timeout arithmetic is not a measured client deadline.

No root/systemd runner, VM, test host or isolation workaround is introduced to
obtain those observations. The missing runtime evidence does not block bounded
source acceptance. Deployment and other protected operations require their own
authorization. Scenario owners are [AdGuard](adguardhome.md),
[Unbound](unbound.md), [NaiveProxy](naiveproxy.md), [VLESS](vless.md),
[Mieru](mieru.md), [AnyTLS](anytls.md), [TrustTunnel](trusttunnel.md),
[AWG readiness](vpn-readiness.md) and [sing-box clients](sing-box-client.md).
