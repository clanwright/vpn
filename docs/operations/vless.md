# Verify the VLESS/REALITY/XHTTP source contract

Run the complete repository gate and retain its generated summary and logs:

```bash
nix develop --offline --max-jobs 0 --builders '' --command scripts/verify.sh
```

The source checks force Xray 26.3.27 package identity, the closed Clan schema,
SOPS template, rendered JSON structure, native credential wiring, nonroot
systemd sandbox, direct destination-scoped ingress and optional loopback
listener. Direct mode requires the consumer's enabled nftables firewall; local
mode adds no firewall rule and leaves public ingress to the consumer.

Repository acceptance does not execute Xray, parsers, listeners, network
probes or tests on real/VM machines. It does not read credentials or contact
the REALITY target. Actual TLS negotiation, UUID/key consistency, relay and
Russian-network reachability remain unverified.

The consumer contract requires one explicit external TLS 1.3/HTTP2 target on
port 443 whose certificate covers the configured server names. No guessed
fallback is provided. Each device has a distinct UUID secret and short ID.
REALITY private key and UUID values belong to consumer SOPS; do not print them
during repository verification.

## Shared public TCP/443

To put Xray behind a consumer-owned TLS passthrough router, keep `bindIPv4`,
`domain` and `port = 443` as the public endpoint and set, for example:

```nix
localListener = {
  ipv4 = "127.0.0.1";
  port = 10443;
};
```

The consumer binds the router to the one public IP:443 and routes the configured
REALITY target SNI names to this socket. Its HTTPS/DoH/Naive names route to its
separate loopback TLS web-server socket. The internal port is not published to
clients. No TLS termination or PROXY protocol header may be inserted before
Xray. `reality.targetHost` remains the external TLS target.

The consumer must define behavior for unknown, absent and malformed SNI without
exposing debug responses or unrestricted target forwarding. SNI routing depends
on a visible matching ClientHello name; encrypted or absent names are not
automatically routed to the REALITY backend. Preserve certificate renewal,
private-site access restrictions, tokenized-URI log suppression and source-IP
policy when introducing the TCP hop. The TCP hop changes the backend's peer
address; loopback must not become proof that the original client was private.

Before consumer activation, review the exact listener/firewall configuration and
public profile endpoint. Consumer runtime acceptance must separately establish
ordinary HTTPS, unauthenticated REALITY target behavior, authenticated VLESS,
Naive and sustained transfers on the intended client networks. This repository
only evaluates the source contracts; it does not perform those runtime checks.
Keep the prior consumer input and ingress configuration for rollback. The shared
router remains a common failure point, and using TCP/443 is not proof of
resistance to traffic classification or IP blocking.

Release, consumer adoption and deployment remain separate owner actions.
Machine facts, operational diagnostics and monitoring belong in the consumer.
Retain the currently deployed input revision and configuration as the consumer's
rollback reference; this repository adds no shared rollback coordinator or
state cleanup.
