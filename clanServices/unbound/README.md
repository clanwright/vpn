# @clanwright/dns-unbound

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это recursive DNS backend на native `services.unbound`. Роль намеренно
ограничена loopback и может быть выбрана AdGuard Home как внутренний
upstream.

## Settings

Настройки: `listen.hosts`, `listen.port`, privacy flags
`prefetch`, `hideIdentity`, `hideVersion`,
`qnameMinimisation` и nullable
`adguardIntegrationProvider`. Provider принимает только `null` или
`dns-adguardhome`.

## Defaults

Listen hosts — `127.0.0.1` и `::1`, порт — `5335`; privacy options
включены. `resolveLocalQueries = false`. По умолчанию
`adguardIntegrationProvider = "dns-adguardhome"`, поэтому Unbound по
умолчанию задаёт ordering edge к AdGuard unit; значение `null` убирает
эту зависимость.

## Exports and dependencies

Typed export роль не публикует. При значении
`adguardIntegrationProvider = "dns-adguardhome"` добавляются
`After=` и `Requires=` для `adguardhome.service`; при `null`
ordering edge отсутствует.

## State and secrets

Собственных SOPS inputs и state paths нет; native Unbound runtime управляет
своими рабочими файлами. Роль не материализует credentials.

## Network exposure

Unbound слушает только loopback на TCP/UDP `5335`; public, tailnet и
WAN listeners не создаются. AdGuard принимает клиентский DNS отдельно и
может направлять запросы на этот backend.

## Verification

Read-only evaluation:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.services.unbound`.
Проверить loopback bind, privacy settings и наличие ordering edge только
при выбранном provider; внешние DNS ports не должны появиться.
