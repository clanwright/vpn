# @clanwright/vpn-amneziawg

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный
API — в [контрактах](../../docs/contracts.md). Gateway-роль создает userspace
AmneziaWG 3.1 interface и публикует typed metadata для клиентских renderer-ов.

## Settings and fixed profile

Точная схема и defaults определены в [`default.nix`](default.nix).
Обязательны `listenIPv4`, `endpointDomain`, `address`,
`privateKeySecretName`, `headerProtectionKeySecretName`, `serverPublicKey` и
непустой список `peers`. При `enableNat = true` обязательны `egressIPv4` и
`clientSubnetIPv4`. Модуль проверяет IPv4/CIDR, безопасные имена, canonical
32-byte WireGuard public keys и глобальную уникальность peer names, public keys
и allowed IPs.

Каждый peer также задаёт обязательный `clientPrivateKeySecretName` — точное
имя consumer-owned SOPS binding. Имя не выводится из machine или profile name.
Имена клиентских private-key bindings должны быть уникальны и не совпадать с
bindings серверного private key или HeaderProtectionKey.

Профиль фиксирован: MTU 1280, S1–S4 `12`, H1–H4 `1/2/3/4`,
ContentPaddingAddition `2-10`, RandomTrailers включен, DisableCookies выключен.
Jc/I1–I5 и пользовательские timer ranges сервер не задает. Поле
`clientPersistentKeepalive` экспортируется клиенту, но серверному peer не
назначается.

## Exports and packages

`vpnProvider` версии схемы 2 содержит UDP endpoint, `transportMetadata.generation = 3`, typed
public `profile`, интерфейс, адрес, MTU и несекретную peer metadata. Имя
HeaderProtectionKey находится отдельно в
`secretNames.headerProtectionKey`; значение секрета в export отсутствует.
Клиентские private-key bindings находятся в `secretNames.clientPrivateKey`.
Public keys экспортируются только в `transportMetadata.peers`; отдельной
дублирующей карты `peerPublicKeys` нет.

Роль использует stock packages из application package set и требует семейство
3.1 для `amneziawg-go` и `amneziawg-tools`. Foreground
`amneziawg-go -f <interface>` является главным процессом systemd service;
kernel `amneziawg` interface backend не используется.
Каждый active userspace process требует уникальные `interfaceName` и
`listenPort` на машине: daemon слушает UDP wildcard, а `listenIPv4` ограничивает
ingress через nftables, но не задает bind address процесса.
Systemd capability set всегда содержит `CAP_NET_ADMIN` и добавляет
`CAP_NET_BIND_SERVICE` только для порта ниже 1024.

## Runtime secrets and failure behavior

Private key и отдельный 32-byte HeaderProtectionKey читаются из SOPS runtime
paths с `root:root`, mode `0400`; изменение любого секрета перезапускает только
`wireguard-<interface>.service`. Bounded `ExecStartPost` ожидает UAPI socket,
передает весь профиль одним `awg set`, а затем назначает адрес/MTU, поднимает
interface и добавляет peer routes. В tools 3.1.20260812 command parser принимает
`private-key` и `header-protection-key` как пути к key files. Их значения не
входят в Nix store, unit text или argv; вывод `awg set` подавлен, потому что при
ошибке upstream parser может вывести значение неверного ключа. Ошибка setup
останавливает supervised daemon, а idempotent `ExecStopPost` удаляет interface
и UAPI socket. `Restart=on-failure` перезапускает весь lifecycle.

До завершения активации модуль сверяет наличие интерфейса, listen port и точные
наборы public peers и AllowedIPs через выборочные поля `awg show`. Неполная
установка peers при успешном `awg set` также считается ошибкой. Диагностика
сообщает этап отказа без вывода ключей или исходного ответа команды.

## Network exposure

Активная роль принимает UDP только на `listenIPv4:listenPort`; nftables rule
ограничен destination IP. При NAT штатный forward chain разрешает client egress
и established return, а отдельная IPv4 table выполняет SNAT только для
`clientSubnetIPv4` и исключает назначения внутри этой подсети.
Несколько active NAT instances объединяют одно общее требование
`net.ipv4.ip_forward = 1`; instance без NAT его не запрашивает.
При `enable = false` роль не публикует metadata и не объявляет secrets,
interface, packages, firewall, forwarding, NAT или sysctl.

## Verification

`checks/awg-contracts.nix` чистой Nix evaluation проверяет typed export,
валидацию, точные AWG3 options, supervised userspace command, отсутствие kernel
backend и server keepalive/J/I/timers, destination-scoped ingress, загрузку
ключей до link-up и failure cleanup. Реальный handshake, transfer,
MTU/fragmentation и cookie behavior source-only проверкой не установлены.
Полная репозиторная процедура описана в
[verification runbook](../../docs/operations/verify.md).
Отрицательные runtime-сценарии и внешняя consumer-приёмка описаны в
[readiness runbook](../../docs/operations/vpn-readiness.md).
