#!/usr/bin/env bash
# Собирает Debian-пакет god-cosmic (arm64) из результата build-component.sh.
#   scripts/make-deb.sh            читает dist/cosmic-comp/, пишет dist/deb/god-cosmic_<версия>_arm64.deb
# Версия: <версия cosmic-comp>+git<дата коммита>.<короткий хэш>-<PKG_REVISION>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRCDIR=$ROOT/dist/cosmic-comp
OUT=$ROOT/dist/deb
PKG=god-cosmic
REV=${PKG_REVISION:-1}
[ -x "$SRCDIR/cosmic-comp" ] || { echo "нет $SRCDIR/cosmic-comp: сначала scripts/build-component.sh cosmic-comp" >&2; exit 1; }

read -r REPO SHA DATE < "$SRCDIR/SOURCE.txt"
UPSTREAM_VER=${UPSTREAM_VER:-1.0.0}
VERSION="$UPSTREAM_VER+git${DATE//-/}.${SHA:0:7}-$REV"

ROOTFS=$(mktemp -d); trap 'rm -rf "$ROOTFS"' EXIT
cp -a "$ROOT/packaging/$PKG/." "$ROOTFS/"
install -d "$ROOTFS/usr/bin" "$ROOTFS/usr/share/doc/$PKG"
install -m755 "$SRCDIR/cosmic-comp" "$ROOTFS/usr/bin/cosmic-comp"

# зависимости: библиотеки из NEEDED (кроме libc/libm/libgcc_s: их закрывают пакеты-заглушки Termux glibc) + xkb-data и EGL/Wayland на время работы
DEPS=$(grep -vE '^(libc6|libgcc-s1|libm6)$' "$SRCDIR/runtime-packages.txt" | sort -u | tr '\n' ',' | sed 's/,$//')
EXTRA="xkb-data, libegl1, libgles2, libwayland-client0, libwayland-server0"
DEPENDS=$(printf '%s, %s' "$DEPS" "$EXTRA" | sed 's/^, //' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u | paste -sd, - | sed 's/,/, /g')

SIZE=$(du -sk "$ROOTFS" | cut -f1)
sed -e "s|@VERSION@|$VERSION|" -e "s|@DEPENDS@|$DEPENDS|" -e "s|@SIZE@|$SIZE|" -e "s|@COMMIT@|$SHA|" \
    "$ROOTFS/DEBIAN/control.in" > "$ROOTFS/DEBIAN/control"
rm -f "$ROOTFS/DEBIAN/control.in"

cat > "$ROOTFS/usr/share/doc/$PKG/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: cosmic-comp
Source: $REPO

Files: usr/bin/cosmic-comp
Copyright: System76 and the COSMIC contributors
License: GPL-3.0-only
 Исходный код: $REPO, коммит $SHA.
 Сборка: https://github.com/CrafterMinecrafter/god-cosmic (components/cosmic-comp.env, scripts/build-component.sh).
 Полный текст GPL-3.0: /usr/share/common-licenses/GPL-3 или https://www.gnu.org/licenses/gpl-3.0.txt

Files: usr/bin/god-cosmic DEBIAN/*
Copyright: CrafterMinecrafter
License: GPL-3.0-or-later
 Лаунчер и скрипты пакета распространяются на тех же условиях, что и cosmic-comp.
EOF
cp "$SRCDIR/SOURCE.txt" "$ROOTFS/usr/share/doc/$PKG/SOURCE"
cp "$SRCDIR/NEEDED.txt" "$ROOTFS/usr/share/doc/$PKG/NEEDED"

# права не зависят от umask/файловой системы, где лежат исходники пакета
find "$ROOTFS" -type d -exec chmod 755 {} +
find "$ROOTFS" -type f -exec chmod 644 {} +
chmod 755 "$ROOTFS/usr/bin/god-cosmic" "$ROOTFS/usr/bin/cosmic-comp" "$ROOTFS/DEBIAN/postinst" "$ROOTFS/DEBIAN/prerm"

mkdir -p "$OUT"
DEB=$OUT/${PKG}_${VERSION}_arm64.deb
dpkg-deb --root-owner-group -Zxz --build "$ROOTFS" "$DEB"
echo "собрано: $DEB ($(du -h "$DEB" | cut -f1))"
dpkg-deb -I "$DEB" | sed -n '1,/^ Description/p' | head -14
