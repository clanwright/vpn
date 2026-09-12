# AnyTLS

`@clanwright/vpn-anytls` runs one stock sing-box 1.14.0 AnyTLS inbound as a
dedicated `anytls` user and service. The gateway binds the exact consumer-owned
IPv4 address and TCP port. TLS is fixed to version 1.3 with the certificate and
key supplied from the consumer-owned ACME directory through systemd credentials.
It is rendered for both Mihomo and sing-box clients and participates in manual
and Auto selection under the publisher's existing `autoProtocols` policy.

The gateway settings are `enable`, `bindIPv4`, `domain`, `port`, `acmeCertName`,
`users` and `dnsEndpoint`. The endpoint contains the consumer-owned canonical
DoH domain, public numeric IPv4 bootstrap address, port and path. Every user
names one device and one distinct SOPS password secret. Password files contain
1–64 raw, unpadded base64url bytes and are rendered only into the root-managed
runtime template. The module leaves AnyTLS padding and session handling at
sing-box defaults. UoT v2 support is part of the AnyTLS protocol implementation
and creates no public UDP listener.

The consumer must enable the NixOS nftables firewall. Sing-box connects directly
to the public numeric `dnsEndpoint.ipv4`, verifies TLS against
`dnsEndpoint.domain`, and derives the HTTPS authority from that TLS name. It
does not use the host resolver, a local DNS transport, an HTTP Host override or
a fallback resolver. Before routing an AnyTLS request, sing-box resolves its
domain through that endpoint with `ipv4_only`, then rejects the complete guarded
IPv4 CIDR set and its native private-IP class. The module-owned nftables output
chain has no DNS exception: after an accept limited to replies from the exact
AnyTLS TCP listener, it rejects nonpublic IPv4 and all IPv6 egress. This also
blocks private destinations carried by later datagrams in one UoT stream.
Ingress uses a destination-scoped firewall accept rule; the module does not
install a port-wide reject that would interfere with a different service using
the same port on another address.

Only one enabled AnyTLS instance may run per machine. A disabled role exports
nothing and declares no users, secrets, templates, ACME reload binding, service,
overlay or nftables table.

Repository checks cover schema, export, rendered config, TLS credentials,
singleton behavior, service hardening, and the native and nftables guards by
pure evaluation. They do not run sing-box, validate a live certificate, open a
listener, send traffic, or establish Russian-network reachability. An AnyTLS
authentication failure closes after TLS; the direct listener has no ordinary
HTTP fallback for an active probe. TLS 1.3 identity and application traffic
must therefore be accepted on the intended client paths after deployment.

See the public [contracts](../../docs/contracts.md),
[architecture](../../docs/architecture.md), and the
[AnyTLS operations guide](../../docs/operations/anytls.md).
