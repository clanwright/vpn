# AmneziaWG 3.1: серверный аудит на 8 сентября 2026

Независимое source review и полный репозиторный gate прошли, включая
композицию двух NAT instances и capabilities низкого/высокого порта;
доказательства — в [основном аудите](audit-2026-09.md).

## Область и решение

Пользователь выбрал переход на AWG3 и серверную архитектуру без ограничений
старых клиентов. Код серверного модуля, typed contract и клиентский renderer
обновлены; смена секретов и deployment не выполнялись.

Проверены код проекта, точные upstream tags, актуальные документы Amnezia,
практические рекомендации оператора и исходный отчет о несовместимости реализаций.
Доступность конкретных серверов из Дом.ру/Т-Мобайл/Yota не измерялась.

## Реализованное состояние проекта

- Package authority использует stock `amneziawg-go` 3.1.20260828 и
  `amneziawg-tools` 3.1.20260812; userspace backend задан явно.
- Серверный профиль фиксирует S/H/padding/cookies и MTU1280. Jc/I1–I5,
  пользовательские timer ranges и server PersistentKeepalive отсутствуют.
- Отдельный `headerProtectionKeySecretName` объявляет runtime SOPS secret.
  Supervised `amneziawg-go -f` создает userspace TUN/UAPI, затем bounded
  ExecStartPost передает private key и HeaderProtectionKey в `awg set` как file
  paths до link-up. Значения не попадают в Nix store, argv, unit text или
  публичный export; вывод parser подавлен. Ошибка останавливает daemon, а
  ExecStopPost удаляет interface и socket.
- Каждый active userspace instance имеет уникальные interface name и UDP port
  на машине. Go daemon слушает wildcard UDP; `listenIPv4` задает
  destination-scoped nftables ingress, а не bind address процесса.
- Service capability set ограничен `CAP_NET_ADMIN`; для выбранного порта443
  добавляется `CAP_NET_BIND_SERVICE`. High-port instance его не получает.
- Active NAT instances агрегируют одно shared требование
  `net.ipv4.ip_forward = 1`; NAT-disabled и retained instances его не задают.
- Валидация до рендера проверяет адреса, allowedIPs, canonical public keys,
  безопасные secret/peer names и дубликаты. Каждый peer получает ровно один
  уникальный `/32` внутри interface/client subnet, отличный от server address.
  Ingress остается ограничен destination IPv4; машинные маршруты и exposure
  policy принадлежат consumer.

## Выбранный целевой профиль

Ниже реализованный инженерный профиль. Это один профиль, не набор альтернатив.
Старые client cores не являются причиной его упрощать.

| Параметр | Выбор | Обоснование |
|---|---|---|
| Реализация | amneziawg-go 3.1.20260828, tools 3.1.20260812 | Точные официальные tags; userspace без случайной подмены kernel backend |
| Generation | Явный AWG3.1 контракт | Не считать установленный бинарник подтверждением активации |
| HeaderProtectionKey | Отдельный случайный 32-байтный runtime-secret на интерфейс | Совместно используется peers этого интерфейса; не заменяет их WireGuard keys |
| S1/S2/S3/S4 | `12/12/12/12` | Допустимый минимум nonce; равные значения рекомендуются с RandomTrailers |
| H1/H2/H3/H4 | `1/2/3/4` | Рекомендованные upstream значения при Header Protection |
| ContentPaddingAddition | `2-10` | Небольшая рандомизация с ограниченным дополнительным объемом |
| RandomTrailers | `on` | Рандомизация handshake/cookie; transport в выбранном профиле обрабатывает ContentPaddingAddition |
| DisableCookies | `off` | Сохраняем защиту handshake под нагрузкой |
| Jc, I1–I5 на сервере | Выключены/не заданы | Предварительные junk/signature-пакеты не обязаны копироваться с клиента на сервер |
| Rekey/Reject/Keepalive timers | Штатные, без пользовательских диапазонов | Для произвольных диапазонов не найдено подтвержденного преимущества, оправдывающего усложнение |
| Server PersistentKeepalive | Выключен | Не создавать постоянный трафик ко всем peers без необходимости |
| MTU интерфейса | `1280` как исходный deployment default | Консервативный запас для обфускации; не объявляется найденным PMTU или максимумом скорости |
| Endpoint | Один согласованный UDP endpoint | Не добавлять автоматическую смену портов/адресов; не занимать endpoint Hysteria2 |

`ContentPaddingAddition=2-10` и MTU1280 — выбранный компромисс, не универсальные
upstream defaults. В точном Go-теге эти механизмы не складываются для transport:
при заданном ContentPaddingAddition RandomTrailers дополняет handshake/cookie,
но не добавляет второй trailer к transport. Handshake UDP payload остается
меньше500 байт. При MTU1280 и S4=12 transport payload ограничен1324 байтами
в обычном состоянии выбранного профиля за счет UDP-window cap; это примерно
1352 байта с outer IPv4 или1372 с outer IPv6 без дополнительных заголовков.
Расчет не заменяет проверку фактического пути и состояния после reconfiguration;
внутренний MTU1280 сам по себе не гарантирует отсутствие внешней фрагментации.
Самые большие transport-пакеты могут не получить дополнительного padding из-за
лимита окна. RandomTrailers и H/S/HeaderProtectionKey должны быть согласованы
с принимающими peers; диапазон ContentPaddingAddition может отличаться,
но целевой экспорт предусматривает2–10 в обе стороны.

Секрет HeaderProtectionKey создается только на этапе отдельно разрешенной
миграции, хранится вне публичного конфига и передается peers защищенным путем.
Смена ключа затрагивает весь интерфейс. В audit нет ключей или live profiles.
В нативном конфиге AWG3 определяется полями и механизмами, а не произвольной
строкой `Version=3`: явное поколение нужно контракту проекта, синтаксис backend
должен соответствовать выбранным tools.

## Что дали интернет-источники

1. **Официальные документы Amnezia.** При Header Protection рекомендуют H1–H4
   1–4, S1–S4 не менее12; с RandomTrailers — одинаковые S. Старый рецепт случайных
   H-диапазонов не нужно переносить механически. Маркетинговые заявления о
   «невидимости» не принимаются как результат проверки на сетях пользователя.
2. **Точные исходники Go.** Переход 20260814 → 20260828 исправляет учет UDP-окна
   для padding и поведение DisableCookies. Поэтому сверяем код, а не только
   описание параметра: выключение cookies в этом теге обходит ветку under-load,
   а не просто убирает один ответ.
3. **Практические рекомендации Amnezia Hosting.** Советуют MTU1280 и небольшой
   padding при падении скорости. Это рекомендация оператора, не официальный
   норматив и не опубликованный контролируемый тест трех нужных сетей.
4. **Первичный issue kernel module #222.** Описывает отказ handshake с header
   protection при рабочем Go-клиенте на том же пути. Это аргумент проверять
   точную реализацию и формат, а не приписывать каждый отказ блокировке.
   Старый kernel client не ограничивает выбранный серверный профиль.

В найденных источниках нет воспроизводимого сентябрьского сравнения параметров
AWG3.1 сразу на Дом.ру, Т-Мобайл и Yota. Поэтому профиль выбран по механике
протокола, актуальным исправлениям и эксплуатационным компромиссам; он не
обещает обход запрета всего UDP, блокировки адреса или мобильных allowlists.

## Проверенное и пределы source-only приёмки

Pure Nix contract проверяет package family/authority, supervised foreground
userspace command, отсутствие kernel backend, точные active options, загрузку
ключей из SOPS files до link-up, failure cleanup, отсутствие секрета в
unit/export и destination-scoped ingress. Negative fixtures принудительно
проверяют неверные адреса, ключи, имена, дубликаты и нарушение peer `/32`
isolation/subnet contract.

В рамках repository verification намеренно не запускались userspace process,
сервисы или application CLI. Поэтому source-only результат не заявляет
фактический handshake, TCP/UDP transfer, пакетные размеры/фрагментацию,
sustained load, rekey/idle, cookie-защиту под нагрузкой или поведение с неверным
содержимым runtime secret. Возможные наблюдения на уже deployed машине являются
отдельной consumer-owned operation, а не отложенным release gate или
обязательством этого аудита. A/B с AWG2 не является условием выбранной
архитектуры.

## Источники и код

- [Официальная документация Amnezia](https://docs.amnezia.org/ru/documentation/amnezia-wg/).
- [Go tag 3.1.20260828](https://github.com/amnezia-vpn/amneziawg-go/tree/v3.1.20260828).
- [Изменения Go между закрепленным и целевым тегами](https://github.com/amnezia-vpn/amneziawg-go/compare/v3.1.20260814...v3.1.20260828).
- [UAPI: валидация](https://github.com/amnezia-vpn/amneziawg-go/blob/v3.1.20260828/device/uapi.go).
- [Отправка и padding](https://github.com/amnezia-vpn/amneziawg-go/blob/v3.1.20260828/device/send.go).
- [Прием и cookies](https://github.com/amnezia-vpn/amneziawg-go/blob/v3.1.20260828/device/receive.go).
- [Tools parser](https://github.com/amnezia-vpn/amneziawg-tools/blob/v3.1.20260812/src/config.c).
- [Рекомендации оператора по 3.1](https://wiki.amnezia.host/en/awg-3-1-upgrade.html).
- [Первичный отчет о несовместимости #222](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/issues/222).
- [Модуль проекта](../clanServices/amneziawg/default.nix), [валидация](../clanServices/amneziawg/validation.nix).
