# TrustTunnel

`@clanwright/vpn-trusttunnel` provides the singleton `gateway` role. It runs
the stock TrustTunnel endpoint 1.1.0 as a dedicated `trusttunnel` user with one
TLS HTTP/2 listener. HTTP/2 carries both TCP and UDP tunnel traffic. The module
does not enable HTTP/1.1, QUIC/HTTP/3, ICMP, rules, reverse proxy, ping,
speedtest or metrics features.

## Settings

| Setting | Contract |
| --- | --- |
| `enable` | Enables the singleton service; defaults to `true`. |
| `bindIPv4` | Exact non-wildcard IPv4 listener and ingress destination. |
| `domain` | TLS hostname and exported client SNI. |
| `port` | TCP listener; defaults to `443`. |
| `acmeCertName` | Consumer-owned certificate name under `/var/lib/acme`. |
| `users` | Nonempty per-device `{ name, passwordSecretName }` list with unique identities and secrets. |
| `dnsResolverIPv4s` | Nonempty unique numeric IPv4 list which must exactly match the NixOS `networking.nameservers` option. |

Each password secret must contain exactly 1 through 64 raw, unpadded base64url
bytes (`A-Z`, `a-z`, `0-9`, `_`, `-`) with no newline. The values are validated
before startup and rendered only into `/run`; changing a password restarts the
service. Device names and secret names are exported, while password values and
live profile URLs remain runtime-only.

The certificate and key enter the unit through systemd credentials. ACME
renewal restarts the unit so both credential copies and the endpoint's loaded
host configuration change together. The endpoint's SIGHUP behavior is not used
because it reloads hosts but cannot refresh systemd's credential copies.

The service pins endpoint logging to `info`. Do not override it to `debug` or
`trace`: endpoint 1.1.0 debug formatting can expose authentication data.

Native private-destination denial remains enabled. A process-scoped nftables
guard additionally denies non-public IPv4 and all IPv6 egress after permitting
only TCP/UDP port 53 to the declared resolver addresses. The service sandbox
allows only IPv4 and Unix address families. Listener replies are explicitly
preserved before the egress denies, and firewall ingress is restricted to the
configured IPv4 and TCP port.

The option equality does not prove the process's actual NSS resolver path or
exclude resolver sources added by DHCP, systemd-resolved, or other consumer
configuration. The consumer verifies the effective resolver and fallback
behavior at runtime.

The provider export uses schema 2, protocol `trusttunnel`, transport `tcp`,
verified TLS, base64url credentials and `http2` upstream protocol. TrustTunnel
is exported for Mihomo profiles only; the official sing-box client renderer has
no TrustTunnel outbound.

See the [consumer integration and acceptance runbook](../../docs/operations/trusttunnel.md).
