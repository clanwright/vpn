# @clanwright/vpn-mihomo-hysteria2

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Модуль запускает самостоятельный stock Mihomo Hysteria2 service. Его config,
process, Unix identity и restart lifecycle не разделяются с другими VPN
protocols. Stable module ID — `@clanwright/vpn-mihomo-hysteria2`, systemd unit —
`mihomo-hysteria2.service`.

## Settings

Параметры: `lifecycle`, `enable`, обязательные `listenIPv4`, `serverName`,
`acmeCertName`, `masqueradeUrl`, список per-device `users` с `name` и
`passwordSecretName`, а также `port` и `obfsPasswordSecretName`.
`listenIPv4` должен быть конкретным адресом; wildcard `0.0.0.0` запрещен.
На одной машине может быть активен только один instance, поскольку unit и
закрытый SOPS template имеют стабильные имена.

Consumer создаёт и привязывает каждый SOPS secret. Пароли пользователей и Gecko
должны быть непустыми unpadded base64url strings (`A-Z`, `a-z`, `0-9`, `_`, `-`),
чтобы literal SOPS substitution оставляла сгенерированный JSON валидным. Каждый
device и Gecko используют отдельный secret; модуль проверяет уникальность secret
names и не принимает secret values в public settings.

## Fixed protocol policy

Server и экспортированный client contract фиксируют:

- Gecko с `obfs-min-packet-size = 512` и `obfs-max-packet-size = 1200`;
- TLS verification и ALPN `h3`;
- один UDP port без hopping;
- отсутствие `up`/`down`, custom flow windows и `udp-mtu`;
- отсутствие Realm, Mimic и ECH.

Gecko obfuscation несовместима с обычным внешним HTTP/3 и не гарантирует
проходимость UDP или работу в конкретной сети.

Stock Mihomo 1.19.30 отключает проверку TLS certificate для отдельного HTTPS
backend, указанного в `masqueradeUrl`. Это ограничение достоверности cover response;
оно не отключает TLS verification между Hysteria client и этим listener.

## Exports and dependencies

`vpnProvider` публикует один UDP endpoint, SNI/ALPN, точные Gecko sizes,
`tlsVerify = true`, `credentialEncoding = "base64url"`, имена устройств и только
имена SOPS secrets. Клиентский consumer должен сгенерировать симметричные поля и
не добавлять hopping, bandwidth caps или TLS bypass.

Certificate generation, secret generation and SOPS bindings остаются у consumer.
Unit получает только выбранные certificate/key через systemd credentials; service
user не входит в группу `acme`. Native NixOS renewal linkage перезапускает unit.

## Runtime and exposure

SOPS-nix формирует закрытый `mihomo-hysteria2.json`; shell generator отсутствует.
Service работает от отдельного system user; privileged UDP port получает только
`CAP_NET_BIND_SERVICE`. Выбранные certificate/key доступны read-only через private
systemd credential directory, system protection read-only, address families
ограничены. Runtime разрешен только на `x86_64-linux`. Firewall должен быть
включен с backend `nftables` и открывает только
`listenIPv4:port/udp` destination-scoped правилом. Другие TCP/UDP ports модуль не
открывает.

## Verification boundary

Repository acceptance ограничена pure Nix evaluation: schema, export, generated
JSON, package authority, unit sandbox and firewall contract. Она не запускает
Mihomo и не подтверждает certificate availability, listener bind, handshake,
TCP/UDP relay, sustained transfer или reachability в сетях пользователя.
