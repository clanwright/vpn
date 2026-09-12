# Public contracts

## Clan modules

Consumers select modules through `clan.modules` and configure their roles using
the settings documented on each module page.

| Stable module ID | Settings and integration |
| --- | --- |
| `@clanwright/vpn-mihomo-vless-xhttp` | [VLESS/XHTTP](../clanServices/mihomo-vless-xhttp/README.md) |
| `@clanwright/vpn-mihomo-hysteria2` | [Hysteria2](../clanServices/mihomo-hysteria2/README.md) (**deprecated**; retained for compatibility) |
| `@clanwright/vpn-amneziawg` | [AmneziaWG](../clanServices/amneziawg/README.md) |
| `@clanwright/vpn-naiveproxy` | [NaiveProxy](../clanServices/naiveproxy/README.md) |
| `@clanwright/vpn-mieru` | [Mieru](../clanServices/mieru/README.md) |
| `@clanwright/vpn-anytls` | [AnyTLS](../clanServices/anytls/README.md) |
| `@clanwright/vpn-client-profiles` | [Client profiles](../clanServices/vpn-client-profiles/README.md) |
| `@clanwright/dns-adguardhome` | [AdGuard Home](../clanServices/adguardhome/README.md) |
| `@clanwright/dns-unbound` | [Unbound](../clanServices/unbound/README.md) |

The VLESS module ID contains `mihomo` for identity stability; its runtime is Xray.
Hysteria2 is discouraged for new use after user-reported blocking of client
connections.

## Exports and helpers

| Flake attribute | Contract |
| --- | --- |
| `clan.exportInterfaces` | `vpnProvider` and `vpnPublisher` typed interfaces. |
| `clanModule` | Nix module registering the export interfaces. |
| `lib.exportInterfaces { lib }` | Constructs the interface definitions. |
| `lib.vpnExports { lib }` | Closed provider/publisher types and projections. |
| `lib.awgValidation { lib }` | AmneziaWG option and package-family validation. |

Provider and publisher schemas reject unknown fields. Their definitions are in
[the export schema](../modules/contracts/vpn-exports.nix); modules and checks
use the same definitions. Provider selection derives the required role from the
protocol; callers do not supply a separate role mapping.

`vpnProvider` uses schema version 2; `vpnPublisher` uses version 1. AWG peer
public keys have one canonical representation in `transportMetadata.peers`.
Each AWG peer supplies `clientPrivateKeySecretName`; its exact consumer binding
is exported through `secretNames.clientPrivateKey`.

Mieru extends provider version 2 with protocol `mieru` and role `gateway`.
Its endpoint requires numeric IPv4 and TCP; `domain = null` is permitted only
for Mieru. Existing protocols still require their domain field. Its exact
transport metadata contains `protocol`, `userNames` and
`credentialEncoding = "base64url"`; `secretNames.users` maps those identities
to consumer-owned secrets. No TLS or arbitrary transport attributes are accepted.
Clients require an updated publisher to consume the new protocol; existing
provider exports retain their schema and behavior.

AnyTLS also extends provider version 2, with protocol `anytls` and role
`gateway`. Its TCP endpoint requires both domain and numeric IPv4. Exact
transport metadata includes the catalog protocol, `userNames`, `tlsServerName`,
`tlsVerify = true`, `tlsMinVersion = "1.3"` and
`credentialEncoding = "base64url"`; `secretNames.users` binds each device to
its consumer-owned password secret. TLS 1.3 is enforced by the server.
Both Mihomo and sing-box publishers support this provider, including UDP via
UoT v2. Consumers must update their publisher before selecting AnyTLS exports.

The AnyTLS gateway requires a consumer-owned `dnsEndpoint` with `domain`,
public `ipv4`, optional `port` (443) and `path` (`/dns-query`). It uses only
that own DoH endpoint, retaining its verified hostname while connecting to
the numeric address. System DNS configuration is independent, with no local
or third-party resolver fallback. Private/reserved IPv4 endpoints are rejected;
the process egress guard has no DNS exceptions into internal networks.

Consumers must use public attributes, without importing internal files under
`modules/`, `packages/`, `checks/` or `clanServices/`. Extending the interface
requires an explicit contract change. Application packages are selected by this
flake; see [package authority](package-authority.md).

## Consumer bindings

Secret values are runtime inputs. The consumer owns credential generation,
SOPS bindings and declared runtime paths. Module pages specify each secret's
format; literal template substitution does not escape arbitrary values.

The consumer also supplies addresses, interfaces, certificates, Caddy site
claims and personal domain/filter rules. Direct Xray, Hysteria2 and AmneziaWG scoped
ingress requires an enabled nftables firewall; those roles assert that backend.

Xray's optional `localListener` binds only to IPv4 loopback behind a
consumer-owned TCP passthrough entry. Its public `bindIPv4`, `domain` and `port`
continue to define the provider endpoint; provider schema version 2 is unchanged.
The local mode creates no ingress firewall rule. SNI routing, public exposure
and web-server composition belong to the consumer; TLS must reach Xray intact.

Hysteria2 requires the NixOS option
`clanwright.vpn.hysteria2.masqueradeRoot` to name an absolute Nix store directory
containing public static content. NaiveProxy requires one explicit listener on
its selected public-site claim, matching the declared bind address. The consumer
supplies AdGuard's Unbound upstream binding and any systemd startup relationship
between the two services.

AdGuard exposes private DNS through typed `dns.privateZones` and `dns.rewrites`.
Each zone declares canonical lowercase ASCII suffixes and numeric private
resolvers; each rewrite source and CNAME target is covered by those zones, or
the answer is a private numeric address. The schema rejects empty groups,
duplicates, public endpoints or answers, loops, wildcards,
rewrite chains and unsafe user-rule overrides. Private routes occur in both
AdGuard upstream paths: failures may try another resolver in the same zone but
never fall through to ordinary public resolution.

`filtering.enable` controls AdGuard's `protection_enabled` flag. The filtering
engine and native rewrites remain enabled so a declarative protection pause
does not disable private aliases. Consumer `filtering.userRules` remain the
allow/deny extension point; `dnsrewrite`, `badfilter` and `important` modifiers
are rejected while private zones are configured because they could bypass or
out-prioritize the typed closure. After native typed rewrites are considered,
generated `@@||<zone>^$important,dnsrewrite` followed by
`@@||<zone>^$important` protect DNS rewrite closure and ordinary zone exceptions
from consumer rules.

The consumer also trusts the enabled remote filter content. A more-specific
important block from such a feed can still block a direct private-name query;
repository evaluation does not assert that current feeds contain no conflict.
This affects answer availability, not the closed private forwarding route.

AdGuard and the profile publisher do not create Network claims, ACME bindings
or Tailscale ordering. Their read-only NixOS integration outputs expose runtime
endpoints and paths for consumer composition:

- `clanwright.dns.adguardhome.integration`: version 1, `uiBackend`,
  `dohBackend` (including TLS server name), and `reloadUnits`; null when disabled.
- `clanwright.vpn.publishers.<instance>`: version 1, consumer-supplied gateway
  domain, publication and public-asset
  paths, static route configuration, reader group, unit names and update status.

The consumer owns host names, bind addresses, certificate permissions, Caddy
claims and private access to the links page. It grants Caddy the exported reader
group and uses the publisher's static route configuration with access logging
suppressed. Tokenized request URIs must never enter access logs.
Each active publisher has a distinct runtime label and gateway domain on its
machine; one static route configuration belongs to one Caddy virtual host.

The profile renderer is internal. Consumers use the publisher role and its
integration output rather than importing renderer files. See the
[migration procedure](operations/migrate-contracts.md) for the breaking changes.

Roles with an `enable` setting use it alone to control their declarations.
Disabled roles do not retain service or secret declarations; credential storage
remains consumer-owned.
Protocol policy with a single supported value is fixed by the implementation.
The VLESS XHTTP export accepts only `mode = "auto"`, matching provider selection
and client rendering. Identity and secret-name rules share the same contract
definitions across provider roles and exports.

AdGuard Home, Unbound and NaiveProxy permit at most one active instance per
machine. A disabled instance does not reserve the native service or emit its
secret declarations. Unbound's `enable` defaults to `true`; existing resolver
settings therefore keep their enabled behavior when this setting is omitted.

## Published profiles

| Path template | Behavior |
| --- | --- |
| `/<token>/mihomo.yaml` | Selective routing in Rule mode. |
| `/<token>/mihomo-full.yaml` | Full routing in Rule mode with private DIRECT exceptions. |
| `/<token>/profile.json` | sing-box Rule/Global modes with separate TCP/UDP selectors; present with an eligible Naive, Hysteria2 or AnyTLS provider. |

These are templates, not live profile URLs. Per-device eligibility, DNS and
routing policy are documented in [client profiles](../clanServices/vpn-client-profiles/README.md).
Generated provider names use canonical machine identities without shortening
machine-name suffixes.

Publisher `profiles[].autoProtocols` controls only automatic selection and probes; manual
compatible connections remain published. Its default includes all supported
protocols for compatibility. An empty list disables automatic selection.
Exclude `amneziawg` to keep AWG manual without background probes or keepalive.
Rule assets use opaque canonical paths while previous URL paths remain aliases.
These aliases preserve rule downloads for already-issued profiles; subscription
token paths and output filenames are unchanged.

AdGuard exposes independent booleans `filtering.safeSearch` (default `true`)
and `filtering.youtubeRestrictedMode` (default `false`). The consumer applies
the same settings to its DNS instances when equivalent filtering is required.

Publisher `clientDnsEndpoints` accepts a nonempty typed list of consumer-owned
DoH endpoints (`domain`, `ipv4`, optional `port` and `path`). It replaces the
implicit single endpoint; the default `null` retains the publisher's own edge
domain/public IPv4. Both formats use only the selected own DoH for upstream DNS,
without a public reserve. Endpoint bootstrap and TLS identity remain distinct.
The consumer owns equivalent filtering and private DNS on every server; checks
prove generated configuration contracts, not runtime failover or filter parity.
