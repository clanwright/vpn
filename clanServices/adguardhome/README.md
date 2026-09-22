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
`dns.upstreamTimeoutSeconds`, `dns.fallbackTimeoutSeconds`,
`dns.silentFailureBudgetSeconds`, `tls.serverName`,
`tls.httpsPort`, `tls.certificateFile`, `tls.privateKeyFile`,
`auth.username`, `auth.passwordSecretName`, `systemResolver.enableLocalStub`,
`filtering.enable`, `filtering.safeSearch`, `filtering.youtubeRestrictedMode`,
`filtering.userRules`, `dns.privateZones` и `dns.rewrites`.
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
таймаут отдельной upstream-попытки — 3 секунды. AdGuard использует 16 секунд
на попытку primary или fallback, а не на весь клиентский запрос.
HTTPS использует порт `8444`,
DoT выключен значением `0`, логин администратора — `admin`, локальный стаб и
auth всегда включён, системный resolver использует `127.0.0.1`.

AdGuard кеширует без искусственного min TTL и optimistic stale. DDR и hosts
file выключены. Родительский контроль, Safe Search для поддерживаемых public
search engines, HaGeZi Multi NORMAL и URLHaus включены; YouTube Restricted Mode
и удалённый Safe Browsing выключены. Библиотечный default `filtering.userRules`
пуст, а постоянные личные правила задаёт consumer.
Query log хранится 7 дней, statistics — 90 дней, IP не анонимизируются.

`filtering.safeSearch` независимо включает Safe Search для Bing, DuckDuckGo,
Ecosia, Google, Pixabay и Yandex. `filtering.youtubeRestrictedMode` отдельно
управляет полем AdGuard Home `safe_search.youtube`, которое принудительно
включает Restricted Mode для YouTube domains. Общий AdGuard flag
`safe_search.enabled` включается, когда активна хотя бы одна из этих политик;
поэтому каждая настройка работает при выключенной другой. Обе настройки —
глобальная DNS-политика роли. Их результат может быть переопределён вне роли
client-specific настройкой AdGuard, upstream family DNS, browser/account или
managed-device policy; repository evaluation не доказывает фактический режим
YouTube на клиенте.

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

## Timeout contract

Контракт описывает один обычный public A/AAAA forwarding exchange при молчащих
upstreams: numeric UDP endpoints принимают отправку, но не отвечают. Это
ожидаемый предел для изолированной consumer-приёмки, **не жёсткий deadline
любого клиентского запроса**. Статические assertions проверяют согласованность
настроек с этой моделью; фактические ответы и время проверяет Clanwright.

Обозначения: `A = dns.upstreamTimeoutSeconds` (default `16`),
`F = dns.fallbackTimeoutSeconds` (default `3`),
`B = dns.silentFailureBudgetSeconds` (default `65`), все в секундах.
Все три значения — положительные целые; `A` и `F` ограничены `9223372036s`,
максимумом целых секунд, представимым штатным Go `time.Duration`.
Фиксированный запас `M = 1s` отведён на локальную передачу, переключение и
обработку ответа в изолированном тесте. Это allowance приёмки, а не гарантия
планировщика при произвольной нагрузке. `B` не передаётся приложению как timeout.

| Путь | Модель ожидания без запаса | Defaults |
| --- | --- | --- |
| Молчащий Unbound до первого обращения к резерву | `2A` | `32s` |
| Encrypted stage dnsproxy, новый DoH client | `F` | `3s` |
| Encrypted stage, уже созданный DoH client с повторами | `3F` | `9s` |
| Следующая plaintext stage, молчащие UDP upstreams | `2F` | `6s` |
| Резервная цепочка с тёплым DoH client | `3F + 2F = 5F` | `15s` |
| Молчащий Unbound, работающий dnsproxy, все public upstreams молчат | `2A + 5F` | `47s` |
| Молчат оба loopback upstream AdGuard, включая dnsproxy | `2A + 2A = 4A` | `64s` |

Внутри каждой стадии dnsproxy провайдеры опрашиваются параллельно: время не
умножается на число провайдеров. Между стадиями переключение последовательное.
Полученный корректный DNS-ответ, включая NXDOMAIN, NODATA или SERVFAIL,
завершает соответствующий обмен; сам rcode не включает следующую стадию.
Если все public upstreams молчат, работающий dnsproxy ожидаемо возвращает
SERVFAIL; этот ответ завершает fallback-попытку AdGuard без её UDP-повтора.

Pure assertions требуют `5F + M <= A` и `4A + M <= B`: резервная цепочка
должна помещаться **в первую** попытку AdGuard, а обе последовательные пары
попыток — в заявленный silent-failure budget. Поэтому default-предел приёмки
составляет `48s` при отвечающем dnsproxy и `65s` при молчании обоих loopback
upstreams. Успешный резерв должен завершиться раньше соответствующего предела;
быстрые transport errors могут сократить ожидание. Для согласованного более
короткого профиля допустимы, например, `A = 11`, `F = 2`, `B = 45`, но это
сокращает отдельную попытку public DNS и требует consumer-приёмки.

Прежние `A = 10`, `F = 3` не оставляли места для тёплой цепочки `5F = 15s`.
Default `F = 3` сохранён, а `A` увеличен до `16`: молчащий Unbound теперь
может задержать первое обращение к резерву примерно на `32s` вместо `20s`.
Это явный компромисс общего stock timeout, который AdGuard применяет и к
primary, и к fallback. Отдельного поддерживаемого retry-count knob здесь нет.

Основание — закреплённые исходники, не runtime-наблюдение:

- [AdGuard Home 0.107.78 go.mod](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/go.mod#L5-L8)
  закрепляет embedded dnsproxy `0.83.0`; один timeout передаётся
  [primary](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/dnsforward.go#L547-L552)
  и [fallback](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/dnsforward/dnsforward.go#L678-L698).
- [Embedded plain DNS](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.0/upstream/plain.go#L86-L129)
  повторяет exchange один раз после `net.Error`/EOF;
  [fallback selection](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.0/proxy/proxy.go#L603-L624)
  происходит только после ошибки primary.
- Standalone dnsproxy `0.83.2` может сделать
  [до двух дополнительных DoH exchanges](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/upstream/doh.go#L155-L188)
  при [retryable error уже созданного клиента](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/upstream/doh.go#L335-L357).
  Его [plain UDP retry](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/upstream/plain.go#L86-L129)
  даёт `2F`; [parallel exchange](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/upstream/parallel.go#L22-L65)
  принимает первый успешный DNS-ответ. Numeric DoH stamps исключают отдельный
  DNS bootstrap, TLS verification остаётся включённой.

Граница модели существенна: отдельные dial deadlines, UDP-ответы с TC или
malformed question и последующий TCP exchange могут добавить ожидание.
Private resolver groups, filtering helper lookups, клиентские повторы,
TLS/HTTP frontend establishment, очереди и перегрузка не входят в `B`.
Cache, Unbound stale и дедупликация способны скрыть проверяемый путь.
Unbound `serve-expired-client-timeout = 1800ms` задаёт ожидание перед допустимым
stale-ответом, а не общий срок рекурсии. Эти свойства не меняются.
Для полной клиентской задержки Clanwright измеряет запрос от отправки до
финального ответа с фактической filtering/frontend policy; выход за `B` в
другом сценарии нельзя выдавать за нарушение доказанного общего deadline.
При обновлении любой из закреплённых библиотек модель повторов пересматривается.

На Harbor наблюдавшиеся около `20s` согласуются с двумя прежними попытками
по `10s`, но не устанавливают причину отказа Unbound. `exchange failed`
описывает попытку primary и не доказывает отсутствие fallback либо клиентский
SERVFAIL. Требуемая [consumer-приёмка](../../docs/operations/adguardhome.md#consumer-runtime-acceptance-specification)
сопоставляет попытки с итоговым ответом отдельно для A и AAAA.

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

Safe Search schema сверена с
[`SafeSearchConfig`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/internal/filtering/safesearch.go#L18-L32)
и [`OpenAPI`](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.78/openapi/openapi.yaml#L2679-L2698)
AdGuard Home 0.107.78, а внешняя семантика — с актуальной официальной
[`Configuration` wiki](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration).
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
