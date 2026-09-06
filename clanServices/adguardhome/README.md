# @clanwright/dns-adguardhome

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это роль DNS-резолвера на базе AdGuard Home. Она предоставляет локальный
DNS-стаб и DoH через Caddy; веб-интерфейс доступен только в административной
сети. Публичный DoT не является частью текущей поверхности.

## Settings

Основные входы роли: `ui.host`, `ui.port`, `ui.domain`, `ingress.publicIPv4`,
`ingress.caddyBindIPv4`, `ingress.tailnetIPv4`, `dns.bindHosts`,
`dns.port`, `dns.upstream`, `dns.bootstrap`, `tls.serverName`,
`tls.httpsPort`, `tls.dotPort`, `acme.certName`, `auth.enable`,
`auth.username`, `auth.passwordSecretName`, `systemResolver.enableLocalStub`
и `adguard.extraSettings`. Активная роль требует адреса, имени сертификата и
непустого TLS server name.

## Defaults

Жизненный цикл по умолчанию — `enabled`; HTTPS использует порт `8444`,
DoT выключен значением `0`, логин администратора — `admin`, локальный
стаб включён, а системные имена резолверов — `127.0.0.1` и `::1`.
Публичный интерфейс и tailnet-интерфейс задаются отдельно.

## Exports and dependencies

Роль регистрирует ACME claim для сертификата и публикует typed DNS-provider
metadata для потребителей. Caddy-конфигурация зависит от claim и от
интерфейса tailnet; локальный резолвер может быть выбран другими сервисами
через inventory.

## State and secrets

Состояние AdGuard Home хранится в `/var/lib/private/AdGuardHome`. Пароль
администратора передаётся только через имя SOPS-секрета
`auth.passwordSecretName`; runtime-файл имеет вид
`/run/secrets/<name>`, владелец `acme:acme`, режим `0440`. Значения
паролей в Git и документации не хранятся.

## Network exposure

DNS TCP/UDP `53` привязан к `tailscale0`. DoH публикуется Caddy на
пути `/dns-query`; UI использует явно заданные `ingress.caddyBindIPv4` и
tailnet bind, а UI route обслуживается только на declared tailnet destination;
interface ingress к этому адресу ограничивает Network firewall. На VPN gateway
`caddyBindIPv4` может быть loopback, когда public TCP listener принадлежит
gateway и передаёт fallback локальному Caddy. Входящий DoT выключен. В режиме
`disabled-retained` сохраняются только state и metadata секрета, без
runtime, ACME claim, firewall и resolver edges.

## Verification

Проверить интерфейс и значения роли можно через read-only evaluation:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
После активации проверяются локальный DNS на `53`, DoH на
`/dns-query` и отсутствие WAN DoT; расшифрованные секреты не выводятся.
