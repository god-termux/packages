# god-cosmic

Сборки компонентов рабочего стола [COSMIC](https://github.com/pop-os/cosmic-epoch) (Rust, Wayland) под **aarch64 glibc** для телефона с god-termux (форк Termux). Собирается в GitHub Actions, а не на телефоне: сборка `-Zbuild-std` под glibc прямо в Termux не получилась (тысячи ошибок `core`/`Ok` not found).

## Как это устроено

- `components/NAME.env` описывает компонент: репозиторий, закреплённый коммит, аргументы `cargo`, пакеты Debian для сборки.
- `scripts/build-component.sh NAME` кросс-компилирует в контейнере **Debian 13 (trixie)** на x86-раннере: библиотеки берутся из multiarch `arm64`, поэтому sonames и версии совпадают с деревом Debian на телефоне (`dapt`).
- В артефакте: бинарник, `NEEDED.txt` (динамические зависимости), `runtime-packages.txt` (что поставить через `dapt install`), `glibc-max.txt` (максимальная версия символов glibc, на телефоне 2.44) и `SOURCE.txt` (коммит исходников).

## Этапы

| Этап | Компонент | Статус |
|---|---|---|
| 1 | `cosmic-comp` (композитор, бэкенд `winit`) | сборка настроена, на телефоне не проверялся |
| 2 | панель, лаунчер, обои, настройки (`cosmic-panel`, `cosmic-launcher`, `cosmic-bg`, `cosmic-settings-daemon`) | не начат |
| 3 | остальное (`cosmic-applets`, `cosmic-settings`, `cosmic-term`, …) | не начат |

## Установка на телефон (пакет `god-cosmic`)

Подписанный apt-репозиторий на GitHub Pages для дерева Debian god-termux (`dapt`):

```sh
curl -fsSL https://crafterminecrafter.github.io/god-cosmic/install.sh | bash   # подключает источник и ключ
dapt update && dapt install god-cosmic
god-cosmic start                       # откроет окно Wayland и запустит COSMIC
god-cosmic run КОМАНДА                  # Wayland-программа внутри COSMIC
god-cosmic status | stop
```

Пакет содержит `cosmic-comp` и лаунчер `god-cosmic`; `postinst` кладёт команду в `$PREFIX/bin`. Зависимости (из Debian 13): `libdisplay-info2`, `libgbm1`, `libinput10`, `libpixman-1-0`, `libseat1`, `libudev1`, `libxkbcommon0`, `xkb-data`, `libegl1`, `libgles2`, `libwayland-client0`, `libwayland-server0`.
Ключ репозитория: `keyrings/god-cosmic-archive-keyring.asc`.

На Android нет DRM/KMS, поэтому `cosmic-comp` работает вложенно (бэкенд `winit`) в Wayland-композитор god-termux; параметры окна (разрешение, частота кадров, режим касаний, клавиатура) задаются в приложении, в «Настройках Wayland».

Проверено 2026-11-24 на телефоне: установка из репозитория, запуск, клиент (`es2gears`) внутри, остановка. Замер вложенности на `es2gears` 300×300: медиана 31 FPS против 37 FPS напрямую на композиторе god-termux (разброс большой, цифры ориентировочные).
Известные ошибки в логе (не фатальные): нет Xwayland, нет D-Bus сессии, `eglQuerySurface BAD_SURFACE`.
Пока нет: панель, обои, лаунчер приложений и остальные компоненты COSMIC (этап 2), родные касания (`wlcomp` не отдаёт `wl_touch`).
Шим god-termux до исправления `eaccess()` (коммит `91eccdbe` в god-termux) не находил `/usr/share/X11/xkb`, поэтому лаунчер задаёт `XKB_CONFIG_ROOT`.

## Сборка вручную

`Actions` → **Build component** → *Run workflow*, поле `component` (по умолчанию `cosmic-comp`). Артефакт появится в запуске.

## Лицензии

Исходники компонентов COSMIC лежат в своих репозиториях под их лицензиями (в основном GPL-3.0). Здесь только описания сборки и скрипты.
