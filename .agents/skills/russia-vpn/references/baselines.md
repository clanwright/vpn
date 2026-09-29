# Baseline protocols and existing installations

Checked 2026-09-29 against the linked official documentation. Use these for existing
working setups and controlled comparisons; nothing here shows that all installations
are blocked or that any is universally reachable in Russia. SEO pages claiming stock
WireGuard or OpenVPN are “fully blocked” cite no method (class S): test the user path.
Inspect the actual implementation before translating option names into Mihomo,
sing-box, mobile apps or other frontends.

## WireGuard

WireGuard is an authenticated UDP tunnel, not browser camouflage. `AllowedIPs` selects
peer traffic and allowed source prefixes; the client or network manager decides
installed routes. Check routes separately and make full-tunnel prefixes intentional for
IPv4 and IPv6. `Endpoint` selects the dialed peer; roaming can update it.

Leave `PersistentKeepalive` off unless idle NAT/firewall state needs preserving;
upstream's 25-second example is a starting point for that, not anti-DPI tuning.
Handshake, routes, sustained transfer and idle reconnect are separate checks. Keep
stock WG distinct from an AWG profile with active extensions.
[Quick start](https://www.wireguard.com/quickstart/),
[cross-platform model](https://www.wireguard.com/xplatform/).

## OpenVPN

UDP is a performance candidate if it passes; TCP/443 is a separately tested
compatibility fallback (TCP-over-TCP may worsen loss recovery). The TLS control plane
does not make the connection ordinary browser HTTPS.

Keep certificate verification and modern `data-ciphers`. `tls-crypt-v2` gives
per-client control-channel protection, differs from `tls-auth` and shared `tls-crypt`,
and does not prove DPI resistance. On 2.6+, `force-cookie` requires compatible
clients: do not break older clients while hardening, and validate both peers. Use
2.7.7 or 2.6.23 or later (security fixes for a reliability-layer TLS timeout and
Windows helper/DACL handling). sing-box 1.14 adds OpenVPN client/server; test the
exact core.
[Releases](https://github.com/OpenVPN/openvpn/releases),
[2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html),
[control-channel protection](https://build.openvpn.net/doxygen/group__tls__crypt.html).

## Trojan

Use a matching TLS identity and a real fallback service. In the original Trojan
client, retain `ssl.verify` and `verify_hostname`; set `sni` to the certificate
hostname; check trust-store/full-chain behavior on the actual platform. These field
names are implementation-specific, not a portable sing-box/Xray snippet.

Server `remote_addr`/`remote_port` designate the fallback; align ALPN with that
service and verify unauthenticated traffic reaches it. A valid certificate with an
incompatible backend still fails plausibility checks. Do not invent cipher lists or
disable verification to fix a hostname mismatch. TLS fallback does not hide endpoint
IP/ASN or reproduce every browser behavior.
[Configuration](https://trojan-gfw.github.io/trojan/config.html),
[protocol](https://trojan-gfw.github.io/trojan/protocol.html).

## Shadowsocks 2022

An encrypted TCP/UDP proxy with a random-looking wire image, not an HTTPS handshake.
Keep its security properties separate from censorship camouflage; a ShadowTLS wrapper
is a different design with additional requirements.

Verify SIP022 support on both ends; generic “Shadowsocks” support may mean older AEAD
only. For `2022-blake3-aes-128-gcm` and `2022-blake3-aes-256-gcm`, use random base64
keys of 16 and 32 bytes, never a human password or legacy derivation. Keep clocks
correct and use an implementation enforcing replay/timestamp checks. Test TCP and UDP
separately, including packet-size behavior; do not reimplement the protocol.
[SIP022](https://shadowsocks.org/doc/sip022.html),
[configuration](https://shadowsocks.org/doc/configs.html).
