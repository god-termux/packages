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

## Запуск на телефоне

На Android нет DRM/KMS, поэтому `cosmic-comp` запускается вложенно в Wayland-композитор god-termux, как `labwc` в `xfce-wl`:

```sh
gh run download -R CrafterMinecrafter/god-cosmic -n cosmic-comp-aarch64   # или из вкладки Actions
chmod +x cosmic-comp
scripts/run-on-phone.sh ./cosmic-comp
```

Библиотеки из `NEEDED.txt` уже есть в стандартном дереве Debian (`dapt`): `libdisplay-info2`, `libgbm1`, `libinput10`, `libpixman-1-0`, `libseat1`, `libudev1`, `libxkbcommon0`, `xkb-data`.

Проверено 2026-11-24 на телефоне: композитор запускается, подключается как клиент `winit` к Wayland-композитору god-termux, поднимает EGL и работает без падений.
Известные ошибки в логе (не фатальные): нет Xwayland, нет D-Bus сессии, `eglQuerySurface BAD_SURFACE`.
Открытые вопросы: что именно рисуется на экране, ввод, остальные компоненты рабочего стола.
Шим god-termux до исправления `eaccess()` (коммит `91eccdbe` в god-termux) не находил `/usr/share/X11/xkb`, поэтому `run-on-phone.sh` задаёт `XKB_CONFIG_ROOT`.

## Сборка вручную

`Actions` → **Build component** → *Run workflow*, поле `component` (по умолчанию `cosmic-comp`). Артефакт появится в запуске.

## Лицензии

Исходники компонентов COSMIC лежат в своих репозиториях под их лицензиями (в основном GPL-3.0). Здесь только описания сборки и скрипты.
