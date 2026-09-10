# Verify the NaiveProxy source contract

Run the complete [verification gate](verify.md):

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh
```

Retain `.work/verification/<UTC-run-id>.<suffix>/summary.tsv` and its stage logs. The
checks force Nix assertions for credentials metadata, Caddy contribution and
listener scoping, destination ACLs, native lifecycle and generated client
policy. They do not execute Caddy, sing-box, parsers or network probes. VM
configurations, VM execution and tests on real machines are prohibited.

The implementation uses Network's exact Caddy with forwardproxy and stock
sing-box with native Naive support. No standalone Naive executable is required.
The Network Caddy package is the approved custom-package exception. The gate
does not build it or claim a successful application exchange.

The consumer owns the selected public-site claim, TCP/443 bind, certificate
identity, device and probe secret bindings, and additional destination denies.
Record and review those values there before adoption. This runbook does not
authorize changing them.
Probe credentials are excluded from ordinary device profiles.

Consumer-owned Clan vars must generate nonempty unpadded base64url passwords
(`A-Z`, `a-z`, `0-9`, `_`, `-`) without whitespace or a terminal newline.
`sops.templates` substitutes tokens literally; it does not escape arbitrary
Caddyfile input. Do not read or print production credentials for source review.

Native Caddy reload retains the running configuration if loading a replacement
fails. The generated file may already contain that rejected replacement, so a
later restart can fail. Correct the declarative input before retrying; old
in-memory credentials may still be valid. There is no addon-owned staging,
refresh daemon or automatic file rollback.

Complete repository verification before an independently approved release or
consumer adoption. The gate provides no claim about actual reload behavior,
tunnels, credential revocation on existing connections or network reachability.
Consumer monitoring and operational procedures remain in the consumer
repository; no live test sequence is included here.
