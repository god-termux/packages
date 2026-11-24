#!/usr/bin/env bash
# Собирает Debian-пакет (arm64) из результата build-component.sh.
#   scripts/make-deb.sh [NAME]     NAME = components/NAME.env (по умолчанию cosmic-comp); читает dist/NAME/, пишет dist/deb/<PKG>_<версия>_arm64.deb
# Имя пакета PKG и описание DESC берутся из env компонента; cosmic-comp (PKG=god-cosmic) дополнительно получает лаунчер из packaging/god-cosmic.
# Версия: <версия cosmic-comp>+git<дата коммита>.<короткий хэш>-<PKG_REVISION>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-cosmic-comp}
# shellcheck disable=SC1090
source "$ROOT/components/$NAME.env"
SRCDIR=$ROOT/dist/$NAME
OUT=$ROOT/dist/deb
PKG=${PKG:-god-${NAME}}
DESC=${DESC:-$NAME for god-termux}
REV=${PKG_REVISION:-$(cat "$ROOT/REVISION" 2>/dev/null || echo 1)}   # повышайте REVISION при изменении упаковки без смены версии исходников
[ -d "$SRCDIR/bin" ] || { echo "нет $SRCDIR/bin: сначала scripts/build-component.sh $NAME" >&2; exit 1; }

read -r REPO SHA DATE < "$SRCDIR/SOURCE.txt"
UPSTREAM_VER=${UPSTREAM_VER:-1.0.0}
VERSION="$UPSTREAM_VER+git${DATE//-/}.${SHA:0:7}-$REV"

ROOTFS=$(mktemp -d); trap 'rm -rf "$ROOTFS"' EXIT
[ -d "$ROOT/packaging/$PKG" ] && cp -a "$ROOT/packaging/$PKG/." "$ROOTFS/"
install -d "$ROOTFS/usr/bin" "$ROOTFS/usr/share/doc/$PKG" "$ROOTFS/DEBIAN"
# файлы, установленные `just install` (usr/share/..., ссылки на бинарники); затем сами бинарники
[ -d "$SRCDIR/root" ] && cp -a "$SRCDIR/root/." "$ROOTFS/"
for b in "$SRCDIR"/bin/*; do install -m755 "$b" "$ROOTFS/usr/bin/$(basename "$b")"; done

# зависимости: библиотеки из NEEDED (кроме libc/libm/libgcc_s: их закрывают пакеты-заглушки Termux glibc) + xkb-data и EGL/Wayland на время работы
DEPS=$(grep -vE '^(libc6|libgcc-s1|libm6)$' "$SRCDIR/runtime-packages.txt" | sort -u | tr '\n' ',' | sed 's/,$//')
EXTRA="xkb-data, libegl1, libgles2, libwayland-client0, libwayland-server0${DEPENDS_EXTRA:+, $DEPENDS_EXTRA}"
DEPENDS=$(printf '%s, %s' "$DEPS" "$EXTRA" | sed 's/^, //' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u | paste -sd, - | sed 's/,/, /g')

SIZE=$(du -sk "$ROOTFS" | cut -f1)
if [ -f "$ROOTFS/DEBIAN/control.in" ]; then
  sed -e "s|@VERSION@|$VERSION|" -e "s|@DEPENDS@|$DEPENDS|" -e "s|@SIZE@|$SIZE|" -e "s|@COMMIT@|$SHA|" \
      "$ROOTFS/DEBIAN/control.in" > "$ROOTFS/DEBIAN/control"
  rm -f "$ROOTFS/DEBIAN/control.in"
else
  cat > "$ROOTFS/DEBIAN/control" <<EOF2
Package: $PKG
Version: $VERSION
Architecture: arm64
Maintainer: CrafterMinecrafter <CrafterMinecrafter@users.noreply.github.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: x11
Priority: optional
Homepage: https://github.com/god-termux/packages
Description: $DESC
 ${NAME} (${REPO##*/}, commit ${SHA:0:12}) built for aarch64 glibc for the god-termux Debian tree (dapt).
 Part of COSMIC for god-termux: see the god-cosmic package.
EOF2
fi

cat > "$ROOTFS/usr/share/doc/$PKG/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${REPO##*/}
Source: $REPO

Files: usr/*
Copyright: System76 and the COSMIC contributors
License: ${LICENSE:-GPL-3.0-only}
 Исходный код: $REPO, коммит $SHA.
 Сборка: https://github.com/god-termux/packages (components/$NAME.env, scripts/build-component.sh).
 Полный текст GPL-3.0: /usr/share/common-licenses/GPL-3 или https://www.gnu.org/licenses/gpl-3.0.txt

Files: DEBIAN/*
Copyright: CrafterMinecrafter
License: GPL-3.0-or-later
 Лаунчер и скрипты пакета распространяются на тех же условиях, что и cosmic-comp.
EOF
cp "$SRCDIR/SOURCE.txt" "$ROOTFS/usr/share/doc/$PKG/SOURCE"
cp "$SRCDIR/NEEDED.txt" "$ROOTFS/usr/share/doc/$PKG/NEEDED"

# права не зависят от umask/файловой системы, где лежат исходники пакета
find "$ROOTFS" -type d -exec chmod 755 {} +
find "$ROOTFS" -type f -exec chmod 644 {} +
for x in "$ROOTFS"/usr/bin/* "$ROOTFS"/DEBIAN/postinst "$ROOTFS"/DEBIAN/prerm; do [ -e "$x" ] && [ ! -L "$x" ] && chmod 755 "$x"; done

mkdir -p "$OUT"
DEB=$OUT/${PKG}_${VERSION}_arm64.deb
dpkg-deb --root-owner-group -Zxz --build "$ROOTFS" "$DEB"
echo "собрано: $DEB ($(du -h "$DEB" | cut -f1))"
dpkg-deb -I "$DEB" | sed -n '1,/^ Description/p' | head -14
