# Public contracts

The stable service surface is `clan.modules`, with exactly seven module IDs:

| Module ID | Role |
| --- | --- |
| `@clanwright/vpn-mihomo-vless-xhttp` | VLESS/XHTTP gateway |
| `@clanwright/vpn-mihomo-hysteria2` | Hysteria2 gateway |
| `@clanwright/vpn-amneziawg` | AmneziaWG gateway |
| `@clanwright/vpn-naiveproxy` | Caddy forward-proxy add-on |
| `@clanwright/vpn-client-profiles` | profile publisher |
| `@clanwright/dns-adguardhome` | DNS/DoH front end |
| `@clanwright/dns-unbound` | recursive DNS backend |

Consumers select these IDs through their catalog and pass only documented Clan
role settings. Module identities and existing settings/defaults are compatibility
surface for `v0.1.0`.

The flake also exposes these helper libraries:

| Attribute | Contract |
| --- | --- |
| `lib.vpnExports { lib }` | Closed provider and publisher export types and projections. |
| `lib.awgValidation { lib }` | AmneziaWG option and package-family validation. |
| `lib.awgPublicKeyCheck { pkgs }` | Build-time public/private key consistency check helper. |
| `lib.clientProfiles { config, lib, pkgs, settings, gatewayProfiles }` | Profile-rendering implementation used by the publisher and checks; domain package authority is applied internally. |

Unknown provider fields are rejected at the typed boundary. A consumer must not
import files below `modules/`, `packages/`, `checks/` or `clanServices/` to
extend this surface. A missing capability requires a reviewed public-contract
change and a new release.

Secret values are outside this contract. Modules accept declared runtime paths
and metadata from the consumer; they do not own, generate or publish consumer
credentials.
