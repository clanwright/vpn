# Clanwright VPN

Seven VPN and DNS modules for Clan/NixOS on `x86_64-linux`.

| Module | Implementation |
| --- | --- |
| [VLESS/XHTTP](clanServices/mihomo-vless-xhttp/README.md) | Xray with REALITY |
| [Hysteria2](clanServices/mihomo-hysteria2/README.md) | Mihomo with Gecko obfuscation |
| [AmneziaWG](clanServices/amneziawg/README.md) | Userspace AmneziaWG 3 |
| [NaiveProxy](clanServices/naiveproxy/README.md) | Caddy forward proxy |
| [Client profiles](clanServices/vpn-client-profiles/README.md) | Mihomo and sing-box profile publisher |
| [AdGuard Home](clanServices/adguardhome/README.md) | DNS/DoH front end and dnsproxy reserve |
| [Unbound](clanServices/unbound/README.md) | Loopback recursive DNS backend |

The repository owns module implementations, defaults, typed contracts, exact
application packages and checks. Consumers own machine composition, secret
bindings, exposure policy, monitoring and deployment.

## Documentation

- [Architecture](docs/architecture.md): service layout and ownership.
- [Public contracts](docs/contracts.md): module IDs, exports and consumer integration.
- [Package authority](docs/package-authority.md): package sources and selection.
- [Verification](docs/operations/verify.md): local checks and retained artifacts.
- [Release](docs/operations/release.md): release procedure.

Module pages document settings and link to their operating procedures.
Documentation describes the checked-in implementation; it does not establish
which version a consumer has deployed.

## Support and verification

Runtime support is `x86_64-linux`. Other flake system outputs support developer
and evaluation tooling only. There is no hosted CI or automatic merging.

Verification uses pure Nix evaluation and static source checks with builders
and build jobs disabled. Application execution, runtime tests, virtual machines,
Linux builds and tests on deployed machines are outside repository verification.
Python code and test harnesses are prohibited.

## License

See [LICENSE](LICENSE).
