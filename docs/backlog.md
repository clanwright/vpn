# Backlog

## Новые VPN-протоколы — сентябрь 2026

Пользователь запросил добавить реализацию Mieru, AnyTLS, TrustTunnel и Sudoku
в бэклог. Mieru реализован в этой ветке на stock 3.36.0, AnyTLS — на stock
sing-box 1.14.0 по решениям 12 сентября 2026; TrustTunnel и Sudoku
**запланированы для отдельного обсуждения и внедрения**.
Release и активация сервисов не входят в согласованный объём.
Исследование upstream — 8 сентября, уточнение Mieru и AnyTLS — 12 сентября 2026.

Серверная архитектура проектируется первой; старые клиенты не ограничивают
выбор. При этом клиентский экспорт и проверка совместимости входят в результат
каждой задачи, а не считаются автоматически доступными. Проектирование
согласованного DNS-каскада не блокирует эти задачи.

### Общие требования к четырем задачам

- Каждый протокол — независимо включаемый модуль и отдельный systemd process;
  не добавлять их в общий runtime существующих VPN. Сохранить существующие
  module IDs. Новые IDs и расширение закрытого provider/export contract
  оформляются явно, без ослабления schema до произвольных attrs.
- Пакет и исходники закрепить точно; проверить toolchain и применимость
  advisories, а перед реализацией повторить проверку актуальных релизов.
  Не использовать установочные скрипты с автоматическим изменением хоста.
- Credentials генерируются и подставляются только через runtime-secret путь.
  Значения, ключи и рабочие URL не попадают в Git/Nix store/артефакты checks.
  Проверить доступ к публичным назначениям и запрет внутренних/metadata сетей
  по literal IP и результатам DNS. Доступ к LAN остается отдельной policy.
- Consumer выбирает адрес/порт, сертификат при необходимости и exposure.
  Несколько standalone процессов не могут одновременно занять один TCP endpoint.
  Не добавлять скрытый L4 multiplexer, новые IP или HTTP/3 как побочный эффект.
- Отдельная consumer-приемка: parser точного пакета, положительная/отрицательная auth, listener
  scope, download/upload, reconnect/idle, sustained transfer и CPU/RAM;
  UDP relay — только при подтвержденной поддержке. GUI health не заменяет эти
  проверки. Финальная доступность проверяется с Дом.ру, Т-Мобайл и Yota.
  Эти runtime-сценарии не выполняются в репозитории: его gate ограничен pure
  Nix evaluation и статической гигиеной согласно [verify](operations/verify.md).
- Сохраняются принятые selective/full, видимость всех server–protocol pairs,
  ручной выбор без автоматической подмены и отсутствие скрытого DIRECT.
  Новый протокол не получает статус рабочего только из-за наличия в Auto.

Контролируемой сентябрьской матрицы на трех пользовательских сетях пока нет.
Рекомендуемые реализации ниже — инженерный выбор исходного профиля,
не обещание обхода IP/ASN allowlist, максимальной скорости или неразличимости.

### Рекомендуемый порядок

| Очередь новых протоколов | Реализация на 08.09.2026 | Зачем добавлять |
| --- | --- | --- |
| 1. Mieru | native `mita` 3.36.0 (согласовано 12.09) | Независимый транспорт без TLS и зависимости от сертификата |
| 2. AnyTLS | отдельный sing-box 1.14.0 | TLS-транспорт с padding и повторным использованием сессий |
| 3. TrustTunnel | официальный endpoint 1.1.0 | Передача TCP и UDP через HTTP/2 |
| 4. Sudoku | SUDOKU-ASCII/sudoku 0.5.0 | Дополнительный эксперимент с преобразованием трафика и HTTPMask |

Это предложение порядка по разнообразию транспорта и стоимости сопровождения,
а не рейтинг обхода блокировок. Новые протоколы не вытесняют исправления
безопасности Unbound и уже согласованную работу над существующими протоколами.
Выбор ниже — рекомендация для обсуждения, не уже утвержденная конфигурация.

### Mieru: отдельный native mita

**Согласованный объём:** модуль для `mita` из stock Mieru **v3.36.0**,
с точным кешированным пакетом, типизированным конфигом и самостоятельным unit.
Пользователь разрешил эту версию 12.09.2026, чтобы не блокировать интеграцию
ожиданием NixOS cache для v3.36.1. Обновление до v3.36.1 остаётся отдельным
пунктом: оптимизация CPU и исправление совместимости внешнего SOCKS5 UDP egress.
Stock-пакет 3.36.0 берётся из уже закреплённого `modern-apps-nixpkgs`.
Реализация и настройки: [модуль Mieru](../clanServices/mieru/README.md).
Runtime-приёмка consumer остаётся отдельной работой.

Согласованный исходный профиль:

- Один внешний TCP listener через `portBindings`; внешний UDP listener пока
  не включать. Поддержку UDP relay внутри TCP проверять отдельно от транспорта.
- Отдельный пользователь и пароль на устройство через `users`; синхронизация
  времени обязательна для протокольной аутентификации.
- Оставить штатный `trafficPattern`: не включать low-entropy shaping,
  пользовательские шаблоны и дополнительный padding без измеренной пользы.
  `mtu` относится к внешнему UDP и не нужен для выбранного TCP профиля.
- Не разрешать private/loopback/link-local/metadata назначения. Native flags
  проверяют TCP до DNS-разрешения и не проверяют назначения отдельных UDP
  датаграмм, поэтому модуль добавляет nftables guard для своего процесса.
  Разрешены узкие DNS-исключения по адресам resolver consumer. Начальный
  серверный egress IPv4-only согласован с текущими профилями; IPv6 на машине
  целиком не отключается. DNS хоста остаётся consumer-owned.
- Не требовать TLS-сертификат или домен: это собственный зашифрованный протокол,
  а не имитация HTTPS. Не добавлять обязательный user hint без проверки
  совместимости выбранного клиентского протокола.
- Экспорт — только Mihomo YAML selective/full; pinned Mihomo поддерживает
  Mieru/TCP и UDP relay. Consumer выбирает providers; выбранный Mieru участвует
  в ручных selectors и Auto на общих основаниях, без отдельного trial-only
  ограничения. Official sing-box не получает Mieru outbound.
- Штатные клиентские `MULTIPLEXING_LOW` и `HANDSHAKE_STANDARD`, без custom
  traffic pattern. Native Mieru JSON/URI не входит в первую реализацию.
- `mita` не умеет привязку к выбранному IP: wildcard TCP listener ограничивается
  модульными ingress rules по заданному consumer IPv4. Конфликт порта и
  размещение процесса остаются обязанностью consumer.

Приемка сверх общих проверок: отзыв одного пользователя без отзыва остальных,
ошибка при неверном пароле, поведение при рассинхронизации часов, TCP и UDP
relay, idle/reconnect и расход CPU. Российские пользовательские сообщения
служат основанием попробовать Mieru, но не доказывают работу на трех наших сетях.

Источники: [реализуемый релиз 3.36.0](https://github.com/enfein/mieru/releases/tag/v3.36.0),
[последующий релиз 3.36.1](https://github.com/enfein/mieru/releases/tag/v3.36.1),
[серверная схема точного тега](https://github.com/enfein/mieru/blob/v3.36.0/docs/server-install.md),
[протокол](https://github.com/enfein/mieru/blob/main/docs/protocol.md),
[traffic patterns](https://github.com/enfein/mieru/blob/main/docs/traffic-pattern.md),
[обсуждение использования в РФ](https://github.com/enfein/mieru/discussions/263).

### AnyTLS: отдельный sing-box inbound

**Согласовано и реализовано 12 сентября 2026:** отдельный модуль AnyTLS на
stock **sing-box v1.14.0**, независимо от Naive и остальных runtime.
Реализация и настройки: [модуль AnyTLS](../clanServices/anytls/README.md).
Предпочтение sing-box основано на документированной конфигурации и интеграции
с пакетной базой проекта; это не утверждение об уязвимости reference-сервера
anytls-go. Release, consumer adoption и runtime-приёмка остаются отдельно.

Согласованный исходный профиль:

- Inbound `type = "anytls"`, явные `listen`/`listen_port`, отдельные `users`
  и обычный проверяемый TLS-сертификат, **только TLS 1.3** по решению владельца.
  TCP 443 предпочтителен только при
  наличии свободного согласованного endpoint.
- Штатный padding: `padding_scheme` не переопределять. Не добавлять REALITY,
  произвольные padding-рецепты или незапрошенный fallback.
- Сохранить штатную работу сессий. `idle_session_check_interval`,
  `idle_session_timeout`, `min_idle_session` — клиентские параметры,
  не серверные настройки inbound.
- Внешний транспорт — TLS/TCP; UDP передается внутри TCP через UoT v2.
  Входящий UDP-порт не нужен, а задержки UDP при потерях TCP остаются ограничением.
- Серверный egress IPv4-only, как у Mieru; IPv6 машины целиком не отключается.
  Процессный guard запрещает private/metadata назначения, включая результаты
  DNS, без исключений для приватных DNS-адресов.
- DNS AnyTLS использует только свой AdGuard через публичный DoH endpoint,
  заданный consumer: hostname, публичный IPv4, port и path. Числовой адрес
  обеспечивает bootstrap, hostname сохраняется для проверки TLS и HTTP.
  Системный DNS машины не меняется; системного или стороннего DNS fallback нет.
- Экспорт в Mihomo YAML selective/full и sing-box JSON. Выбранные consumer
  providers участвуют в ручном выборе и Auto как остальные протоколы;
  существующий `autoProtocols` управляет автоматическим выбором.
- Не добавлять клиентские metadata, TCP Fast Open или произвольные TLS/ALPN
  настройки. Прямой listener не имеет HTTP fallback: успешный TLS handshake
  не означает, что endpoint отвечает как обычный сайт при active probing.

Проверка upstream 12 сентября подтвердила точные схемы sing-box 1.14.0 и
совместимость формата Mihomo 1.19.30. Контролируемых измерений AnyTLS за
август–сентябрь на наших трёх операторах не найдено; это основание для отдельной
приёмки, а не обещание обхода блокировок.

Приемка: проверка TLS identity и отрицательная проверка неправильного
сертификата на контрольном клиенте, пользовательская auth, повторное
использование сессий, длительные соединения и UoT v2. Не считать наличие
AnyTLS в клиенте доказательством корректного UDP relay.

Источники: [sing-box 1.14.0](https://github.com/SagerNet/sing-box/releases/tag/v1.14.0),
[AnyTLS inbound](https://sing-box.sagernet.org/configuration/inbound/anytls/),
[исходники exact inbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/protocol/anytls/inbound.go),
[исходники exact outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/protocol/anytls/outbound.go),
[Mihomo AnyTLS](https://wiki.metacubex.one/en/config/proxies/anytls/),
[reference implementation](https://github.com/anytls/anytls-go),
[протокол v0.0.13](https://github.com/anytls/anytls-go/blob/v0.0.13/docs/protocol.md).

### TrustTunnel: официальный endpoint, HTTP/2

**Задача:** добавить официальный **TrustTunnel v1.1.0** (01.09.2026)
как отдельный серверный модуль. В этой версии исправлены утечка UDP sockets
по timeout и классификация глобальных IPv6 адресов. Старые сообщения о сбоях
не означают, что эти дефекты сохраняются в выбранном релизе.

Рекомендуемый исходный профиль:

- Только `listen_protocols.http2`, без блока `listen_protocols.quic`.
  Обычный TLS-сертификат, отдельные отзываемые credentials; один публичный
  TCP endpoint. HTTP/3 не входит в эту задачу.
- `allow_private_network_connections = false`; проверить запреты по IP,
  DNS-именам и после резолвинга. Не включать reverse proxy к внутреннему
  origin без отдельной потребности.
- `per_client_metrics = false`; endpoint метрик доступен только оператору.
  Включение метрик с username/IP не требуется для проверки здоровья протокола.
- Начальная приемка — TCP и UDP через H2. ICMP не включать в обязательный
  контракт первого внедрения; проверить возможность его отключения в точном
  пакете и не выдавать raw-network capabilities автоматически.
- Конфиги `vpn.toml`, `hosts.toml`, `credentials.toml`, `rules.toml`
  генерировать и валидировать согласованно; credentials только в runtime.

Приемка: длительная передача более 1 GiB, ограниченный рост RSS и числа sockets,
UDP timeout cleanup, reconnect после обрыва H2, отрицательная auth и доступ
к private/metadata назначениям. Предыдущие отчеты о panic/reconnect служат
сценариями регрессии, а не доказательством блокировки операторами РФ.
Проверить оба security advisory; исправления вышли в 0.9.114 и 0.9.115,
поэтому не помечать 1.1.0 затронутым только по наличию advisory.

Источники: [релиз 1.1.0](https://github.com/TrustTunnel/TrustTunnel/releases/tag/v1.1.0),
[конфигурация](https://github.com/TrustTunnel/TrustTunnel/blob/master/CONFIGURATION.md),
[протокол](https://github.com/TrustTunnel/TrustTunnel/blob/master/PROTOCOL.md),
[SSRF advisory](https://github.com/TrustTunnel/TrustTunnel/security/advisories/GHSA-hgr9-frvw-5r76),
[prefix-rule advisory](https://github.com/TrustTunnel/TrustTunnel/security/advisories/GHSA-fqh7-r5gf-3r87),
[отчет о памяти/panic](https://github.com/TrustTunnel/TrustTunnel/issues/140),
[отчет о reconnect](https://github.com/TrustTunnel/TrustTunnel/issues/144).

### Sudoku: самостоятельный сервер, ограниченное испытание

**Задача:** добавить canonical **SUDOKU-ASCII/sudoku v0.5.0** (05.09.2026).
Не подменять его несовместимым Xray `finalmask`. В 0.5.0 исправлены обрывы
mux при высокой конкуренции и удалены устаревшие реализации HTTPMask.

Рекомендуемый исходный профиль по текущему upstream server template:

- `mode = "server"`, `transport = "tcp"`, один `local_port`;
  `aead = "chacha20-poly1305"`, никогда `none`.
- `padding_min = 5`, `padding_max = 15`, `ascii = "prefer_entropy"`,
  `enable_pure_downlink = true`; без пользовательских таблиц.
- `multiplex = "off"` для исходного профиля. Исправление mux в новом релизе
  само по себе не доказывает пользу его включения на наших путях.
- HTTPMask: `disable = false`, `mode = "auto"`;
  `suspicious_action = "fallback"`, fallback только на локальный decoy.
  Подготовка decoy и возможная TLS termination должны быть явными частями
  consumer composition. Не предполагать наличие серверных TLS-полей по
  клиентскому полю `tls` и не обещать HTTPS-маскировку голого TCP endpoint.
- TCP relay и UDP через UoT; отдельный публичный UDP listener не нужен.

Перед фиксацией конфигурации реализации сверить template/schema именно с
тегом 0.5.0: текущая документация изменяемая, а минимальный client example
использует HTTPMask `ws`, когда server example — `auto`. Проверить их
совместимость, место TLS termination, модель ключей и индивидуального отзыва;
не обещать per-device credentials до подтверждения серверной схемой.

Приемка: неправильный ключ/AEAD, устойчивость fallback к probing без раскрытия
служебных ошибок, HTTPMask interop, UDP relay, reconnect и длительная нагрузка.
Теория энтропии и заявления upstream не заменяют измерение доступности в РФ.
До приемки держать отдельным испытательным профилем, не включать в рабочий Auto.

Источники: [релиз 0.5.0](https://github.com/SUDOKU-ASCII/sudoku/releases/tag/v0.5.0),
[canonical upstream](https://github.com/SUDOKU-ASCII/sudoku),
[configuration guide](https://github.com/SUDOKU-ASCII/sudoku/blob/main/configs/README.md),
[server template](https://github.com/SUDOKU-ASCII/sudoku/blob/main/configs/server.config.json),
[Mihomo Sudoku schema](https://wiki.metacubex.one/en/config/proxies/sudoku/).

### Что решить при подключении к consumer

Для выбранного протокола определить конкретный consumer endpoint: доступный
IP/порт, сертификат или decoy при необходимости. Это реальная граница решения:
на одном IP несколько независимых TCP-серверов не займут одновременно 443.
Сейчас не предполагается покупка IP, скрытый multiplexer или замена рабочего
сервиса. Для Sudoku отдельно закрыть TLS termination и отзыв ключей, для
TrustTunnel — поддержку и привилегии ICMP. Остальные обратимые детали пакета,
systemd и checks решаются при реализации внутри утвержденного профиля.

## TCP performance policy

BBR, FQ and the existing TCP sysctl policy remain in the consumer's common
machine layer. A future change may evaluate moving that policy into this domain,
but it requires a separate ownership decision, public contract, checks and
release. It must preserve host applicability and must not silently alter VPN
protocol behavior.

## Package-source cleanup — resolved in the September candidate

The unused standalone NaiveProxy wrapper is removed. The client uses stock
sing-box with native Naive support and stock Cronet; Network's Caddy remains
the explicitly approved custom-package exception. Consumer adoption remains
separate from repository verification.
