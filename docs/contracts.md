# Public contracts

## Clan modules

Consumers select modules through `clan.modules` and configure their roles using
the settings documented on each module page.

| Stable module ID | Settings and integration |
| --- | --- |
| `@clanwright/vpn-mihomo-vless-xhttp` | [VLESS/XHTTP](../clanServices/mihomo-vless-xhttp/README.md) |
| `@clanwright/vpn-mihomo-hysteria2` | [Hysteria2](../clanServices/mihomo-hysteria2/README.md) |
| `@clanwright/vpn-amneziawg` | [AmneziaWG](../clanServices/amneziawg/README.md) |
| `@clanwright/vpn-naiveproxy` | [NaiveProxy](../clanServices/naiveproxy/README.md) |
| `@clanwright/vpn-client-profiles` | [Client profiles](../clanServices/vpn-client-profiles/README.md) |
| `@clanwright/dns-adguardhome` | [AdGuard Home](../clanServices/adguardhome/README.md) |
| `@clanwright/dns-unbound` | [Unbound](../clanServices/unbound/README.md) |

The VLESS module ID contains `mihomo` for identity stability; its runtime is Xray.

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

Consumers must use public attributes, without importing internal files under
`modules/`, `packages/`, `checks/` or `clanServices/`. Extending the interface
requires an explicit contract change. Application packages are selected by this
flake; see [package authority](package-authority.md).

## Consumer bindings

Secret values are runtime inputs. The consumer owns credential generation,
SOPS bindings and declared runtime paths. Module pages specify each secret's
format; literal template substitution does not escape arbitrary values.

The consumer also supplies addresses, interfaces, certificates, Caddy site
claims and personal domain/filter rules. Xray, Hysteria2 and AmneziaWG scoped
ingress requires an enabled nftables firewall; those roles assert that backend.

Hysteria2 requires the NixOS option
`clanwright.vpn.hysteria2.masqueradeRoot` to name an absolute Nix store directory
containing public static content. NaiveProxy requires one explicit listener on
its selected public-site claim, matching the declared bind address. The consumer
supplies AdGuard's Unbound upstream binding and any systemd startup relationship
between the two services.

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

## Published profiles

| Path template | Behavior |
| --- | --- |
| `/<token>/mihomo.yaml` | Selective routing in Rule mode. |
| `/<token>/mihomo-full.yaml` | Full routing in Rule mode with private DIRECT exceptions. |
| `/<token>/profile.json` | sing-box Rule/Global modes with SELECTIVE/FULL selectors; present only with an eligible Naive provider. |

These are templates, not live profile URLs. Per-device eligibility, DNS and
routing policy are documented in [client profiles](../clanServices/vpn-client-profiles/README.md).
Generated provider names use canonical machine identities without shortening
machine-name suffixes.
