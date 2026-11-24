#!/data/data/com.termux/files/usr/bin/bash
# Запуск cosmic-comp на телефоне с god-termux: вложенно в Wayland-композитор (wlrun), бэкенд winit.
#   run-on-phone.sh ./cosmic-comp
# FHS_DEBIAN=1       пути /usr, /etc берутся из Debian-дерева (dapt)
# XKB_CONFIG_ROOT    запасной обход, пока в шиме нет перехвата eaccess() (libxkbcommon не находил /usr/share/X11/xkb)
P=${PREFIX:-/data/data/com.termux/files/usr}; D=$P/debian
BIN=${1:-./cosmic-comp}
exec env FHS_DEBIAN=1 XKB_CONFIG_ROOT=$D/usr/share/X11/xkb COSMIC_BACKEND=winit RUST_LOG=${RUST_LOG:-warn} \
  XDG_RUNTIME_DIR=$P/tmp XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config} XDG_DATA_DIRS=$D/usr/share \
  wlrun "$BIN"
