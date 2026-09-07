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

Operator commands belong only in `docs/operations/`. Before release, run the
complete local verification gate and retain its generated artifacts. A passing
gate does not authorize deployment, provider/DNS changes, secret mutation or
release publication.

The repository skill `.agents/skills/rkn-vpn-hardening/SKILL.md` supports
Russia-specific censorship and VPN detection analysis.
