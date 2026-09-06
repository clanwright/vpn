# @clanwright/vpn-mihomo-hysteria2

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это самостоятельный Hysteria2 gateway-фрагмент для общего
`mihomo-runtime`. Он обслуживает только Hysteria2 UDP protocol и
экспортирует typed provider metadata для клиентов и probes.

## Settings

Параметры: `lifecycle`, `enable`, обязательные `listenIPv4`,
`serverName`, `acmeCertName`, `masqueradeUrl`, список `users` с
`name` и `passwordSecretName`, а также `port`, `ignoreClientBandwidth`
и `obfsPasswordSecretName`.

## Defaults

Lifecycle и `enable` включены, порт — `443`, `ignoreClientBandwidth`
включён. ACME cert name, server name, masquerade URL, obfuscation secret и
user list задаются явно; ALPN текущего runtime — `h3`.

## Exports and dependencies

Экспорт `vpnProvider` описывает protocol `hysteria2`, UDP endpoint,
SNI/ALPN metadata и имена user secrets. Роль подключает общий
`modules/edge/mihomo-runtime.nix`; certificate claim и Caddy ownership
приходят из composition.

## State and secrets

Собственного persistent state нет. Пароли пользователей и obfuscation
password читаются через SOPS runtime paths, создаваемые общим runtime
модулем; в typed export передаются только имена и несекретная metadata.

## Network exposure

Роль создаёт один destination-scoped UDP listener на
`listenIPv4:443` (или заданном `port`) и соответствующее правило
firewall. TCP/VLESS, AmneziaWG и другие протоколы этим фрагментом не
включаются.

## Verification

Проверить provider export и networkCore можно read-only:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
Проверить Hysteria2 UDP endpoint, ALPN `h3`, certificate dependency и
наличие только ожидаемых secret names; значения секретов не выводить.
