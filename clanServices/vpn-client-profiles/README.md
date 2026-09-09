# @clanwright/vpn-client-profiles

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это publisher клиентских конфигураций Mihomo и Sing-box. Он собирает
typed non-secret metadata VPN providers, генерирует профили и связывает их
с Caddy profile page; protocol gateway roles остаются независимыми.

## Settings

Входы: `lifecycle`, `enable`, `localMachineName`,
`configGatewayDomain`, `publicIPv4`, `caddyBindIPv4`, `tailnetIPv4`,
`edgeDomain`, `acmeCertName`, `secretPrefix`,
`excludedProfileNames`, `tailnetAdminDomains`, `personalProxyDomains`, `profiles`,
`providerRefs`, `profileLinks` и `linksPage`. Provider refs
содержат machine, instance и canonical protocol.

## Defaults

Lifecycle включён, publisher `enable = false`, `secretPrefix` и
gateway address fields пусты или nullable. Из публикации исключается
профиль `probe`; links page включена, path —
`/config-links/`, title — `VPN client profiles`, tailnet-only режим
включён.

## Exports and dependencies

Role экспортирует `vpnPublisher` и выбирает providers через raw Clan
exports и `clanLib.selectExports`: `naiveproxy` требует addon, а
`vless-xhttp`, `hysteria2`, `amneziawg` — gateway. Отсутствующий,
disabled, неоднозначный или несоответствующий provider блокирует
генерацию.

Mihomo и Sing-box передаются роли из `apps-nixpkgs`; сама
роль не выбирает package stream и не собирает сторонние клиенты локально.

Sing-box профиль сохраняет Naive как отдельный HTTPS/H2 outbound с проверкой
TLS, `quic = false`, `udp_over_tcp = false` и `insecure_concurrency = 0`.
UDP, совпавший с защищаемыми rule sets, отклоняется до Naive: TCP-only путь не
получает скрытый DIRECT fallback. Ранее согласованные прямые исключения для
LAN, router, Tailscale и DNS обрабатываются раньше. Native `Rule`/`Global`
режимы имеют независимые `SELECTIVE`/`FULL` selectors и Auto selections.
Mihomo публикуется двумя Rule-mode файлами: `mihomo.yaml` заканчивает обычный
трафик в DIRECT, а `mihomo-full.yaml` — в FULL после тех же прямых исключений.
DIRECT не входит в VPN selectors: при отказе выбранного пути защищаемый трафик
не переключается автоматически, а отключение VPN остаётся явным действием
пользователя в клиенте.

Если для публикуемого Sing-box профиля нет eligible Naive provider, renderer
не публикует `profile.json` и не добавляет ссылку на него. Mihomo-файлы с
eligible providers других протоколов продолжают публиковаться. Так защищаемый
трафик нельзя случайно направить в DIRECT через профиль, выглядящий как VPN.

Selective policy использует только blocked/geoblocked и dependency rule sets.
Личные домены задаёт consumer через `personalProxyDomains`; библиотека не
содержит пользовательский список. При миграции прежние строки из
`rules/personal-proxy-domains.txt` нужно перенести в этот setting как доменные
суффиксы без `+.`.

Sing-box DNS сначала принимает любой ответ основного AdGuardHome, затем при
transport error гоняет encrypted reserve (Cloudflare Standard, Quad9 `.10`
без ECS, Google), и только после transport errors — plaintext адреса в том же
порядке. DNS response, включая NXDOMAIN или SERVFAIL, завершает tier. Mihomo
по принятому решению использует только основной AdGuardHome, без клиентского DNS
fallback и дополнительного локального resolver. Его DNS fallback filters не
выражают этот transport-only каскад без изменения семантики. Если
AdGuardHome недоступен и нет кэшированного ответа, новые DNS-запросы
Mihomo завершаются ошибкой.

Naive credentials выбираются по именам профилей из provider export. Карта не
ограничена встроенными device names, а probe публикуется только если consumer
явно включает его в `profiles` и `providerRefs`; штатный default исключает
`probe` из публикации.

## State and secrets

Runtime files находятся под `/run/mihomo-client-config/<machine>` и
`/run/caddy-auth`; persistent state роль не объявляет. UUID/password/
key inputs читаются по SOPS paths через заданные secret names. Generated
profiles, link tokens и credentials не записываются в Git или Nix store.
Имена machine/profile/instance ограничены безопасными 64-символьными
идентификаторами, а secret names — сегментным SOPS path grammar. Каждый
profile link обязан ссылаться на renderer-owned path-token secret. Сам token
должен состоять из 32–128 unpadded base64url символов без завершающего newline;
renderer проверяет raw bytes до генерации Caddy fragment и links page.

## Network exposure

Publisher добавляет Caddy config gateway и optional tailnet-only links
page; public bind и certificate claim задаются явно. Mirror jobs для
rule assets и HageZi работают как timers, но не создают новый VPN
listener. Profile page не является публичной WAN admin surface.

## Verification

Read-only evaluation:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
Проверить protocol-role mapping, ровно один export на providerRef,
generated runtime paths, Caddy tailnet policy и список исключённых
profiles без вывода файлов с credentials.
