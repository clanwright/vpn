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
`excludedProfileNames`, `tailnetAdminDomains`, `profiles`,
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

Mihomo, Sing-box и AmneziaWG tools передаются роли из `apps-nixpkgs`; сама
роль не выбирает package stream и не собирает сторонние клиенты локально.

## State and secrets

Runtime files находятся под `/run/mihomo-client-config/<machine>` и
`/run/caddy-auth`; persistent state роль не объявляет. UUID/password/
key inputs читаются по SOPS paths через заданные secret names. Generated
profiles, link tokens и credentials не записываются в Git или Nix store.

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
