# Hysteria2: актуальность конфигурации на 7 сентября 2026

Независимое source review и полный репозиторный gate кандидата прошли;
доказательства — в [основном аудите](audit-2026-09.md).

Исходная реализация обновлена по согласованному решению; deployment, secrets и
runtime не менялись. Пользователь сообщает о полном отказе прежнего Hysteria2
на Дом.ру, Т-Мобайл и Yota. Причина не установлена; подтвержденного handshake
или transfer после изменения нет.

## Вывод

Обновления Hysteria2 действительно затрагивали маскировку, QUIC, безопасность
и reconnect. Текущая конфигурация проекта не использует все доступные возможности,
но не найдена обязательная новая настройка, отсутствие которой объясняет полный
отказ. Совместимый старый конфиг и оптимальность в текущей сети — разные вопросы.

**Реализованное решение: Gecko вместо Salamander** как единственный целевой
вариант Hysteria2. Пользователь исключил сравнительный этап и параллельный
Salamander-профиль. Server и client contract используют симметричные размеры
512–1200; отдельный stock Mihomo 1.19.30 service больше не делит config, process
или lifecycle с VLESS.
Gecko остается экспериментальным upstream-механизмом; выбор не доказывает,
что причина текущего отказа устранена.

## Что менялось upstream

| Изменение | Применимость к проекту |
|---|---|
| Gecko в официальном Hysteria 2.9.2, 23 мая 2026 | Добавляет фрагментацию и padding handshake поверх обфускации. Поддержка подтверждена по исходникам выбранного ядра и включена в контракт кандидата |
| Chrome QUIC parroting в 2.11.0; улучшение и исправление BBR small-MTU panic в 2.12.0 | Нельзя переносить на Mihomo автоматически: это другая реализация с собственными зависимостями |
| Stateless resets в 2.12.1, 9 августа; переключатель отключения в 2.12.2, 23 августа | Улучшение reconnect после сна/устаревшего соединения. Не объясняет само по себе полный отказ первого подключения |
| Изменение UDP relay совместимости официального клиента 2.8.2 со старым сервером | Касается UDP relay, TCP relay не затронут. Не установлено, что пользователь использует такую пару |

Официальный Hysteria 2.12.2 — отдельное приложение, не «версия Hysteria внутри
Mihomo». Замена server/client implementation ради его функций — отдельная
архитектурная миграция, которой для Gecko не требуется.

## Что есть в нашей реализации

Пакет проекта Mihomo 1.19.30; на Mac найден bundled Mihomo 1.19.29. Фактические
серверные процессы, Android и Nikki cores не проверены. Mihomo 1.19.30 закрепляет
MetaCubeX/sing-quic `38b0e9295f51` от 26 июля; 1.19.29 — `68e10a6afdc3` от 27 мая.

| Поле | Реализованный renderer | Оценка |
|---|---|---|
| Protocol | Hysteria2 с обеих сторон | Корректно по исходникам |
| ALPN | `h3` с обеих сторон | Согласован |
| TLS | SNI, certificate и обязательная client verification; systemd передает unit только выбранные certificate/key | Фактический certificate и время проверить при приемке |
| Обфускация | Только `gecko`, min 512 и max 1200 на server/client | Pure contracts подтверждают симметричный generated config, не сетевую эффективность |
| Auth/obfs secrets | Per-device SOPS names, отдельный Gecko secret, unpadded base64url contract | Consumer генерирует и привязывает значения; совпадение runtime не доказано |
| Bandwidth | `up`/`down` отсутствуют, server игнорирует client bandwidth | Штатный BBR без произвольных Brutal rates |
| Порты | Один destination-scoped UDP endpoint | Hopping отсутствует |
| MTU/windows | Не переопределены | Используются defaults Mihomo/sing-quic |
| Runtime | `mihomo-hysteria2.service`, отдельный non-root user и SOPS JSON template | Low port получает только `CAP_NET_BIND_SERVICE`; Realm/Mimic/ECH отсутствуют |
| Masquerade backend | Stock Mihomo отключает certificate verification для исходящего HTTPS cover request | Не влияет на client→listener TLS verification, но cover response не аутентифицирует upstream |
| Placement | Один active instance на `x86_64-linux`, конкретный `listenIPv4`, включенный nftables firewall | Wildcard `0.0.0.0`, второй active instance и другой backend отклоняются assertions |

**Gecko поддерживается симметрично:** outbound есть уже в Mihomo 1.19.29;
listener 1.19.30 явно выбирает Gecko и передает пароль и размеры в ServiceOptions.
Предварительное предположение о поддержке только клиентом по тексту документации
опровергнуто точным исходником. Сервер менять ради Gecko не нужно.

У Mihomo 1.19.30 есть outbound `handshake-timeout`, которого нет в 1.19.29.
Это управление ожиданием handshake, не обход фильтрации. Параметры официального
Hysteria `disableChromeParrot`/`disableStatelessReset` нельзя копировать в Mihomo:
они не представлены в проверенном H2 config API. Отсутствие поля само по себе
не доказывает отсутствие всех похожих механизмов внутри QUIC dependency.

## Статус выбранного направления

1. Repository server закреплен на stock Mihomo 1.19.30. Версии фактических
   client cores и deployed server по-прежнему требуют отдельной проверки.
2. Public provider metadata и client renderer передают Gecko, exact sizes,
   ALPN, TLS verification и base64url credential contract.
3. Server использует Gecko 512–1200; Salamander compatibility path удален.
4. Сохранены TLS verification, ALPN h3, отсутствие bandwidth caps и штатные
   flow-control/MTU. Port hopping, Realm, Mimic и ECH не добавлены.
5. Осталась live-приемка: новое подключение, TCP и UDP relay, длительная передача,
   idle/reconnect на трех пользовательских сетях. HEAD delay test недостаточен.

## Проверка исходной реализации

`checks/hysteria-contracts.nix` pure-evaluates schema, exact JSON, provider
metadata, stock package identity, systemd credentials/capabilities/sandbox и
destination-scoped nftables firewall. Negative contracts отклоняют wildcard bind,
unsupported platform, выключенный/неверный firewall и два active instances.
Проверка не запускает Mihomo или listener и не
использует application parser. Production certificate, secret values, bind,
handshake и traffic остаются непроверенными.

Gecko может помочь при распознавании формы handshake-пакетов, но не исправляет
неверный адрес, пароль, сертификат, закрытый listener или запрет всего UDP.
Salamander/Gecko не имеют обычного внешнего вида HTTP/3; не обещать одновременно
стандартный H3 masquerade на внешнем проводе и включенную обфускацию.

В предыдущей проверке issue Mihomo #2792 исключен для текущего uncapped
renderer: проблемный guard требует `ReceiveBPS > 0`. Автоматическая смена
`ignore-client-bandwidth` не обоснована этим issue.

## Источники

- [Изменения официального Hysteria](https://v2.hysteria.network/docs/Changelog/).
- [Релиз 2.12.2](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.12.2).
- [Описание Gecko](https://v2.hysteria.network/docs/advanced/Full-Server-Config/#obfuscation).
- [Mihomo listener 1.19.30](https://github.com/MetaCubeX/mihomo/blob/v1.19.30/listener/sing_hysteria2/server.go).
- [Mihomo outbound 1.19.29](https://github.com/MetaCubeX/mihomo/blob/v1.19.29/adapter/outbound/hysteria2.go).
- [Mihomo outbound 1.19.30](https://github.com/MetaCubeX/mihomo/blob/v1.19.30/adapter/outbound/hysteria2.go).
- [Точные зависимости](https://github.com/MetaCubeX/mihomo/blob/v1.19.30/go.mod).
- [Server module проекта](../clanServices/mihomo-hysteria2/default.nix).
- [Client renderer проекта](../clanServices/vpn-client-profiles/client-profiles.nix).
