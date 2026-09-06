# Clanwright VPN

Public VPN and DNS domain for an author-operated `x86_64-linux` Clan/NixOS
stack. The first release preserves seven independently selected service IDs:

- `@clanwright/vpn-mihomo-vless-xhttp`
- `@clanwright/vpn-mihomo-hysteria2`
- `@clanwright/vpn-amneziawg`
- `@clanwright/vpn-naiveproxy`
- `@clanwright/vpn-client-profiles`
- `@clanwright/dns-adguardhome`
- `@clanwright/dns-unbound`

The domain owns their implementation, defaults, public contracts, exact
application packages and checks. Consumers own composition, machine facts,
secret values and bindings, exposure policy, operator entrypoints, monitoring
and cross-domain integration.

`v0.1.0` is the first release. It keeps the existing shared
Mihomo runtime, profile formats, AdGuard-to-Unbound DNS path and AWG2-compatible
AmneziaWG parameters. It adds no HTTP/3 or other protocol change.

See [architecture](docs/architecture.md), [contracts](docs/contracts.md),
[package authority](docs/package-authority.md), and the
[verification procedure](docs/operations/verify.md).

## Support

Runtime modules and packages support `x86_64-linux`. Darwin outputs are limited
to developer and evaluation tooling required by the repository checks. The
repository has no hosted CI or automatic merging.

## Verification

Follow the [verification procedure](docs/operations/verify.md). It retains
stage logs, durations and a summary under the ignored `.work/verification/`
directory. A passing build is not deployment or live endpoint evidence.

## License

Licensed under the terms in [LICENSE](LICENSE).
