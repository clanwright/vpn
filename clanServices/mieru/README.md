# @clanwright/vpn-mieru

## Назначение

Роль `gateway` запускает stock Mieru `3.36.0` как отдельный native-процесс
`mita`. Сервер принимает один TCP transport; UDP-запросы клиентов Mieru
ретранслируются внутри этого TCP transport и не создают публичный UDP listener.
Модуль не добавляет TLS, домен, front site или скрытый multiplexer.

Границы домена описаны в [архитектуре](../../docs/architecture.md), публичный
API — в [контрактах](../../docs/contracts.md), подготовка consumer и runtime
приёмка — в [операционной инструкции](../../docs/operations/mieru.md).

`mita` слушает wildcard address: в его server schema нет bind-address field.
Поэтому `ingressIPv4` — consumer-owned public endpoint и адрес firewall guard,
а не утверждение о socket bind. Module-owned nftables base chain отбрасывает
TCP на выбранном порту для любого другого IPv4 и для IPv6 до правил обычного
NixOS firewall; обычный firewall отдельно разрешает только
`ingressIPv4:port`. Consumer по-прежнему владеет адресом, внешней экспозицией,
provider firewall, NAT и проверкой конфликтов порта.

## Settings

- `enable` — включает роль, default `true`.
- `ingressIPv4` — точный non-wildcard IPv4 endpoint.
- `port` — единственный TCP port, default `443`.
- `users` — непустой список устройств `{ name, passwordSecretName }`.
- `dnsResolverIPv4s` — непустой уникальный список точных IPv4 system
  resolvers. Он обязан совпадать с `networking.nameservers`.

Пример consumer settings:

```nix
{
  enable = true;
  ingressIPv4 = "192.0.2.13";
  port = 8443;
  users = [
    {
      name = "phone";
      passwordSecretName = "vpn/mieru/phone-password";
    }
  ];
  dnsResolverIPv4s = [ "127.0.0.1" ];
}
```

Каждое устройство использует отдельный consumer-owned SOPS secret. Raw secret
должен содержать 1–64 ASCII bytes из `[A-Za-z0-9_-]`: padding `=`, whitespace,
newline и другие bytes отклоняются до запуска без печати значения. Полный JSON
с credential placeholders создаётся только через runtime SOPS template с mode
`0400`; committed JSON и actual credentials модуль не создаёт.
Для consumer-generated пароля рекомендуется 32 случайных байта, закодированных
в unpadded base64url (43 символа); ограничение формата само по себе не гарантирует
достаточную энтропию.

## Native config и процесс

Generated server JSON фиксирует один `TCP` port binding, `loggingLevel = INFO`,
`dns.dualStack = ONLY_IPv4`, per-device users и явные
`allowPrivateIP = false`, `allowLoopbackIP = false`. `trafficPattern`, UDP MTU,
custom DNS upstream и native egress rules не генерируются. Standard upstream
traffic pattern поэтому остаётся implicit default.

`mita.service` использует upstream foreground path `mita run`, static
user/group `mita`, `/run/mita/mita.sock` и `/var/lib/mita`. Upstream может
оставить management RPC активным после ошибки запуска proxy listener, поэтому
bounded `postStart` проверяет, что именно main PID владеет wildcard TCP LISTEN
socket на выбранном порту. Это server readiness check, не проверка handshake,
relay traffic или client acceptance. Upstream runtime singleton paths означают,
что на машине разрешён только один active Mieru instance.

## Destination guard

Native Mieru `allowPrivateIP` и `allowLoopbackIP` не закрывают DNS-resolved и
per-datagram UDP relay destinations. Module-owned `inet` nftables output chain
по static UID `mita` сначала сохраняет `ct direction reply`, затем разрешает
только TCP/UDP port 53 к `dnsResolverIPv4s`, блокирует private, loopback,
link-local/metadata, CGNAT, documentation, benchmark, multicast и reserved IPv4,
и блокирует весь IPv6 egress. Остальной public IPv4 egress разрешён.

Guard требует enabled NixOS nftables firewall. `mita.service` связан с
`nftables.service` через ordering, requirement, `BindsTo` и `PartOf`, чтобы
процесс не продолжал работать после остановки или restart firewall unit.
Effective table content, static service identity, package, command и runtime
paths защищены assertions от consumer override. Если consumer использует local
resolver из denied range, исключение остаётся узким: только объявленный IPv4 и
TCP/UDP port 53.

## Export

Role публикует `vpnProvider` schema v2 с `protocol = "mieru"`, endpoint
`{ domain = null; ipv4 = ingressIPv4; port; transport = "tcp"; }`, metadata
`userNames` и `credentialEncoding = "base64url"`, а также
`secretNames.users = { <device> = <SOPS-name>; }`. Disabled role не публикует
export и не объявляет unit, users, secrets, template, overlay или nftables table.

## Границы проверки

Pure Nix contracts проверяют schema, exact generated JSON/export, package
authority, singleton, runtime wiring, listener ownership probe и неизменность
ingress/egress guards. Они не запускают `mita`, не строят package и не проверяют
доступность из России. Полное принятие требует owner-side import, handshake,
sustained TCP и UDP-relay transfer, reconnect/idle и проверки на целевых сетях с
точными версиями client/core/server. Разница часов более четырёх минут также
может сломать протокол; time synchronization остаётся consumer-owned.

Upstream schema и runtime behavior:

- <https://github.com/enfein/mieru/blob/v3.36.0/pkg/appctl/proto/servercfg.proto>
- <https://github.com/enfein/mieru/blob/v3.36.0/pkg/appctl/server.go>
- <https://github.com/enfein/mieru/blob/v3.36.0/pkg/cli/server.go>
- <https://github.com/enfein/mieru/blob/v3.36.0/docs/operation.md>
