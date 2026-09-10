# Architecture

The seven modules are independently selectable and share one versioned flake.
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

- VLESS/REALITY with XHTTP runs in Xray.
- Hysteria2 runs in a separate Mihomo service with Gecko obfuscation and serves
  static masquerade content from a consumer-supplied store directory.
- AmneziaWG runs as a userspace generation-3 UDP gateway with a runtime
  header-protection key and individual peer keys.
- NaiveProxy contributes a Caddy `forward_proxy` fragment to a consumer-selected
  public site. The consumer supplies Network's Caddy package with the required
  plugins.

The profile publisher passes selected typed provider exports and per-device
bindings directly to its renderer.
It renders Mihomo selective/full profiles and publishes a sing-box profile only
for devices with an eligible Naive provider. Personal proxy domain additions
come from the consumer.

## DNS

AdGuard Home provides the DNS/DoH front end. Its normal upstream is loopback
Unbound, bound explicitly by the consumer. The consumer also owns any systemd
startup relationship between AdGuard and Unbound. The AdGuard role configures a
loopback dnsproxy reserve: parallel encrypted providers, followed by plaintext
providers only after encrypted exchange failures. Received NXDOMAIN or SERVFAIL
does not activate the plaintext tier.

Mihomo profiles use primary AdGuard DNS only. If AdGuard is unavailable, new
queries without a usable cached answer fail. The sing-box profile has its own
DNS cascade. The server reserve does not provide client failover around AdGuard.

## Verification boundary

Runtime support is `x86_64-linux`. Repository checks evaluate schemas, contracts,
generated configurations and combined Clan composition without running services
or application parsers. See [verification](operations/verify.md) for the gate,
artifacts and limits of its evidence.
