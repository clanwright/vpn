# Architecture

The seven modules are independently selectable and share one versioned flake.
Their public entrypoints are listed in [contracts](contracts.md).

## Ownership

| Repository | Consumer |
| --- | --- |
| Service implementation and defaults | Placement and composition |
| Typed provider and publisher exports | Machine facts and secret bindings |
| Exact application packages | Exposure, certificates and Caddy site claims |
| Module and integration contracts | Operator entrypoints, monitoring and deployment |

The flake does not import a consumer checkout. TCP tuning belongs to the consumer.

## VPN services

- VLESS/REALITY with XHTTP runs in Xray.
- Hysteria2 runs in a separate Mihomo service with Gecko obfuscation and serves
  static masquerade content from a consumer-supplied store directory.
- AmneziaWG runs as a userspace generation-3 UDP gateway with a runtime
  header-protection key and individual peer keys.
- NaiveProxy contributes a Caddy `forward_proxy` fragment to a consumer-selected
  public site. The consumer supplies Network's Caddy package with the required
  plugins.

The profile publisher passes selected typed provider exports and per-device
bindings directly to its renderer.
It renders Mihomo selective/full profiles and publishes a sing-box profile only
for devices with an eligible Naive provider. Personal proxy domain additions
come from the consumer.

Rendering, public rule-asset refresh and secret publication are separate
components. Public rule assets live in persistent state; credentials and
token-named publication paths live only under `/run`. Initial publication waits
for a complete required asset set. Refresh failures retain accepted public
assets without a hard expiry and expose nonsecret status for consumer monitoring.

A publication refresh withdraws the old profile generation before rendering
and exposes a complete generation only on success. Failed refreshes cannot keep
serving revoked credentials. Caddy uses static routes and does not require,
restart or reload for the publisher. The consumer supplies site claims, grants
the exported reader group and restricts access to the links page. Access logging
of tokenized URIs is suppressed.

## DNS

AdGuard Home provides the DNS/DoH front end. Its normal upstream is loopback
Unbound, bound explicitly by the consumer. The consumer also owns any systemd
startup relationship between AdGuard and Unbound. The AdGuard role configures a
loopback dnsproxy reserve: parallel encrypted providers, followed by plaintext
providers only after encrypted exchange failures. Received NXDOMAIN or SERVFAIL
does not activate the plaintext tier.

AdGuard exposes typed local UI/DoH backend metadata. The consumer supplies
certificate file bindings and permissions, ACME reload relationships, Caddy
publication and firewall exposure. The role does not depend on Network's schema.

Mihomo profiles use primary AdGuard DNS only. If AdGuard is unavailable, new
queries without a usable cached answer fail. The sing-box profile has its own
DNS cascade. The server reserve does not provide client failover around AdGuard.

## Verification boundary

Runtime support is `x86_64-linux`. Repository checks evaluate schemas, contracts,
generated configurations and combined Clan composition without running services
or application parsers. See [verification](operations/verify.md) for the gate,
artifacts and limits of its evidence.
