# AdGuard Home: аудит на 8 сентября 2026

## Статус

Независимое source review и полный репозиторный gate прошли; результат —
в [основном аудите](audit-2026-09.md). Принятый дефект версии EDNS ниже остаётся открытым.

Репозиторная доработка завершает выбранный source-контракт AdGuard Home:
локальный Unbound остается единственным primary, постоянный native dnsproxy
реализует encrypted/plaintext fallback, admin-auth получает готовый bcrypt-хеш
из SOPS, а UI и DoH имеют раздельные Caddy listeners. Изменений consumer,
DNS-провайдеров, сертификатов, секретов, машин и релиза в этой работе нет.

Проверка ограничена чистым Nix evaluation и source review. AdGuard Home,
dnsproxy и VM не запускались. Поэтому документ подтверждает декларативную
конфигурацию и ограничения модуля, но не доказывает фактическое поведение
systemd, сетевую доступность или устойчивость на российских сетях.

## Пакеты и принятый пробел версии

Роль получает оба пакета из domain platform pin и утверждениями запрещает
подмену. Финальный выбор:

| Компонент | Версия | Основание |
|---|---:|---|
| AdGuard Home | 0.107.78 | Stock-пакет закрепленного apps-nixpkgs, готовый output есть в Nix cache |
| Go toolchain | 1.26.7 | Фактический toolchain выбранного derivation |
| dnsproxy | 0.83.2 | Stock-пакет закрепленного apps-nixpkgs, точная исследованная версия |

Отдельный wrapper или локальный пакет 0.107.79 не используется. Go 1.26.7
содержит toolchain security fixes, ради которых рассматривалось обновление.
При этом остается принятый compatibility gap AdGuard Home
[issue #8183](https://github.com/AdguardTeam/AdGuardHome/issues/8183): в 0.107.78
заблокированный ответ на EDNS(0)-запрос может не содержать OPT. Строгий клиент
может отвергнуть такой ответ; это не классифицировано как подтвержденная
уязвимость выбранного профиля. DoQ выключен, поэтому исправление DoQ resource
exhaustion из 0.107.79 к активным listeners не относится.

## DNS-каскад

AdGuard отправляет обычные запросы на единственный consumer-owned endpoint
Unbound, по умолчанию `127.0.0.1:5335`. В модуле нет `Requires` или ordering на
Unbound: неуспешный backend не блокирует жизненный цикл frontend. Единственный
fallback AdGuard — `127.0.0.1:5336`, где native `services.dnsproxy` выполняет:

1. параллельный DoH к [Cloudflare Standard](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/),
   Quad9 `9.9.9.10` без threat blocking и Google Public DNS;
2. только после ошибок обмена всего encrypted-пула — параллельный plaintext к
   `1.1.1.1:53`, `9.9.9.10:53` и `8.8.8.8:53`.

DNS stamps содержат статический connect IP и отдельную TLS identity. Bootstrap
и host resolver не нужны, TLS verification не отключена. По исходникам
[dnsproxy 0.83.2](https://github.com/AdguardTeam/dnsproxy/blob/v0.83.2/proxy/proxy.go)
fallback открывается при ошибке exchange. Полученные NXDOMAIN и SERVFAIL
возвращаются клиенту и не открывают следующий уровень. Fallback pool самого
dnsproxy опрашивается параллельно.

AdGuard имеет общий `upstream_timeout=10s`; timeout каждой из двух стадий
dnsproxy равен 3s. Typed assertion требует `2 * timeout + 1 < 10`, чтобы
plaintext-ступень помещалась во внешний бюджет. Это расчетная граница source
конфигурации, а не измеренная latency.

AdGuard и Unbound кешируют ответы. У AdGuard `cache_ttl_min=0`,
`cache_ttl_max=0`, `cache_optimistic=false`; dnsproxy cache явно выключен.
Stale разрешен только политикой Unbound. DNSSEC включен, ECS, DNS64, DHCP,
hosts-file, DDR, HTTP/3, DoT, DoQ и DNSCrypt выключены. Plain DNS rate limit
равен 0 только вместе с обязательной private listener policy и закрытым native
firewall; `refuse_any=true` сохранен.

## Фильтрация и журналы

Сохраняются HaGeZi Multi NORMAL, URLHaus, parental control и Safe Search.
Удаленный Safe Browsing выключен. Filtering/protection и rewrites включены,
blocked response TTL равен 10s. Личные allow/deny rules удалены из library
defaults: typed `filtering.userRules` имеет пустой default, а значения задаёт
consumer. Freeform `extraSettings` удален, чтобы новые или неизвестные ключи
AdGuard не могли обойти typed policy роли.

Query log хранится 7 дней, statistics — 90 дней, IP клиентов не
анонимизируются. Эти данные остаются диагностическими и чувствительными;
политика Caddy access logs и внешнего мониторинга принадлежит consumer.

## Auth и декларативная конфигурация

Активный lifecycle требует auth. Consumer SOPS secret содержит один готовый
60-символьный bcrypt token (`$2a$`, `$2b$` или `$2y$`, cost 04–31) без пробелов
и завершающего LF. Secret объявлен как `root:root 0400`; plaintext password и
runtime bcrypt generation исключены.

Модуль сериализует полный typed attrset через `builtins.toJSON`, который YAML
parser принимает как JSON subset, и вставляет только SOPS placeholder.
`services.adguardhome.settings=null` отключает штатное копирование NixOS-модуля.
SOPS template имеет `root:root 0400`, restartUnits для AdGuard и передается
через systemd `LoadCredential`. Перед штатным ExecStart native unit выполняет
прямой `install -m 600` в StateDirectory и `AdGuardHome --check-config` тем же
закрепленным пакетом. DynamicUser, StateDirectory, штатный ExecStart и sandbox
NixOS-модуля не заменяются. UI-записи диагностические: restart восстанавливает
декларативный файл.

При `sops.useSystemdActivation=true` unit получает `After` и `Wants` на
`sops-install-secrets.service`; при activation-script mode отсутствующий unit
не добавляется. AdGuard мягко запрашивает dnsproxy через `Wants`/`After`, без
`Requires`. В `disabled-retained` сохраняются state declaration и metadata
секрета, а runtime, template, ACME/Caddy contributions, firewall и resolver
edges отсутствуют.

## Экспозиция

Plain DNS обязан включать `127.0.0.1` и может слушать только loopback, RFC1918
или Tailscale IPv4 адреса; порт 53 firewall открывается лишь на `tailscale0`.
UI backend закреплен на `127.0.0.1`, UI route — на выбранном tailnet IPv4.
Public DoH route — на явном non-wildcard IPv4 и только `/dns-query`. Оба Caddy
fragment проверяют local destination address и строковый порт `443`, что не
дает объединенному Caddy server обслужить route на соседнем listener.

Caddy соединяется с `https://127.0.0.1:8444`, передает выбранный Host/SNI и
проверяет сертификат; `tls_insecure_skip_verify` отсутствует. Native UI/HTTPS
порты firewall не открывает. Состав адресов, ACME, public ingress, monitoring
и load controls остаются границей consumer composition.

## Доказанная граница

Pure-Nix contracts проверяют обе lifecycle-ветки, точные package identities,
полный generated attrset, SOPS/systemd edges, Caddy fragments и отрицательные
варианты для package overrides, wildcard/public binds, портов и upstream.
Никакой parser или runtime binary в
этих проверках не исполняется. Поэтому свойства, зависящие от запуска процесса
или сети, остаются недоказанными этим аудитом по определению принятого scope.

Репозиторные команды и интерпретация результатов находятся в
[операторском документе](operations/adguardhome.md). Общая архитектурная
граница описана в [architecture.md](architecture.md), consumer contract — в
[contracts.md](contracts.md), политика Unbound — в
[audit-unbound-2026-09.md](audit-unbound-2026-09.md).
