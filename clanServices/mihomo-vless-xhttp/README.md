# @clanwright/vpn-mihomo-vless-xhttp

## Purpose and role

The stable module ID `@clanwright/vpn-mihomo-vless-xhttp` provides one independent stock Xray
VLESS/REALITY/XHTTP gateway. It does not share process, configuration, package,
or restart state with Hysteria2.

## Settings

The exact schema and defaults are defined in [`default.nix`](default.nix).
The consumer supplies an exact `bindIPv4`, endpoint `domain`, per-device
`profiles`, and client publication metadata. Each profile has its own SOPS UUID
secret name and REALITY short ID. `reality.targetHost` names the REALITY target;
port 443, TLS 1.3, and HTTP/2 are fixed policy, and `serverNames` must contain the
target. The XHTTP path must start with `/`; server mode is fixed to `auto`.

The target declarations are configuration preconditions. Pure evaluation cannot
prove the target's live protocol negotiation or certificate SANs; verify those
from each deployment location before activation.

## Runtime and secrets

The module uses the native NixOS Xray service with the injected stock Xray
26.3.27 package. SOPS renders one root-only runtime JSON template. UUIDs and the
REALITY private key remain placeholders during Nix evaluation and never enter
the store. Xray runs under systemd's dynamic non-root identity and receives only
`CAP_NET_BIND_SERVICE` for the default low port.

The generated inbound uses VLESS `decryption: none`, REALITY `show: false` and
`xver: 0`, XHTTP over TCP in server mode `auto`, and no Vision flow or fallback.
Padding, buffering, and XMUX overrides are omitted so the pinned Xray defaults
apply.

## Export and exposure

Each device short ID is exactly 16 lowercase hex characters (8 bytes).
Short forms and uppercase spellings are rejected, avoiding equivalent
zero-padded/case-varied identities in Xray's decoder.

`vpnProvider` retains protocol `vless-xhttp` and publishes the endpoint,
REALITY target/server names/public key, per-profile short IDs, XHTTP path/mode,
fingerprint, DoH metadata, and secret names. The module opens only the exact
`bindIPv4:port` destination through nftables; it does not add a global allowed
TCP port.
The consumer must explicitly enable the nftables firewall backend; an active
role rejects disabled firewalls or the iptables backend.

Operator checks and activation guidance are in
[`docs/operations/vless.md`](../../docs/operations/vless.md).
