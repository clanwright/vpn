# Аудит Unbound — 7 сентября 2026

## Репозиторная доработка от 8 сентября

Реализован кандидат согласованного Unbound-прохода: пакет 1.26.0 с systemd support,
loopback/port contract, host-aware IPv6, мягкая зависимость AdGuard, DNSSEC и
bounded stale. Исходный снимок аудита ниже сохранён для прослеживаемости.
Пакет взят напрямую из уже закреплённого `apps-nixpkgs`, без собственного
override и без изменения lockfile. Наличие точного output в `cache.nixos.org`
проверено; это не является проверкой выполнения бинарного файла.

Окончательная граница проверки от 8 сентября: только pure Nix assertions и
статическая гигиена. Python, VM, Linux builders, application parser/CLI и тесты
на реальных машинах запрещены. Readiness и DNS runtime tests удалены по решению
владельца. Их отсутствие не маскируется успешной проверкой выполнения.

Независимое source review завершено без существенных открытых замечаний.
Исправлены обходы DNSSEC/include и подмена рекурсии через зоны или local-data:
effective directives теперь имеют закрытый набор, remote control выключен.
Отделены семейства исходящей рекурсии от
listener-адресов; отрицательные проверки изолированы друг от друга. Проверка
общей Clan-композиции прошла на уровне evaluation. Полный gate после интеграции
прошёл; результат зафиксирован в [основном аудите](audit-2026-09.md). Runtime-поведение
не входит в согласованную репозиторную приёмку и не объявляется проверенным.

Уточнение trust-anchor finding: upstream допускает status `1` при успешном
использовании builtin anchor/certificate update, а status `0` не отличает все
ошибки от отсутствия изменений/RFC5011 update. Поэтому штатное сообщение NixOS
не доказывает ошибочную обработку; preStart сохранён. Пригодность anchor и
Internet refresh требуют отдельной проверки, а не вывода по одному exit status.

Сначала завершаются все VPN-аудиты, затем отдельно разрешаются релиз
и только потом consumer adoption. Трёхступенчатый DNS-каскад, bootstrap и
frontend cache/timeout policy остаются отдельным аудитом AdGuard.

Операторская приёмка описана в [runbook](operations/unbound.md).

## Решение и границы

Выбрана архитектура AdGuard Home + локальный рекурсивный Unbound на VPN-сервере,
с зашифрованным резервом Cloudflare Standard, Quad9 без threat blocking с
DNSSEC validation и Google Public DNS, опрашиваемым параллельно. Yandex
полностью исключен, включая plaintext fallback. Удаление
Unbound не планируется. Это аудит и рекомендации, не внедренная конфигурация.
Расположение, ресурсы, исходящие маршруты и привязка клиентского DNS к выбранному
VPN-выходу принадлежат consumer; наличие Unbound само не обеспечивает эту привязку.

Проверены исходники базовой ревизии `06b5652`, закрепленный NixOS module и
официальные материалы upstream на 2026-09-07. Рабочие серверы, журналы,
эффективные consumer-конфигурации и сетевые запросы не проверялись.

## Исторический снимок до доработки

| Параметр | Что установлено по исходникам |
|---|---|
| Пакет | Репозиторный `unbound-with-systemd` 1.25.1; целевой upstream 1.26.0 |
| Listener | `127.0.0.1` и `::1`, TCP/UDP 5335 |
| Использование host resolver | `resolveLocalQueries=false`; Unbound сам не подменяет DNS хоста |
| Рекурсия | Роль не задает forward-zone; используются стандартные root hints Unbound |
| DNSSEC | NixOS включает root trust anchor; файл `/var/lib/unbound/root.key`, preStart запускает unbound-anchor |
| Privacy | `hide-identity`, `hide-version`, `qname-minimisation` включены |
| Кеш | `prefetch=true`; прочие параметры в роли не заданы и наследуются |
| AdGuard integration | Добавляет `After` и `Requires`; upstream AdGuard автоматически не меняет |
| Доступ | NixOS ACL по умолчанию разрешает loopback; роль не открывает firewall |
| Проверка | В базовой ревизии был тест `READY=1`; впоследствии удалён по согласованной границе проверки |

Источники проекта: [Unbound module](../clanServices/unbound/default.nix),
[AdGuard module](../clanServices/adguardhome/default.nix),
[контрактные проверки](../checks/unbound-contracts.nix),
[integration fixture](../checks/fixtures/example-clan.nix).

## Обновление безопасности — высокий приоритет

Закрепленный пакет собирается из upstream `release-1.25.1` без security patches.
NLnet Labs 22 июля 2026 опубликовали исправления в 1.25.2, в том числе
CVE-2026-44690 (отравление кеша при aggressive NSEC) и CVE-2026-50045
(обход ограничения числа запросов при DNSSEC validation). Рекурсивный backend
обрабатывает внешние ответы даже при loopback listener; loopback не исключает
этот класс угроз. Эксплуатация на рабочих серверах не проверялась.

**Выбор: обновить до 1.26.0**, сохранив `unbound-with-systemd`. Это приоритетнее
тюнинга кеша. Не все advisories относятся к текущей схеме: проблемы DoQ и
DNSCrypt требуют включенных соответствующих функций, чего роль не делает.

## Что исправить в первую очередь

1. **Независимость AdGuard.** Жесткий `Requires=unbound.service` мешает старту
   AdGuard при неуспешной активации Unbound. Его fallback тогда недоступен.
   Рекомендация: мягкая зависимость запуска без обязательной готовности backend;
   порядок запуска не должен задерживать доступность AdGuard до таймаута Unbound.
2. **Явная привязка backend.** Роль интеграции не задает upstream. В fixture он
   указан вручную, а defaults AdGuard содержат внешние серверы. Для выбранной
   схемы primary должен быть только локальным Unbound; внешние резолверы — в
   отдельном fallback, без гонки с рекурсией. Consumer задает привязку через
   публичный контракт, а интеграционная проверка подтверждает ее.
3. **Проверка listener.** `listen.hosts` принимает любые строки, а порт — любой
   integer, несмотря на обещанный loopback-only backend. Рекомендация: разрешать
   только loopback-адреса, валидный непустой список и порт 1–65535. Явные ACL
   loopback сохранить; внешний listener не добавлять.
4. **IPv4-only hosts.** Роль безусловно добавляет `::1`, заменяя условное поведение
   NixOS. Это не доказанный отказ запуска: upstream включает `ip-freebind`.
   Рекомендация: учитывать host IPv6 policy и отдельно проверить IPv4-only режим.
5. **Trust-anchor observability.** NixOS preStart маскирует ошибку unbound-anchor
   сообщением об обновлении. Это не доказывает отключение DNSSEC, но READY=1 не
   подтверждает пригодность root.key. Проверять существующий и новый anchor,
   журнал обновления и DNSSEC-положительные/отрицательные ответы.

## Выбранные практики кеширования и доступности

Основной принцип: обычный кеш допустим на двух слоях, выдачей просроченных
записей управляет только Unbound. Сначала попытка получить свежие данные,
затем ограниченный stale-ответ для переживания отказов.

| Настройка | Рекомендация | Причина |
|---|---|---|
| Unbound `prefetch` | Сохранить `yes` | Обновлять популярные записи до истечения TTL |
| Unbound `cache-min-ttl` | Сохранить `0` | Не продлевать короткие authoritative TTL |
| Unbound `serve-expired` | Принято `yes` | Переживать временную недоступность authoritative DNS |
| `serve-expired-ttl` | `86400` секунд | Конечный срок устаревших записей; upstream baseline, не гарантия доступности |
| `serve-expired-ttl-reset` | `no` | Не продлевать stale бесконечно при повторных отказах |
| `serve-expired-client-timeout` | `1800` мс | Дать обновлению шанс до выдачи stale; не использовать immediate-stale `0` |
| `serve-expired-reply-ttl` | `30` секунд | Быстро перепроверять аварийный ответ |
| AdGuard `cache_ttl_min` | Изменить `300 → 0` | Не задерживать смену адресов сайтов искусственно |
| AdGuard `cache_optimistic` | Изменить `true → false` | Убрать второй независимый stale-кеш с текущим горизонтом 12 часов |

Stale не помогает для ранее неизвестного имени и может вернуть уже нерабочий
адрес. Это осознанный компромисс доступности; не выключать DNSSEC ради него.
Отдельно проверить сроки подписей, отрицательные ответы и смену адреса сайта.
Точные значения `serve-expired-*` в таблице остаются рекомендациями, которые
нужно утвердить приемочными измерениями; принято само правило, что stale выдает
только Unbound, а AdGuard использует `cache_ttl_min=0` и
`cache_optimistic=false`.

Текущий AdGuard `upstream_timeout=3s` — жесткий бюджет для холодной рекурсии;
его достаточность не измерена. Рекомендую начать с документированного baseline
AdGuard 10 секунд, затем измерить cold-cache и время перехода на encrypted
fallback. Это может увеличить ожидание при «молчащем» backend; приемка должна
измерить весь путь, а не только успешные кешированные ответы.

## Что оставить из upstream defaults 1.26.0

Сохранить EDNS buffer и максимум UDP 1232 байта, поддержку UDP и TCP.
Увеличение размера без измерений повышает риск IP-фрагментации; снижение до
512 увеличивает долю TCP. IPv6 transport включать согласно возможностям хоста,
не смешивая это с выдачей AAAA клиентам.

Сохранить `harden-short-bufsize`, `harden-glue`, `harden-dnssec-stripped`,
`harden-below-nxdomain` и, после обновления пакета, `aggressive-nsec` включенными.
Оставить `prefetch-key` выключенным до измерений. Не включать дополнительные
проверки referral path, strict QNAME и 0x20 casing как универсальное усиление:
они имеют цену совместимости и не решают клиентскую маршрутизацию DNS.

## Безопасность, приватность и эксплуатация

- Сохранить DNSSEC validation и автоматически обслуживаемый root trust anchor.
  DNSSEC обеспечивает подлинность подписанных данных, не шифрование рекурсии.
- Сохранить qname minimisation без strict-режима: совместимость с некорректными
  authoritative серверами важнее максимального сокращения запросов любой ценой.
- Не передавать ECS с домашней подсетью клиента. Для VPN-трафика география DNS
  должна соответствовать месту выхода; это обеспечивается маршрутизацией.
- Не делать публичных DNS/DoH/DoT listeners у Unbound: внешний frontend — AdGuard.
  Незашифрованный loopback между ними допустим; запросы рекурсии к authoritative
  DNS уходят с VPN-сервера и обычно не зашифрованы.
- Не включать отдельный журнал каждого запроса в Unbound: согласованный query
  log 7 дней хранит AdGuard. Диагностику backend вести через ошибки и агрегаты.
- Сохранить пакет с systemd support и `Type=notify`; не заменять unit на simple.
- Не вводить регулярную загрузку root hints из случайных источников или cron:
  встроенные hints и поддержка root trust anchor решают разные задачи.
- Не назначать большие кеши, buffers и число threads по универсальному рецепту.
  Начальный профиль — upstream defaults; изменения только по нагрузке, памяти,
  cache hit/miss, latency и очередям на конкретной машине.

## Приемка будущего изменения

Нужны проверка окончательного rendered config, схемы listener/ACL/порта,
trust anchor и отсутствия случайного forward-zone; DNSSEC valid/bogus и
обычная рекурсия по UDP/TCP; работа при отключенном host IPv6; сохранение
AdGuard при неудачном старте/остановке Unbound; encrypted fallback без циклов
bootstrap; fresh/stale/expired ответы и возврат к свежим данным.

Отдельный отрицательный тест: NXDOMAIN, SERVFAIL и DNSSEC bogus не должны
превращаться в принятый plaintext-ответ через резерв. Сам флаг AdGuard
`enable_dnssec` управляет DO-битом и не заменяет валидатор. DNSSEC обязателен
для primary и encrypted fallback; системное время и выход TCP/UDP 53 к Internet
— условия работы рекурсии, проверяемые в consumer.

Уточнение полного [аудита AdGuard](audit-adguardhome-2026-09.md): dnsproxy
0.83.2 запускает fallback при ошибке обмена, но не при полученном SERVFAIL.
Поэтому DNSSEC bogus не вызывает такой переход, а некоторые другие отказы
рекурсии тоже останутся SERVFAIL. В AdGuard 0.107.79 настроенный bootstrap
не передается fallback upstream; резерв должен обходиться без разрешения
своего имени через системный AdGuard, иначе возможна циклическая зависимость.

Plaintext DNS принят только как сознательно более слабый последний аварийный
путь после ошибок обмена с primary и всеми encrypted providers, и для selective,
и для full. Точные plaintext-адреса не выбраны; Yandex исключен и здесь.
Для plaintext не обещаются шифрование, аутентификация канала или сквозная
DNSSEC-защита. Это DNS-исключение не разрешает protected web/app traffic идти
DIRECT. Полный отказ AdGuard может временно обойти parental, Safe Search и
пользовательские фильтры ради доступности; резерв через живой AdGuard сохраняет
фильтрацию.

Плоский fallback AdGuard не выражает три последовательных уровня. Отдельный
loopback `dnsproxy` (encrypted parallel, затем plaintext) остается кандидатом,
но эта архитектура не одобрена и не реализована. `sing-box` 1.14 с найденными
по исходникам `evaluate`/`race` — второй кандидат; закрепленный 1.13.19 их не
имеет. Нужны parser/runtime-тесты, прежде чем выбирать подход или утверждать,
что каскад невозможен. Подробности и официальные ссылки провайдеров приведены
в [аудите AdGuard](audit-adguardhome-2026-09.md).

## Официальные источники

- [Закрепленный NixOS module](https://github.com/NixOS/nixpkgs/blob/59ea0b1c043c463e39fcb3cfb9a5c8bcf0777c72/nixos/modules/services/networking/unbound.nix).
- [Закрепленный package source](https://github.com/NixOS/nixpkgs/blob/59ea0b1c043c463e39fcb3cfb9a5c8bcf0777c72/pkgs/by-name/un/unbound/package.nix).
- [Unbound 1.26.0 release](https://github.com/NLnetLabs/unbound/releases/tag/release-1.26.0).
- [Manual точного тега 1.26.0](https://raw.githubusercontent.com/NLnetLabs/unbound/release-1.26.0/doc/unbound.conf.5.in).
- [Security advisories NLnet Labs](https://nlnetlabs.nl/projects/unbound/security-advisories/).
- [AdGuard Home configuration](https://adguard-dns.io/kb/adguard-home/configuration/).

Документ рекомендует параметры для выбранной архитектуры; конфигурации,
пакеты, секреты и runtime в ходе этого аудита не изменялись.
