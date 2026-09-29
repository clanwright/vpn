# TCP protocol configuration

Read after [selection](protocols.md). Checked 2026-09-29; recheck installed versions. These are checkpoints, not deployment-ready
profiles or evidence of nationwide RU reachability.

## REALITY

- Server `target` (older `dest`) and `serverNames` must match the target's certificate names and
  TLS behavior; target is not a client field. A popular SNI is not an allowlist token. Check the
  actual endpoint and its unauthorized-fallback behavior.
- Match client key material and a supported `fingerprint`; `shortId` is even-length hex, at most
  16 characters; `serverNames` take no wildcards. Keep keys out of examples and logs.
- Xray warns on apple/icloud targets and non-443 listen ports (maintainer rationale: such servers
  get IPs blocked easily; [release](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)).
  Prefer a target that negotiates X25519 or X25519MLKEM768 directly; a target answering
  HelloRetryRequest aborted authenticated sessions
  ([#6861](https://github.com/XTLS/Xray-core/issues/6861), open, one reporter). Do not copy a
  universal public domain.
  [REALITY configuration](https://xtls.github.io/en/config/transports/reality.html).

REALITY works with RAW/XHTTP/gRPC, not WebSocket; check the exact transport/flow/security
combination and do not add Vision to every VLESS profile
([matrix](https://xtls.github.io/en/config/transport.html)). Do not put a REALITY endpoint behind a
TLS-terminating CDN; use the provider-supported TLS/HTTP design for that leg. gRPC is not
automatically safer: upstream documents probing and routing caveats and recommends XHTTP for new
designs ([gRPC](https://xtls.github.io/en/config/transports/grpc.html)).

### Server core and client set are one decision (Xray 26.9.8+)

Xray 26.9.8+ REALITY rejects a ClientHello without `X25519MLKEM768` placed before plain `X25519`.
A rejected hello is silently forwarded to `target`: the client sees `reality verification failed`,
the server logs nothing, and `minClientVer` does not bypass it. This is interoperability, not a
block.

| Client / core | Against a 26.9.8+ server | Evidence |
| --- | --- | --- |
| Xray client, `chrome`/`firefox`/`safari` | Works (first three uTLS presets; mapping inferred from source) | Maintainer [#6714](https://github.com/XTLS/Xray-core/issues/6714) plus community A/B |
| Mihomo 1.19.30/.31 | Only `chrome` with `reality-opts.support-x25519mlkem768: true`; edge/firefox or unset fail; one report says repeat the option inside XHTTP `download-settings` | Community, [3x-ui #6568](https://github.com/MHSanaei/3x-ui/issues/6568), [Xray #6477](https://github.com/XTLS/Xray-core/issues/6477) |
| Official sing-box, tested 1.12.25-1.14.1 and alpha.2/.6 | Fails ([#4520](https://github.com/SagerNet/sing-box/issues/4520), open; 1.14.2 untested) | Community, packet level |
| Karing, Stash, Loon (default node), ShellCrash | Fail; Karing works against server 26.7.28 ([#1952](https://github.com/KaringX/karing/issues/1952)) | Community, single reports |

- Mihomo >=1.19.31 reads `support-x25519mlkem768=true` from VLESS/VMess share links when a REALITY
  public key is present ([PR #3199](https://github.com/MetaCubeX/mihomo/pull/3199)); older cores
  and links without it get the default (off). Check the imported runtime config and patch it.
  Mihomo maintainers will not target Xray 26.7.11+
  ([wiki](https://wiki.metacubex.one/en/config/proxies/tls/)); do not wait for a fix.
- Before upgrading a server (panels such as 3x-ui bundle 26.9.9), list every client core and
  fingerprint that must connect. Keep a pinned older server or move all clients to Xray-based cores
  with an ML-KEM-capable preset. Forks with newer hellos exist; verify per build.
- Servers 26.7.11-26.7.28 default `minClientVer` to 26.3.27 and reject clients advertising older
  versions (Mihomo reports 1.8.2); lower the floor deliberately.
- Snapshot: [Xray v26.9.9](https://github.com/XTLS/Xray-core/releases/tag/v26.9.9); v26.3.27 is the
  last tag not flagged pre-release, every later tag is. sing-box stable 1.14.2; Mihomo 1.19.31;
  Naive v154.0.8037.49-2. One core's defaults do not carry over to another.

## XHTTP

- Modes: `auto` can change mode when security or `downloadSettings` changes; per
  [maintainer discussion #4113](https://github.com/XTLS/Xray-core/discussions/4113) it picks
  `stream-one` for REALITY, or `stream-up` with separate download settings. A pinned server mode can
  reject other client modes. Check mode, path, headers, buffering and timeouts through the actual
  reverse proxy/CDN. `noGRPCHeader`/`noSSEHeader` are compatibility options, not hardening.
- Connection count: XMUX request reuse and TCP connection reuse are distinct. Xray 26.7.28+
  defaults `maxConnections` to 3 when `xmux` is unset, citing a reported per-destination cap of
  about 4 concurrent connections ([#6376](https://github.com/XTLS/Xray-core/issues/6376)). Field
  reports conflict: a Moscow MTS user ran 3 unblocked for a month and saw blocks above 3; another
  moved back to 6 during an August ban wave. Count TCP connections per destination and compare 3
  against 6 on the affected operator. `maxConnections` and `maxConcurrency` cannot be set together.
  Go 1.27 builds (26.9.8+) may not bound cold-pool dials
  ([#6797](https://github.com/XTLS/Xray-core/issues/6797), open; `-tags http2legacy` restored the
  cap for the reporter).
- CDN paths: on Xray 26.7.11+ give `path` a file-like extension (older builds forced a trailing
  `/` and produced CDN 403s, [#6385](https://github.com/XTLS/Xray-core/discussions/6385)). A
  CDN-origin 403 is not carrier packet dropping; one report
  ([#6264](https://github.com/XTLS/Xray-core/issues/6264)) saw a dashed UUID path 403 on one CDN
  while an undashed one passed.
- Russian CDN fronting (community, mobile allowlist context, unverified): Selectel and TimeWeb CDNs
  reported CDNvideo-based; CDNvideo-style filters reported to 403 POST bodies, `x_padding` names
  and UUID paths; try GET-based modes and non-default padding names as isolated A/B steps. Provider
  accounts reported banned within weeks. See [hosting.md](hosting.md).

## NaiveProxy

Use the maintained stable Chromium-aligned client and a compatible Naive server plugin, not an
arbitrary HTTP CONNECT proxy. For TCP/H2 the proxy scheme is `https://`; `quic://` switches the
outer transport to UDP. Keep authentication, certificate verification and `probe_resistance`; review
`hide_ip`/`hide_via`. Serve a real front page and compression, and verify unauthenticated requests
reach that site. Restrict local listeners; a loopback listener is still visible to local apps.
[Setup and rationale](https://github.com/klzgrad/naiveproxy).

- Install a stable tag, not `master`:
  [v154.0.8037.49-2](https://github.com/klzgrad/naiveproxy/releases/tag/v154.0.8037.49-2) adds
  `trust_anchors` to the ClientHello (RU effect unmeasured). Only sing-box 1.15.0-alpha.9 carries
  Naive 154.x; sing-box stable 1.14.x embeds 150.x.
- For stalls after long-lived connections (possibly CGNAT), use `--tunnel-timeout`/`--idle-timeout`
  (v148+).
- Padding and browser-like handshakes reduce particular signals, not traffic analysis or
  service-side VPN detection: a UMich group reported an undisclosed traffic-analysis finding
  ([#824](https://github.com/klzgrad/naiveproxy/issues/824), maintainer: no action needed). Do not
  claim Naive is unanalyzable.
- sing-box Naive inbound: use v1.13.6+ (padding-memory fix,
  [#4002](https://github.com/SagerNet/sing-box/issues/4002)); an arbitrary fork may lack it.

## TLS knobs are not interchangeable

A browser-named `fingerprint` imitates part of the handshake, not the browser stack. sing-box
discourages uTLS and prefers Naive; REALITY requires a compatible fingerprint. Neither position
establishes a nationwide winner.

Fingerprint choice on RU paths conflicts: community reports say Chrome presets fare worse on some
paths (Firefox helped), while a maintainer says Chrome is current and the cause is connection counts
([#6299](https://github.com/XTLS/Xray-core/issues/6299)). No controlled study exists; do not treat rotation as a remedy (one report of 10-15 minutes of
restored connection, [#6785](https://github.com/XTLS/Xray-core/discussions/6785)).
Against 26.9.8+ servers rotate only among ML-KEM-capable presets; avoid `random`/`randomized` (it
can advertise ML-KEM without a key share).

ECH needs compatible client/server configuration and bootstrap. It hides the inner name, not the
destination IP or local VPN state, and does not by itself grant allowlist access; inspect whether
ECH was negotiated. Go 1.27 builds (Xray 26.9.8+) reject ECH with minimum TLS below 1.3
([#6737](https://github.com/XTLS/Xray-core/issues/6737)): leave `min` empty. No 2026 RU ECH measurement exists.

Fragmentation and spoofing act at different layers: sing-box `fragment`/`record_fragment`, sing-box
1.14 `tls.spoof` (forged ClientHello with an allowed SNI, needs CAP_NET_RAW/root), Xray finalmask TCP
masks (`fragment`, `header-custom`, `sudoku`, `xmc`). Community: fragmenting the `downloadSettings`
hello fixed an SNI-blacklist block, but fragmentation is not reported to help the 16-20 KB freeze;
no RU measurement of `spoof` exists. Run one measured comparison for a matching handshake failure,
then check latency and sustained traffic; do not stack options or use them against L3 denial.
[sing-box TLS fields](https://sing-box.sagernet.org/configuration/shared/tls/).

## Community failures that change configuration decisions

Scoped reports; check that the deployed build lacks a fix before applying a workaround.
- iOS ([Xray #5918](https://github.com/XTLS/Xray-core/discussions/5918),
  [#6728](https://github.com/XTLS/Xray-core/issues/6728)): Happ/Streisand core 26.2.6 completed TLS
  but sent no XHTTP payload; Shadowrocket/Karing timed out on RAW+REALITY+Vision against 26.7.28
  (maintainer: probably the `minClientVer` floor). Re-test on a 26.9.8+ server, comparing RAW
  against XHTTP on one device; these are leads, not proof all iOS XHTTP fails.
- [NTC 26076](https://ntc.rkn.quest/t/26076) (Remnawave + Xray 26.7.28, foreign hosts, one
  operator): about 1.4 KB of ClientHello leaves the client, then no payload reaches the server, even
  with `security: none`, other fingerprints/SNI, and plain `ncat`. Treat as IP-level degradation of
  that host: run the [diagnostics](diagnostics.md) split, compare a fresh IP, see
  [evidence.md](evidence.md).
- Community preference is conditional: in the
  [April Naive discussion](https://ntc.rkn.quest/t/naive-proxy-пока-лучший-вариант/23843) one author
  moved from failed XHTTP/REALITY to Naive while another saw XHTTP work, without operator/version
  controls. Use such disagreement to pick a second implementation to test.
- Port/mux, SNI, fragmentation or Vision changes were not a durable cure in
  [multi-ISP REALITY reports](https://github.com/net4people/bbs/issues/546); keep them as
  symptom-specific A/B controls.
