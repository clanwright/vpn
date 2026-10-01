# Architecture

The nine modules are independently selectable and share one versioned flake.
Their public entrypoints are listed in [contracts](contracts.md).

## Ownership

| Repository | Consumer |
| --- | --- |
| Service implementation and defaults | Placement and composition |
| Typed provider exports | Machine facts and secret bindings |
| Exact application packages | Exposure, certificates and native Caddy sites |
| Module and integration contracts | Operator entrypoints, monitoring and deployment |

The flake does not import a consumer checkout. TCP tuning belongs to the consumer.

## VPN services

- VLESS/REALITY with XHTTP runs in Xray, either directly on its public endpoint
  or on an optional loopback listener behind consumer-owned TCP passthrough.
  Public profile addresses and ports are independent of that local listener;
  the consumer owns shared-port SNI routing and HTTPS composition.
- AmneziaWG runs as a userspace generation-3 UDP gateway with a runtime
  header-protection key and individual peer keys.
- NaiveProxy extends a native Caddy vhost selected by canonical domain with
  `forwardProxy = true` and a full authenticated CONNECT route at order 500.
  The consumer owns the base site, exact IPv4/TCP443 listener, aliases and
  physical certificate ID. Root catch-all attaches CONNECT once automatically;
  consumers attach the same fragment inside named canonical/alias Host routes
  on the public listener that could shadow an allowed target. Ordinary sites
  retain GET/certificate bases and do not become forwardProxy sites. Network supplies the
  sole specialized Caddy package; advertised public IPv4 and actual bind IPv4
  remain separate.
- Mieru runs stock native `mita` in its own service, with a TCP transport and
  UDP relay over TCP. It requires no domain or certificate. The process binds
  its port on wildcard addresses; module firewall guards restrict ingress to
  the consumer-selected IPv4 and restrict service-originated destinations.
  Consumer supplies the system resolver addresses and owns host DNS configuration.
  Mieru is selectable in the single Mihomo profile, including its ordinary Auto
  groups when permitted by the profile's `autoProtocols`. It is not exported
  to sing-box.
- AnyTLS uses native NixOS `services.sing-box`, `sing-box.service` and its
  Unix identity, accepting
  TCP on the consumer-selected IPv4 endpoint with TLS 1.3 only. Each device has
  its own runtime password. Default padding and session reuse are preserved;
  UDP uses UoT v2 inside TCP. Process-scoped network rules restrict new egress
  to public IPv4 destinations without private DNS exceptions. DNS uses only
  the consumer's own public DoH endpoint, pinned by IPv4 with verified hostname;
  it has no system or third-party resolver fallback. Consumer owns this endpoint,
  the certificate and placement; host DNS configuration stays independent. Both
  Mihomo and sing-box profiles include AnyTLS in ordinary manual and Auto
  selection when permitted by the consumer's existing policy.

- TrustTunnel runs stock endpoint 1.1.0 in its own service and Unix identity,
  accepting HTTP/2 on a consumer-selected IPv4 TCP endpoint. TCP and UDP travel
  inside H2; HTTP/3 and ICMP are disabled. Each device has a runtime password,
  and invalid authentication receives HTTP 404. The endpoint uses a verified
  TLS identity, but does not serve a cover website on the tunnel hostname.
  Native destination checks and process-scoped network rules deny internal
  destinations; address-family restrictions and an IPv6 egress rule enforce
  IPv4-only beyond the upstream `ipv6_available` flag. DNS uses the host resolver;
  the consumer directs that resolver to its own AdGuard and supplies numeric
  DNS addresses for narrow process-guard exceptions. Host DNS stays consumer
  owned. Mihomo profiles include TrustTunnel in manual and policy-controlled
  Auto selection, including protected UDP; official sing-box has no matching
  outbound. See the [module](../clanServices/trusttunnel/README.md).

Provider modules publish schema 3 through a shared closed native type, with
exactly one `connection` tag and its client-facing payload. Clan scope supplies
service, role, machine and instance identity. The publisher selects accounts
through explicit profile-to-account maps; protocol policy stays internal.

The private publisher compiler owns the settings interface, normalization,
provider selection and per-device account bindings. Production and checks use
the same compiler; it returns validated settings and the artifact manifest.
The renderer returns only that manifest.
It renders one Mihomo profile and publishes a sing-box profile
for devices with an eligible Naive or AnyTLS provider or a selected external
subscription. Personal proxy domain additions come from the consumer.

The publisher separates manual availability from automatic protocol selection.
Both formats expose the same `Ручной` and `Авто` groups and connection names;
UDP follows the manual selection and protected UDP is rejected, never sent
DIRECT, when the selected connection lacks UDP. Both formats configure
local IPv6 and Tailscale exceptions and an explicit external IPv6 rejection rule.
An early `.ru` DIRECT exception follows that rejection and precedes protected
routing in both formats and sing-box Global routing; Mihomo Global mode
bypasses rules. `.ru` uses real DNS answers rather than
FakeIP; sing-box resolves it with `ipv4_only` through ordinary DNS rules before
DIRECT. MetaCubeX AI and GitHub feeds join the existing protected TCP/UDP policy.
Sing-box enables automatic TUN routing without explicit included or excluded
route lists. Local route precedence and concurrent SFM/Tailscale compatibility
remain part of [client acceptance](operations/sing-box-client.md#sfm-tailscale-and-lan-routing-acceptance),
including external IPv6 rejection on the device.

Rendering produces an internal artifact manifest: client templates, output
formats, structural secret bindings and required public assets. The runtime
publisher reads that manifest without knowing protocol-specific client fields.
An explicit asset catalog supplies opaque publication paths, refresh sources and
readiness requirements. The 11 historical asset-path aliases are retired by
[ADR-0001](adr/0001-retire-asset-path-aliases.md); canonical assets and native
host aliases are preserved. These are private implementation interfaces, not new
consumer configuration. Checks derive their views from the canonical manifest;
there are no NixOS render, manifest or publication-phase projections.

External subscriptions are publisher inputs, not Clan provider exports.
The consumer selects source IDs, SOPS URL-secret bindings and explicit device
profiles. A runtime adapter extracts supported Xray connection tuples and
composes client-specific outbounds and selectors through the manifest. It
does not import upstream DNS, routing or inbounds. External Auto eligibility
is separate from the own-provider protocol policy. Subscription credentials
and accepted snapshots stay private under `/run`, separate from public assets.

External subscriptions retain a bounded publisher loop and due-source
round-robin because accepted-at TTL, retries, auth rotation, atomic global
withdrawal and publication of own providers before remote fetch share lifecycle
state. Public asset mirrors use native timers. The `65 * sourceCount + 30` TTL
holdback is conservative policy; its reserve is not a measured hard deadline.
External sing-box connections intentionally retain first-own-DoH bootstrap
policy; no race/failover behavior is claimed for that path.

Clients download rule assets directly from the publisher's pinned IPv4 while
retaining the gateway hostname for HTTPS verification. Downloads do not depend
on a selected VPN. MRS refresh validates the declared domain/IP behavior with
the stock Mihomo parser before replacing the persistent cache.
The AI/GitHub Mihomo assets use classical text to retain regex rules, with the
existing nonempty validator; syntax acceptance remains consumer-owned. Their
sing-box counterparts use binary SRS validation. Both formats reference those
assets through the catalog and require them before publication; new assets
have opaque canonical paths without legacy aliases.

Public rule assets live in persistent state; credentials and
token-named publication paths live only under `/run`. Initial publication waits
for a complete required asset set. Refresh failures retain accepted public
assets without a hard expiry and expose nonsecret status for consumer monitoring.

A publication refresh withdraws the old profile generation before rendering
and exposes a complete generation only on success. Failed refreshes cannot keep
serving revoked credentials. Caddy uses static routes and does not require,
restart or reload for the publisher. The consumer supplies native sites, grants
the exported reader group and restricts access to the links page. Access logging
of tokenized URIs is suppressed.

The native publisher integration is schema 2: site-level `logConfig` preserves
unconditional `log_skip` before alias responses at order 1000, including
configured aliases. Its complete matcherless `routeConfig` keeps canonical
host/path guards inside and attaches at order 1500. Native order is explicit
CONNECT 500, aliases 1000, publisher 1500 and terminal fallback 2000. Consumers
merge context-bearing fragments without parsing or unwrapping their contents.

Network owns native Caddy/ACME composition, stable physical certificate IDs
and the sole specialized Caddy package; native ACME/Lego retains certificate
authority. The released Network input must support the exported seam before
consumer adoption. Qualification and runtime limits have one owner:
[verification](operations/verify.md#evidence-and-runtime-acceptance).

TrustTunnel’s retained 15-second `/proc` readiness probe requires positive
MAINPID ownership of the exact listener socket. Upstream 1.1.0 uses
`Type=simple` without notify support; native `Type=exec` establishes execution
and failure behavior, not that positive ownership. This requirement is
independent of Mieru’s RPC readiness behavior.

## DNS

AdGuard Home provides the DNS/DoH front end. Its normal upstream is loopback
Unbound, bound explicitly by the consumer. The consumer also owns any systemd
startup relationship between AdGuard and Unbound. The AdGuard role configures a
loopback dnsproxy reserve: parallel encrypted providers, followed by plaintext
providers only after encrypted exchange failures. Received NXDOMAIN or SERVFAIL
does not activate the plaintext tier.
AdGuard's timeout applies separately to primary and fallback attempts; it is
not a total client deadline. The [retry-aware timing contract](../clanServices/adguardhome/README.md#timeout-contract)
reserves time for the warm encrypted-to-plaintext cascade and declares an
isolated silent-failure acceptance budget. Clanwright measures final A/AAAA
answers and elapsed time; source assertions do not prove runtime failover.

AdGuard Home, Unbound, NaiveProxy and AnyTLS each allow one active instance per machine;
their native services or Caddy integration are singletons. Disabled instances
do not claim that slot. Private DNS validation and policy rendering are isolated
in a pure internal module; the AdGuard integration retains assertions on the
final effective configuration after NixOS option merging.

AdGuard’s optional native `systemResolver.enableLocalStub` role capability and
current default preserve host DNS behavior through NixOS resolver options.
There is no repository-owned `resolv.conf` writer.

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
