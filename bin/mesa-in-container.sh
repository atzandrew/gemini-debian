#!/usr/bin/env bash
# Runs INSIDE the debian:trixie container started by bin/build-mesa.sh.
set -euo pipefail
source /work/config.env
export DEBIAN_FRONTEND=noninteractive
PATCH=/work/build/mesa/gemini-panfrost-t880.patch
OUT=/work/out/mesa.new

sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev fakeroot ca-certificates >/dev/null

mkdir -p /src && cd /src
echo "    fetching Debian mesa source"
apt-get source -qq mesa
cd /src/mesa-*/
VER=$(dpkg-parsechangelog -S Version)
echo "    Debian mesa: $VER"
case "$VER" in 25.0.7-*) ;; *) echo "!! patch is for Mesa 25.0.7, Debian has $VER"; exit 1 ;; esac

echo "    checking the patch applies"
patch -p1 --dry-run < "$PATCH" || { echo "!! patch does not apply to Debian's $VER"; exit 1; }
cp "$PATCH" debian/patches/gemini-panfrost-t880.patch
echo gemini-panfrost-t880.patch >> debian/patches/series

NEW="${VER}+gemini1"
{
  printf 'mesa (%s) %s; urgency=medium\n\n' "$NEW" "$DEBIAN_SUITE"
  printf '  * Gemini PDA (Mali-T880): panfrost polygon-list clear + dma-buf caps\n'
  printf '    (gemini-nixos patches/mesa-panfrost-geminipda-25.0.7.patch).\n\n'
  printf ' -- gemini-debian <root@gemini>  %s\n\n' "$(date -R)"
  cat debian/changelog
} > /tmp/changelog && mv /tmp/changelog debian/changelog

echo "    installing build dependencies (large)"
apt-get build-dep -y -qq ./ >/dev/null

echo "    building $NEW with $(nproc) jobs"
DEB_BUILD_OPTIONS="nocheck noddebs parallel=$(nproc)" dpkg-buildpackage -b -us -uc

mkdir -p "$OUT"
cp /src/*.deb "$OUT/"
chown -R "$HOST_UID:$HOST_GID" "$OUT" /work/build/mesa
echo "    built $(ls "$OUT" | wc -l) packages"
