# Repository instructions

This repository owns the public implementation, defaults, typed contracts,
exact packages and checks for its seven VPN/DNS Clan modules. Preserve stable
module IDs and reject consumer-internal imports, package substitution and
reverse dependencies on a consumer checkout.

Keep composition, machine facts, secret values and bindings, exposure policy,
operator entrypoints, monitoring and cross-domain checks in the consumer. Never
print or persist secret values, private keys, passwords, tokens or live profile
URLs.

Runtime support is `x86_64-linux`; Darwin support is limited to developer and
evaluation tooling required by existing checks. TCP tuning remains consumer
owned. Do not introduce HTTP/3 or other protocol changes as incidental work.

Virtual machines are prohibited in this project. Do not add VM configurations,
NixOS VM tests, QEMU/KVM/TCG runners, or verification steps that create or boot
VMs. Repository checks must run without launching virtual machines.

Do not add Python code, scripts, or Python-based test harnesses. Implement
configuration and checks in Nix; checks may invoke packaged CLI tools from
their Nix build phases.

Operator commands belong only in `docs/operations/`. Before release, run the
complete local verification gate and retain its generated artifacts. A passing
gate does not authorize deployment, provider/DNS changes, secret mutation or
release publication.

The universal skill `.agents/skills/russia-vpn/SKILL.md` supports VPN
selection, configuration and diagnosis for Russia, including RKN/TSPU blocking
and app-side detection.
