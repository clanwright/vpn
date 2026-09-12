# AnyTLS operations

The `@clanwright/vpn-anytls` gateway runs a separate stock sing-box 1.14.0
process on one consumer-owned IPv4 TCP endpoint. The consumer owns the address,
hostname, ACME certificate, firewall availability, public AdGuard DoH endpoint,
secret values and deployment. Do not put passwords or live profile URLs in
commands, tickets, logs or repository files.

## Preconditions

- The selected IPv4 address and TCP port are assigned to the machine and free.
- The endpoint domain resolves to that address and the named ACME certificate
  covers the domain.
- The NixOS firewall uses the nftables backend and `networking.nftables.enable`
  is true.
- `dnsEndpoint.domain` names the consumer-owned public AdGuard DoH endpoint;
  its public-only numeric `ipv4` is the bootstrap address. The optional `port`
  and `path` default to `443` and `/dns-query`.
- Every device has a distinct SOPS secret containing 1–64 raw unpadded
  base64url bytes, without a trailing newline.

The module loads `/var/lib/acme/<acmeCertName>/fullchain.pem` and `key.pem`
through systemd credentials and registers `anytls.service` for ACME reloads.
It renders secret values only into `/run/secrets-rendered/anytls.json`, owned by
the `anytls` user with mode `0400`.

## Server inspection

After an approved deployment, inspect declarations without printing the
rendered configuration:

```console
systemctl status anytls.service --no-pager
systemctl show anytls.service -p User -p Group -p MainPID -p LoadCredential
journalctl -u anytls.service --since -15m --no-pager
nft list table inet vpn_anytls_egress
```

The unit must run as `anytls`, load both TLS credentials, and own the configured
IPv4 TCP listener. The nftables output chain must preserve replies from that
exact listener, reject private and metadata IPv4 destinations, and reject IPv6
egress. It has no DNS port or destination exception. For every AnyTLS request,
the sing-box route first resolves a domain through the single configured public
DoH endpoint with `ipv4_only`, then applies explicit rejects for the complete
guarded IPv4 CIDR set and the native private-IP class. The DoH transport dials
the numeric IPv4 bootstrap while TLS identity and HTTP authority use the domain;
it does not use `networking.nameservers` or a fallback resolver.

Do not print the SOPS secret files, the runtime JSON template, process
environment, subscription output, or URLs containing profile tokens.

## Client acceptance

Repository evaluation and server status do not establish client acceptance.
Test each intended Mihomo and sing-box client/core version on the required
networks. Verify all of the following:

1. The correct domain validates with TLS 1.3, while TLS 1.2, a wrong hostname
   or an untrusted certificate fails. Certificate renewal restarts the service
   with the new credential files.
2. Every device credential authenticates, and an incorrect or revoked password
   fails without affecting other devices.
3. TCP application traffic sustains a transfer and survives reconnect and idle
   periods.
4. A UDP application works through AnyTLS UoT v2. No public UDP listener is
   expected.
5. Selective, full, manual and Auto selection behave as intended for the
   published profile.
6. TCP and UoT requests to private, loopback, link-local, CGNAT and metadata
   destinations fail, both as literal IPs and through names resolving to those
   addresses. Include a public-to-private DNS answer change. There is no
   private-destination DNS exception.
7. IPv6-only destinations are unavailable through the tunnel. Public IPv4
   transfer, larger UDP datagrams, session reuse and idle reconnect behave
   correctly without sustained CPU or memory growth.

Perform the network acceptance on Dom.ru, T-Mobile and Yota independently.
Keep readable nonsecret results with exact client/core/server versions and the
test date in the consumer's working artifacts.

The direct listener does not provide an ordinary HTTP fallback after a probe.
In non-connected multi-destination UoT, a later datagram carrying a hostname
instead of a numeric destination fails closed in the pinned implementation;
it does not fall back to the system resolver. Include the actual application's
UDP behavior in client acceptance rather than assuming all UoT modes resolve
per-datagram names.
Passing these checks on one network does not prove availability on another
operator or region, and successful TLS/authentication alone does not prove
sustained TCP or UoT traffic.
