# Review a VLESS/REALITY/XHTTP candidate

Run the complete repository gate and retain its generated summary and logs:

```bash
scripts/verify.sh
```

The source checks force Xray 26.3.27 package identity, the closed Clan schema,
SOPS template, rendered JSON structure, native credential wiring, nonroot
systemd sandbox and destination-scoped ingress. The consumer must enable its
nftables firewall; the module rejects an incompatible backend rather than
silently changing it.

Repository acceptance does not execute Xray, parsers, listeners, network
probes or tests on real/VM machines. It does not read credentials or contact
the REALITY target. Actual TLS negotiation, UUID/key consistency, relay and
Russian-network reachability remain unverified.

For a future separately approved consumer migration, the contract requires
one explicit external TLS 1.3/HTTP2 target on port 443 whose certificate covers
the configured server names. No guessed fallback is provided. Each device has
a distinct UUID secret and short ID. REALITY private key and UUID values belong
to consumer SOPS; do not print them during repository review.

Release, consumer adoption and deployment remain separate owner actions.
Machine facts, operational diagnostics and monitoring belong in the consumer.
The previous input revision and configuration remain the basis for its recovery
procedure; this repository adds no shared rollback coordinator or state cleanup.
