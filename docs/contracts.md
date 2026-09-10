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
| `lib.clientProfiles { config, lib, pkgs, settings, gatewayProfiles }` | Profile renderer with repository-owned package selection. |

Provider and publisher schemas reject unknown fields. Their definitions are in
[the export schema](../modules/contracts/vpn-exports.nix); modules and checks
use the same definitions.

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
its selected public-site claim, matching the declared bind address. Unbound's
optional AdGuard integration requests startup with `Wants=`; the consumer must
still supply AdGuard's upstream binding.

## Published profiles

| Path template | Behavior |
| --- | --- |
| `/<token>/mihomo.yaml` | Selective routing in Rule mode. |
| `/<token>/mihomo-full.yaml` | Full routing in Rule mode with private DIRECT exceptions. |
| `/<token>/profile.json` | sing-box Rule/Global modes with SELECTIVE/FULL selectors; present only with an eligible Naive provider. |

These are templates, not live profile URLs. Per-device eligibility, DNS and
routing policy are documented in [client profiles](../clanServices/vpn-client-profiles/README.md).
