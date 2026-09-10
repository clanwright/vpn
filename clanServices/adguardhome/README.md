# @clanwright/dns-adguardhome

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это роль DNS-фронтенда на базе AdGuard Home. Она предоставляет локальный
DNS-стаб и DoH через Caddy, применяет фильтры и передаёт обычные запросы
локальному рекурсивному Unbound. При ошибке обмена с Unbound единственный
fallback AdGuard — отдельный loopback `dnsproxy`: он параллельно опрашивает
Cloudflare Standard, Quad9 без threat blocking и Google Public DNS по DoH,
а plaintext `1.1.1.1`, `9.9.9.10` и `8.8.8.8` использует только после ошибок
всех encrypted upstream. Корректные NXDOMAIN и SERVFAIL не переключают каскад.

## Settings

Точная схема и defaults определены в [`default.nix`](default.nix).
Основные входы роли: `ui.host`, `ui.port`, `dns.bindHosts`,
`dns.port`, `dns.upstream`, `dns.fallbackPort`,
`dns.fallbackTimeoutSeconds`, `tls.serverName`,
`tls.httpsPort`, `tls.certificateFile`, `tls.privateKeyFile`,
`auth.username`, `auth.passwordSecretName`, `systemResolver.enableLocalStub`
и `filtering.userRules`. `dns.upstream` содержит ровно
один числовой loopback endpoint Unbound в формате `127.0.0.1:<port>`.

## Defaults

`enable` по умолчанию — `true`; primary указывает на consumer-owned
Unbound `127.0.0.1:5335`. Fallback `dnsproxy` слушает `127.0.0.1:5336`, его
таймаут каждой из двух стадий — 3 секунды при внешнем бюджете AdGuard 10 секунд.
HTTPS использует порт `8444`,
DoT выключен значением `0`, логин администратора — `admin`, локальный стаб и
auth всегда включён, системный resolver использует `127.0.0.1`.

AdGuard кеширует без искусственного min TTL и optimistic stale. DDR и hosts
file выключены. Родительский контроль, Safe Search, HaGeZi Multi NORMAL,
URLHaus включены; удалённый Safe Browsing выключен. Библиотечный default
`filtering.userRules` пуст, а постоянные личные правила задаёт consumer.
Query log хранится 7 дней, statistics — 90 дней, IP не анонимизируются.

## Exports and dependencies

Read-only NixOS output `clanwright.dns.adguardhome.integration` содержит
`schemaVersion = 1`, `uiBackend` с host/port, `dohBackend` с host/port/serverName
и `reloadUnits`. При отключённой роли output равен null. Consumer использует
эти сведения для своих Caddy claims, ACME reload bindings и сетевой политики.
Модуль не зависит от схемы Network и не объявляет Caddy или Tailscale edges.

## State and secrets

Состояние AdGuard Home хранится в `/var/lib/private/AdGuardHome`. SOPS-секрет
`auth.passwordSecretName` должен содержать один полный 60-символьный bcrypt
token без пробелов и завершающего перевода строки: `$2a$`, `$2b$` или `$2y$`,
cost `04`–`31` и 53 символа bcrypt alphabet. Секрет и полный отрендеренный
template имеют `root:root 0400`.
Template передаётся сервису как systemd credential; перед каждым стартом
`install -m 600` восстанавливает `/var/lib/AdGuardHome/AdGuardHome.yaml`, после
чего точный бинарник запускает `--check-config`. Ротация template перезапускает
`adguardhome.service`. Изменения через UI пригодны для диагностики, но следующий
restart восстанавливает декларативную конфигурацию.

`tls.certificateFile` и `tls.privateKeyFile` — явные абсолютные runtime paths.
Consumer обеспечивает их наличие и права чтения сервисом, а также перезагрузку
экспортированных `reloadUnits` после обновления сертификата. Роль не предполагает
группу `acme` и не владеет выпуском сертификатов.

## Network exposure

Plain DNS допускает только loopback, RFC1918 и Tailscale IPv4 listener; он
обязан включать `127.0.0.1`. Firewall и публичную публикацию определяет consumer.
Consumer fixture показывает DoH только на `/dns-query`, HTTPS backend с проверкой
сертификата и заданным SNI, а UI — на отдельном private listener с проверкой
destination address. Это пример композиции, не автоматически включаемая политика.
При `enable = false` роль не объявляет runtime, state, secrets, template или
resolver edges.

## Verification

Репозиторные source-проверки описаны в
[runbook AdGuard Home](../../docs/operations/adguardhome.md). Они проверяют
typed contract, сгенерированную конфигурацию и отрицательные ограничения
чистым Nix evaluation, не запуская AdGuard Home, dnsproxy или VM. Реальное
поведение systemd и сетевых путей этим результатом не доказано.
