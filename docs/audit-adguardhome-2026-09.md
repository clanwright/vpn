# AdGuard Home: аудит на 7 сентября 2026

## Статус

Полный отдельный разбор серверного модуля, дополняющий
[аудит Unbound](audit-unbound-2026-09.md). Схема AdGuard + локальный
рекурсивный Unbound + encrypted fallback уже выбрана. Настройки ниже —
рекомендации для обсуждения, кроме явно отмеченных принятых требований.
Изменены только документы; runtime, пакеты, DNS, сертификаты и секреты не менялись.
База исследования — 7 сентября; финальная сверка точного кода и документа
завершена 8 сентября 2026. Планируемые релизы не считаются опубликованными.

## Принятые решения 8 сентября

- Primary — AdGuard Home с локальным рекурсивным Unbound.
- Encrypted fallback — Cloudflare Standard, Quad9 без threat blocking с
  DNSSEC validation и Google Public DNS; все три провайдера опрашиваются
  параллельно. Yandex полностью исключен из резервов, включая plaintext.
- Plaintext DNS допустим только как последний аварийный путь после ошибок
  обмена с primary и всеми encrypted resolvers, одинаково для selective и
  full. Точные plaintext-адреса еще не выбраны.
- DNSSEC обязателен на primary и encrypted fallback. NXDOMAIN, SERVFAIL и
  DNSSEC bogus не являются поводом перейти на plaintext и обойти результат.
- Родительский контроль и Safe Search остаются включенными. Выключается только
  удаленный Safe Browsing; HaGeZi Multi NORMAL и URLHaus сохраняются.
- Stale разрешен только в Unbound после попытки обновления. В AdGuard приняты
  `cache_ttl_min=0` и `cache_optimistic=false`; точные сроки stale и таймауты
  остаются рекомендациями для проверки при реализации.
- Query log хранится 7 дней без IP-анонимизации, statistics — 90 дней. Для
  service journal сохраняется текущая политика без нового произвольного срока.
- Общий публичный DoH разрешен без per-device auth и ClientID. Автоматическое
  включение в профили и настройка домашнего DNS на роутере сохраняются.
  Конкретные load controls остаются consumer-задачей без выбранных значений;
  WAN-доступ к plain DNS и UI остается закрытым.

Это целевая политика, а не описание уже внедренной конфигурации. Plaintext-путь
сознательно слабее: для него не обещаются шифрование, аутентификация канала или
сквозная DNSSEC-защита. DNS-исключение не разрешает DIRECT для защищенного
web/app traffic. При полном отказе AdGuard аварийный путь может временно обойти
parental, Safe Search и пользовательские фильтры ради доступности; fallback
через работающий AdGuard продолжает проходить его фильтрацию.

## Текущее состояние и основные находки

Проверен [серверный модуль](../clanServices/adguardhome/default.nix) базовой
ревизии `06b5652`. Consumer может переопределять значения через
`adguard.extraSettings`; таблица описывает defaults, а не работающие серверы.

| Область | Сейчас | Вывод |
|---|---|---|
| Пакет | 0.107.78 | Целевой stable 0.107.79; не путать планируемый 0.107.80 с опубликованным релизом |
| Primary | Четыре внешних адреса Cloudflare/Quad9, `parallel` | Не соответствует выбранному локальному Unbound без явной consumer-привязки |
| Fallback | Google DoH и AdGuard Unfiltered DoH | В проверенном 0.107.79 fallback не получает настроенный bootstrap; возможен цикл через системный resolver |
| Bootstrap | Публичный plaintext DNS, включая IPv6 | Это запросы имен upstream с сервера; не шифрованный bootstrap и не доказанный клиентский leak |
| DNSSEC | `enable_dnssec=true` | DO-флаг к upstream, а не собственный валидатор AdGuard |
| Кэш | 32 MiB, min TTL 300, optimistic stale до 12 часов | Нежелательное продление коротких TTL и второй stale-слой поверх Unbound |
| ECS / AAAA | ECS выключен, AAAA разрешены | Сохранить; ответы AAAA и возможность IPv6 transport — разные вопросы |
| Plain DNS | `bind_hosts=["::"]`, port 53, firewall contribution только tailscale0 | Проверить итоговую WAN-изоляцию, сузить bind к нужным адресам |
| Public DoH | Caddy публикует точный `/dns-query`, allowed_clients пуст | Нет ограничения кругом пользовательских устройств |
| Backend TLS | HTTPS loopback 8444, задан SNI, но `tls_insecure_skip_verify` | Убрать обход проверки сертификата, сохранив корректный SNI и доверенную цепочку |
| UI | HTTP loopback 3000; Caddy UI route разрешен по tailnet listener | Полезная изоляция, но `auth.enable=false` по умолчанию не обеспечивает admin auth |
| Auth lifecycle | SOPS `acme:acme 0440`, пустые restartUnits | Изменение secret само по себе не доказывает обновления действующего пароля |
| Конфигурация | `mutableSettings=false` | Изменения из UI не должны считаться постоянным источником истины |
| Логи | Query log 7 дней, statistics 90 дней, IP без анонимизации | Сохранить все три значения; для service journal оставить текущую политику |

Дополнительные проблемы: недостаточная проверка портов/IP/имен и свободных
attrs; имя admin подставляется в YAML; пароль передается htpasswd аргументом;
временный auth fragment не имеет cleanup trap. Нужны безопасная сериализация,
stdin вместо передачи пароля в argv и проверка результата на фиктивных данных.
Ошибки не доказывают произошедшую утечку, а текущий живой пароль не проверялся.

## Версия и безопасность

Рекомендуем [AdGuard Home 0.107.79](https://github.com/AdguardTeam/AdGuardHome/releases/tag/v0.107.79),
опубликованный 17 августа. В [changelog точного тега](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.79/CHANGELOG.md)
есть исправление обработки блокированных запросов без EDNS OPT и усиление
защиты DoQ от истощения ресурсов. DoQ в нашем профиле выключен, поэтому
DoQ advisory не объявляется активной уязвимостью этого listener.

Upstream также обновил Go до 1.26.6 ради security fixes. Для Nix-сборки
важен фактический compiler/toolchain, а не только версия приложения: смена
source tag сама по себе не доказывает включение исправлений Go.
`strict_sni_check` в 0.107.79 deprecated; не включать его как универсальное
усиление и убрать из управляемого baseline после проверки миграции.

## Один целевой DNS-профиль

| Настройка | Решение или рекомендация (принятые требования перечислены выше) |
|---|---|
| Primary upstream | Только локальный Unbound, явный `127.0.0.1:5335` |
| Mode | `load_balance`; с одним primary нет гонки внешних resolver с Unbound |
| Encrypted fallback | Cloudflare Standard + Quad9 без threat blocking с DNSSEC + Google Public DNS, параллельно; Yandex исключен |
| Plaintext fallback | Последний аварийный путь только после ошибок обмена primary и всех encrypted upstream; точные адреса не выбраны |
| Startup | AdGuard продолжает запускаться при недоступном Unbound; убрать жесткую зависимость readiness |
| upstream_timeout | 10s как исходный бюджет холодной рекурсии, с измерением полного fallback latency |
| DNSSEC | `enable_dnssec=true`; валидация Unbound и validating fallback, без обхода bogus через непроверенный резерв |
| Cache | enabled, 32 MiB; `cache_ttl_min=0`, `cache_ttl_max=0`, `cache_optimistic=false` |
| Stale | Только Unbound по отдельному аудиту; не два независимых слоя |
| ECS | Выключен |
| AAAA | Не подавлять глобально; `aaaa_disabled=false` |
| DNS64 / DHCP | Выключены; не добавлять без соответствующей сетевой архитектуры |
| Private PTR | `use_private_ptr_resolvers=false`; частные зоны при необходимости задает consumer адресно |
| hostsfile | Выключить для ответов клиентам, если consumer не объявляет явной потребности; личные host entries не должны случайно менять DNS всех устройств |
| DDR | Выключить для исходного явно управляемого DNS-профиля; автодискавери не должен объявлять недоступный backend port |
| HTTP/3 / DoQ / DoT | Не включать; выбран HTTPS frontend через Caddy, без добавления transport |
| pending_requests | Сохранить enabled |
| Goroutines/resources | Не увеличивать текущие лимиты без измерений очередей и памяти |
| Plain UDP rate limit | Для целевого private-only DNS выключить (`0`) после подтверждения WAN-изоляции; не применять общий /24 лимит к собственным устройствам |

Общий принцип: фильтрация управляется локально в AdGuard; fallback не должен
скрыто добавлять семейную или иную несовпадающую политику блокировки.
DNSSEC не шифрует запросы Unbound к authoritative DNS. Серверный bootstrap
и отдельный клиентский fallback — разные пути; их нельзя считать взаимозаменяемыми.
Основание по ключам: [официальная конфигурация](https://adguard-dns.io/kb/adguard-home/configuration/).

**Семантика fallback проверена по точному коду.** В dnsproxy 0.83.2 переход
происходит при ошибке обмена с primary, а не по RCODE. Полученный корректный
ответ SERVFAIL/NXDOMAIN возвращается клиенту; private PTR исключен из fallback.
Резервные upstream опрашиваются параллельно независимо от режима primary.
Следовательно, отказ DNSSEC сохраняется, но SERVFAIL из-за иной проблемы
рекурсии также не будет исправлен резервом. Не объявляем эту схему защитой
от любого DNS-отказа и не включаем обход SERVFAIL ценой DNSSEC.
Источник: [dnsproxy точного тега](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/proxy/proxy.go).

Выбранную трехступенчатую последовательность текущий плоский список fallback
AdGuard сам не выражает. Отдельный loopback `dnsproxy`, который параллельно
опрашивает encrypted providers и лишь затем использует plaintext, остается
кандидатом: архитектура не одобрена и не реализована. Второй кандидат —
`sing-box` 1.14 с `evaluate`/`race`, найденный по исходникам; закрепленный
1.13.19 этой возможности не имеет. Кандидат требует тестов parser и runtime,
поэтому преждевременно объявлять такую реализацию невозможной или выбранной.

Провайдерские свойства сверять по официальным описаниям:
[Cloudflare для операторов](https://developers.cloudflare.com/1.1.1.1/infrastructure/network-operators/),
[адреса и функции Quad9](https://quad9.net/service/service-addresses-and-features/) и
[FAQ Google Public DNS](https://developers.google.com/speed/public-dns/faq).
Расширенное исследование вариантов каскада и границ их проверки находится в
[основном аудите](audit-2026-09.md#исследование-dns-каскада-от-8-сентября).

В AdGuard 0.107.79 `setupFallbackDNS` не передает настроенный Bootstrap,
в отличие от primary upstream. С учетом `systemResolver.enableLocalStub=true`
hostname fallback может снова потребовать работающий AdGuard. Рекомендуем
выбирать резерв с заранее заданным адресом подключения и проверяемой TLS
identity, без обращения к host resolver для его bootstrap. Просто заполнить
`bootstrap_dns` недостаточно. Источник:
[AdGuard fallback setup](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.79/internal/dnsforward/dnsforward.go).

## Фильтры и влияние на доступность в РФ

Сейчас включены HaGeZi Multi NORMAL, URLHaus, удаленный Safe Browsing,
родительский контроль и принудительный Safe Search большинства поисковиков.
В defaults также есть личные блокировки/исключение. Это дополнительная
политика ограничений, не настройка обхода блокировок РФ.

Рекомендуем сохранить **HaGeZi Multi NORMAL + URLHaus**, обновление раз в
24 часа и отдельные постоянные пользовательские allow/deny rules в consumer.
Не добавляем более агрессивный Multi Pro/Ultimate или множество перекрывающихся
списков. [Автор HaGeZi](https://github.com/hagezi/dns-blocklists) позиционирует
Normal как вариант с небольшим риском ограничений; это не гарантия отсутствия
false positives на пользовательских приложениях.

Принято сохранить `parental_enabled` и `safe_search.enabled`, а отключить только
удаленный `safebrowsing_enabled`. Защита от вредоносных доменов остается в
локальных HaGeZi Multi NORMAL и URLHaus. Удаленный Safe Browsing добавляет
внешний сервис к DNS filtering path; его отключение не означает отключения
остальной фильтрации. Не удаляем личные правила без переноса в consumer.

Сохраняем filtering/protection и `blocking_mode=default`; blocked TTL
рекомендуем сократить с 60s до upstream default 10s, чтобы исправленное
исключение быстрее подхватывалось клиентами. Это TTL отфильтрованных ответов,
а не authoritative TTL или stale-кэш.
При ошибке загрузки фильтра нужен последний рабочий список и видимый возраст
данных. Проверить это на точной версии; не принимать пустой/поврежденный ответ
за успешное обновление. Пользовательские исключения должны переживать restart
и обновление списков; изменение только через UI при declarative config этого
не гарантирует.

`private_networks=[]` означает встроенные локальные диапазоны для обработки
private PTR, а не запрет ответов с частными IP. Поэтому не считаем этот
параметр защитой от DNS rebinding. Добавление rebind-фильтра потребует
проверки собственных split-DNS/tailnet имен и точных исключений; в исходный
набор фильтров без этой проверки его не добавляем.

Списки блокировок РФ, используемые для VPN routing, не становятся DNS denylist.
При отказе сайта проверяем query log и причину ответа: фильтр, DNSSEC,
upstream timeout и блокировка TCP/IP — разные отказы. Не исправляем их массовым
отключением DNSSEC, AAAA или добавлением всех доменов категории в allowlist.

## DNS, DoH и административный доступ

Plain DNS привязать к loopback и явно выбранным частным адресам; WAN/53 закрыт
по обеим IP families. UI сохраняет tailnet-only доступ с обязательной auth.
Нативные backend ports 3000/8444 не должны обходить Caddy policy с WAN.
В точном upstream HTTPS listener использует DNS `bind_hosts`, а не `ui.host`.
Поэтому loopback для Caddy требуется включать явно; привязка только UI
к 127.0.0.1 не обеспечивает такую же привязку HTTPS backend.
TLS-проверку Caddy → AdGuard включить с текущим server name и доверенным
сертификатом; не заменять это случайным plaintext listener на всех интерфейсах.

Для персонального публичного DoH выбран общий endpoint без индивидуальной
ручной настройки устройств. Ранее предложенные per-device ClientID не выбираем.
Upstream поддерживает ClientID в URL и allowed_clients, но это справка о
возможностях, а не требование целевой схемы. Использование общего endpoint
третьими лицами разрешено. Load controls принадлежат consumer и должны быть
проверены отдельно; конкретные лимиты не выбраны. Общий адрес не является
аутентификацией.
Источники:
[secure setup](https://adguard-dns.io/kb/adguard-home/running-securely/),
[ClientID](https://adguard-dns.io/kb/adguard-home/clients/).

Проверить доверие к proxy headers: Caddy должен передавать реальный адрес
без доверия произвольному клиентскому X-Forwarded-For, а AdGuard доверять
только фактическому loopback proxy. Иначе per-client ACL/статистика неверны.
В точном dnsproxy 0.83.2 `ratelimit=20` применяется только к plain UDP,
а не DoH/TCP/DoT/DoQ/DNSCrypt. Он группирует источники по /24 и /56 и молча
отбрасывает превышение. В AdGuard 0.107.79 при создании middleware также
не передается `RatelimitWhitelist` в `AllowlistAddrs`: по исходникам текущие
loopback исключения не действуют; runtime-воспроизведение еще не выполнено.
Поэтому для выбранного закрытого plain DNS рекомендуем rate limit 0 после
подтверждения сетевой изоляции, сохраняя `refuse_any=true`. Это не рекомендация
выключать лимит у публичного UDP resolver. Доступ и ограничение злоупотреблений
публичным DoH решаются отдельно во frontend/consumer.
Источники: [AdGuard wiring](https://github.com/AdguardTeam/AdGuardHome/blob/v0.107.79/internal/dnsforward/config.go),
[точный limiter](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/ratelimit/ratelimit.go).

## Управление и журналы

Сохраняем query log **7 дней**, IP-анонимизацию не включаем. Statistics
сохраняем **90 дней**. Для service journal сохраняем текущую политику, не вводя
новый произвольный срок; service log — не verbose, без credentials.
Caddy DoH access log может содержать `dns=` из GET-запроса и ClientID в path;
не сохранять полный URL, оставить обезличивание только секретной части URL,
а не IP клиента. Это отдельная настройка consumer, не глобальное удаление
диагностики всех Caddy sites.

UI session TTL сейчас 30 дней; рекомендуем 24 часа, сохраняя 5 попыток auth
и 15 минут блокировки. Runtime auth-secret должен читаться только нужным
процессом, корректно применяться при ротации и не появляться в argv/logs.
Изменения в UI использовать для диагностики; постоянные фильтры и настройки
фиксировать в декларативном источнике. Native DNS sandbox NixOS сохраняем.

## Приемка будущего изменения

Проверить полную конфигурацию точной версии и миграцию state; DNSSEC valid/bogus;
cold/cache/stale; недоступный и медленный Unbound, fallback и возврат к primary;
NXDOMAIN/SERVFAIL отдельно от timeout; bootstrap при пустом кэше и отказе
локального DNS; A/AAAA и private PTR; ложную блокировку и постоянное исключение;
неудачное обновление фильтра; auth rotation и certificate reload;
DoH GET/POST и proxy headers; недоступность UI/backend/plain DNS с WAN.

До live-проверки это source audit. Нет доказанной приемки на Дом.ру,
Т-Мобайл/Yota и нет основания объявлять DNS encryption гарантией обхода
российского IP/SNI/allowlist-фильтра. Не выбраны точные plaintext resolver и
не реализована архитектура, которая гарантирует их использование только после
исчерпания всех encrypted exchange paths.
