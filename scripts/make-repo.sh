#!/usr/bin/env bash
# Собирает подписанный apt-репозиторий (плоская схема dists/stable/main) из dist/deb/*.deb в каталог site/ для GitHub Pages.
#   GPG_KEY_B64   секретный ключ подписи (base64, gpg --export-secret-keys | base64 -w0)
#   scripts/make-repo.sh
# Результат: site/{pool,dists/stable/{Release,InRelease,Release.gpg,main/binary-arm64/Packages*},keyrings,index.html}
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SITE=$ROOT/site
URL=${REPO_URL:-https://god-termux.github.io/god-cosmic}
rm -rf "$SITE"; mkdir -p "$SITE/pool/main/g/god-cosmic" "$SITE/dists/stable/main/binary-arm64" "$SITE/keyrings"
cp "$ROOT"/dist/deb/*.deb "$SITE/pool/main/g/god-cosmic/"
cp "$ROOT"/keyrings/god-cosmic-archive-keyring.gpg "$ROOT"/keyrings/god-cosmic-archive-keyring.asc "$SITE/keyrings/"

cd "$SITE"
apt-ftparchive packages pool > dists/stable/main/binary-arm64/Packages
gzip -9kf dists/stable/main/binary-arm64/Packages
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=god-cosmic -o APT::FTPArchive::Release::Label=god-cosmic \
  -o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Architectures=arm64 -o APT::FTPArchive::Release::Components=main \
  -o "APT::FTPArchive::Release::Description=COSMIC for god-termux" \
  release dists/stable > dists/stable/Release

if [ -n "${GPG_KEY_B64:-}" ]; then
  GH=$(mktemp -d); chmod 700 "$GH"; export GNUPGHOME=$GH
  echo "$GPG_KEY_B64" | base64 -d | gpg --batch --import 2>/dev/null
  KEY=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
  gpg --batch --yes --pinentry-mode loopback --local-user "$KEY" --clearsign -o dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --local-user "$KEY" -abs -o dists/stable/Release.gpg dists/stable/Release
  rm -rf "$GH"
else
  echo "::warning::GPG_KEY_B64 не задан: репозиторий НЕ подписан" >&2
fi

cat > index.html <<EOF
<!doctype html><meta charset="utf-8"><title>god-cosmic apt repository</title>
<h1>god-cosmic</h1>
<p>COSMIC для god-termux (Debian arm64, дерево <code>dapt</code>).</p>
<pre>
# в Termux с god-termux:
curl -fsSL $URL/install.sh | bash
dapt install god-cosmic
god-cosmic start
</pre>
<p>Исходники сборки: <a href="https://github.com/god-termux/god-cosmic">github.com/god-termux/god-cosmic</a>.</p>
<ul>
<li><a href="keyrings/god-cosmic-archive-keyring.asc">ключ репозитория</a></li>
<li><a href="dists/stable/Release">dists/stable/Release</a></li>
</ul>
EOF
sed "s|@URL@|$URL|g" "$ROOT/scripts/install.sh.in" > install.sh
find . -type f | sort | sed 's|^\./||' | head -30
