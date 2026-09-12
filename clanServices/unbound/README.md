# @clanwright/dns-unbound

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это recursive DNS backend на native `services.unbound`. Роль ограничена
loopback и может быть выбрана AdGuard Home как внутренний upstream. Она не
задаёт AdGuard upstream и не открывает firewall: DNS-композиция остаётся у
consumer.

## Settings

Точная схема и defaults определены в [`default.nix`](default.nix).
`enable` по умолчанию равен `true`; при `false` роль не объявляет native
Unbound runtime. На одной машине допускается ровно один active instance,
поскольку все instances используют общий `services.unbound` unit и state.
Один disabled instance может соседствовать с одним active.
`listen.hosts` принимает `null` либо непустой список loopback IP literals.
Разрешены IPv4 из `127.0.0.0/8` и `::1`; hostnames, wildcard и public addresses
отклоняются. `listen.port` принимает `1..65535`. Privacy flags:
`prefetch`, `hideIdentity`, `hideVersion`, `qnameMinimisation`.

## Defaults and resolver policy

При `listen.hosts = null` effective listener — `127.0.0.1` и, только если host
IPv6 включён, `::1`. Явный список сохраняется; `::1` на IPv4-only
host отклоняется. Порт — `5335`, `resolveLocalQueries = false`.
Inbound listener/ACL не управляет исходящей рекурсией: IPv4 recursion включена,
а IPv6 recursion следует общей `networking.enableIPv6` host policy.

Native root trust anchor и DNSSEC validation остаются включены. Effective
policy фиксирует validator module, запрещает permissive mode и локальные
insecure trust exceptions, а также требует `harden-dnssec-stripped`. Unbound слушает
UDP и TCP, использует EDNS buffer `1232`, QNAME minimisation без strict mode,
`prefetch`, `cache-min-ttl = 0` и не получает ECS/per-query logging от роли.
Bounded stale policy: `serve-expired = yes`, horizon `86400`, без TTL reset,
fresh-answer wait `1800ms`, stale reply TTL `30s`.

## Integration dependency

Startup composition с AdGuard, включая systemd dependencies, принадлежит
consumer.

## Trust-anchor lifecycle

Используется native NixOS lifecycle и `${stateDir}/root.key`. В закреплённом
NixOS module `unbound-anchor` status `1` обрабатывается как событие обновления:
upstream определяет его как использование builtin anchor или certificate
update. Status `0` означает как отсутствие нужного обновления/RFC5011 success,
так и ошибку; поэтому status сам по себе не различает сетевую ошибку при
сохранённом usable anchor. Роль не заменяет native preStart ненадёжной проверкой
и не отключает DNSSEC. Pure evaluation не подтверждает фактический refresh или
содержимое runtime-журнала.

## State and secrets

Собственных SOPS inputs и state paths нет; native Unbound runtime управляет
рабочими файлами. Роль не материализует credentials.

## Verification

`unbound-contracts` проверяет schema defaults/invalid values, IPv4-only policy,
effective override assertions и generated native configuration средствами Nix.
Application parser/CLI, runtime tests, VM и тесты на реальных машинах запрещены.
Реальный `READY=1`, DNS responses, trust-anchor refresh и фактический AdGuard
fallback не проверяются и не объявляются доказанными.
Проверки и runtime acceptance описаны в
[runbook Unbound](../../docs/operations/unbound.md).

Freeform `include`, `include-toplevel` и server-level `include` отклоняются:
они могли бы добавить listeners или ослабить DNSSEC после проверки typed attrs,
а native NixOS checkconf отключается при top-level `include`.
Набор effective directives закрыт штатными полями закреплённого NixOS-модуля
и полями роли. Forward/stub/auth zones, local-data, RPZ и другие freeform
расширения отклоняются; remote control выключен. Это исключает замену
рекурсии синтезированными ответами или другим источником.
