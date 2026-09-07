# UDP protocol configuration

Read after [selection](protocols.md). Research checked 2026-09-07. UDP reachability
and client compatibility must be established independently.

## AmneziaWG

Pin the AWG generation and the server/client implementation pair. The current
upstream documents AWG3 `HeaderProtectionKey`; older implementations can miss
AWG2 `S3`/`S4`, ranged `H1`–`H4` or `I1`–`I5` settings. Do not assume a GUI
import preserved them. Keep required protocol-facing parameters consistent,
header ranges non-overlapping and junk packets below the usable path MTU.
`Jc`/`Jmin`/`Jmax` are client-side junk controls and need not mirror the server.
Do not share a universal set of camouflage constants or paste another peer's
key. Enabling AWG extensions is not transparent stock-WireGuard compatibility.
[Protocol/configuration source](https://github.com/amnezia-vpn/amneziawg-go).

Snapshot: client `5.0.2.1` (2026-09-03) was a pre-release; the researched ordinary
release was `4.8.21.0` (2026-07-10). AWG3 availability in a release line does not
establish compatibility across every OS, kernel module and external importer.
[Official client releases](https://github.com/amnezia-vpn/amnezia-client/releases/).
Require a real handshake and sustained traffic on each deployed OS/import path.

## Hysteria2 and TUIC

Hysteria version 2 is not QUIC version 2: verify the negotiated wire version
and support in both implementations before applying QUIC-version research.
Hysteria2 uses QUIC and has HTTP/3 masquerade behavior; TUIC relays over QUIC
streams/datagrams. Pin TUIC protocol and implementations: the project does not
provide one official implementation or guarantee cross-version compatibility.
[Hysteria protocol](https://v2.hysteria.network/docs/developers/Protocol/),
[TUIC specification](https://github.com/tuic-protocol/tuic).

QUIC needs a UDP path capable of at least 1200-byte UDP payloads. Do not force
IP fragmentation or a tiny outer packet limit to make it pass. Port hopping
cannot repair an operator policy dropping all UDP. Keep an independently tested
TCP path when UDP failure is in scope.
[RFC 9000 §14](https://www.rfc-editor.org/rfc/rfc9000.html#section-14),
[RFC 9308 §2.1](https://www.rfc-editor.org/rfc/rfc9308.html#section-2.1).


### Hysteria2 settings that change the outcome

| Setting | Starting decision | Failure/tradeoff to verify |
| --- | --- | --- |
| `tls.sni`, trust roots or pin; `auth` | Match the server identity and authenticate; leave `insecure` disabled | A wrong SNI, pin or clock is not censorship. Certificate verification and proxy authentication serve different purposes. |
| `bandwidth.up` / `bandwidth.down` | Leave unspecified for automatic congestion control on variable mobile links | Setting a direction selects Brutal; inflated rates can create loss and instability. If used, choose conservative measured rates for that direction. |
| `obfs.type: salamander` | Enable only for a demonstrated need and matching secret on both ends | Scrambles QUIC into random-looking UDP; it no longer has ordinary HTTP/3 wire appearance. Wrong secret resembles a timeout. |

[Official client configuration](https://v2.hysteria.network/docs/advanced/Full-Client-Config/).

Use server `masquerade` with actual file/proxy content when ordinary H3 behavior
is the design. A uniform default 404 is less plausible. Optional TCP HTTP/HTTPS
listeners add operational surface; upstream does not establish that their
absence is a deployed detection signal. `ignoreClientBandwidth` changes whether
clients may use the requested Brutal rates, so inspect both ends.
[Official server configuration](https://v2.hysteria.network/docs/advanced/Full-Server-Config/).

Salamander's outer scrambling changes how unauthenticated network probes see
the service; do not describe it as “HTTP/3 with extra invisibility.”
[Protocol obfuscation design](https://v2.hysteria.network/docs/developers/Protocol/#salamander-obfuscation).

Port hopping is a conditional remedy for port-specific UDP trouble, not all-UDP
filtering. It requires the corresponding server-side port exposure/forwarding;
adding it changes firewall scope. It is incompatible with Mimic. Test fixed-port
UDP first and account for NAT/reconnection behavior.
[Port hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/).

Version pitfall: upstream documents v2.8.2 clients losing UDP relay with older
servers even though TCP relay works. Verify both relay types, not merely tunnel
connection. [Changelog](https://v2.hysteria.network/docs/Changelog/#282).
See [Mimic](emerging.md) for a separate Linux-only outer-packet experiment;
it is not the ordinary Hysteria2 UDP profile.

### TUIC implementation-specific settings

For sing-box, match `uuid`/`password`, TLS identity/trust and any configured ALPN
with the server. `congestion_control` defaults to `cubic`; compare `bbr` only
with measured throughput/loss rather than treating it as camouflage.
`udp_relay_mode: native` is the starting point; `quic` uses reliable streams and
adds overhead. `udp_over_stream` is a separate extension requiring a compatible
server and conflicts with `udp_relay_mode`. Do not enable both or assume another
TUIC implementation understands the extension. The `network` selector controls
which application traffic is relayed, not whether the outer tunnel uses UDP.
[sing-box outbound](https://sing-box.sagernet.org/configuration/outbound/tuic/).

Leave `zero_rtt_handshake` false; enabling it introduces replay risk.
Keep per-user authentication and the intended listen address; verify UDP reachability
to the listener and sustained relayed TCP and UDP. Check exact protocol version,
ALPN and certificate behavior before diagnosing a handshake failure as DPI.
[sing-box inbound](https://sing-box.sagernet.org/configuration/inbound/tuic/).

## August community regression checks

The following Amnezia issues were open when inspected on 2026-09-07. An open
report is not proof every current build is affected; scope each check to its
importer/OS/engine and inspect later fixes when using this reference.

| Reported environment and source | Symptom / useful check |
| --- | --- |
| 5.0.0.5, Arch Linux, self-hosted `.conf` import; [#2942](https://github.com/amnezia-vpn/amnezia-client/issues/2942), 2026-08-05 | AWG3-only fields were dropped, while the equivalent `vpn://` import worked. Compare sanitized effective fields; do not generalize the `.conf` defect to subscription/API paths. |
| 5.0.0.5, Ubuntu 26.04, third-party profile; [#2957](https://github.com/amnezia-vpn/amnezia-client/issues/2957), 2026-08-07 | UI DNS overrides were saved but embedded profile DNS still applied. Check the actual resolver; placing the intended DNS in the source profile before import was the reported workaround. |
| Windows, imported AWG3; [#3064](https://github.com/amnezia-vpn/amnezia-client/issues/3064), 2026-08-27 | Configured 1280 became live 1376; small packets passed and larger traffic failed. Check live adapter MTU. Other OS impact was inferred, not demonstrated; 1280 is not a universal target. |
| 5.0.1.5 self-host installer, Ubuntu 24.04; [#3089](https://github.com/amnezia-vpn/amnezia-client/issues/3089), 2026-08-29 | Generated server MTU 1420 versus client 1376 coincided with large server-to-client failures; matching 1376 fixed that setup. Check both ends' actual output before tuning obfuscation. |
| AWG3.1 self-hosted deployment; [#3082](https://github.com/amnezia-vpn/amnezia-client/issues/3082), 2026-08-28 | Reported recovery changed both `Jc` 4→6 and empty `I1`→nonempty. Port/provider/MTU controls were useful, but two simultaneous changes leave causality unresolved. Do not prescribe those constants. |

A [Beeline LTE report](https://github.com/amnezia-vpn/amnezia-client/issues/2155)
(2026-01-25, Pixel/Android 16, Amnezia 4.8.12.7) described AWG2 forwarding
stopping after 1–5 minutes while Wi-Fi worked. That is a reason for an idle/NAT,
client-policy and sustained-transfer comparison, not proof of a current blanket
Beeline block.

For Hysteria port hopping, a [Debian 13/container IPv6 report](https://github.com/apernet/hysteria/issues/1590)
(2026-05-29, 2.9.2) had the fixed port working while generated range redirection
failed. Inspect the bind address and generated IPv4/IPv6 rules before treating
hopping timeouts as DPI. A user's successful DNAT change is not a universal
firewall recipe or authorization to change the firewall.
