#!/usr/bin/env bash
# Метапакет god-cosmic-desktop: тянет все компоненты COSMIC из components/*.env.
#   scripts/make-meta.sh   добавляет dist/deb/god-cosmic-desktop_<дата>_all.deb
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); OUT=$ROOT/dist/deb
# состав берём из components/*.env (PKG), а не из dist/deb: компонент, упавший в этой сборке, всё равно остаётся в зависимостях
DEPS=$(for f in "$ROOT"/components/*.env; do ( unset PKG; source "$f"; echo "${PKG:-}" ); done | grep . | sort -u | paste -sd, - | sed 's/,/, /g')
[ -n "$DEPS" ] || { echo "нет компонентов" >&2; exit 1; }
# звук (PipeWire + туннель в PulseAudio Android), буфер обмена и шина — пакеты Debian, нужные лаунчеру god-cosmic
DEPS="$DEPS, pipewire, pipewire-bin, pipewire-pulse, wireplumber, wl-clipboard, dbus"
mkdir -p "$OUT"
VERSION=1.0.0+$(date -u +%Y%m%d)-1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir -p "$T/DEBIAN" "$T/usr/share/doc/god-cosmic-desktop"
cat > "$T/DEBIAN/control" <<EOF2
Package: god-cosmic-desktop
Version: $VERSION
Architecture: all
Maintainer: CrafterMinecrafter <CrafterMinecrafter@users.noreply.github.com>
Depends: $DEPS
Section: metapackages
Priority: optional
Homepage: https://github.com/god-termux/packages
Description: COSMIC desktop for god-termux (all components)
 Compositor, panel, applets, wallpaper, launcher, workspaces overview, settings daemon and OSD.
 Start with: god-cosmic start --desktop
EOF2
echo "Meta-package without files. Components keep their own licenses (see each package)." > "$T/usr/share/doc/god-cosmic-desktop/README"
find "$T" -type d -exec chmod 755 {} +; find "$T" -type f -exec chmod 644 {} +
dpkg-deb --root-owner-group -Zxz --build "$T" "$OUT/god-cosmic-desktop_${VERSION}_all.deb"
