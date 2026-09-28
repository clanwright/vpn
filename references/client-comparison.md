# Клиенты и полнота экспорта — 28 сентября 2026

Исследование первичных источников, без установки приложений и сетевых испытаний.
Точная матрица ниже относится к закреплённым ядрам репозитория, не автоматически
к встроенным ядрам GUI. Требуемые ОС пользователь пока не уточнил; рекомендации
для desktop и мобильных платформ разделены. Цены и стоимость перехода не учитываются.

## Результат аудита собственного экспорта

Пропущенных поддерживаемых собственных протоколов не обнаружено. Текущие
Mihomo 1.19.31 / sing-box 1.14.1 и сборочные возможности зафиксированы в
[package authority](../docs/package-authority.md); фактический экспорт — в
[renderer](../clanServices/vpn-client-profiles/client-profiles.nix).

| Наш provider | Mihomo: ядро / экспорт | sing-box: ядро / экспорт |
| --- | --- | --- |
| VLESS XHTTP REALITY, без Vision | Да / да; TCP и XUDP | Нет XHTTP / нет |
| AmneziaWG generation 3, параметры v3.1 | Да / да | Нет AWG / нет |
| Naive HTTPS/H2 через Caddy | Нет Naive / нет | Да / да; TCP |
| Mieru TCP | Да / да; TCP и UDP relay | Нет / нет |
| AnyTLS | Да / да; TCP и UoT | Да / да; TCP и UoT |
| TrustTunnel H2 | Да / да; TCP и UDP relay | Нет / нет |

Первичные exact-tag источники: [Mihomo parser](https://github.com/MetaCubeX/mihomo/blob/v1.19.31/adapter/parser.go),
[VLESS](https://github.com/MetaCubeX/mihomo/blob/v1.19.31/adapter/outbound/vless.go),
[AWG](https://github.com/MetaCubeX/mihomo/blob/v1.19.31/adapter/outbound/wireguard.go),
[sing-box registry](https://github.com/SagerNet/sing-box/blob/v1.14.1/include/registry.go),
[transport union](https://github.com/SagerNet/sing-box/blob/v1.14.1/option/v2ray_transport.go),
[WireGuard schema](https://github.com/SagerNet/sing-box/blob/v1.14.1/option/wireguard.go).
Naive UoT нельзя включать только по наличию клиентского флага: совместимость
нашего Caddy endpoint с ним не установлена.

Внешний Skala TCP/REALITY/Vision поддерживается обоими ядрами, но не является
нашим provider `vless-xhttp`. Для него нужен отдельный импорт, без подмены
транспорта. Внешний XHTTP/TLS поддерживается Mihomo; sing-box 1.14.1 не имеет
XHTTP. [sing-box VLESS](https://github.com/SagerNet/sing-box/blob/v1.14.1/protocol/vless/outbound.go),
[REALITY/uTLS](https://github.com/SagerNet/sing-box/blob/v1.14.1/common/tls/reality_client.go).

## Четыре варианта

| Вариант | Подтверждённая область | Ограничение для нашего набора |
| --- | --- | --- |
| Clash Verge Rev / Mihomo | Desktop, широкий набор Mihomo, YAML, группы и правила | Нет Naive в выбранном ядре; CVR не мобильный клиент |
| Официальные sing-box GUI | Apple/Android/Windows/Linux, свои JSON, Naive и AnyTLS | Нет XHTTP/AWG/Mieru/TrustTunnel в проверенном ядре |
| Happ | Xray JSON, TCP/REALITY/Vision; XHTTP подтверждён документацией/Android release | Поддержка Naive/AWG/Mieru/AnyTLS/TrustTunnel не установлена |
| INCY | Xray/VLESS, XHTTP/TLS; мобильный native AWG 3.1 | Desktop AWG явно не поддерживается; остальные четыре семейства не подтверждены |

«Не подтверждено» не означает доказанную невозможность. Ни Happ, ни INCY по
найденным источникам не покрывают весь наш набор. У Skala в сохранённом
[референсе](skala-vpn.json) два транспорта VLESS, а не шесть наших протоколов.

### Версии, платформы и контроль конфигурации

- **CVR:** stable [2.5.6, 26 сентября](https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.6).
  Его [build script](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.6/scripts/prebuild.mjs#L154)
  выбирает Mihomo latest при сборке; точное встроенное ядро не установлено.
  [Настройки приложения имеют приоритет над частью скриптов/конфига](https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.5).
  Поэтому проверять нужно эффективный профиль. Код приложения публичен.
- **sing-box:** [1.14.2, 24 сентября](https://github.com/SagerNet/sing-box/releases/tag/v1.14.2)
  опубликован с GUI assets, но repo pin остаётся 1.14.1. Есть официальные
  [Windows/Linux, Android и Apple клиенты](https://sing-box.sagernet.org/clients/).
  [Apple/Android build](https://github.com/SagerNet/sing-box/blob/v1.14.2/cmd/internal/build_libbox/main.go)
  включает Naive; legacy Android 5 — исключение. [Документация Apple](https://sing-box.sagernet.org/clients/apple/)
  сообщает проблемы обновления через App Store и ограниченный TestFlight;
  свежесть обычной iOS-установки не подтверждена наличием GitHub-релиза.
  [Собственный JSON, remote updates, Selector/URLTest dashboard](https://sing-box.sagernet.org/clients/general/).
- **Happ:** stable desktop [4.3.0, 15 сентября](https://github.com/Happ-proxy/happ-desktop/releases/tag/4.3.0),
  Android [4.4.1, 11 сентября](https://github.com/Happ-proxy/happ-android/releases/tag/4.4.1),
  [Apple listing](https://apps.apple.com/us/app/happ-proxy-utility/id6504287215) — 5.9.0.
  Точные текущие встроенные ядра не установлены. [Xray JSON передаётся 1:1](https://github.com/HappDev/happ_su/blob/main/dev-docs/examples-of-links-and-parameters.md);
  обычные UI-настройки маршрутизации тогда не применяются. [Desktop custom-tunnel-config](https://github.com/HappDev/happ_su/blob/main/dev-docs/app-management.md)
  для sing-box не доказывает поддержку всех современных outbound-протоколов.
  [Приложение проприетарное, ядра отдельно лицензированы](https://github.com/HappDev/happ_su/blob/main/third-party-libraries.md).
- **INCY:** [desktop 3.8.8, 22 сентября](https://github.com/INCY-DEV/incy-platforms/releases/tag/desktop-v3.8.8),
  [iOS 2.6.2, 21 сентября](https://apps.apple.com/ru/app/incy/id6756943388);
  iOS 2.6.1 явно объявлял Xray 26.9.9. Android release manifest указывает 3.3.6,
  но [manifest](https://github.com/INCY-DEV/incy-platforms/blob/main/RELEASE.json) отстаёт по другим платформам.
  Desktop core и эквивалентность macOS App Store/DMG не установлены.
  [Xray JSON импортируется с runtime-патчами](https://docs.incy.cc/en/full-xray-config/),
  включая inbounds, DNS-direct rules, stats и FakeDNS pool. [AWG](https://docs.incy.cc/en/subscription-format/#5-amneziawg-wireguard-conf-in-the-body)
  работает нативно на мобильных платформах; desktop `.conf` использует обычный
  WireGuard и не применяет AWG-параметры. [VLESS transport/flow fields](https://docs.incy.cc/en/share-links/).
  [Публичный репозиторий](https://github.com/INCY-DEV/incy-platforms) распространяет
  релизы/метаданные, а не полный исходный код приложения.

Happ и INCY документируют свои direct/proxy/DNS политики:
[Happ](https://github.com/HappDev/happ_su/blob/main/dev-docs/routing.md),
[INCY](https://docs.incy.cc/en/routing/). Перенос нашей политики представим,
но эквивалентность порядка правил и независимого TCP/UDP выбора не проверена.
Импорт нескольких подписок не доказывает единую Auto-группу между ними.

## Инженерный выбор, не рейтинг измеренной надёжности

Для desktop с нашим приоритетом широты протоколов и управляемых профилей:
**1 — CVR/Mihomo, 2 — sing-box, 3 — Happ, 4 — INCY.** Последние два ниже из-за
неподтверждённого покрытия нашего набора и меньшей проверяемости приложения;
Happ выше INCY здесь за документированный Xray JSON passthrough. Это не доказательство
лучшей скорости или устойчивости. Для мобильного VLESS+AWG INCY может быть выше Happ;
CVR как приложение вообще не участвует в мобильном выборе.

С нуля при сохранении всех шести протоколов текущая пара оправдана. Если важнее
одно семейство приложений и допустим меньший набор, sing-box с Naive+AnyTLS —
разумная основа; доставку актуального iOS-клиента нужно решить отдельно.
Если необходим XHTTP и максимальный desktop-охват, основа — Mihomo; Naive потребует
другого ядра. Отказ от Naive позволит рассматривать один Mihomo-клиент на desktop.

Есть ещё отдельный вопрос «одно окно, несколько ядер»: [v2rayN](https://github.com/2dust/v2rayN)
имеет [интеграцию Xray/Mihomo/sing-box](https://github.com/2dust/v2rayN/blob/master/v2rayN/ServiceLib/Manager/CoreInfoManager.cs).
Полный наш набор и единый Auto между ядрами не проверены; это кандидат исследования,
а не доказанная замена. Качество обхода в российских сетях и стабильность приложений
этим исследованием не измерялись.
