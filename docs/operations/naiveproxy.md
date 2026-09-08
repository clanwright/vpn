# Accept a NaiveProxy candidate

This runbook separates repository verification from consumer activation.
Provider, DNS, live certificates, credentials and deployment still require
the owner's explicit scope. Use dummy credentials in isolated tests; never
paste production profile URLs, passwords or adapted Caddy JSON into a report.

## Repository checks

Run the complete gate:

```bash
scripts/verify.sh
```

Retain `.work/verification/<UTC-run-id>/summary.tsv` and its stage logs.
VM configurations and VM-based tests are prohibited in this project. Repository
checks run without launching virtual machines. Actual traffic and native Caddy
reload acceptance require separate runtime evidence on an explicitly authorized
existing environment; parser and contract checks alone do not establish it.

## Consumer preparation

Before an approved activation, record the selected public-site claim, expected
TCP/443 bind, certificate name, device/probe secret bindings and additional
destination denies. Keep addresses and other private machine facts in the
consumer's private working area. Confirm the cover site and other sites on
the shared Caddy process have independent health checks.

The old fixed `ibelyasov`, `bsv`, `probe` password map remains a valid input.
Adding a new identity to the map does not provision its secret or migrate an
installed client. Prepare those consumer changes explicitly. Probe credentials
must not be offered as an ordinary device profile.

Generate passwords in consumer-owned Clan vars using a nonempty unpadded
base64url alphabet (`A-Z`, `a-z`, `0-9`, `_`, `-`), with no whitespace or
terminal newline. `sops.templates` performs literal substitution, not escaping:
arbitrary human-entered strings are outside this contract. Verify this constraint
privately before adoption; any required rotation is a separate authorized action.
Do not inspect or print production passwords to review this repository change.

## Positive and negative acceptance

After an approved activation, verify the actually running binaries and effective
configuration, not only the source lockfile. Use a trusted client certificate
store and the endpoint's real TLS/SNI identity. Never disable TLS verification
to make a test pass.

1. Check the cover site without authentication, then authenticated Naive H2
   traffic using both the selected sing-box build and the standalone test client.
2. Verify a wrong password cannot reach the target and does not expose a proxy
   authentication challenge. A wrong TLS identity must fail on the client.
3. Transfer data in both directions, including a destination outside ports
   80/443. Compare complete payloads; a handshake or HEAD response is insufficient.
4. Confirm private, loopback, metadata, CGNAT/Tailscale and IPv6 ULA destinations
   fail, by literal address and by a name resolving to a forbidden address.
   Include the consumer's administrative endpoints and IPv4-mapped IPv6 cases.
5. Test CONNECT to an authority matching a sibling named Caddy site. Check
   HTTP/80 and extra tailnet listeners do not become proxy listeners.
6. Exercise idle/reconnect and a sustained transfer through a successful
   credential refresh. Check other sites on the same Caddy process.
7. With approved dummy or test configuration, confirm a rejected Caddy reload
   leaves the previous in-memory configuration running. The generated file may
   already have changed; correct it before a restart. A failed update is a failure:
   old credentials may remain valid and must not be reported as revoked.
8. Revoke one test identity and establish fresh connections: it must fail while
   another identity succeeds. Record separately whether already established
   tunnels survive a graceful reload; rejection of new auth is not immediate
   termination of old tunnels.
9. On the client, ensure UDP matching the Naive-protected policy is rejected,
   the manual choice remains fixed, and intended direct exceptions still work.

The existing profile is selective. General full/selective mode work and the
new DNS cascade have their own acceptance; do not infer their completion here.

## Rollback and evidence

Native Caddy reload retains the running configuration if loading a replacement
fails. The runtime file may already contain the rejected replacement: a subsequent
restart is not a rollback and can fail. Treat the update as failed and restore
the intended declarative configuration or secret input before retrying. There is
no addon-owned staging, snapshot, refresh service or automatic file rollback.
Do not print fragments or run an unsanitized adapter command on production
credentials.

For package/module rollback, retain the previous consumer generation and input
revision before activation. A rollback of code does not automatically undo
credential revocation or restore old secret values; coordinate those separately.

Finish live acceptance on Dom.ru, T-Mobile and Yota with dates, platform/core
versions, application use and sustained transfer results. Store private path
metadata in the consumer. Mark untested networks explicitly; local Nix gates
do not establish Russian-network reachability.
