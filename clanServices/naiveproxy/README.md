# @clanwright/vpn-naiveproxy

## Purpose and role

Граница домена описана в [архитектуре](../../docs/architecture.md), публичный API — в [контрактах](../../docs/contracts.md).

Это addon-роль для NaiveProxy. Она генерирует Caddy
`forward_proxy` fragment и присоединяет его к уже существующему public
site claim; собственного сайта, домена и сертификата роль не создаёт.
Effective Caddy address этого claim становится catch-all `:443`, чтобы
`CONNECT` с произвольным origin host достигал `forward_proxy`; выбранный claim
по-прежнему владеет bind addresses, TLS certificate и cover site.
На именованных vhost с тем же bind ранний `CONNECT` route ограничен только
пересечением local listeners, поэтому дополнительный tailnet listener не
становится forward proxy.

## Settings

Параметры: `enable`, `machineName`, `selectedPublicSiteClaim`,
`selectedPublicSiteEndpoint` с полями `domain`, `publicIPv4`,
`caddyBindIPv4`, и обязательные password secret names для
`ibelyasov`, `bsv`, `probe`. Endpoint должен совпадать с выбранным
claim.

## Defaults

`enable` по умолчанию `true`; адресные поля endpoint по умолчанию
пусты и становятся обязательными после выбора claim. Пользовательские
password secret names задаются явно, чтобы один addon не выбирал
credentials неявно.

## Exports and dependencies

Экспорт `vpnProvider` содержит protocol `naiveproxy`, TCP endpoint
`443` и несекретную metadata. Роль зависит от существующего
`networkCore.publicSite` claim с `publicSite = true`; она только
добавляет Caddy fragment и reload dependency.

## State and secrets

Persistent state и собственный root/site отсутствуют. Пароли читаются из
SOPS runtime paths `/run/secrets/<name>` с root-only режимом
`0400`; изменение любого из трёх secret inputs перезапускает Caddy.
Значения паролей и profile URLs не записываются в Git.

## Network exposure

NaiveProxy использует TCP `443` уже выбранного public site и не открывает
другой listener. Domain/certificate/static root/firewall ownership остаются
у владельца сайта; addon не добавляет отдельный WAN endpoint.

## Verification

Проверить claim и provider export можно read-only:
`nix eval --no-write-lock-file .#nixosConfigurations.<machine>.config.networkCore`.
Нужно подтвердить совпадение domain и caddy bind address, наличие только
ожидаемого fragment и корректные secret paths без раскрытия значений.
