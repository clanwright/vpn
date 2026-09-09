# Changelog

## Unreleased — September 2026 audits

- Use stock cached application packages; retain only the approved existing
  Network Caddy plugin recipe as an exception.
- Separate Xray VLESS/REALITY/XHTTP and Gecko Hysteria services; implement
  supervised AWG3 userspace configuration and matching client exports.
- Harden native Naive, Unbound and AdGuard configuration, credentials,
  scoped ingress and DNS policy.
- Publish selective/full client configurations with typed per-device bindings;
  omit sing-box publication when the device has no eligible Naive provider.
- Replace application and runtime checks, including the earlier Unbound
  readiness check, with pure Nix assertions and static verification. Prohibit
  Python, VM configuration/execution, real-machine tests and external builders.

The candidate has passed repository acceptance, tracked
in [the main audit](docs/audit-2026-09.md). The accepted Mihomo DNS policy uses
only primary AdGuardHome, without client fallback or another local resolver; if
it is unavailable and no answer is cached, new Mihomo DNS queries fail.

## 0.1.1

- Export the systemd-enabled Unbound package required by the native NixOS
  `Type=notify` service.
- Add a VM-free native-process check for Unbound readiness notification.

This entry describes the candidate contents; it does not claim publication,
consumer adoption, deployment or live endpoint acceptance.

## 0.1.0

Initial public release candidate.

- Publish seven existing VPN and DNS Clan module IDs without changing their
  settings, defaults, runtime services, profile formats or DNS flow.
- Publish closed VPN provider/profile contracts and AmneziaWG validation
  helpers.
- Own the exact Mihomo, Mihomo keygen, Sing-box, NaiveProxy and AmneziaWG
  package set used by the modules and domain checks.
- Add local static, flake evaluation, Linux contract/fixture/render/key checks,
  and owned-package verification with retained logs and durations.

This entry describes the candidate contents; it does not claim publication,
consumer adoption, deployment or live endpoint acceptance.
