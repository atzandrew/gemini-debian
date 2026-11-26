#!/usr/bin/env bash
# Runs INSIDE the debian:trixie container started by bin/build-mesa-astro.sh.
set -euo pipefail
source /work/config.env
export DEBIAN_FRONTEND=noninteractive
PATCH=/work/build/mesa-astro/astro-panfrost.patch
OUT=/work/out/mesa-astro.new
WANT=26.1.6-1~bpo13+1

sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
cat > /etc/apt/sources.list.d/backports.sources <<'SRC'
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev fakeroot ca-certificates patch >/dev/null

mkdir -p /src && cd /src
echo "    fetching Debian mesa $WANT source (trixie-backports)"
apt-get source -qq -t trixie-backports "mesa=$WANT"
cd /src/mesa-*/
VER=$(dpkg-parsechangelog -S Version)
echo "    Debian mesa: $VER"
[ "$VER" = "$WANT" ] || { echo "!! patch is for $WANT, got $VER"; exit 1; }

echo "    checking the patch applies"
patch -p1 --dry-run < "$PATCH" || { echo "!! patch does not apply to $VER"; exit 1; }
cp "$PATCH" debian/patches/astro-panfrost-keep-transcendental-branches.patch
echo astro-panfrost-keep-transcendental-branches.patch >> debian/patches/series

NEW="${VER}+astro1"
{
  printf 'mesa (%s) %s-backports; urgency=medium\n\n' "$NEW" "$DEBIAN_SUITE"
  printf '  * Astro Slide (Mali-G57): panfrost Bifrost/Valhall peephole-select keeps\n'
  printf '    branches holding transcendentals (gemini-debian patches/\n'
  printf '    mesa-panfrost-keep-transcendental-branches-26.1.6.patch).\n\n'
  printf ' -- gemini-debian <root@gemini>  %s\n\n' "$(date -R)"
  cat debian/changelog
} > /tmp/changelog && mv /tmp/changelog debian/changelog

echo "    installing build dependencies (large, from trixie as Debian's backports build)"
# From trixie, not -t trixie-backports: the result must keep the library
# dependencies of Debian's own 26.1.6~bpo13 packages (libwayland-client0 >=
# 1.23 etc.), else it pulls more than Mesa from backports onto the device.
# The one build-dep trixie lacks (header-only, no runtime dependency):
apt-get install -y -qq -t trixie-backports directx-headers-dev >/dev/null
apt-get build-dep -y -qq ./ >/dev/null

echo "    building $NEW with $(nproc) jobs"
DEB_BUILD_OPTIONS="nocheck noddebs parallel=$(nproc)" dpkg-buildpackage -b -us -uc

mkdir -p "$OUT"
cp /src/*.deb "$OUT/"
echo "    built $(ls "$OUT" | wc -l) packages"
