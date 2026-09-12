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
`auth.username`, `auth.passwordSecretName`, `systemResolver.enableLocalStub`,
`filtering.enable`, `filtering.userRules`, `dns.privateZones` и `dns.rewrites`.
`dns.upstream` содержит ровно
один числовой loopback endpoint Unbound в формате `127.0.0.1:<port>`.
На одной машине допускается ровно один active instance: роль владеет общими
native `adguardhome` и `dnsproxy` runtimes, state path и integration output.
Disabled instance не заявляет эти ресурсы и может соседствовать с одним active.

`dns.privateZones` — список непустых групп вида:

```nix
{
  domains = [ "internal.example.invalid" ];
  upstreams = [ { address = "10.20.0.53"; port = 53; } ];
}
```

Домены — канонические DNS-суффиксы в lowercase ASCII: до 253 символов, labels
до 63 символов из `a-z`, `0-9` и внутренних дефисов, без trailing dot.
Resolver address — частный числовой IPv4-адрес или `::1`; numeric endpoint не
требует DNS bootstrap. Пустые группы, повторяющиеся zones/domains/resolvers, публичные
адреса, небезопасный синтаксис и известные петли через собственный DNS, Unbound
или fallback отклоняются при evaluation.

`dns.rewrites` задаёт точные aliases без wildcard, цепочек, self-reference и
циклов. Например:

```nix
{
  domain = "admin.example.invalid";
  answer = "node.internal.example.invalid";
}
```

Source name и CNAME target должны попадать в объявленные private zones; вместо
CNAME допускается частный числовой IP. Повторы отклоняются. Для CNAME дальнейшее
разрешение выполняется по target qname.

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

`filtering.enable = false` — поддерживаемая декларативная пауза защиты: она
меняет только `protection_enabled`. AdGuard filtering engine и native rewrites
остаются включены, поэтому typed private rewrites продолжают действовать.
Императивное выключение engine через UI не является поддерживаемым состоянием.
`filtering.userRules` остаётся местом для consumer allow/deny rules, но при
непустых private zones правила с modifiers `dnsrewrite`, `badfilter` или
`important` запрещены: они могли бы обойти typed validation или отменить
сгенерированное исключение.

Роль добавляет `@@||<zone>^$important,dnsrewrite`, затем
`@@||<zone>^$important` перед consumer rules. Native typed rewrites
применяются до filter rules. Когда обычное zone exception выигрывает, private
query обходит parental filtering; combined exception защищает DNS rewrite
closure. Consumer rules не могут отменить эти exclusions. Более специфичное
`$important` blocking rule из включённого remote filter всё ещё может блокировать
прямой запрос к private name. Consumer доверяет содержимому и доступности
выбранных filter feeds; репозиторная evaluation не доказывает отсутствие такого
конфликта. Он блокирует ответ, но не создаёт выход в public forwarding path.
Политика обычных public names не меняется. Conditional private routes добавляются и в
`upstream_dns`, и в `fallback_dns`. Ошибка private resolver повторяется только
между resolvers этой зоны и может увеличить ожидание; запрос не уходит в
обычные Unbound/dnsproxy defaults. Consumer обязан настроить сам private
resolver так, чтобы protected names не рекурсировались и не пересылались в
public DNS: библиотека не может проверить поведение внешнего сервера.

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

Для private zones роль генерирует DS guard в `dns.blocked_hosts`, поскольку
dnsproxy выбирает resolver для DS по parent name. DS over TCP получает REFUSED,
а over UDP drops; остальные qtypes, включая HTTPS, следуют private routing. DNS privacy
не является авторизацией: listeners, firewall, client DNS routing и HTTPS
names/certificates принадлежат consumer. Имена остаются видимы читателям
конфигурации и query log, а ответы — авторизованным DNS-клиентам.

## Verification

Репозиторные source-проверки описаны в
[runbook AdGuard Home](../../docs/operations/adguardhome.md). Они проверяют
typed contract, сгенерированную конфигурацию и отрицательные ограничения
чистым Nix evaluation, не запуская AdGuard Home, dnsproxy или VM. Реальное
поведение systemd и сетевых путей этим результатом не доказано.

Route/rewrite semantics сверены с исходниками AdGuard Home 0.107.78:
[`filtering`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/filtering/filtering.go),
[`dnsforward`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/filter.go),
[`access`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/access.go),
[`middleware`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/middleware.go)
и [`fallback setup`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/dnsforward.go#L678-L699),
а DS selection — с dnsproxy 0.83.0, встроенным в этот AdGuard Home:
[`upstreams`](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.0/proxy/upstreams.go)
и [`proxy`](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.0/proxy/proxy.go).
Это source evidence, а не runtime-проверка. Отдельный loopback fallback service
использует stock dnsproxy 0.83.2.
