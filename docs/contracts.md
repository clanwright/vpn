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

Consumers select these IDs through their catalog and pass documented Clan
role settings and explicitly documented NixOS inputs. Module identities remain stable; the September candidate changes
settings and exports together where the new protocol contract requires it.
Consumer migration must use this candidate's documented schema.

The flake also exposes these helper libraries:

| Attribute | Contract |
| --- | --- |
| `lib.vpnExports { lib }` | Closed provider and publisher export types and projections. |
| `lib.awgValidation { lib }` | AmneziaWG option and package-family validation. |
| `lib.clientProfiles { config, lib, pkgs, settings, gatewayProfiles }` | Profile-rendering implementation used by the publisher and checks; domain package authority is applied internally. |

Unknown provider fields are rejected at the typed boundary. A consumer must not
import files below `modules/`, `packages/`, `checks/` or `clanServices/` to
extend this surface. A missing capability requires a reviewed public-contract
change and a new release.

Secret values are outside this contract. Modules accept declared runtime paths
and metadata from the consumer; they do not own, generate or publish consumer
credentials.

The publisher exposes a selective Mihomo configuration at `/<token>/mihomo.yaml`
and a full configuration at `/<token>/mihomo-full.yaml`. Both use Rule mode so
private DIRECT exceptions precede the final routing decision. The sing-box
`/<token>/profile.json` uses native Rule/Global mode matching with separate
SELECTIVE/FULL selectors. These are path templates, not live profile URLs.
The sing-box profile is published only when the device has an eligible Naive
provider. Otherwise its file, handler and link are absent; the publisher does
not offer a direct-only configuration as a VPN profile.

Consumer `personalProxyDomains` supplies persistent domain suffix additions
without a `+.` prefix. No personal domain list is compiled into the library.

The owner accepted primary AdGuard-only DNS for Mihomo on 9 September 2026.
Mihomo has no client DNS fallback or additional local resolver; an AdGuard
outage leaves new queries without a usable cached answer unresolved. The
sing-box client retains its strict DNS cascade, and the server-side dnsproxy
reserve remains separate.

Xray, Hysteria and AWG scoped ingress requires the consumer's enabled nftables
firewall. These roles assert the selected backend; they do not silently change
the consumer's firewall implementation.

Hysteria accepts the consumer's static content through the NixOS option
`clanwright.vpn.hysteria2.masqueradeRoot`, a required absolute Nix store
directory path when the service is active. It renders a native `file://`
masquerade without selecting, copying or fetching a site. The consumer owns
the path and public contents; VPN does not depend on a site module or a web
server. The former role setting `masqueradeUrl` is removed. See the
[module settings](../clanServices/mihomo-hysteria2/README.md#settings).

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
bounded stale policy. The effective directive set is closed: forwarding, local
answer synthesis, RPZ and other freeform extensions are rejected, and remote
control remains disabled. The optional AdGuard integration requests backend startup
with `Wants=` and adds no backend readiness wait or hard service dependency.
The consumer still supplies the AdGuard upstream binding explicitly.

The AdGuard role's admin secret now contains a single bcrypt hash rather than
a plaintext password. The consumer owns hash generation and the SOPS binding;
the value must be a valid bcrypt token without whitespace or a terminal newline.
SOPS templates perform literal substitution, so arbitrary strings are outside
this contract. The hash is inserted only at runtime, passed through a systemd
credential and copied into AdGuard's private working configuration. Restart
restores the declarative input; UI edits are temporary.

Personal DNS rules belong to the consumer's `filtering.userRules` list, empty by
default. The role does not expose a freeform AdGuard settings escape hatch:
listener, auth, filtering and cascade policy remain explicit typed contracts.

The same role manages the native dnsproxy reserve service. Its package belongs
to VPN's exact package set; the consumer does not supply a replacement binary.
The agreed plaintext reserve is Cloudflare, non-blocking Quad9 and Google and
must follow failure of all encrypted exchanges. Received NXDOMAIN or SERVFAIL
does not trigger that less protected tier. Public exposure and end-to-end
activation remain consumer responsibilities. Repository acceptance is pure Nix
evaluation and static hygiene; it does not include machine or runtime tests.
