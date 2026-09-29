# UDP protocol configuration

Read after [selection](protocols.md). Research checked 2026-09-29. Establish UDP
reachability and client compatibility independently.

## AmneziaWG

Pin the AWG generation and the server/client engine pair. A GUI import, older kernel
module or OpenWrt/Keenetic vendor build may drop newer fields: compare sanitized
effective settings on both ends. AWG extensions are not stock-WireGuard compatible;
never paste another peer's key.
[Configuration source](https://github.com/amnezia-vpn/amneziawg-go#configuration).

- **Header protection (AWG 3+):** `HeaderProtectionKey` must match on both ends;
  `S1`–`S4` must then be at least 12 (cipher nonce), with `H1`–`H4` = 1, 2, 3, 4 per
  vendor. Use non-overlapping `H` ranges only when it is off.
- **AWG 3.1:** set `RandomTrailers` on both sides; `DisableCookies` is local. Neither
  is in the engine README; evidence is engine commit history and
  [vendor docs](https://docs.amnezia.org/documentation/amnezia-wg).
- **Client-side:** keep `Jmax` below the usable path MTU; set `ContentPaddingAddition` on
  both sides (README); `I1`–`I5` are sent before each handshake.
- **Engine pair:** kernel module `v3.1.20260906` is the first with random trailers on
  I1–I5/dummy-junk packets; amneziawg-go master (2026-08-28) lacks it. Mixed
  userspace/kernel peers with `I1` + `RandomTrailers` are untested: pin one pair and
  test both directions.

Client: stable `5.0.3.0` (desktop installer provisions AWG 3.1 only). Require a real
handshake and sustained traffic on each deployed OS, kernel module and import path.
[Releases](https://github.com/amnezia-vpn/amnezia-client/releases/).

### Installer defaults (5.0.2.1 and later)

[PR #3115](https://github.com/amnezia-vpn/amnezia-client/pull/3115): the self-host
generator emits equal `S1`–`S4` = 12, `H` = 1..4, `RandomTrailers` and `DisableCookies`
on, random `Jc` 4–6, `Jmin`/`Jmax` 10/50, no `ContentPaddingAddition`, a per-install
`HeaderProtectionKey` and a **static `I1` identical across installs** (a DNS-response
imitation). The server config has no `MTU`; the desktop client hard-codes 1376.

- A byte-identical `I1` is the universal constant this skill warns against
  ([#2857](https://github.com/amnezia-vpn/amnezia-client/issues/2857), open). Replace
  generated shared constants deliberately, one change at a time; `I1` is not covered by
  header protection. No evidence TSPU matches that literal (plausibility only), and a
  random-blob `I1` is not shown safer than none (weak Tele2/Megafon report).
- Vendor [troubleshooting](https://docs.amnezia.org/troubleshooting/self-hosted-amneziawg-not-working) suggests a port below 9999 and a replacement `I1`; it omits `Jc` and MTU.
- MTU 1280 is the vendor recommendation for 3.1 and cured one reported "handshake, no
  traffic" case ([#3192](https://github.com/amnezia-vpn/amnezia-client/issues/3192));
  it did not resolve [#3043](https://github.com/amnezia-vpn/amnezia-client/issues/3043).
  Not a universal target: read live MTU on both ends.

### Exclude first-hop reachability before tuning

Since 2026-09-21 many self-hosted AWG servers (2.0 and 3.1) stopped working
([#3192](https://github.com/amnezia-vpn/amnezia-client/issues/3192)): several VPSes
neither pinged nor accepted SSH from Russian addresses but answered from abroad; moving
hoster helped some. Reporters mix IP blocks, SSH-only filtering and installer defects;
no captures exist. Before AWG tuning, test ping/SSH to the server from the affected
path and a foreign vantage; see
[diagnostics.md](diagnostics.md), [evidence.md](evidence.md), [hosting.md](hosting.md).
Downgrading the client does not help a blocked IP.

## Hysteria2 and TUIC

Hysteria version 2 is not QUIC version 2: no released client dials QUIC v2
([PR #1673](https://github.com/apernet/hysteria/pull/1673) unmerged); sing-box and TUIC dial v1 only. The FOCI 2026 SNI finding covers QUIC
v1 ([evidence.md](evidence.md)), so a v1 Initial carrying a blocked SNI is exposed.
TUIC has no official implementation: pin its protocol and implementations.
[Hysteria protocol](https://v2.hysteria.network/docs/developers/Protocol/),
[TUIC specification](https://github.com/tuic-protocol/tuic).

QUIC needs a UDP path carrying at least 1200-byte payloads; do not force IP
fragmentation or a tiny outer limit to make it pass. Port hopping cannot repair an
all-UDP drop; keep an independently tested TCP path.
[RFC 9000 §14](https://www.rfc-editor.org/rfc/rfc9000.html#section-14),
[RFC 9308 §2.1](https://www.rfc-editor.org/rfc/rfc9308.html#section-2.1).

### Hysteria2 settings that change the outcome

Use `2.12.3` or later (avoid 2.11.x on low-MTU paths); pin server and client.
[Changelog](https://v2.hysteria.network/docs/Changelog/).

| Setting | Starting decision | Failure/tradeoff to verify |
| --- | --- | --- |
| `tls.sni`, trust roots or pin; `auth` | Match the server identity and authenticate; leave `insecure` disabled | A wrong SNI, pin or clock is not censorship. |
| Chrome QUIC parroting (client default; `quic.disableChromeParrot`) | Keep the default; use an ECDSA/RSA server certificate | Ed25519 certificates fail the handshake. `tls.ech` is silently ignored while parroting is on ([#1684](https://github.com/apernet/hysteria/issues/1684), open); ECH needs the parrot disabled. Parrot emits a real QUIC Initial (v1 SNI exposure applies). |
| `bandwidth.up` / `bandwidth.down` | Leave unspecified for automatic congestion control on variable mobile links | Setting a direction selects Brutal; inflated rates create loss. If used, choose conservative measured rates; compare `bandwidth.disableLossCompensation`. |
| `obfs.type: salamander` or `gecko` | Enable only for a demonstrated need and a matching secret on both ends | The server stops being a valid HTTP/3 server and presents no QUIC Initial. Gecko (experimental) also fragments the handshake into padded datagrams. A wrong secret resembles a timeout. |
| `quic.disableStatelessReset` (server) | Leave stateless resets on so idle mobile clients reconnect fast | Disable only if a QUIC middlebox interacts badly; interop is unverified. |

[Client configuration](https://v2.hysteria.network/docs/advanced/Full-Client-Config/).

Use server `masquerade` with real file/proxy content when ordinary H3 behavior is the
design (not with Salamander/Gecko); a default 404 is less plausible. Inspect
`ignoreClientBandwidth` on both ends. Obfuscated Hysteria2 is not HTTP/3.
[Server configuration](https://v2.hysteria.network/docs/advanced/Full-Server-Config/),
[obfuscation design](https://v2.hysteria.network/docs/developers/Protocol/#salamander-obfuscation).

Port hopping is a conditional remedy for port-specific UDP trouble, not all-UDP
filtering. It needs matching server-side port exposure/forwarding and widens firewall
scope; test fixed-port UDP first. It is incompatible with Mimic (a separate Linux-only
outer-packet experiment: [emerging.md](emerging.md)). Verify both TCP and UDP relay, not
merely tunnel connection.
[Port hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/).

### sing-box 1.14 and TUIC

sing-box Hysteria2 parrots Chrome by default (`disable_chrome_parrot`; the Ed25519
failure applies) and supports `gecko`. Hysteria, Hysteria2 and TUIC share QUIC options
(`initial_packet_size`, `disable_path_mtu_discovery`); TUIC gets no parrot. Check the
installed core before copying option names.
[Hysteria2](https://sing-box.sagernet.org/configuration/outbound/hysteria2/).

For TUIC, match `uuid`/`password`, TLS identity/trust and any ALPN with the server.
Keep `congestion_control` `cubic` unless measured throughput/loss favors `bbr` (not
camouflage). Start with `udp_relay_mode: native`; `quic` adds overhead.
`udp_over_stream` needs a compatible server and conflicts with `udp_relay_mode`. Leave
`zero_rtt_handshake` false (replay risk), keep per-user authentication and verify
sustained relayed TCP and UDP. Check protocol version, ALPN and certificate before
diagnosing a handshake failure as DPI.
[Outbound](https://sing-box.sagernet.org/configuration/outbound/tuic/),
[inbound](https://sing-box.sagernet.org/configuration/inbound/tuic/).

## Amnezia symptom checks

Open defects or unresolved reports on current builds; scope each to its
importer/OS/engine.

- **Imported third-party profile ignores the UI DNS**
  ([#2957](https://github.com/amnezia-vpn/amnezia-client/issues/2957)): the embedded
  profile DNS wins on 5.0.3.0. Check the actual resolver; put the intended DNS in the
  source profile before import.
- **Small packets pass, large fail**
  ([#3064](https://github.com/amnezia-vpn/amnezia-client/issues/3064),
  [#3089](https://github.com/amnezia-vpn/amnezia-client/issues/3089)): 5.0.3.0
  hard-codes desktop MTU 1376 (1280 on mobile/macOS-NE), overriding a configured 1280,
  and writes no server `MTU`; server 1420 vs client 1376 coincided with failures and
  matching 1376 fixed that setup. Read live MTU on both ends before tuning obfuscation.
- **AWG 3.1 handshake succeeds, no traffic**
  ([#3082](https://github.com/amnezia-vpn/amnezia-client/issues/3082),
  [#3043](https://github.com/amnezia-vpn/amnezia-client/issues/3043)): causes
  unresolved (one recovery changed `Jc` and `I1` together; #3043 persisted with MTU
  1280). Compare engine, client version and MTU before blaming DPI; do not prescribe
  `Jc`/`I1` constants.
- **Installer reports success, server down**
  ([#3117](https://github.com/amnezia-vpn/amnezia-client/issues/3117), fix
  [#3167](https://github.com/amnezia-vpn/amnezia-client/pull/3167) unmerged):
  `awg-quick up` can fail in the container (stale host kernel module) with the error
  swallowed. Check `modinfo amneziawg` on the host and container logs.
