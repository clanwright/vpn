# Adopt the revised integration contracts

This release changes provider schema 3, native AnyTLS, native Network/NaiveProxy
composition, publisher integration schema 2 and asset-path aliases. Use only
public attributes from [contracts](../contracts.md). Release publication,
consumer input adoption and deployment remain separately authorized operations.

## Provider schema 3

Upgrade all six providers and the publisher together. Schema 2 is rejected;
there is no compatibility adapter. Preserve the nine stable module IDs,
consumer SOPS bindings, per-device accounts, explicit path-token secrets and
publication URLs.

Replace each provider ref's `protocol` and `profileNames` with an explicit map:

```nix
providerRefs = [{
  machine = "gateway-a";
  instanceId = "vpn";
  clients = { laptop = "device-a"; phone = "device-b"; };
  display = { label = "A"; };
}];
```

Keys are declared publisher profiles; values are existing provider accounts.
Enumerate intended profiles explicitly, including identity mappings where needed.
Empty maps, unknown names, shared account assignments and duplicate refs fail.
External subscription `profileNames` remain unchanged.

Each export contains `schemaVersion = 3` and one native `connection.<tag>`.
`endpoint.domain` becomes `endpoint.hostname`; Mieru retains IPv4/port only.
Provider IPv4 is mandatory. Credential maps become `clients.<account>` bindings;
VLESS short IDs, REALITY client policy and DoH hints remain explicit. XHTTP
exports only its path; `auto` is fixed renderer policy. AWG exports client
addresses/private-key bindings, server public key and header-key binding;
server peer public keys remain provider settings. Preserve nullable keepalive.
Do not rotate credentials for this shape change. The
[payload table](../contracts.md#exports-and-helpers) is authoritative.

## Native AnyTLS

AnyTLS occupies native `services.sing-box`, `sing-box.service` and its Unix
identity with the exact stock package. Remove competing settings/inbounds and
namespace definitions before adoption; merged conflicts are rejected. Preserve
consumer certificate and password bindings, TLS 1.3/UoT policy and public own-DoH
endpoint. Source guards and consumer acceptance scenarios are documented in the
[AnyTLS module](../../clanServices/anytls/README.md) and [runbook](anytls.md).

## Publisher integration schema 2

Use `config.clanwright.vpn.publishers.<instance>` for the complete read-only
integration output. Attach `logConfig` at site level with `lib.mkBefore`, before
native alias responses at order 1000. Its unconditional `log_skip` covers
canonical and configured alias requests. Attach complete `routeConfig` with
`lib.mkAfter` at order 1500 before terminal fallback 2000. Preserve Nix string
context and artifact dependencies; do not parse, unwrap or rerender fragments.
The route has a matcherless outer block and canonical host/path guards inside.
There is no schema 1 compatibility output.

Preserve the existing two tokenized endpoints, private links, reader group,
distinct publisher runtime labels/gateway hosts and exposure policy. Caddy
remains independent of publisher readiness and profile-secret restarts. Existing
profile settings, explicit token bindings, DNS policy, manual/conditional Auto
selection and client Rule/Global modes retain their
[current contract](../../clanServices/vpn-client-profiles/README.md). This release
does not require a group rename or another profile/token migration.

## Native NaiveProxy and certificates

Replace `selectedPublicSiteClaim` and `selectedPublicSiteEndpoint` with required
`domain`, advertised `publicIPv4` and actual `bindIPv4`. Select the existing
native vhost by canonical `domain`, retain its base owner, aliases and physical
certificate ID, and declare exactly `[ bindIPv4 ]` on TCP `443`. The addon sets
the unique `forwardProxy = true` extension without repeating ownership. Native
Caddy uses `httpsPort = 443`; arbitrary-port support is outside this contract.

The complete read-only `clanwright.vpn.naiveproxy.connectRoute` attaches once
automatically to the selected root catch-all. Do not add a second root copy.
Attach the same fragment inside every named canonical/alias native Host route
on the selected public listener that can shadow an allowed target:

```nix
services.caddy.virtualHosts."cover.example.invalid".extraConfig =
  lib.mkBefore config.clanwright.vpn.naiveproxy.connectRoute;
```

Preserve native Host wrappers, aliases, base owners, hostName, certificates,
listeners and ordinary GET routes. Ordinary sites do not set `forwardProxy`.
Native merging retains the complete authentication, ACL, probe-resistance policy,
runtime import and string context. Outer terminal Host precedence is separate
from inner CONNECT order 500. Exact local bind/443 guards preserve private,
mixed and disjoint listeners. Destination authority port is independent of local
listener port; `{http.request.local.port} == 443` compares numerically. This is
listener-wide authentication, not a TLS SNI allowlist. No scanner, registry,
new listener or firewall opening is introduced.

Network owns native Caddy/ACME, the specialized Caddy package and producer
publication. Preserve stable physical certificate IDs, native reader targets
and ACME/Lego authority. Adopt a published compatible producer input, including
consumer nested edges, through a separately authorized change. Established
[AdGuard/DNS bindings](../contracts.md#consumer-bindings) remain unchanged.

## Asset-path alias retirement

[ADR-0001](../adr/0001-retire-asset-path-aliases.md) retires exactly 11 historical
catalog aliases. After adoption, old profiles using those paths may lose asset
refresh; unknown external use and that consequence are accepted. Preserve all
15 canonical asset/hash paths, both tokenized endpoints, private links and native
host aliases. The decision does not authorize adoption or deployment.

## Verification and delivery

Run the complete [repository gate and synthetic harness](verify.md), retain
artifacts and obtain review of the final source. Evaluate intended consumer
composition, native package authority, certificate permissions, static routing,
log suppression and private-links exposure. Runtime evidence follows the
single [PREDEPLOY boundary](verify.md#evidence-and-runtime-acceptance); source
checks do not establish startup, parser acceptance or network behavior.
