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

## Запуск на телефоне (план, не проверено)

На Android нет DRM/KMS, поэтому `cosmic-comp` запускается вложенно в Wayland-композитор god-termux, как `labwc` в `xfce-wl`:

```sh
dapt install $(cat runtime-packages.txt)   # библиотеки из Debian
wlrun env COSMIC_BACKEND=winit ./cosmic-comp
```

Бэкенд выбирает `COSMIC_BACKEND` (`kms`, `x11`, `winit`); без переменной при наличии `WAYLAND_DISPLAY` он сначала пробует `x11`.
Открытый вопрос: будет ли внутри композитора god-termux работать EGL/GL для `winit` или потребуется программный рендер.

## Сборка вручную

`Actions` → **Build component** → *Run workflow*, поле `component` (по умолчанию `cosmic-comp`). Артефакт появится в запуске.

## Лицензии

Исходники компонентов COSMIC лежат в своих репозиториях под их лицензиями (в основном GPL-3.0). Здесь только описания сборки и скрипты.
