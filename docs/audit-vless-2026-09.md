# VLESS / REALITY / XHTTP: аудит на 7 сентября 2026

## Статус

Независимое source review и полный репозиторный gate прошли;
доказательства — в [основном аудите](audit-2026-09.md).

Согласованная source-реализация выполнена: стабильный module ID
`vpn-mihomo-vless-xhttp` теперь создаёт отдельный stock Xray 26.3.27 вместо
общего с Hysteria2 процесса Mihomo. Изменены контракт, runtime-only SOPS
template, systemd sandbox, firewall и pure Nix assertions. Deployment,
provider/DNS, реальные credentials и работающие серверы не изменялись.

По принятой границе проверки Xray/parser/listener не запускались. Поэтому этот
статус подтверждает структуру исходников и вычисленную NixOS-конфигурацию, но не
аутентификацию, достижимость, target TLS/SAN или клиентскую совместимость.

## Текущее состояние

Исходная проблема зафиксирована на ревизии
`06b5652b932a9779931088626c60279618850505`; после приёмки владелец
9 сентября разрешил commit/push исправлений в `main`.

| Область | Что есть | Оценка |
|---|---|---|
| Реализация | Отдельный native `xray.service`, stock Xray 26.3.27 | Процесс, package, config и restart не разделяются с Hysteria2 |
| Transport | Прямой TCP, XHTTP `path`, server mode `auto` | Vision, fallback и ручные padding/XMUX overrides отсутствуют |
| REALITY | Явный target `host:443`, TLS 1.3/H2 declarations, matching `serverNames` | Формат проверяется; live TLS/H2 и SAN pure evaluation не доказывает |
| Ingress | nftables rule только для `bindIPv4:port` | Глобальный `allowedTCPPorts` модулем не добавляется |
| Секреты | Native SOPS template `0400`, systemd credential | Private key и UUID остаются runtime-only placeholders при evaluation |
| Изоляция | `DynamicUser`, `NoNewPrivileges`, только `CAP_NET_BIND_SERVICE` для низкого порта | Для высокого порта capabilities пусты; `CAP_NET_ADMIN` из native module удалён |
| Проверки | Pure schema/render/package/service/firewall assertions | Application CLI, parser, listener и сеть намеренно не запускались |

Основание: [контракт и runtime](../clanServices/mihomo-vless-xhttp/default.nix),
[pure assertions](../checks/xray-contracts.nix),
[профили](../clanServices/vpn-client-profiles/client-profiles.nix) и
[операционная граница](operations/vless.md).
Fingerprint, public key и DoH в export — параметры клиентов/публикации,
а не дополнительные настройки серверного listener. Vision для XHTTP сейчас
не включен — это корректно.

Schema отклоняет неверный IPv4, target port не `443`, path без начального `/`,
short ID вне канонических 16 lowercase hex символов и public key неверного формата. Assertions отклоняют дубликаты
profile names, UUID secret names, short IDs и `serverNames`, требуют target host
в `serverNames`, ровно H2 и разные target/endpoint domains с учётом DNS case
equivalence. Активный instance на машине один; firewall должен быть включён
и использовать nftables. Соответствие
public/private key, UUID values, сертификат и доступность target не устанавливаются
этой source-only приёмкой. Итоговую exposure policy и возможное открытие того же порта
другими сервисами проверяет consumer.

## Реализованная архитектура

Отдельный Xray-core обслуживает прямой VLESS + REALITY + XHTTP на согласованном
TCP endpoint, обычно `443`. Hysteria2 остаётся отдельным сервисом.
Это инженерный выбор ради изоляции процессов и использования реализации
авторов REALITY/XHTTP; он не доказывает превосходство Xray по скорости или
доступности в РФ. Mihomo умеет обслуживать этот transport, его замена не
является обязательным исправлением протокольной ошибки.

Цена решения — ещё один точный package pin, service и набор проверок.
Стабильный module ID `vpn-mihomo-vless-xhttp` сохраняется; историческое имя
не вынуждает сохранять старую реализацию. Контракт consumer теперь явно задаёт
target и отдельные UUID secret name/short ID на устройство. Конкретные адреса,
exposure policy и привязки секретов
остаются у consumer; TCP sysctl/BBR/FQ принадлежат consumer, не этому модулю.

| Настройка | Рекомендация | Причина |
|---|---|---|
| Transport/security | `xhttp` + `reality`, прямой TCP | Сохраняет выбранный протокол без добавления CDN, HTTP/3 или второго transport |
| Server XHTTP mode | `auto` | Сервер принимает поддерживаемые режимы, не навязывая `packet-up` |
| VLESS flow | Не задавать Vision | Vision не комбинируется с XHTTP |
| VLESS encryption | Без дополнительного слоя; обычный `decryption: none` | REALITY уже обеспечивает защищенный transport; новая согласованная схема здесь не нужна |
| XHTTP path | Один явный путь с `/`, согласованный с экспортом | Это адресация transport, не замена аутентификации |
| Padding / buffering / XMUX | Штатные параметры выбранного тега | Не найдено универсальных измерений для ручных значений на этих трех сетях |
| REALITY target | Проверенный TLS 1.3 + H2 endpoint на `443` | Выбирается с позиции конкретного VPS; SAN сертификата должен покрывать используемые serverNames |
| REALITY logging / PROXY protocol | `show: false`, `xver: 0` | Не включать debug и PROXY protocol без соответствующей топологии |
| Credentials | Отдельный UUID на устройство; private key только runtime | Возможность индивидуального отзыва без хранения секретов в Nix store |
| finalmask / fragmentation / дополнительная ML-DSA подпись | Не включать в исходный профиль | Дополнительные зависимости и отпечатки без подтвержденной необходимости |
| Service / firewall | Отдельный непривилегированный процесс с необходимыми capabilities; ingress по bind address | Изоляция от Hysteria2 и соблюдение публичного контракта |

Серверный `auto` не является автоматическим поиском обхода блокировок.
В описании авторов он принимает `packet-up`, `stream-up`, `stream-one`;
клиентский `auto` при REALITY выбирает `stream-one`, если нет отдельного
`downloadSettings`. Это разные решения на разных концах.
Основание: [описание XHTTP авторами](https://github.com/XTLS/Xray-core/discussions/4113).
Ограничение Vision подтверждено [отчетом Xray](https://github.com/XTLS/Xray-core/issues/5576).

Конкретный target нельзя честно назначить один для всех будущих VPS по списку
«популярных SNI». Выбран один способ: прямой внешний HTTPS target, проверяемый
с каждого места развертывания по TLS/H2, сертификату, доступности и поведению
неавторизованного REALITY соединения. Близость сети — дополнительный критерий,
не гарантия. Собственный Caddy fallback или loopback target в эту рекомендацию
не добавляются. Требования: [официальный REALITY README](https://github.com/XTLS/REALITY).

## Выбранная версия и границы рекомендации

Xray добавлен как точная stock-зависимость проекта. На дату исследования
[v26.3.27](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27) обозначен
GitHub как Latest/stable; [v26.7.28](https://github.com/XTLS/Xray-core/releases/tag/v26.7.28)
от 28 июля — **Pre-release**. Для исходного профиля рекомендуем точный
**v26.3.27**, а не движущаяся `main`. Нужные этому профилю возможности уже
есть в стабильной версии; исследование не установило обязательного для него
исправления, ради которого следует принять риск июльского prerelease.
Это выбор по требованиям и известным ограничениям, не доказательство отсутствия
ошибок в мартовской версии. Перед будущим внедрением релизы и advisories
нужно проверить повторно: этот документ фиксирует состояние на 7 сентября.

У мартовского стабильного релиза уже есть исправление REALITY + `auto` и
оптимизации XHTTP, поэтому выбранная архитектура не требует июля только ради
этих возможностей. Изменения `main` после 28 июля, в том числе изменения
дефолтов XMUX, нельзя приписывать июльскому тегу.

В ветке 26.7 сообщалось о несовместимости REALITY с Mihomo 1.19.28/1.19.29:
[Xray #6477](https://github.com/XTLS/Xray-core/issues/6477),
[Mihomo #3042](https://github.com/MetaCubeX/mihomo/issues/3042).
Это граница клиентской миграции, а не доказательство DPI-блокировки.
Не обещаем, что все текущие Clash/Nikki клиенты продолжат работать после замены.

Точная схема стабильного тега проверена в
[transport_internet.go v26.3.27](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go):
`network: xhttp`, `security: reality`, `realitySettings.target/serverNames/privateKey/shortIds`,
`show: false`, `xver: 0` и `xhttpSettings.path/mode: auto` поддерживаются.
Для baseline `minClientVer` не задаем. В этом теге у него нет нижней границы
по умолчанию; в v26.7.28 незаданное поле уже означает `26.3.27`.
Это проверка source schema и pure Nix render, не исполненный parser/runtime test
нового service.

## Что известно о РФ

Просмотрены первичные сообщения, включая последующие уточнения:

- [net4people #490](https://github.com/net4people/bbs/issues/490): наблюдения
  ограничения потоков на части сетей, не универсальный порог для всей России.
- [net4people #546](https://github.com/net4people/bbs/issues/546), ноябрь 2025:
  XHTTP/mux помогали части пользователей, затем автор уточнил отсутствие
  универсального результата. Это историческое наблюдение, не сентябрьский тест.
- [net4people #650](https://github.com/net4people/bbs/issues/650), август 2026:
  разные результаты пользователей MTS; успех обычного REALITY не доказывает
  обход подтвержденного мобильного allowlist.

Дата обращения — 7 сентября 2026. Контролируемой проверки этого целевого
профиля на Дом.ру, Т-Мобайл и Yota нет. Нельзя обещать «необнаружимость» или
обход запрета доступа к IP VPS настройкой SNI/XHTTP. Не переносим сообщения
об отдельных timeout на все установки Mihomo.

## Выполненная и будущая приемка

Pure Nix assertions проверяют точный package, JSON render, `decryption: none`,
отсутствие Vision/fallback/manual XMUX, runtime placeholders, systemd sandbox,
отсутствие Mihomo service и destination-scoped ingress. Полный результат хранит
repository verification gate.

После отдельного разрешения на consumer adoption и deployment остаются:
live TLS 1.3/H2/SAN target check, соответствие public/private key, Xray parser,
listener, положительная аутентификация и отказ неверным UUID/short ID,
неавторизованное REALITY-поведение, длительные download/upload и UDP relay,
idle reconnect и restart/failure isolation от Hysteria2. Прикладную приемку
нужно повторить на Дом.ру, Т-Мобайл и Yota. Ни одна из этих runtime/network
проверок текущим source-аудитом не объявляется пройденной.
