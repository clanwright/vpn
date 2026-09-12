# Architecture

The eight modules are independently selectable and share one versioned flake.
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

- VLESS/REALITY with XHTTP runs in Xray, either directly on its public endpoint
  or on an optional loopback listener behind consumer-owned TCP passthrough.
  Public profile addresses and ports are independent of that local listener;
  the consumer owns shared-port SNI routing and HTTPS composition.
- Deprecated Hysteria2 runs in a separate Mihomo service with Gecko obfuscation
  and serves static masquerade content from a consumer-supplied store directory.
  It is retained for compatibility and discouraged for new use after a
  user report of blocked client connections.
- AmneziaWG runs as a userspace generation-3 UDP gateway with a runtime
  header-protection key and individual peer keys.
- NaiveProxy contributes a Caddy `forward_proxy` fragment to a consumer-selected
  public site. The consumer supplies Network's Caddy package with the required
  plugins.
- Mieru runs stock native `mita` in its own service, with a TCP transport and
  UDP relay over TCP. It requires no domain or certificate. The process binds
  its port on wildcard addresses; module firewall guards restrict ingress to
  the consumer-selected IPv4 and restrict service-originated destinations.
  Consumer supplies the system resolver addresses and owns host DNS configuration.
  Mieru is selectable in both Mihomo profiles, including their ordinary Auto
  groups when permitted by the profile's `autoProtocols`. It is not exported
  to sing-box.

Provider modules construct their common export envelope through the shared
contract implementation. Protocol-specific transport data remains owned by
each provider; consumers select those exports through the public helpers.

The profile publisher normalizes its settings and passes selected typed
provider exports and per-device bindings to its renderer.
It renders Mihomo selective/full profiles and publishes a sing-box profile
for devices with an eligible Naive or Hysteria2 provider. Personal proxy domain additions
come from the consumer.

The publisher separates manual availability from automatic protocol selection.
Sing-box uses independent TCP and UDP selectors; protected UDP uses Hysteria2
or is rejected when no compatible provider exists. Both formats capture and
reject external IPv6 while preserving local IPv6 and Tailscale access.

Rendering produces an internal artifact manifest: client templates, output
formats, structural secret bindings and required public assets. The runtime
publisher reads that manifest without knowing protocol-specific client fields.
An explicit asset catalog supplies opaque publication paths, legacy URL aliases, refresh sources and
readiness requirements. These are private implementation interfaces, not new
consumer configuration.

Clients download rule assets directly from the publisher's pinned IPv4 while
retaining the gateway hostname for HTTPS verification. Downloads do not depend
on a selected VPN. MRS refresh validates the declared domain/IP behavior with
the stock Mihomo parser before replacing the persistent cache.

Public rule assets live in persistent state; credentials and
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

AdGuard Home, Unbound and NaiveProxy each allow one active instance per machine;
their native services or Caddy integration are singletons. Disabled instances
do not claim that slot. Private DNS validation and policy rendering are isolated
in a pure internal module; the AdGuard integration retains assertions on the
final effective configuration after NixOS option merging.

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

The publisher accepts a consumer-owned list of DoH endpoints with numeric
bootstrap addresses. Mihomo uses all endpoints for ordinary and proxy-server
DNS; sing-box races the own DoH responses. Neither client profile includes a
public DNS reserve. Endpoint connection does not depend on resolving its own
hostname through another server or on the selected VPN. If every endpoint is
unavailable, queries needing upstream resolution fail; existing cache, static
records and fake-IP policy remain separate. The consumer owns equivalent
filtering, private DNS records and reachability on every endpoint. Omitting the
list preserves a single own DoH from the publisher's edge domain and public IP.
The server-side AdGuard reserve remains independent of client endpoint failover.

## Verification boundary

Runtime support is `x86_64-linux`. Repository checks evaluate schemas, contracts,
generated configurations and combined Clan composition without running services
or application parsers. See [verification](operations/verify.md) for the gate,
artifacts and limits of its evidence.
