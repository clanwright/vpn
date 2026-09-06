# @clanwright/vpn-amneziawg

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это gateway-роль для нативного интерфейса AmneziaWG. Она компилирует
параметры сервера в NixOS WireGuard interface с `type = "amneziawg"` и
публикует typed metadata для клиентов и проверок.

## Settings

Входы включают `lifecycle`, `enable`, `interfaceName`, обязательные
`listenIPv4`, `address`, `privateKeySecretName`, `serverPublicKey` и
`peers`, а также `endpointDomain`, `listenPort`, `mtu` и
`extraOptions`. При `enableNat = true` обязательны `egressIPv4` и
`clientSubnetIPv4`. Пиры задают только несекретную адресную метаинформацию и
имена secret inputs.

## Defaults

Жизненный цикл и `enable` по умолчанию включены, порт — `443`, имя
интерфейса — `awg0`, `endpointDomain` пуст, `mtu` не переопределён,
NAT включён, `extraOptions` — пустой набор. Активная роль требует
непустых адреса, server public key, private-key name и списка пиров.

## Exports and dependencies

Экспорт `vpnProvider` содержит протокол `amneziawg`, UDP endpoint,
адрес и несекретную информацию о пирах. Роль использует пакеты
`apps-nixpkgs` и проверяет согласованные семейства `amneziawg-go 3.1.*` и
`amneziawg-tools 3.1.*`; ingress и forwarding добавляются в штатные allow-chains
NixOS nftables firewall, а SNAT принадлежит отдельной таблице роли. Текущий contract сохраняет прежний
AWG2-совместимый набор `extraOptions`; AWG3-only keys и timing fields не
добавлены.

## State and secrets

Серверный ключ читается из SOPS runtime path
`config.sops.secrets.<privateKeySecretName>.path`, обычно
`/run/secrets/<name>`, с владельцем `root:root` и режимом `0400`.
Ротация перезапускает только соответствующий
`wireguard-<interface>.service`. Значения ключей и preshared keys в Git
не попадают; отдельные probe keys принадлежат probe-роли.

## Network exposure

Активный интерфейс принимает только UDP на `listenIPv4:listenPort`;
правило nftables firewall ограничено destination IP. При NAT штатный
forward allow-chain разрешает исходящий клиентский трафик и established return
на интерфейсе роли, а отдельная IPv4 NAT table выполняет SNAT только для
`clientSubnetIPv4`; публичного TCP-входа роль не создаёт.
`disabled-retained` сохраняет идентичность и secret metadata, но убирает
интерфейс, пакеты, firewall, forwarding, NAT и sysctl-эффекты.

## Verification

Read-only проверка интерфейса выполняется через
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
Перед активацией следует проверить непустые обязательные поля, допустимые
AWG extra options и версии пакетов; после активации — состояние
`wireguard-<interface>.service` и адресный UDP rule без вывода секретов.
