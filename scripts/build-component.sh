#!/usr/bin/env bash
# Сборка одного компонента COSMIC для aarch64-unknown-linux-gnu (glibc) в контейнере debian:trixie на x86-раннере.
#   scripts/build-component.sh NAME     NAME = components/NAME.env
# Библиотеки берутся из Debian 13 arm64 (multiarch), как в дереве dapt на телефоне: те же sonames и версии.
# Результат: dist/NAME/ (bin/*, root/ с установленными файлами, NEEDED.txt, runtime-packages.txt, glibc-max.txt, SOURCE.txt).
# Переменные components/NAME.env: REPO, REF, CARGO_ARGS, BINS (список исполняемых файлов) или BIN_GLOB, HOST_DEPS, ARM64_DEPS,
#   BUILD_ENV (переменные окружения сборки, "A=1 B=2"), INSTALL_FILES="src:dst ..." (файлы из исходников в пакет), JUST_INSTALL=1 (после сборки выполнить `just install` в каталог dist/NAME/root).
set -euo pipefail
NAME=${1:?usage: build-component.sh NAME}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
source "$ROOT/components/$NAME.env"
TARGET=aarch64-unknown-linux-gnu
WORK=${WORK:-$ROOT/work}; DIST=$ROOT/dist/$NAME
BINS=${BINS:-${BIN:-}}; JUST_INSTALL=${JUST_INSTALL:-0}; BUILD_ENV=${BUILD_ENV:-}
rm -rf "$DIST"; mkdir -p "$WORK" "$DIST/bin" "$DIST/root"
export DEBIAN_FRONTEND=noninteractive

echo "::group::apt"
dpkg --add-architecture arm64
apt-get update
ARM=""; for p in $ARM64_DEPS; do ARM="$ARM $p:arm64"; done
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends ca-certificates curl git build-essential pkg-config cmake \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu $HOST_DEPS $ARM
# just из репозитория Debian слишком старый для justfile COSMIC (модули `mod`, `a::b`): берём релиз
if [ "$JUST_INSTALL" = 1 ]; then
  JUST_VER=1.40.0   # скрипт just.systems ходит в API GitHub и упирается в лимит (403): берём архив по прямой ссылке
  curl -fsSL --retry 5 --retry-delay 3 "https://github.com/casey/just/releases/download/$JUST_VER/just-$JUST_VER-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin just
  just --version
fi
echo "::endgroup::"

echo "::group::source $REPO @ $REF"
SRC=$WORK/$NAME-src
if [ ! -d "$SRC/.git" ]; then git init -q "$SRC"; git -C "$SRC" remote add origin "$REPO"; fi
git -C "$SRC" fetch -q --depth 1 origin "$REF"
git -C "$SRC" checkout -q FETCH_HEAD
echo "$REPO $(git -C "$SRC" rev-parse HEAD) $(git -C "$SRC" log -1 --format=%cs)" > "$DIST/SOURCE.txt"
echo "::endgroup::"

if [ "${DATA_ONLY:-0}" = 1 ]; then   # пакет без кода (иконки): только `just install`
  echo "::group::just install (data only)"
  (cd "$SRC" && just --set rootdir "$DIST/root" install)
  echo "::endgroup::"
  : > "$DIST/NEEDED.txt"; : > "$DIST/runtime-packages.txt"; echo "n/a" > "$DIST/glibc-max.txt"
  echo "== $NAME: data only, $(du -sh "$DIST/root" | cut -f1)"
  exit 0
fi

echo "::group::rust"
if ! command -v rustup >/dev/null; then curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none; fi
export PATH="$HOME/.cargo/bin:$PATH"
cd "$SRC"
rustup show active-toolchain >/dev/null 2>&1 || rustup toolchain install --profile minimal   # версия из rust-toolchain.toml
rustup target add "$TARGET"
rustc -V; cargo -V
echo "::endgroup::"

# кросс-сборка: pkg-config смотрит в multiarch-каталоги arm64, линкер и компилятор C — кросс-gcc
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++ AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export BINDGEN_EXTRA_CLANG_ARGS="--target=aarch64-linux-gnu --sysroot=/usr/aarch64-linux-gnu -I/usr/include/aarch64-linux-gnu"
export CARGO_PROFILE_RELEASE_LTO=false CARGO_PROFILE_RELEASE_DEBUG=false CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
for kv in $BUILD_ENV; do export "$kv"; done
echo "::group::cargo build"
# shellcheck disable=SC2086
cargo build --release --target "$TARGET" $CARGO_ARGS
echo "::endgroup::"

REL=$SRC/target/$TARGET/release
if [ -n "${BIN_GLOB:-}" ]; then
  BINS=$(cd "$REL" && for f in $BIN_GLOB; do [ -f "$f" ] && [ -x "$f" ] && echo "$f"; done | tr '\n' ' ')
fi
[ -n "$BINS" ] || { echo "нет исполняемых файлов (BINS/BIN_GLOB)" >&2; exit 1; }
for b in $BINS; do
  [ -f "$REL/$b" ] || { echo "binary not found: $REL/$b" >&2; exit 1; }
  install -m755 "$REL/$b" "$DIST/bin/$b"
  aarch64-linux-gnu-strip --strip-unneeded "$DIST/bin/$b" || true
done

if [ "$JUST_INSTALL" = 1 ]; then
  echo "::group::just install"
  # justfile ищет бинарники в target/release, а кросс-сборка кладёт их в target/$TARGET/release
  mkdir -p "$SRC/target/release"; for b in $BINS; do install -m755 "$REL/$b" "$SRC/target/release/$b"; done
  (cd "$SRC" && just --set rootdir "$DIST/root" install)
  # установленные just'ом бинарники берём как есть (включая ссылки); strip уже сделан для $BINS
  for b in $BINS; do [ -e "$DIST/root/usr/bin/$b" ] && install -m755 "$DIST/bin/$b" "$DIST/root/usr/bin/$b"; done
  find "$DIST/root" -type f | sed "s|$DIST/root/||" | sort | head -80
  echo "::endgroup::"
fi

# файлы из исходников без justfile: INSTALL_FILES="путь_в_исходниках:путь_в_пакете ..."
for pair in ${INSTALL_FILES:-}; do
  src=${pair%%:*}; dst=${pair#*:}
  [ -e "$SRC/$src" ] || { echo "нет $SRC/$src (INSTALL_FILES)" >&2; exit 1; }
  install -Dm0644 "$SRC/$src" "$DIST/root/$dst"
done

# NEEDED, версия glibc и пакеты Debian считаем по всем бинарникам
: > "$DIST/NEEDED.txt"; : > "$DIST/glibc-max.txt.all"
for b in $BINS; do
  aarch64-linux-gnu-readelf -d "$DIST/bin/$b" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' >> "$DIST/NEEDED.txt"
  aarch64-linux-gnu-objdump -T "$DIST/bin/$b" | grep -oE 'GLIBC_[0-9.]+' >> "$DIST/glibc-max.txt.all" || true
done
sort -u -o "$DIST/NEEDED.txt" "$DIST/NEEDED.txt"
# наивысшая версия символов glibc: должна быть не выше glibc на телефоне (2.44)
sort -uV "$DIST/glibc-max.txt.all" | tail -1 > "$DIST/glibc-max.txt"; rm -f "$DIST/glibc-max.txt.all"
# пакеты Debian, которые на телефоне нужно поставить через dapt (по NEEDED)
# (не все NEEDED-библиотеки обязаны быть в базе dpkg: ошибки поиска не должны ронять сборку)
: > "$DIST/runtime-packages.txt"
while read -r so; do
  # usrmerge: dpkg хранит путь как /lib/..., а не /usr/lib/...; пробуем оба
  pkg=$(dpkg -S "/lib/aarch64-linux-gnu/$so" "/usr/lib/aarch64-linux-gnu/$so" 2>/dev/null | head -1 | cut -d: -f1 | sed 's/:arm64//' || true)
  if [ -n "$pkg" ]; then echo "$pkg" >> "$DIST/runtime-packages.txt"; fi
done < "$DIST/NEEDED.txt"
sort -u -o "$DIST/runtime-packages.txt" "$DIST/runtime-packages.txt"
echo "== $NAME: $(du -sh "$DIST/bin" | cut -f1), glibc max $(cat "$DIST/glibc-max.txt")"
echo "== NEEDED:"; cat "$DIST/NEEDED.txt"
echo "== пакеты Debian для телефона:"; cat "$DIST/runtime-packages.txt"
