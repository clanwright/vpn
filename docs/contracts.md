# Public contracts

## Clan modules

Consumers select modules through `clan.modules` and configure their roles using
the settings documented on each module page.

| Stable module ID | Settings and integration |
| --- | --- |
| `@clanwright/vpn-mihomo-vless-xhttp` | [VLESS/XHTTP](../clanServices/vless-xhttp/README.md) |
| `@clanwright/vpn-amneziawg` | [AmneziaWG](../clanServices/amneziawg/README.md) |
| `@clanwright/vpn-naiveproxy` | [NaiveProxy](../clanServices/naiveproxy/README.md) |
| `@clanwright/vpn-mieru` | [Mieru](../clanServices/mieru/README.md) |
| `@clanwright/vpn-anytls` | [AnyTLS](../clanServices/anytls/README.md) |
| `@clanwright/vpn-trusttunnel` | [TrustTunnel](../clanServices/trusttunnel/README.md) |
| `@clanwright/vpn-client-profiles` | [Client profiles](../clanServices/vpn-client-profiles/README.md) |
| `@clanwright/dns-adguardhome` | [AdGuard Home](../clanServices/adguardhome/README.md) |
| `@clanwright/dns-unbound` | [Unbound](../clanServices/unbound/README.md) |

The VLESS module ID contains `mihomo` for identity stability; its runtime is Xray.

## Exports and helpers

| Flake attribute | Contract |
| --- | --- |
| `clan.exportInterfaces` | `vpnProvider` typed interface. |
| `clanModule` | Nix module registering the export interface. |
| `lib.exportInterfaces { lib }` | Constructs the interface definition. |

The closed provider schema is defined in
[the export schema](../modules/contracts/vpn-exports.nix). Modules and checks use
that same native Nix type: `schemaVersion = 3` and exactly one
`connection.<tag>` selected by `lib.types.attrTag`. Unknown fields, unknown tags,
multiple tags and older schemas are rejected. The publisher declares no exports.

`Endpoint` means `{ hostname; ipv4; port; }`, with a valid DNS hostname,
mandatory numeric IPv4 and port 1–65535. Mieru uses `{ ipv4; port; }`.
The publisher never substitutes its own address for a provider endpoint.

| Connection tag | Payload beyond `clients` | `clients.<account>` |
| --- | --- | --- |
| `naiveproxy` | `endpoint` | `passwordSecret` |
| `vless-xhttp` | `endpoint`, `reality = { serverName; publicKey; fingerprint; supportX25519MLKEM768; }`, `xhttp.path`, `doh = { hostname; ipv4; }` | `uuidSecret`, `shortId` |
| `amneziawg` | `endpoint`, `serverPublicKey`, `headerProtectionKeySecret` | `ipv4`, `privateKeySecret`, nullable `keepaliveSeconds` |
| `mieru` | numeric `endpoint` | `passwordSecret` |
| `anytls` | `endpoint` | `passwordSecret` |
| `trusttunnel` | `endpoint` | `passwordSecret` |

Client keys are the actual provider authentication accounts or device/peer IDs;
secret fields contain consumer-owned SOPS binding names, never values. VLESS
short IDs are exactly 16 lowercase hex digits. Server private-key bindings,
AWG peer public keys and server-only configuration stay in provider settings.
Fixed protocol policy is internal: XHTTP `auto`, AWG generation 3 and MTU 1280,
AnyTLS verified TLS 1.3 with UoT v2, Mieru TCP relay and TrustTunnel verified H2.
VLESS effective fingerprint/MLKEM policy and DoH pinning hints are retained;
AWG nullable keepalive semantics are unchanged. VLESS retains the three
supported fingerprint choices and endpoint MLKEM opt-in because they select
supported client features per endpoint. Chrome with MLKEM remains the deployment
recommendation; changing protocol policy or existing consumers is separate work.

Selection obtains machine, instance, service and role identity from Clan's
native export scope. It requires exactly one matching export from a known
provider service/role and checks that its connection tag matches that scope.
Scope identity is not duplicated in the exported payload.

Publisher `providerRefs` contain `machine`, `instanceId`, a nonempty
`clients = { <publisher-profile> = "<provider-account>"; }` map and optional
`display`. Every profile and account must exist. A provider account cannot be
assigned to multiple profiles within a ref; duplicate refs are rejected.
There is no `protocol` discriminator or empty-list selection of all accounts.
External subscription `profileNames` remain a separate explicit source input.
See [migration](operations/migrate-contracts.md).

AnyTLS requires a consumer-owned public `dnsEndpoint` with domain, numeric IPv4,
optional port (443) and path (`/dns-query`). Its native sing-box singleton uses
only that pinned, verified DoH endpoint; host resolver configuration remains
independent. The process guard has no private DNS exceptions. Both Mihomo and
sing-box support the provider. Consumers must reserve the native sing-box
service/settings/user namespace for this module.

TrustTunnel requires explicit `dnsResolverIPv4s` for narrow TCP/UDP port 53
exceptions in its process guard. This list does not configure the host resolver.
The consumer owns its effective resolver and fallback policy. Native destination
checks deny tunneled access to internal DNS addresses, and process restrictions
enforce IPv4-only. It is exported to Mihomo; official sing-box has no matching
outbound.

Consumers must use public attributes, without importing internal files under
`modules/`, `packages/`, `checks/` or `clanServices/`. Extending the interface
requires an explicit contract change. Application packages are selected by this
flake; see [package authority](package-authority.md).

## Consumer bindings

Secret values are runtime inputs. The consumer owns credential generation,
SOPS bindings and declared runtime paths. Module pages specify each secret's
format; literal template substitution does not escape arbitrary values.

The consumer also supplies addresses, interfaces, certificates, Caddy site
claims and personal domain/filter rules. Direct Xray and AmneziaWG scoped
ingress requires an enabled nftables firewall; those roles assert that backend.

Xray's optional `localListener` binds only to IPv4 loopback behind a
consumer-owned TCP passthrough entry. Its public `bindIPv4`, `domain` and `port`
continue to define the provider endpoint; the schema 3 endpoint remains public.
The local mode creates no ingress firewall rule. SNI routing, public exposure
and web-server composition belong to the consumer; TLS must reach Xray intact.

NaiveProxy requires explicit `domain`, advertised `publicIPv4` and actual
`bindIPv4`. The native `services.caddy.virtualHosts.<domain>` must have one
existing base owner and exactly `[ bindIPv4 ]` on TCP `443`; it is the only
vhost with `forwardProxy = true`, with native Caddy `httpsPort = 443`. Network
owns the unique base-owner/extension contract. The addon does not redeclare the site owner,
listeners, aliases or physical certificate ID. Its read-only
`clanwright.vpn.naiveproxy.connectRoute` is the complete authenticated CONNECT
fragment, including the same runtime authentication, ACL and probe-resistance
import and internal method/address/443
guards inside a matcherless outer route. The selected root catch-all receives
one automatic attachment at order 500. Consumers explicitly attach the same
fragment with `lib.mkBefore` inside each named canonical/alias native Host route
on the selected public listener that can shadow an allowed CONNECT target.
Outer terminal Host precedence is separate from inner order 500. Authentication
is listener-wide, not a TLS SNI allowlist; the destination authority port is
not the local listener port. The local-port expression uses numeric `== 443`,
not a quoted string; source adaptation alone does not prove its effective type.
Local bind/443 guards retain private, mixed and
disjoint listener boundaries. Ordinary sites do not set `forwardProxy = true`;
site ownership, hostName, certificates, listeners and GET remain unchanged.
There is no scanner or registry. Its provider
export lists each `passwordSecretNames` authentication identity as a key in
`connection.naiveproxy.clients` with its password binding. The consumer
supplies AdGuard's Unbound upstream binding and any systemd startup relationship
between the two services.

AdGuard's typed `dns.upstreamTimeoutSeconds`, `dns.fallbackTimeoutSeconds` and
`dns.silentFailureBudgetSeconds` describe a retry-aware silent-upstream timing
model: `5F + 1 <= A` and `4A + 1 <= B`, with defaults `A=16`, `F=3`, `B=65`
seconds. The budget is a consumer acceptance envelope, not an application
deadline for every client request. See the [scope, source evidence and
tradeoff](../clanServices/adguardhome/README.md#timeout-contract) and
[Clanwright acceptance](operations/adguardhome.md#consumer-runtime-acceptance-specification).

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

AdGuard and the profile publisher do not create Caddy sites, ACME bindings
or Tailscale ordering. Their read-only NixOS integration outputs expose runtime
endpoints and paths for consumer composition:

- `clanwright.dns.adguardhome.integration`: version 1, `uiBackend`,
  `dohBackend` (including TLS server name), and `reloadUnits`; null when disabled.
- `clanwright.vpn.publishers.<instance>`: version 2, consumer-supplied gateway
  domain, publication and public-asset paths, site-level `logConfig`, complete
  `routeConfig`, reader group, unit names and update status.

The consumer owns host names, bind addresses, certificate permissions, Caddy
sites and private access to the links page. It grants Caddy the exported reader
group and attaches `logConfig` at site level before alias responses at order
1000. Its unconditional `log_skip` covers canonical and configured alias requests.
`routeConfig` is a matcherless outer `route` with canonical-host/path guards
inside, attached at order 1500 before terminal fallback at 2000. Consumers
compose the context-bearing fragments without parsing, unwrapping or rerendering
them. Tokenized request URIs must never enter access logs.
Each active publisher has a distinct runtime label and gateway domain on its
machine; one static route configuration belongs to one Caddy virtual host.

Native composition qualification and outstanding runtime acceptance are defined
in [verification](operations/verify.md#evidence-and-runtime-acceptance).

The profile renderer is internal. Consumers use the publisher role and its
integration output rather than importing renderer files. See the
[migration procedure](operations/migrate-contracts.md) for provider schema 3 and
the separated publication/exposure contracts.

Consumers may use Access's public
`lib.tailscaleReadyGate { pkgs; ipv4; interface; }` for private-listener startup.
This optional integration is separately qualified in ignored consumer artifacts;
VPN has no shipped Access input, lock edge or mandatory fixture dependency.
When selected, effective native Tailscale retains Access package authority and
the finite helper attaches to ordinary native `ExecStartPre` for the selected
IPv4/native interface, without a reload hook, watcher, privileged prefix or
sandbox relaxation. The startup evidence boundary is defined in
[verification](operations/verify.md#evidence-and-runtime-acceptance).


The publisher accepts `externalSubscriptions.<sourceId>` with `urlSecretName`,
optional `label`, `format = "xray-json"`, explicit nonempty `profileNames`, `auto` (default true),
and per-source `refreshIntervalSeconds`, `retryIntervalSeconds`,
`maxStaleSeconds` (defaults 3600, 300, 86400). Source IDs and secret names use
the existing safe identity grammars. The URL and downloaded credentials are
runtime-only secrets; consumers supply the SOPS binding, never literal URLs
in Nix settings. External sources do not impersonate Clan provider exports or
extend their protocol enum. Import extracts compatible connections and keeps
the publisher's DNS/routing policy. See the
[subscription contract](../clanServices/vpn-client-profiles/README.md#external-subscriptions)
for the supported input combinations and update semantics.

Roles with an `enable` setting use it alone to control their declarations.
Disabled roles do not retain service or secret declarations; credential storage
remains consumer-owned.
Protocol policy with a single supported value is fixed by the implementation.
The schema 3 VLESS XHTTP payload contains only `xhttp.path`; `auto` is fixed
internal client-renderer policy, not an exported mode field. Identity and
secret-name rules share the same contract
definitions across provider roles and exports.

AdGuard Home, Unbound and NaiveProxy permit at most one active instance per
machine. A disabled instance does not reserve the native service or emit its
secret declarations. Unbound's `enable` defaults to `true`; existing resolver
settings therefore keep their enabled behavior when this setting is omitted.

## Published profiles

| Path template | Behavior |
| --- | --- |
| `/<token>/mihomo.yaml` | Selective routing in Rule mode; client Global mode uses the manual selection. |
| `/<token>/profile.json` | sing-box Rule/Global modes with the same selection groups; present with an eligible Naive or AnyTLS provider or a selected external subscription. |

These are templates, not live profile URLs. Per-device eligibility, DNS and
routing policy are documented in [client profiles](../clanServices/vpn-client-profiles/README.md).
Both formats expose `Ручной` with every published compatible connection,
including manual-only ones. When automatic candidates exist, `Авто` appears
first in `Ручной` and probes only connections admitted by `autoProtocols` or
auto-eligible external sources. With no candidates, `Авто` is omitted and
manual selection defaults to the first compatible connection. Neither selector
contains DIRECT. The group names are fixed. UDP follows the connection
selected in `Ручной`; protected UDP is rejected rather than sent DIRECT when that
connection lacks UDP. Mihomo also defines `GLOBAL` as `Ручной` and the
conditional `Авто`, so the
client Global mode never starts on DIRECT.

Connection names are client-visible labels, not identifiers. An optional
`providerRefs[].display = { label; country; countryCode; }` renders
`<flag> <country> · <label>`, where the flag comes from the uppercase ISO
alpha-2 `countryCode`; `country` and `countryCode` are set together. Without
`display`, the machine name is the label and no flag is shown. External nodes
use the subscription remark and `externalSubscriptions.<sourceId>.label`
(default: the source ID) as `<remark> · <label>`, or `<label>` without a remark.
Colliding names gain the protocol (`VLESS`, `AWG`, `Naive`, `Mieru`, `AnyTLS`,
`TrustTunnel`) or the external transport (`REALITY`, `XHTTP`), then an ordinal
from 2. External labels must differ from provider labels. Names never contain
instance IDs, profile names or hashes; secret bindings keep their own internal
identifiers.

The Mihomo profile and sing-box route `.ru` directly after local exceptions
and external IPv6 rejection, before protected TCP/UDP rules and, in sing-box,
before Global routing. Mihomo Global mode bypasses rules, including `.ru`. `.ru` is excluded from FakeIP; sing-box resolves it with `ipv4_only`
through its own DNS rules before selecting DIRECT. MetaCubeX `category-ai-!cn`
and `github` join the existing protected policy. Ordinary Rule-mode traffic
still defaults to DIRECT.
These are renderer defaults and add no publisher settings.

Publisher `profiles[].autoProtocols` controls only automatic selection and probes; manual
compatible connections remain published. Its default includes all supported
protocols for compatibility. An empty list excludes own providers from automatic selection; external
source `auto` eligibility remains independent.
Exclude `amneziawg` to keep AWG manual without background probes or keepalive.
Rule assets use stable opaque canonical paths. The 11 historical catalog aliases
are retired under [ADR-0001](adr/0001-retire-asset-path-aliases.md); old profiles
may lose asset refresh after future adoption. All 15 canonical assets, tokenized
profile endpoints, output filenames, private links and native host aliases
remain unchanged.
The new AI/GitHub assets use only opaque canonical paths: classical text in
Mihomo to retain regex rules and binary SRS in sing-box. Their required asset
references participate in the existing readiness guard. Classical text uses
the existing nonempty validator, which does not validate rule syntax.

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
