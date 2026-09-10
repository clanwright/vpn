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

Optional private zones form a closed conditional-routing branch in both
AdGuard upstream lists. Their numeric private resolvers never fall through to
Unbound or the public reserve. Native exact rewrites may return a private address
or a CNAME whose target remains inside the declared zones. Native typed rewrites
run before generated important and combined important/DNS-rewrite exceptions.
Consumer rules cannot cancel those exceptions. When the ordinary exception
wins, parental filtering is skipped; a more-specific important block from an
enabled remote feed can still block a direct private-name lookup. That bounded
filter-content trust affects availability, not private forwarding closure.
Ordinary public policy is unchanged. A DS parent-selection guard prevents
private-zone DS queries from escaping that branch.

AdGuard exposes typed local UI/DoH backend metadata. The consumer supplies
certificate file bindings and permissions, ACME reload relationships, Caddy
publication and firewall exposure. The role does not depend on Network's schema.
The consumer also owns private-resolver behavior, listeners, client routing and
name/certificate authorization. Source configuration and query logs still reveal
names to their readers; private routing is not an access-control boundary.

Mihomo profiles use primary AdGuard DNS only. If AdGuard is unavailable, new
queries without a usable cached answer fail. The sing-box profile has its own
DNS cascade. The server reserve does not provide client failover around AdGuard.

## Verification boundary

Runtime support is `x86_64-linux`. Repository checks evaluate schemas, contracts,
generated configurations and combined Clan composition without running services
or application parsers. See [verification](operations/verify.md) for the gate,
artifacts and limits of its evidence.
