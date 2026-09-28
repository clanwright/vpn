# VPN routing research reference

Research date: 2026-09-28. The user approved three implementation changes:

- .ru domain names go DIRECT before VPN list matches.
- Add category-ai-!cn and github service packs to the existing selective policy.
- Preserve the remaining DIRECT default and existing local/IPv6 protections.

Current behavior belongs in the [publisher documentation](../clanServices/vpn-client-profiles/README.md).
This note records research rationale, not a deployment result.

[Client comparison and export audit](client-comparison.md) records the subsequent
Mihomo/sing-box/Happ/INCY comparison and exact-core capability boundaries.

## Retained reference

The local ignored reference `.work/references/skala-vpn.json`, which is not
distributed in Git, retains one sanitized example of each of the two Skala
transports plus DNS/routing facts. It contains no subscription URL or usable
credentials. It deliberately replaces the full 14-profile snapshot, downloaded
lists, generated comparisons, scripts and logs removed during cleanup.

## Findings used for the change

- Existing Legiz ru-bundle already combines itdog Russia-inside, no-russia-hosts
  and Antifilter Community. Re-filter and HaGeZi DoH are separate current inputs.
- Service packs supplement block/geoblock lists with maintained service domains.
  The AI category includes OpenAI, Anthropic, Google DeepMind and other AI products.
  Baseline plus AI category already covered all 28 itdog Google AI suffixes in
  the inspected snapshot; adding both was redundant.
- Domain-only comparison after .ru exclusion found 104 wholly new AI clauses
  plus one partial extension; GitHub added 54 wholly new clauses plus three
  partial extensions. Counts are not working-site counts and exclude IP/ASN
  matches, consumer additions and live binaries. Detailed source lists were
  intentionally not retained.
- AI rules include a dynamic Azure WebPubSub regex. MetaCubeX domain MRS drops
  regex criteria; full Mihomo classical text and sing-box SRS retain them.
- Whole Google/social/communication packs and additional overlapping RU
  aggregators were not selected. Google Play and Chinese AI packs remain
  research candidates, not approved implementation scope.
- .ru DIRECT is an explicit user preference, including when a blocked-domain
  list contains that name. It does not imply all Russian IPs or other TLDs.

## Primary sources and observed freshness

- [Podkop community lists](https://podkop.net/docs/sections/#списки-сообщества--community-lists)
  and [Google AI guidance](https://podkop.net/docs/faq/#как-настроить-работу-gemini).
- [Legiz aggregation](https://github.com/legiz-ru/mihomo-rule-sets#ru-bundle-with-asn-block).
- [AI category](https://github.com/v2fly/domain-list-community/blob/master/data/category-ai-!cn)
  and [GitHub category](https://github.com/v2fly/domain-list-community/blob/master/data/github).
- [MetaCubeX conversion semantics](https://github.com/MetaCubeX/meta-rules-converter/blob/main/input/geosite.go)
  and [build workflow](https://github.com/MetaCubeX/meta-rules-dat/blob/master/.github/workflows/run.yml).
- [MetaCubeX meta build](https://github.com/MetaCubeX/meta-rules-dat/commit/61fd90847a78311ac89422e5f128f5d903e5fdb8)
  and [sing build](https://github.com/MetaCubeX/meta-rules-dat/commit/739838017cc4632f9961e6010c74f45a4e4ad37f):
  both labeled Released on 2026-09-28 08:59.
- [itdog release](https://github.com/itdoginfo/allow-domains/releases/tag/2026-09-21_15-16): 2026-09-21T15:16:44Z.

These establish source content and maintained community practice, not a
nationwide reachability benchmark. No runtime traffic was tested.
