# @clanwright/vpn-client-profiles

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это publisher клиентских конфигураций Mihomo и Sing-box. Он собирает
typed non-secret metadata VPN providers, генерирует профили и связывает их
с Caddy profile page; protocol gateway roles остаются независимыми.

## Settings

Точная схема и defaults определены в [`default.nix`](default.nix), а типы
профилей, provider refs и links page — в [`types.nix`](types.nix).
Входы: `enable`, `localMachineName`,
`configGatewayDomain`, `publicIPv4`, `edgeDomain`, `clientDnsEndpoints`,
`tailnetAdminDomains`, `personalProxyDomains`, `profiles`,
`providerRefs`, `externalSubscriptions`, `profileLinks` и `linksPage`. Provider refs
содержат machine, instance, canonical protocol и optional `display`. Publisher profiles содержат
`name`, `pathTokenSecretName`, `kind` (`mobile` или `router`), optional `publishProfileJson` и
`autoProtocols`. `pathTokenSecretName` — consumer-owned SOPS secret с path token профиля;
модуль использует имя как задано и не строит имена secrets из префиксов или имён машин.
Имена credential secrets собственных серверов приходят из typed providers. Profile links
содержат `name`, `label` и `accountDomain` и используют path token своего профиля.

## External subscriptions

`externalSubscriptions` добавляет сторонние подключения в выбранные профили.
Consumer задаёт имя SOPS-секрета со ссылкой; сам URL читается только в runtime.
Пустой attrset по умолчанию сохраняет публикацию только собственных providers.

```nix
externalSubscriptions.skala = {
  urlSecretName = "vpn/subscriptions/skala";
  label = "Skala";
  format = "xray-json";
  profileNames = [ "laptop" "phone" ];
  auto = true;
  refreshIntervalSeconds = 3600;
  retryIntervalSeconds = 300;
  maxStaleSeconds = 86400;
};
```

Имена в `profileNames` должны явно выбирать объявленные профили. Источник не
добавляется остальным устройствам. `auto = true` по умолчанию
добавляет совместимые внешние узлы в «Авто»; `false` оставляет их только в
«Ручной». Эта настройка независима от `autoProtocols` собственных providers:
внешний VLESS TCP не выдаётся за собственный `vless-xhttp`.

Начальный формат — JSON-массив Xray-профилей, как в локальном игнорируемом
референсе Skala `.work/references/skala-vpn.json`, который не распространяется
в Git. Поддерживаются две комбинации:

| Внешнее подключение | Mihomo | Sing-box |
| --- | --- | --- |
| VLESS TCP / REALITY / Vision | Да | Да |
| VLESS XHTTP / TLS, `packet-up` | Да | Нет |

Пустой или отсутствующий `xhttpSettings.host` допустим: поле не передаётся в
Mihomo, и заголовок Host, как в Xray, берётся из `serverName`.

Один сервер с двумя транспортами остаётся двумя вариантами подключения.
Импортируются параметры подключения, а не чужие DNS, routing, inbounds или
группы выбора. Наши DIRECT-исключения, `.ru`, списки и защищённый TCP/UDP
сохраняются. Несовместимые узлы пропускаются без подмены транспорта или
ослабления проверки TLS. Поддержка в формате не доказывает доступность
конкретного сервера и UDP relay на клиентской сети.

Параметры времени задаются для каждого источника: успешное обновление раз в
час, повтор после ошибки через пять минут, последняя принятая копия не старше
суток. Запуск publisher и смена содержимого URL-секрета запускают загрузку.
Обновление приложения на устройстве независимо: оно получает новые узлы при
следующем обновлении нашей подписки. Уже скачанный клиентский конфиг не
отзывается удалением узла из следующей публикации.

Принятые узлы и URL хранятся в приватном каталоге
`/run/vpn-client-profiles/<machine>/external-cache`, отдельно от public assets.
Успешный пустой ответ или ответ без совместимых узлов заменяет старый набор;
удаление источника и смена содержимого URL-секрета исключают прежнюю копию.
HTTP 401/403, невалидный ответ и ошибки проверки TLS также исключают кеш.
Последняя копия сохраняется только при предусмотренных временных сетевых
ошибках и HTTP 408/429/5xx, до установленного срока.

При отсутствии всех совместимых подключений конкретный артефакт и ссылка
на него не публикуются. При наличии собственных узлов они сохраняются при
отказе внешнего источника. Поведение защищённого UDP определяется оставшимися
совместимыми узлами; их отсутствие не включает DIRECT fallback.

С внешними источниками publication unit работает как один последовательный
`Type=simple` процесс: сначала публикует доступные узлы, затем обновляет
источники с ограниченным временем загрузки и пересобирает результат.
Активный unit сам по себе не означает готовности первого профиля. Перед
загрузкой копии, близкие к сроку истечения, могут быть исключены заранее,
чтобы ожидание источника не оставляло просроченные узлы в публикации.
Приостановка процесса или машины не даёт гарантий точного времени отзыва;
перед публикацией свежесть проверяется повторно. Без внешних источников
сохраняется прежний `oneshot` режим.

Для внешних VLESS в Sing-box имя сервера разрешается через первый собственный
DoH (`own-doh-0`) с `ipv4_only`; чужие DNS не добавляются. Это отдельное
разрешение адреса VPN-сервера, а не изменение DNS-политики сайтов.
Диагностика обновления содержит ID источника, безопасные причины и счётчики:
`mihomo`, `sing-box`, `skipped` (пропущенные прокси-узлы) и `service`
(служебные outbounds `freedom`, `blackhole`, `dns`, `loopback`). Каждый
пропущенный узел даёт отдельную строку `result=skipped` с индексом профиля в
ответе, очищенным remark, целью (`all` или `sing-box`) и фиксированным кодом
причины, например `insecure-tls`, `unsupported-protocol`, `duplicate` или
`unsupported-xhttp` для XHTTP-узла, недоступного в Sing-box. Сырой ответ
подписки, адреса, URL и credentials в журнал не выводятся.

## Defaults

Publisher `enable = false`, `localMachineName` и gateway address fields пусты
или nullable. При `enable = false` роль не объявляет сервисы и секреты.
Публикуются ровно профили из `profiles`; links page включена, path —
`/config-links/`, title — `VPN client profiles`. Private exposure links page
задаётся только в consumer.

## Exports and dependencies

Role не объявляет собственных exports и выбирает providers через raw Clan
exports и `clanLib.selectExports`: `naiveproxy` требует addon, а
`vless-xhttp`, `amneziawg`, `mieru`, `anytls`, `trusttunnel` — gateway. Отсутствующий,
выключенный, неоднозначный или несоответствующий provider блокирует
генерацию. Renderer принимает выбранные typed `vpnProvider` exports напрямую;
`providerRefs.profileNames` сужает их `profileNames` без промежуточных
protocol-specific adapter shapes.

Каждый renderer формирует внутренний manifest конкретных артефактов. Артефакт
содержит non-secret template, формат и имя выходного файла, ссылки на явный
каталог public assets и typed secret bindings. Binding задаёт только secret
name, одно из закрытых правил чтения (`literal`, `wireguard-private-key`,
`base64url`), точный структурный путь и placeholder. Manifest проверяет, что
каждый placeholder связан ровно один раз, target существует, а asset reference
есть в каталоге. Publication применяет этот manifest без protocol branches и
без знания полей конкретного client format.

Mieru экспортируется только в Mihomo YAML: `transport = TCP`,
`udp = true` (UDP relay внутри TCP), `MULTIPLEXING_LOW` и `HANDSHAKE_STANDARD`.
Custom traffic pattern и TLS/SNI-параметры не добавляются. Consumer выбирает
provider refs; выбранный Mieru доступен вручную и участвует в «Авто», если
`autoProtocols` содержит `mieru`. Sing-box Mieru не поддерживает.

Mieru credentials выбираются по имени device profile из `secretNames.users`.
Пароль — 1–64 ASCII-байта из `A-Za-z0-9_-`, без padding, пробелов, NUL и
переводов строк. Publisher проверяет raw bytes до подстановки, не обрезая их;
невалидный пароль блокирует публикацию. Это совпадает с серверным контрактом.

AnyTLS экспортируется в оба формата. Mihomo 1.19.31 получает `udp = true`,
что включает встроенный UoT v2, SNI и обязательную проверку сертификата; этот
core не имеет полей ограничения версии TLS для AnyTLS. Sing-box 1.14.1 также
использует встроенный UoT v2, проверяет сертификат и явно ограничивает TLS
значениями `min_version = "1.3"` и `max_version = "1.3"`. Пароль устройства
берётся из точного `secretNames.users` map и подставляется через generic manifest
binding с `base64url`. Custom padding, session metadata, idle-session overrides,
ciphers, ALPN, TFO и client fingerprint не добавляются.

TrustTunnel экспортируется только в Mihomo YAML. Для точного
Mihomo 1.19.31 renderer использует числовой IPv4 endpoint, `type = trusttunnel`,
имя device profile как `username`, проверяемый SNI, `skip-cert-verify = false`,
`client-fingerprint = chrome`, `quic = false` и `udp = true`. Это H2-профиль:
H3/QUIC, ClientRandom, health checks и pool tuning не добавляются. Пароль берётся
из точного `secretNames.users` map и остаётся runtime-only через manifest binding
с `base64url`. Sing-box TrustTunnel outbound и официальный client export не
публикуются.

## Группы и имена подключений

Оба формата показывают две группы выбора с фиксированными именами. «Ручной»
(Mihomo `select`, sing-box `selector`) содержит первым пунктом «Авто», затем все
опубликованные подключения профиля, включая manual-only. «Авто» (`url-test` /
`urltest`) содержит только подключения из `autoProtocols` и внешние узлы с
`auto = true`; DIRECT в него не входит. Без кандидатов «Авто» не создаётся.
Правила защищённого трафика ведут в «Ручной». Отдельных UDP-групп и
FULL-профиля нет.

UDP идёт через подключение, выбранное в «Ручной». Mihomo 1.19.31 пропускает
совпавшее правило, если выбранный proxy не поддерживает UDP, поэтому после
правил «Ручной» стоят явные `REJECT` для защищённого UDP. В sing-box outbound
без UDP, например Naive, завершает UDP-соединение ошибкой. В обоих случаях
DIRECT не используется.

Весь трафик через VPN включается режимом «Глобальный» в клиенте. Mihomo в этом
режиме не применяет правила и использует группу `GLOBAL`; её встроенный вариант
начинается с DIRECT. Профиль задаёт `GLOBAL` из «Ручной» и «Авто», поэтому
глобальный режим идёт через ручной выбор. Локальные и `.ru` исключения в этом
режиме Mihomo не действуют; LAN, Tailscale и закреплённые endpoint остаются вне
TUN через `route-exclude-address`. Sing-box направляет Global в «Ручной» после
локальных и `.ru` исключений.

Имя подключения — отображаемая метка, а не идентификатор. Consumer задаёт её
для provider ref:

```nix
providerRefs = [
  {
    machine = "gateway-a";
    instanceId = "vpn-mihomo-vless-xhttp";
    protocol = "vless-xhttp";
    display = { label = "A"; country = "Литва"; countryCode = "LT"; };
  }
];
```

Получается `🇱🇹 Литва · A`: флаг строится из заглавного ISO alpha-2 кода,
`country` и `countryCode` задаются вместе. Без `display` меткой служит machine
name без флага. Метка и страна — до 64 байт без управляющих символов и
пробелов по краям; служебные имена групп (`Ручной`, `Авто`, `GLOBAL`, `DIRECT`,
`REJECT` и др.) недопустимы. Внешний узел получает `<remark> · <label>`, где
remark берётся из подписки как есть, а `label` — из источника (по умолчанию его
ID); без remark имя равно `<label>`. Метки внешних источников должны отличаться
от меток providers.

Номера, хеши, instance ID, имя профиля и протокол в имя не входят. При
совпадении имён внутри профиля добавляется протокол (`VLESS`, `AWG`, `Naive`,
`Mieru`, `AnyTLS`, `TrustTunnel`) или транспорт внешнего узла (`REALITY`,
`XHTTP`), а при оставшемся совпадении — порядковый номер начиная с 2. Имена
собственных подключений вычисляются по всем providers профиля, поэтому Mihomo и
sing-box показывают одно имя. Внешние имена вычисляет публикация по всем
совместимым узлам до разделения по форматам; смена `label` применяется при
следующей публикации без повторной загрузки. Кеш подписки, сохранённый прежней
схемой имён, при обновлении сбрасывается и загружается заново. Placeholders
секретов по-прежнему используют внутренний machine/instance namespace.

Смена имён сбрасывает сохранённый в клиенте выбор один раз: `store-selected`
хранит выбор по имени подключения.

`vpnProvider` использует версию схемы 2. Read-only NixOS
output `clanwright.vpn.publishers.<instance>` содержит `schemaVersion = 1`,
`configGatewayDomain`, `profileRoot`, `assetRoot`, `linksRoot`, `routeConfig`, `readerGroup`,
`publicationUnit`, `refreshUnit` и `statusPath`. Consumer использует эти
данные для собственного Caddy site claim и private links route. Публичного
helper `lib.clientProfiles` нет; внутренние renderer-файлы не являются API.

У active publisher-инстансов на одной машине должны быть разные
`localMachineName`: это consumer-defined имя runtime-каталогов и units.
Совпадения отклоняются при evaluation, чтобы инстансы не перезаписывали
публикацию друг друга.
Каждому publisher нужен отдельный `configGatewayDomain` и Caddy virtual host:
два набора token routes и `/assets/v1/catalog/` нельзя объединять в одном site.
Повторяющиеся gateway domains на одной машине также отклоняются.

Mihomo поступает из `apps-nixpkgs`, а Sing-box — из
`modern-apps-nixpkgs`; точные revisions и package outputs описаны в
[package authority](../../docs/package-authority.md). Роль получает выбранные
пакеты через flake dependency injection и не собирает клиенты локально.

Sing-box профиль сохраняет Naive как отдельный HTTPS/H2 outbound с проверкой
TLS, `quic = false`, `udp_over_tcp = false` и `insecure_concurrency = 0`.
AnyTLS добавляется в sing-box как TCP/UDP outbound; требуется core 1.14.0 или
новее. Прямые исключения для LAN, router, Tailscale и DNS обрабатываются раньше.
Native `Rule` и `Global` режимы используют одну группу «Ручной». Mihomo
публикуется одним Rule-mode файлом `mihomo.yaml`, который заканчивает обычный
трафик в DIRECT. DIRECT не входит в VPN selectors: при отказе выбранного пути защищаемый трафик
не переключается автоматически, а отключение VPN остаётся явным действием
пользователя в клиенте.

Если для публикуемого Sing-box профиля нет eligible Naive или AnyTLS provider, renderer
не публикует `profile.json` и не добавляет ссылку на него. Mihomo-файл с
eligible providers других протоколов продолжает публиковаться. При наличии
только Naive публикуется sing-box, а несовместимый Mihomo-файл и ссылка на него
не создаются.

`profiles[].autoProtocols` — список canonical protocol IDs, разрешённых для автоматического
выбора и фоновых URL-проб. Default включает все поддерживаемые протоколы;
`[]` оставляет «Ручной» без группы «Авто». Например, consumer может задать
для каждого профиля
`[ "vless-xhttp" "naiveproxy" "mieru" "anytls" "trusttunnel" ]`, сохранив AWG вручную.
Для исключённого AWG отключается также persistent keepalive. При отсутствии
кандидатов группа «Авто» не создаётся; DIRECT в защищённые
selectors не добавляется. В полностью ручном режиме по умолчанию выбран
первый совместимый outbound; фоновые URL-пробы не создаются.

```nix
profiles = map (name: {
  inherit name;
  autoProtocols = [ "vless-xhttp" "naiveproxy" "mieru" "anytls" "trusttunnel" ];
}) [ "device-a" "device-b" ];
```

Это настройки publisher role. Общий каталог consumer может передать одинаковые
`profiles`, `providerRefs`, `clientDnsEndpoints` и `personalProxyDomains` каждому
publisher, меняя его адреса и размещение. Предпочтительный источник подписки
задаётся в consumer/client; порядок DNS endpoints не задаёт приоритет загрузки
подписки и не создаёт автоматический failover между её URL.

Оба формата задают явное правило запрета внешнего IPv6 до обычного fallback.
Loopback, link-local, ULA, multicast и Tailscale остаются локальными
исключениями. Захват трафика проверяется отдельно на устройстве.
Это политика запрета внешнего IPv6, а не обещание
поддержки IPv6 через VPN. DNS upstream использует IPv4.

Mihomo-профиль использует TUN `auto-route`, `auto-detect-interface` и
`strict-route` без явного `route-address`. Исключения LAN, Tailscale и
закреплённых IPv4 endpoints остаются в `route-exclude-address`; имя интерфейса
не задаётся. Проверка маршрутов на устройстве остаётся частью client acceptance.

Sing-box TUN использует `auto_route` и `strict_route` без `route_address`
и `route_exclude_address`. Отсутствие `route_address` оставляет выбор стандартных
маршрутов клиенту; явный список `0.0.0.0/0`, `::/0` не генерируется.
Семантика описана в [sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/#route_address).
`route.auto_detect_interface` сохранён, имя физического или Tailscale-интерфейса
в профиль не встраивается. Минимальная версия sing-box остаётся 1.14.0.
Настройки самого SFM могут дополнительно создавать исключения, например
`excludeDefaultRoute` и `excludeAPNs`; отсутствие исключений в JSON не отменяет
эти настройки приложения.

Профиль сохраняет FakeIP `198.18.0.0/15`, локальные правила `DIRECT` и явный
запрет внешнего IPv6. Захват FakeIP и внешнего IPv6, наличие системных маршрутов
LAN/Tailscale и сосуществование VPN-клиентов проверяет consumer на устройстве.
Если локальный трафик попадёт в TUN, правило `DIRECT` само по себе не гарантирует
выход через Tailscale: автоопределение может привязать исходящий сокет к
физическому интерфейсу. Отключение `auto_detect_interface` не отключает монитор
доступности сети SFM.

В [операторском A/B-тесте 26 сентября](https://github.com/clanwright/vpn/issues/2#issuecomment-5845378043)
на SFM 1.14.1/macOS с включённым Tailscale исходный профиль VPN v0.9.4
терял доступный интерфейс. Удаление только `route_address` устранило
`missing default interface` и `no available network interface`, восстановило
сайты и загрузку пяти наборов правил; маршрут к DNS Tailscale сохранился.
Генератор теперь соответствует этому варианту. Механизм сбоя macOS и минимальный
проблемный префикс не установлены. Проверка LAN, прикладного доступа к tailnet,
длительной передачи, повторного запуска и смены сети остаётся незавершённой.

Чистые проверки подтверждают поля генератора и порядок правил, но не выбор
маршрута операционной системой и не совместимость всех клиентов.
Сценарий сравнения и требования к доказательствам описаны в
[клиентской приёмке](../../docs/operations/sing-box-client.md).
Рабочая совместимая схема отслеживается в [#2](https://github.com/clanwright/vpn/issues/2).
DNS-домены подписок и их исправление остаются отдельной задачей consumer.

Sing-box сохраняет FakeIP: `experimental.cache_file` содержит `enabled: true`
и `store_fakeip: true`. Генератор не меняет путь или идентификатор кеша при
обновлении профиля; размещением файла управляет клиент. Обычный перезапуск
должен повторно использовать этот файл. Уже утраченные соответствия настройка
не восстанавливает. Кеши Clash и SFM независимы: при переключении требуется
завершить приложения с сохранёнными DNS-ответами, сбросить системный DNS-кеш
и получить новые ответы через целевой клиент. Порядок действий и отдельная
проверка сохранности FakeIP приведены в
[операционной инструкции](../../docs/operations/sing-box-client.md#fakeip-cache).

Naive/Cronet также выполняет внутреннюю UDP-проверку доступности IPv6.
На сети без IPv6 она может записать `no route to host`, даже если профиль
использует IPv4 endpoints и `quic: false`. Правило запрета внешнего IPv6
относится к маршрутизируемому трафику приложений и не управляет этой внутренней
проверкой. Источник сообщения, ограничения и граница исправления клиента
описаны в [разборе Naive](../../docs/operations/sing-box-client.md#naive-startup-ipv6-reachability-probe).

Публичные URL правил и локальные пути Mihomo cache содержат стабильные
обезличенные идентификаторы. Прежние `/assets/v1/catalog/<имя>` остаются
алиасами тех же файлов, поэтому ранее выданные профили сохраняют доступ к
правилам. Это изменение путей, а не шифрование содержания публичных списков.

Selective policy использует blocked/geoblocked и dependency rule sets.
В защищённую TCP/UDP policy также входят MetaCubeX `category-ai-!cn` и `github`
под внутренними тегами `ai_domains` и `github_domains`. Остальной трафик
Rule mode обоих форматов сохраняет default `DIRECT`.
Домены `.ru` направляются в `DIRECT` в Mihomo Rule mode и в Sing-box,
включая его Global mode. Это исключение идёт после локальных правил и запрета
внешнего IPv6, но до Global Sing-box, защищённого UDP и всех feed rules, включая
личные домены. Mihomo Global mode правила не применяет. `.ru` исключён из FakeIP обоих форматов. Sing-box перед этим
`DIRECT` явно разрешает `.ru` с `ipv4_only` через обычные DNS rules; общее
разрешение остальных DIRECT-доменов остаётся на прежнем месте.
Личные домены задаёт consumer через `personalProxyDomains`; библиотека не
содержит пользовательский список. Значения задаются как доменные суффиксы без
`+.`.

`clientDnsEndpoints` задаёт непустой список собственных DoH consumer. Каждый
элемент содержит `domain`, `ipv4`, `port` (по умолчанию `443`) и `path`
(по умолчанию `/dns-query`). Домены — уникальные канонические lowercase ASCII
FQDN, адреса — числовые IPv4; путь не содержит query, fragment или credentials.
Upstream DNS остаётся IPv4-only. Число endpoint не фиксировано.

```nix
clientDnsEndpoints = [
  { domain = "dns-a.example.invalid"; ipv4 = "192.0.2.10"; }
  { domain = "dns-b.example.invalid"; ipv4 = "198.51.100.20"; }
  { domain = "dns-c.example.invalid"; ipv4 = "203.0.113.30"; }
];
```

Пример использует вымышленные домены и адреса. `null` (default, включая
отсутствующую настройку) сохраняет один собственный DoH из `edgeDomain` и
`publicIPv4`, порт `443`, путь `/dns-query`. Явный список заменяет этот endpoint,
а пустой список отклоняется. IP служит адресом подключения, домен — HTTPS/TLS
именем с обязательной проверкой сертификата.

Mihomo использует весь список в `nameserver` и `proxy-server-nameserver`:
endpoint равноправны, запросы выполняются параллельно. DoH подключаются напрямую
с закреплёнными адресами, независимо от доступности DNS и выбранного VPN.
Sing-box 1.14 использует собственные DoH через `evaluate`/`race`/`respond`,
принимая DNS-ответ, включая блокирующий, без перехода к публичным резолверам.
Публичного encrypted или plaintext резерва в обоих форматах нет.

В Sing-box FakeIP применяется только к запросам `A`/`AAAA` для выбранных
доменов с сохранением административных исключений. Остальные типы запросов
к тем же доменам проходят в общий набор собственных DoH. Ограничение
[`query_type`](https://sing-box.sagernet.org/configuration/dns/rule/#query_type)
входит в логическое `and` вместе с условиями домена; политика `ipv4_only`
и запрет внешнего IPv6 сохраняются.

Для обязательного dialer resolver Sing-box использует статические bootstrap
записи; обычные DIRECT-запросы проходят через общий набор DoH до подключения.
Bootstrap не использует Unix-specific путь `/dev/null`; точные записи
собственных endpoint задаются в профиле и имеют приоритет перед системным
hosts-файлом. Непредопределённые имена hosts transport может искать в системном
hosts; обычное разрешение клиентского трафика использует собственные DoH.
Загрузка rule sets выполняется напрямую
через закреплённый IPv4 publisher с сохранением HTTPS hostname и TLS verification,
без зависимости от выбранного VPN.

При транспортном отказе отдельных DoH остаются остальные собственные endpoint.
Если все недоступны, запросы, которым нужен upstream DNS, завершаются ошибкой.
Кэш, статические записи и существующая fake-IP policy сохраняются; это не
обещание ошибки для каждого обращения к клиентскому DNS. Приватные имена,
которым нужен реальный DNS-ответ, также используют собственный набор серверов.
Consumer отвечает за доступность каждого DoH с клиентских сетей, одинаковую
эффективную фильтрацию, состояние списков и приватные записи на всех серверах.
При смене адресов он обновляет настройки и доставляет новые профили клиентам.

Семантика upstream: [Mihomo DNS](https://wiki.metacubex.one/en/config/dns/),
[Sing-box DNS actions](https://sing-box.sagernet.org/configuration/dns/rule_action/).

Исходный HTTP bootstrap сверен с sing-box 1.14.0; выбранный пакет сейчас 1.14.1:
[HTTP client](https://sing-box.sagernet.org/configuration/shared/http-client/),
[hosts transport](https://sing-box.sagernet.org/configuration/dns/server/hosts/).

Naive credentials выбираются по именам профилей из provider export. Карта не
ограничена встроенными device names; профиль получает Naive-подключение, только
если consumer явно включает его в `profiles` и допускает в `providerRefs`.

## State and secrets

Secret runtime files находятся под `/run/vpn-client-profiles/<machine>`.
UUID/password/key inputs читаются по SOPS paths через заданные secret names.
Generated profiles, link tokens и credentials не записываются в Git или Nix store.
Имена machine/profile/instance ограничены безопасными 64-символьными
идентификаторами, а secret names — сегментным SOPS path grammar. Каждый
profile использует отдельный path-token secret из `pathTokenSecretName`; он не может
совпадать с credential secret или secret URL внешней подписки, потому что token
становится публичным сегментом URL. Сам token
должен состоять из 32–128 unpadded base64url символов без завершающего newline;
renderer проверяет raw bytes до публикации файлов и links page.

Публикация — одна транзакция для всех profiles и links page. Старое дерево
убирается из выдачи перед генерацией; новое становится доступным только после
успешного завершения. Ошибка или остановка publisher убирает текущую публикацию,
поэтому старые credentials не остаются доступными при неудачном обновлении.
Загруженные ранее профили у клиентов этим не отзываются: provider credential
revocation остаётся операцией consumer. Publisher добавляет секретам только
publication unit как restart target; другие роли могут объявлять собственные
restart targets для тех же bindings.

При отказе журнал содержит только фиксированные `stage` и `reason`: в частности,
`assets-readiness` / `required-assets-missing-or-empty`, `mihomo-validation` /
`config-rejected`, `file-installation` / `install-failed`. Чтение credentials,
рендеринг и очистка имеют отдельные этапы. Содержимое профилей, credentials,
ссылки с токенами и необработанный вывод валидаторов остаются скрытыми.

Публичные rule assets сохраняются в
`/var/lib/vpn-client-profiles/<machine>/assets`. Publisher запускает refresh unit
через `Wants` и ждёт завершения попытки через `After`. Затем он синхронизирует
локальный список и проверяет полный набор обязательных файлов. Неуспешный
refresh не запрещает публикацию при наличии полного кеша; отсутствующий или
пустой обязательный файл блокирует публикацию. Оба сервиса повторяют неудачные
попытки автоматически. Ошибка обновления сохраняет последнюю
принятую копию без жёсткого срока; возраст и ошибки доступны через несекретный
`statusPath` для consumer monitoring. Это не гарантирует актуальность selective
rules при длительной недоступности upstream.

`statusPath` — JSON по именам скачиваемых файлов: `attempted_at`, `result`
(`refreshed` или `failed`), `reason` и время последнего принятого обновления
`refreshed_at`, сохраняемое после ошибки. Для ошибок записи самого status file
consumer также учитывает результат refresh unit. Локальный список
`personalProxyDomains` синхронизирует только publication unit до проверки
готовности; удалённый refresh его не перезаписывает.
Нужные файлы, refresh actions, readiness paths и Caddy asset routes выводятся
из ссылок артефактов на единый внутренний asset catalog. Lifecycle не исследует
дерево Mihomo и не определяет необходимость assets по наличию `rule-providers`.
При runtime-загрузке SRS проходит проверку штатным sing-box, а MRS —
декодирование штатным Mihomo с проверкой ожидаемого `domain` или `ipcidr`
behavior до атомарной замены кэша. Ошибка сохраняет предыдущий файл. Для
текстовых upstream-списков принятие ограничено успешным HTTP-ответом и
непустым файлом. Repository checks проверяют генерацию этих действий, не
запуская parser или приложения.

MetaCubeX feeds берутся из `meta-rules-dat`: Mihomo использует
`meta/geo/geosite/classical/category-ai-!cn.list` и `github.list` как
`behavior = classical`, `format = text`, сохраняя `DOMAIN-REGEX` rules.
Эти текстовые файлы используют только существующую проверку `nonempty`,
которая не подтверждает синтаксис или полноту содержимого. Sing-box использует
соответствующие `sing/geo/geosite/category-ai-!cn.srs` и `github.srs` с обычной
SRS validation. Все четыре assets обязательны для соответствующих артефактов
и имеют только opaque canonical URL без новых legacy aliases.

`secure-dns.txt` загружается из официального HaGeZi
[`wildcard/doh-onlydomains.txt`](https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/doh-onlydomains.txt)
как текстовый список доменов. Отдельный `adblock/doh.txt` остаётся источником
для `filters.srs`. Проверка содержимого списка точной версией Mihomo из
[package authority](../../docs/package-authority.md) относится к приёмке
consumer; чистая Nix evaluation её не заменяет.

## Network exposure

Consumer объявляет Caddy config gateway, bind/certificate claims и private
links page, а также добавляет `readerGroup` к supplementary groups Caddy.
`routeConfig` статичен, не содержит токенов, host/bind/TLS и подавляет access
logging. Caddy не импортирует runtime fragments, не зависит от publication unit
и не перезапускается при обновлении профилей. Ошибка publisher делает недоступной
только публикацию. Mirror timers обновляют публичные assets без нового listener.

## Verification

`checks/domain-contracts.nix` и `checks/client-render-smoke.nix` проверяют
protocol-role mapping, единственность export для provider ref, generated runtime
paths, Caddy tailnet policy и исключённые profiles. DNS checks проверяют
типизированный список, bootstrap-привязки, включение собственных endpoint,
отсутствие публичного резерва и DIRECT/DNS routing. Проверки не подтверждают
работу клиентов, сетевую доступность или содержимое runtime credentials.
Полная репозиторная процедура описана в
[verification runbook](../../docs/operations/verify.md).
