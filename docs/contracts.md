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

The Naive add-on accepts an identity-to-secret-name map; the former
`ibelyasov`, `bsv`, `probe` keys remain valid. `probeUserName` identifies the
probe account and excludes it from ordinary device profiles. Secret values must
be nonempty unpadded base64url strings without whitespace or a terminal newline.
The consumer's Clan vars generator owns this constraint: sops-nix templates do
literal runtime substitution and do not escape arbitrary Caddyfile tokens.

Naive uses a native `sops.templates` fragment and the existing Caddy reload
lifecycle. It has no dedicated generator, staging, refresh or rollback service.
The selected public-site claim must have one explicit listener matching the
declared bind address. `additionalDeny` accepts IP addresses/CIDRs only; hostname
denies are excluded because the pinned upstream matcher is case-sensitive.

The Unbound role accepts `listen.hosts = null` for automatic loopback selection:
IPv4 loopback plus IPv6 loopback when the host enables IPv6. An explicit list
must be nonempty and contain supported loopback IP literals; an explicit IPv6
listener conflicts with a host that disables IPv6. Ports must be in 1-65535.
The effective backend configuration retains loopback ACLs, DNSSEC validation and
bounded stale policy. The optional AdGuard integration requests backend startup
with `Wants=` and adds no backend readiness wait or hard service dependency.
The consumer still supplies the AdGuard upstream binding explicitly.
