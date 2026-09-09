# @clanwright/vpn-naiveproxy

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это addon-роль для NaiveProxy. Она генерирует Caddy
`forward_proxy` fragment и присоединяет его к уже существующему public
site claim; собственного сайта, домена и сертификата роль не создаёт.
Effective Caddy address этого claim становится catch-all `:443`, чтобы
`CONNECT` с произвольным origin host достигал `forward_proxy`; выбранный claim
по-прежнему владеет bind addresses, TLS certificate и cover site.
На именованных vhost с тем же bind ранний `CONNECT` route ограничен методом,
точным local address и TCP-портом `443`. Claim с отдельным tailnet listener не
получает forward-proxy route. Выбранный claim обязан иметь ровно один явный
listener; wildcard и смешанный public/tailnet bind отклоняются.

## Settings

Параметры: `enable`, `machineName`, `selectedPublicSiteClaim`,
`selectedPublicSiteEndpoint` с полями `domain`, `publicIPv4`,
`caddyBindIPv4`, карта `passwordSecretNames` вида `identity = secret-name`,
`probeUserName` и `additionalDeny`. Прежняя карта с ключами `ibelyasov`, `bsv`,
`probe` остаётся допустимой. Identity и machine name — ограниченные токены;
secret names допускают namespace через `/`, но не traversal или управляющие
символы. Endpoint должен совпадать с выбранным claim.

## Defaults

`enable` по умолчанию `true`; адресные поля endpoint по умолчанию
пусты и становятся обязательными после выбора claim. Пользовательские
password secret names задаются явно, чтобы один addon не выбирал credentials
неявно. `probeUserName` по умолчанию равен `probe`; он входит в server auth и
`userNames`, но исключён из обычных `profileNames`.

## Exports and dependencies

Экспорт `vpnProvider` содержит protocol `naiveproxy`, TCP endpoint
`443` и несекретную metadata. Роль зависит от существующего
`networkCore.publicSite` claim с `publicSite = true`; она только
добавляет Caddy fragment и reload dependency.

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
через argv и не записывает в Nix store, Git или логи. Произвольные legacy
password strings с Caddy syntax не входят в контракт и требуют отдельно
согласованной rotation перед применением.

Поскольку adapted Caddy config содержит basic-auth material, addon добавляет
`persist_config off` и требует `services.caddy.resume = false`: новые runtime
credentials не попадают в autosave. Удаление autosave, созданного прежней
конфигурацией, остаётся отдельной consumer-side операцией с секретными данными
и не выполняется модулем автоматически.

## Network exposure

NaiveProxy использует TCP `443` уже выбранного public site и не открывает
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

Contract checks подтверждают legacy и произвольные identity maps, разделение
probe, отрицательные assertions, оба sops-nix activation mode, template
permissions/reload metadata, ACL order и listener isolation. Проверки — pure
Nix; application parser/CLI, runtime tests, VM и тесты на реальных машинах
запрещены. Реальные auth, relay и reload не объявляются проверенными.
Границы проверки и native lifecycle описаны в
[операционном runbook](../../docs/operations/naiveproxy.md).
