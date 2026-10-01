# @clanwright/vpn-naiveproxy

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это addon-роль для native Caddy virtual host, выбранного по canonical `domain`.
Она добавляет `forwardProxy = true` и authenticated CONNECT fragment; base site
owner, listeners, aliases и physical certificate ID остаются у consumer.
Выбранный vhost имеет catch-all address `:443` и ровно один явный IPv4 listener,
совпадающий с `bindIPv4`. Advertised `publicIPv4` не заменяет фактический bind.

Read-only `clanwright.vpn.naiveproxy.connectRoute` — полный authenticated CONNECT
fragment с matcherless outer `route` и внутренними guards по методу и точному
local `bindIPv4:443`. Он импортирует тот же runtime policy с authentication, ACL и probe resistance, сохраняя Nix string context.
Root catch-all получает fragment автоматически ровно один раз. Consumer явно
присоединяет тот же fragment через `lib.mkBefore` (500) внутри каждого named
canonical/alias native Host route на выбранном PUBLIC listener, способного
перехватить разрешённый CONNECT target. Внешний terminal Host route имеет
приоритет перед root catch-all; внутренний order 500 сам по себе это не исправляет.

Это listener-wide authentication, без TLS SNI allowlist. Port destination
authority не является портом local listener. Guard сравнивает
`{http.request.local.port} == 443` численно, без quoted `"443"`; одна adaptation
не доказывает effective type. Обычные сайты не получают
`forwardProxy = true`; owner, hostName, certificates, listeners и GET routes
сохраняются. Local bind/443 guard сохраняет private, mixed и disjoint listener
boundaries. Нет sibling scanner, registry, открытия listener или firewall.
Точный consumer callsite приведён в
[migration runbook](../../docs/operations/migrate-contracts.md#native-naiveproxy-and-certificates).

## Settings

Точная схема и defaults определены в [`default.nix`](default.nix).
Параметры: `enable`, обязательные `domain`, `publicIPv4`, `bindIPv4`,
карта `passwordSecretNames` вида `identity = secret-name`
и `additionalDeny`. Identity — ограниченный токен;
secret names допускают namespace через `/`, но не traversal или управляющие
символы. Native vhost по ключу `domain` должен иметь существующего owner
и точный listener `[ bindIPv4 ]` на TCP `443`. Ровно один выбранный vhost
может иметь `forwardProxy = true`; unique owner/extension contract задаёт
Network. Native Caddy должен иметь `httpsPort = 443`, Caddyfile reload enabled
и `resume = false`.
На одной машине допускается ровно один active instance: instances разделяют
machine-wide Caddy integration и runtime template namespace. Disabled instance
не заявляет эти ресурсы и может соседствовать с одним active.

## Defaults

`enable` по умолчанию `true`; `domain`, `publicIPv4` и `bindIPv4`
не имеют defaults и задаются явно. Пользовательские
password secret names задаются явно, чтобы один addon не выбирал credentials
неявно. Каждая identity из `passwordSecretNames` получает server auth и
экспортируется как ключ `connection.naiveproxy.clients`; служебных identity модуль не резервирует.

## Exports and dependencies

Экспорт `vpnProvider` schema 3 содержит `connection.naiveproxy`, endpoint
`{ hostname; ipv4; port = 443; }` и `clients.<username>.passwordSecret`.
Имена accounts совпадают с реальными server auth usernames; экспорт содержит
только binding names, без значений паролей. Роль расширяет существующий
`services.caddy.virtualHosts.<domain>`; base owner не объявляется повторно.
Native composition использует специализированный Network-owned Caddy и
публичный native Caddy/ACME API. Совместимость producer input и границы
приёмки определены в [verification](../../docs/operations/verify.md#evidence-and-runtime-acceptance).

## State and secrets

Persistent state и собственный root/site отсутствуют. `sops-nix`, подключённый
через Clan, нативно создаёт закрытый runtime template
`/run/secrets/rendered/naiveproxy-<machine>.caddy` с owner `root`, Caddy group и
mode `0440`. Caddy импортирует этот fragment; изменение template вызывает
штатный `caddy reload`. При systemd activation Caddy получает `Wants=` и
`After=` для `sops-install-secrets.service`, а при activation-script mode
несуществующий unit не объявляется. `Wants=` сохраняет порядок cold start, но
не останавливает Caddy при обновлении native SOPS unit.

Password value должен быть непустым unpadded base64url token:
`[A-Za-z0-9_-]+`, без LF, CR, пробелов и padding `=`. Этот формат генерируется
consumer-side Clan vars и безопасно подставляется `sops-nix` непосредственно в
Caddyfile token. Модуль не читает и не меняет secret values, не передаёт их
через argv и не записывает в Nix store, Git или логи. Password strings с Caddy
syntax не входят в контракт.

Поскольку adapted Caddy config содержит basic-auth material, addon требует
эффективную Network policy с `persist_config off` и `services.caddy.resume = false`.
Отключение persistence задаёт Network; новые runtime credentials не должны
попадать в autosave. Модуль не удаляет существующий autosave:
это отдельная consumer-side операция с секретными данными.

## Network exposure

NaiveProxy использует TCP `443` выбранного native vhost и не открывает
другой listener. Domain/certificate/static root/firewall ownership остаются
у владельца сайта; addon не добавляет отдельный WAN endpoint.

Destination policy разрешает все TCP-порты публичного интернета. Явные deny
для private, loopback, link-local, CGNAT/Tailscale, documentation, benchmark,
multicast/reserved IPv4 и IPv6 ULA/link-local/special ranges идут до финального
`allow all`. `additionalDeny` добавляет consumer-owned IPv4/IPv6 адреса и CIDR
перед разрешающим правилом. Hostname здесь запрещены: точный forwardproxy
parser сопоставляет их case-sensitive и раннее domain rule может создать обход
после DNS resolution. Domain allow rules модуль также не создаёт.

## Verification

Contract checks подтверждают произвольные identity maps, совпадение
`connection.naiveproxy.clients`, отрицательные assertions, оба sops-nix
activation mode, template permissions/reload metadata, ACL order и listener
isolation. Проверки — pure Nix; application parser/CLI, runtime tests, VM и
тесты на реальных машинах запрещены. Реальные auth, relay и reload не
объявляются проверенными.
Границы проверки и native lifecycle описаны в
[операционном runbook](../../docs/operations/naiveproxy.md).
