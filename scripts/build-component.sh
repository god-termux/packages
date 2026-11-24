#!/usr/bin/env bash
# Сборка одного компонента COSMIC для aarch64-unknown-linux-gnu (glibc) в контейнере debian:trixie на x86-раннере.
#   scripts/build-component.sh NAME     NAME = components/NAME.env
# Библиотеки берутся из Debian 13 arm64 (multiarch), как в дереве dapt на телефоне: те же sonames и версии.
# Результат: dist/NAME/ (бинарник, NEEDED.txt, runtime-packages.txt, glibc-max.txt, источник REF).
set -euo pipefail
NAME=${1:?usage: build-component.sh NAME}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
source "$ROOT/components/$NAME.env"
TARGET=aarch64-unknown-linux-gnu
WORK=${WORK:-$ROOT/work}; DIST=$ROOT/dist/$NAME
mkdir -p "$WORK" "$DIST"
export DEBIAN_FRONTEND=noninteractive

echo "::group::apt"
dpkg --add-architecture arm64
apt-get update
ARM=""; for p in $ARM64_DEPS; do ARM="$ARM $p:arm64"; done
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends ca-certificates curl git build-essential pkg-config cmake \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu $HOST_DEPS $ARM
echo "::endgroup::"

echo "::group::source $REPO @ $REF"
SRC=$WORK/$NAME-src
if [ ! -d "$SRC/.git" ]; then git init -q "$SRC"; git -C "$SRC" remote add origin "$REPO"; fi
git -C "$SRC" fetch -q --depth 1 origin "$REF"
git -C "$SRC" checkout -q FETCH_HEAD
echo "$REPO $(git -C "$SRC" rev-parse HEAD)" > "$DIST/SOURCE.txt"
echo "::endgroup::"

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
echo "::group::cargo build"
# shellcheck disable=SC2086
cargo build --release --target "$TARGET" $CARGO_ARGS
echo "::endgroup::"

BINPATH=$SRC/target/$TARGET/release/$BIN
[ -f "$BINPATH" ] || { echo "binary not found: $BINPATH" >&2; exit 1; }
install -m755 "$BINPATH" "$DIST/$BIN"
aarch64-linux-gnu-strip --strip-unneeded "$DIST/$BIN" || true
aarch64-linux-gnu-readelf -d "$DIST/$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | sort -u > "$DIST/NEEDED.txt"
# наивысшая версия символов glibc: должна быть не выше glibc на телефоне (2.44)
aarch64-linux-gnu-objdump -T "$DIST/$BIN" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1 > "$DIST/glibc-max.txt" || true
# пакеты Debian, которые на телефоне нужно поставить через dapt (по NEEDED)
# (не все NEEDED-библиотеки обязаны быть в базе dpkg: ошибки поиска не должны ронять сборку)
: > "$DIST/runtime-packages.txt"
while read -r so; do
  f=$(ls /usr/lib/aarch64-linux-gnu/"$so" /lib/aarch64-linux-gnu/"$so" 2>/dev/null | head -1 || true)
  if [ -n "$f" ]; then
    pkg=$(dpkg -S "$f" 2>/dev/null | head -1 | cut -d: -f1 | sed 's/:arm64//' || true)
    if [ -n "$pkg" ]; then echo "$pkg" >> "$DIST/runtime-packages.txt"; fi
  fi
done < "$DIST/NEEDED.txt"
sort -u -o "$DIST/runtime-packages.txt" "$DIST/runtime-packages.txt"
echo "== $NAME: $(du -h "$DIST/$BIN" | cut -f1), glibc max $(cat "$DIST/glibc-max.txt")"
echo "== NEEDED:"; cat "$DIST/NEEDED.txt"
echo "== пакеты Debian для телефона:"; cat "$DIST/runtime-packages.txt"
