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
`configGatewayDomain`, `publicIPv4`, `edgeDomain`, `clientDnsEndpoints`, `secretPrefix`,
`excludedProfileNames`, `tailnetAdminDomains`, `personalProxyDomains`, `profiles`,
`providerRefs`, `profileLinks` и `linksPage`. Provider refs
содержат machine, instance и canonical protocol. Publisher profiles содержат
`name`, `kind`, optional `publishProfileJson` и `autoProtocols`; имена credential secrets
приходят исключительно из typed providers.

## Defaults

Publisher `enable = false`, `secretPrefix` и gateway address fields пусты
или nullable. При `enable = false` роль не объявляет сервисы и секреты.
Из публикации исключается
профиль `probe`; links page включена, path —
`/config-links/`, title — `VPN client profiles`. Private exposure links page
задаётся только в consumer.

## Exports and dependencies

Role экспортирует `vpnPublisher` и выбирает providers через raw Clan
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

Mieru экспортируется только в Mihomo selective/full YAML: `transport = TCP`,
`udp = true` (UDP relay внутри TCP), `MULTIPLEXING_LOW` и `HANDSHAKE_STANDARD`.
Custom traffic pattern и TLS/SNI-параметры не добавляются. Consumer выбирает
provider refs; выбранный Mieru доступен вручную и участвует в Auto, если
`autoProtocols` содержит `mieru`. Sing-box Mieru не поддерживает.

Mieru credentials выбираются по имени device profile из `secretNames.users`.
Пароль — 1–64 ASCII-байта из `A-Za-z0-9_-`, без padding, пробелов, NUL и
переводов строк. Publisher проверяет raw bytes до подстановки, не обрезая их;
невалидный пароль блокирует публикацию. Это совпадает с серверным контрактом.

AnyTLS экспортируется в оба формата. Mihomo 1.19.30 получает `udp = true`,
что включает встроенный UoT v2, SNI и обязательную проверку сертификата; этот
core не имеет полей ограничения версии TLS для AnyTLS. Sing-box 1.14.0 также
использует встроенный UoT v2, проверяет сертификат и явно ограничивает TLS
значениями `min_version = "1.3"` и `max_version = "1.3"`. Пароль устройства
берётся из точного `secretNames.users` map и подставляется через generic manifest
binding с `base64url`. Custom padding, session metadata, idle-session overrides,
ciphers, ALPN, TFO и client fingerprint не добавляются.

TrustTunnel экспортируется только в Mihomo selective/full YAML. Для точного
Mihomo 1.19.30 renderer использует числовой IPv4 endpoint, `type = trusttunnel`,
имя device profile как `username`, проверяемый SNI, `skip-cert-verify = false`,
`client-fingerprint = chrome`, `quic = false` и `udp = true`. Это H2-профиль:
H3/QUIC, ClientRandom, health checks и pool tuning не добавляются. Пароль берётся
из точного `secretNames.users` map и остаётся runtime-only через manifest binding
с `base64url`. Sing-box TrustTunnel outbound и официальный client export не
публикуются.

Имена proxies включают полный canonical machine ID и instance ID. Компоненты
кодируются с длиной, поэтому разные пары machine/instance не могут дать одно
имя. Compatibility aliases для прежних имён без `-grosbeak` не создаются.

`vpnProvider` использует версию схемы 2, `vpnPublisher` — 1. Read-only NixOS
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
новее. TCP и UDP имеют отдельные selectors. Защищённый UDP направляется через
AnyTLS, а при его отсутствии отклоняется без DIRECT
fallback. Прямые исключения для
LAN, router, Tailscale и DNS обрабатываются раньше. Native `Rule`/`Global`
режимы имеют независимые `SELECTIVE`/`FULL` selectors и Auto selections.
Mihomo публикуется двумя Rule-mode файлами: `mihomo.yaml` заканчивает обычный
трафик в DIRECT, а `mihomo-full.yaml` — в FULL после тех же прямых исключений.
DIRECT не входит в VPN selectors: при отказе выбранного пути защищаемый трафик
не переключается автоматически, а отключение VPN остаётся явным действием
пользователя в клиенте.

Если для публикуемого Sing-box профиля нет eligible Naive или AnyTLS provider, renderer
не публикует `profile.json` и не добавляет ссылку на него. Mihomo-файлы с
eligible providers других протоколов продолжают публиковаться. При наличии
только Naive публикуется sing-box, а несовместимые Mihomo-файлы и ссылки на них
не создаются.

`profiles[].autoProtocols` — список canonical protocol IDs, разрешённых для автоматического
выбора и фоновых URL-проб. Default включает все поддерживаемые протоколы;
`[]` оставляет ручные selectors без Auto-групп. Например, consumer может задать
для каждого профиля
`[ "vless-xhttp" "naiveproxy" "mieru" "anytls" "trusttunnel" ]`, сохранив AWG вручную.
Для исключённого AWG отключается также persistent keepalive. При отсутствии
кандидатов Auto соответствующая группа не создаётся; DIRECT в защищённые
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

Оба формата перехватывают внешний IPv6 и отклоняют его явным правилом до
обычного fallback. Loopback, link-local, ULA, multicast и Tailscale остаются
локальными исключениями. Это политика запрета внешнего IPv6, а не обещание
поддержки IPv6 через VPN. DNS upstream использует IPv4.

Sing-box TUN задаёт положительный `route_address`: всё адресное пространство
IPv4 и IPv6 за вычетом `10.0.0.0/8`, `100.64.0.0/10`, `169.254.0.0/16`,
`172.16.0.0/12`, `192.168.0.0/16`, `224.0.0.0/4`, `::1/128`, `fc00::/7`,
`fe80::/10` и `ff00::/8`. Эти назначения остаются системной маршрутизации,
включая маршруты отдельного Tailscale-клиента. Генератор не задаёт
`route_exclude_address`: на Apple такие исключения направляют трафик на
основной физический интерфейс и могут конкурировать с другим VPN.
Имя Tailscale-интерфейса в профиль не встраивается.
Семантика описана в [sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/#route_address)
и реализована в [Apple-клиенте версии 1.14.0](https://github.com/SagerNet/sing-box-for-apple/blob/008f73fc6d576aced976659d6dc52a9a12365c24/Library/Network/ExtensionPlatformInterface.swift#L58-L147).
Настройки самого SFM могут дополнительно создавать исключения, например
`excludeDefaultRoute` и `excludeAPNs`; отсутствие исключений в JSON не отменяет
эти настройки приложения.
Общий профиль сохраняет требование sing-box 1.14.0; явные маршруты поддержаны
Apple-клиентами и [SFA 1.14.0](https://github.com/SagerNet/sing-box-for-android/blob/af61098358a8141dea71f232b7eaebf4ccee8868/app/src/main/java/io/nekohasekai/sfa/bg/VPNService.kt#L85-L115).
Точное дополнение содержит 47 IPv4 и 134 IPv6 маршрута; совместимость структуры
подтверждена исходниками, применение этого списка на устройствах требует приёмки.

FakeIP `198.18.0.0/15` остаётся внутри TUN; внешний IPv6 также перехватывается
для явного запрета. `auto_route`, `strict_route` и
`route.auto_detect_interface` сохранены. Последний параметр выбирает интерфейс
исходящих соединений sing-box, а не маршрут к Tailscale для приложений.
Положительные маршруты не создают отсутствующие LAN/Tailscale routes:
их наличие и сосуществование VPN-клиентов проверяет consumer на каждом устройстве.

Чистые проверки доказывают точное покрытие адресного пространства без обходных
диапазонов, но не выбор маршрута операционной системой. Приёмка на Apple
требует фиксации маршрута к Tailscale-адресу при одновременно включённых клиентах,
успешного HTTPS с проверкой TLS через этот адрес, сохранения LAN-доступа и
интернет-политики после переподключения. Ранее наблюдавшийся таймаут при SFM
остаётся гипотезой о конфликте маршрутов до такой фиксации. DNS-домены подписок
и их исправление остаются отдельной задачей consumer.

Публичные URL правил и локальные пути Mihomo cache содержат стабильные
обезличенные идентификаторы. Прежние `/assets/v1/catalog/<имя>` остаются
алиасами тех же файлов, поэтому ранее выданные профили сохраняют доступ к
правилам. Это изменение путей, а не шифрование содержания публичных списков.

Selective policy использует только blocked/geoblocked и dependency rule sets.
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

HTTP bootstrap сверен с sing-box 1.14.0:
[HTTP client](https://sing-box.sagernet.org/configuration/shared/http-client/),
[hosts transport](https://sing-box.sagernet.org/configuration/dns/server/hosts/).

Naive credentials выбираются по именам профилей из provider export. Карта не
ограничена встроенными device names, а probe публикуется только если consumer
явно включает его в `profiles` и `providerRefs`; штатный default исключает
`probe` из публикации.

## State and secrets

Secret runtime files находятся под `/run/vpn-client-profiles/<machine>`.
UUID/password/key inputs читаются по SOPS paths через заданные secret names.
Generated profiles, link tokens и credentials не записываются в Git или Nix store.
Имена machine/profile/instance ограничены безопасными 64-символьными
идентификаторами, а secret names — сегментным SOPS path grammar. Каждый
profile link обязан ссылаться на renderer-owned path-token secret. Сам token
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
