# AnyTLS

`@clanwright/vpn-anytls` runs one stock sing-box 1.14.1 AnyTLS inbound through
native NixOS `services.sing-box`, `sing-box.service` and the `sing-box` Unix
identity. The gateway binds the exact consumer-owned
IPv4 address and TCP port. TLS is fixed to version 1.3 with the certificate and
key supplied from the consumer-owned ACME directory through systemd credentials.
It is rendered for both Mihomo and sing-box clients and participates in manual
and Auto selection under the publisher's existing `autoProtocols` policy.

The gateway settings are `enable`, `bindIPv4`, `domain`, `port`, `acmeCertName`,
`users` and `dnsEndpoint`. The endpoint contains the consumer-owned canonical
DoH domain, public numeric IPv4 bootstrap address, port and path. Every user
names one device and one distinct SOPS password secret. Password files contain
1–64 raw, unpadded base64url bytes and enter native settings as `_secret` file
references. Native pre-start substitution writes `/run/sing-box/config.json`
without placing values in the store. AnyTLS padding and session handling stay at
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
nothing and declares no users, secrets, ACME reload binding, service,
overlay or nftables table.

Native `services.sing-box.package` explicitly selects stock sing-box 1.14.1.
The consumer's independent `pkgs.sing-box` alias may differ; no AnyTLS global
overlay or host-alias equality is required. Effective service package and
ExecStart, native vendor provenance and all namespace/security guards remain
mandatory, including rejection of an effective service-package override.

The native service, settings, users, credentials, directories and generated unit
are checked after option merging. Competing inbounds, runtime configuration files
and namespace overrides are rejected. The merged global environment is limited
to native locale/timezone keys, manager `DefaultEnvironment` stays empty,
and the unit retains its native PATH. Native unit aliases and foreign-unit
aliases targeting `sing-box.service` are rejected. The native
user and group retain automatic UID/GID allocation and exclusive identity and
membership: foreign users cannot select `sing-box` as their primary or
supplementary group, and foreign group member lists cannot name that user.
The assembly guard requires stock sing-box, package declarations from the actual
pinned NixOS `modulesPath`, and enabled native-origin entries with unchanged
targets for `systemd/system` and `systemd/system.conf`. Competing entries targeting
those paths, a replacement `systemd` directory and `systemd/system.conf.d` entries
are rejected, as is suppression or replacement of the service.

This trusts native module declarations and each native service’s exact package
authority. It does not inspect unbuilt vendor outputs, prove the final assembled
systemd directory or protect against arbitrary hostile Nix code that spoofs
declaration origins. ACME renewal restarts `sing-box.service`
to refresh the systemd certificate copies; no dedicated AnyTLS fallback unit is used.

The schema 3 export contains `connection.anytls`, `endpoint = { hostname; ipv4; port; }`
and `clients.<device>.passwordSecret`.

Repository checks force schema, export, rendered config, TLS credential wiring,
singleton isolation and native/nftables guards through pure evaluation. An
AnyTLS authentication failure closes after TLS; the direct listener has no
ordinary HTTP fallback for an active probe. Runtime acceptance and the limits
of native unit provenance are defined in
[verification](../../docs/operations/verify.md#evidence-and-runtime-acceptance);
client scenarios belong to the operations guide.

See the public [contracts](../../docs/contracts.md),
[architecture](../../docs/architecture.md), and the
[AnyTLS operations guide](../../docs/operations/anytls.md).
