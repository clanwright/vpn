# @clanwright/vpn-mihomo-vless-xhttp

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это самостоятельный VLESS/REALITY + XHTTP gateway-фрагмент для общего
`mihomo-runtime`. Он владеет своим TCP listener и не включает Hysteria2,
AmneziaWG, NaiveProxy или publisher профилей.

## Settings

Входы: `lifecycle`, `enable`, обязательные `bindIPv4`, `domain`,
`reality.serverName`, `reality.dest`, `reality.shortIds`,
`reality.publicKey`, `reality.privateKeySecretName`, `xhttp.path`
и `profiles` с `name`, `vlessUuidSecretName`, `kind`. Также
задаются `port`, `clientFingerprint`, `doh.domain`,
`doh.ipv4`, `xhttp.mode` и optional `publishProfileJson`.

## Defaults

Lifecycle и `enable` включены, fingerprint — `edge`, XHTTP mode —
`packet-up`; порт и DoH values задаются composition. Profile kind по
умолчанию `mobile`; активная роль требует reality и XHTTP inputs.

## Exports and dependencies

Экспорт `vpnProvider` описывает protocol `vless-xhttp`, TCP endpoint,
REALITY/XHTTP/fingerprint/DoH metadata и только имена UUID/key secrets.
Runtime и secret materialization выполняет общий
`modules/edge/mihomo-runtime.nix`.

## State and secrets

Persistent state роль не создаёт. UUID values и REALITY private key
читаются через SOPS runtime paths; в репозитории остаются только input
names. Generated profile bodies не являются state этого gateway и
публикуются отдельной publisher-ролью.

## Network exposure

Создаётся один TCP listener на `bindIPv4:port` с адресным firewall
правилом. Hysteria2/UDP и другие протоколы не слушаются этим фрагментом;
DoH metadata используется клиентскими профилями и не добавляет listener.

## Verification

Read-only evaluation:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
Проверить typed provider protocol, REALITY/XHTTP consistency, TCP
destination rule и runtime secret paths без вывода их содержимого.
