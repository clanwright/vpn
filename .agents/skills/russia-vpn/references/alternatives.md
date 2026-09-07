# DPI tools and emergency alternatives

Checked 2026-09-07. These solve different problems from a full-device VPN.
No controlled August–September Russian trial covering these alternatives was
located. Use upstream capabilities and scoped community observations to design
a trial; do not turn a tool's availability into a working-path claim.

## zapret2, ByeDPI and GoodbyeDPI

Start by checking ordinary TCP connection and destination reachability with the
tool disabled. If the IP/port path already fails, packet-desynchronization
presets cannot restore a denied destination. Once the path works, isolate the
handshake/request that triggers failure before searching strategies.

Inspect capture/filter scope, payload matching, hostlists, bootstrap DNS and
interaction with the existing firewall/VPN. A strategy for one domain/transport
need not fit another; compare individually and retain a known-working build.
Do not stack several packet interceptors or disable firewall/AV protections as
an unexplained permanent workaround.

- **zapret2:** programmable packet manipulation, not an exit-IP provider. The
  [official manual/project](https://github.com/bol-van/zapret2) governs filter and
  strategy syntax; verify exact OS/build. [v1.0.3](https://github.com/bol-van/zapret2/releases/tag/v1.0.3)
  (2026-07-21) had follow-on commits by the cutoff. Current zapret2 excludes macOS;
  [zapret1 is EOL](https://github.com/bol-van/zapret). No preset is a global RU default.
- **ByeDPI:** a [2026-05-30 issue](https://github.com/hufrea/byedpi/issues/401)
  relays an MGTS observation favoring domain-specific strategies over one global
  strategy. It was closed not planned and does not validate duplicate processes.
  Use the installed implementation's supported grouping/routing, then test each
  intended domain; the missing build/region controls limit generalization.
- **GoodbyeDPI:** [Windows/WinDivert tool](https://github.com/ValdikSS/GoodbyeDPI).
  Its `-q` option blocks QUIC, which can push applications toward TCP; a resulting
  improvement is not evidence that UDP became reachable. Check driver and local
  stack compatibility and the actual DNS effects of the chosen preset.

These tools do not provide a foreign exit or full-device confidentiality merely
by changing packet presentation. A working desync strategy can be useful on its
own when those are not the user's goals.

## Tor transports

[Official bridge guidance](https://support.torproject.org/little-t-tor/circumvention/using-bridges/)
covers obfs4, meek, Snowflake and WebTunnel support through Lyrebird; inspect the
actual client distribution and bridge/bootstrap requirements. obfs4/WebTunnel
bridge lines and Snowflake's discovery path are different dependencies. Test
bootstrap and the required application, not just whether a bridge address opens.

The [March–April Snowflake report](https://github.com/net4people/bbs/issues/603)
contains Pion DTLS fingerprint observations and maintainer packet analysis.
It supports checking proxy implementation/update and discovery/NAT behavior;
it does not prove all WebRTC or all Snowflake is blocked. No new August–September
RU efficacy campaign was located. Tor Browser support is not equivalent to
transparent full-device TCP/UDP VPN coverage.

[Conjure](https://github.com/refraction-networking/conjure) requires deployed
station/registration infrastructure with ISP-side integration. Do not present
it as another VPS protocol a user can simply enable; first establish an
accessible deployment and supported client.

## Resolver or relay paths

[Slipstream](emerging.md) is one experimental DNS-carried TCP option. Other
choices have different security and payload scope:

- [iodine](https://github.com/yarrick/iodine) needs delegated DNS and a matching
  server/client. Its tunnel is IPv4 and unencrypted; sensitive use requires an
  authenticated encrypted layer inside it. DNS reachability alone does not prove
  that the resolver carries the required query sizes, rate or sustained traffic.
- [dnstt](https://www.bamsoftware.com/software/dnstt/protocol.html) defines a
  separate reliable encrypted channel over DNS. Compare resolver, message-size,
  latency/rate and server-identity requirements; DoH is an additional reachable
  service dependency, not immunity to filtering. Do not promise VPN-like speed.
- A [WebRTC/SFU proposal](https://github.com/net4people/bbs/issues/618)
  (2026-05-20) describes service-specific relay experiments. No named-operator
  controlled allowance test was established. Relay permission, key handling,
  session setup, capacity and service changes are part of the design, not free
  general Internet transit. Keep it a research option rather than a ready fallback.

ICMP tunneling has no current validated design in this baseline. A successful
ping is not proof of a usable, authenticated, bidirectional data channel. Neither
DNS nor ICMP tunneling repairs an unavailable first hop or full radio outage.
