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
только `name`, `kind` и optional `publishProfileJson`; имена credential secrets
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
`vless-xhttp`, `hysteria2`, `amneziawg`, `mieru` — gateway. Отсутствующий,
выключенный, неоднозначный или несоответствующий provider блокирует
генерацию. Renderer принимает выбранные typed `vpnProvider` exports напрямую;
`providerRefs.profileNames` сужает их `profileNames` без промежуточных
protocol-specific adapter shapes.

Поддержка `hysteria2` сохранена только для совместимости с существующими
provider refs и профилями. Протокол deprecated и не рекомендуется для новых
профилей после пользовательского сообщения о блокировке клиентских подключений.

Mieru экспортируется только в Mihomo selective/full YAML: `transport = TCP`,
`udp = true` (UDP relay внутри TCP), `MULTIPLEXING_LOW` и `HANDSHAKE_STANDARD`.
Custom traffic pattern и TLS/SNI-параметры не добавляются. Consumer выбирает
provider refs; выбранный Mieru участвует в обычных ручных selectors и Auto,
без отдельного ограничения для нового протокола. Sing-box Mieru не поддерживает
и продолжает публиковаться только при eligible Naive provider.

Mieru credentials выбираются по имени device profile из `secretNames.users`.
Пароль — 1–64 ASCII-байта из `A-Za-z0-9_-`, без padding, пробелов, NUL и
переводов строк. Publisher проверяет raw bytes до подстановки, не обрезая их;
невалидный пароль блокирует публикацию. Это совпадает с серверным контрактом.

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
UDP, совпавший с защищаемыми rule sets, отклоняется до Naive: TCP-only путь не
получает скрытый DIRECT fallback. Прямые исключения для
LAN, router, Tailscale и DNS обрабатываются раньше. Native `Rule`/`Global`
режимы имеют независимые `SELECTIVE`/`FULL` selectors и Auto selections.
Mihomo публикуется двумя Rule-mode файлами: `mihomo.yaml` заканчивает обычный
трафик в DIRECT, а `mihomo-full.yaml` — в FULL после тех же прямых исключений.
DIRECT не входит в VPN selectors: при отказе выбранного пути защищаемый трафик
не переключается автоматически, а отключение VPN остаётся явным действием
пользователя в клиенте.

Если для публикуемого Sing-box профиля нет eligible Naive provider, renderer
не публикует `profile.json` и не добавляет ссылку на него. Mihomo-файлы с
eligible providers других протоколов продолжают публиковаться.

Selective policy использует только blocked/geoblocked и dependency rule sets.
Личные домены задаёт consumer через `personalProxyDomains`; библиотека не
содержит пользовательский список. Значения задаются как доменные суффиксы без
`+.`.

`clientDnsEndpoints` задаёт непустой список собственных DoH consumer. Каждый
элемент содержит `domain`, `ipv4`, `port` (по умолчанию `443`) и `path`
(по умолчанию `/dns-query`). Домены — уникальные канонические lowercase ASCII
FQDN, адреса — числовые IPv4; путь не содержит query, fragment или credentials.
Текущие профили остаются IPv4-only. Число endpoint не фиксировано.

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

Для обязательного dialer resolver Sing-box использует статические bootstrap
записи; обычные DIRECT-запросы проходят через общий набор DoH до подключения.
Bootstrap hosts transport читает `/dev/null` вместо системного hosts-файла;
эта конфигурация рассчитана на Linux, Android и Apple clients.

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
При runtime-загрузке SRS проходит проверку штатным sing-box; для MRS и
текстовых upstream-списков принятие ограничено успешным HTTP-ответом и
непустым файлом. Cache не является доказательством корректности всех rule sets
для реального клиента.

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
