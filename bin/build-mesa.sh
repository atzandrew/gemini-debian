#!/usr/bin/env bash
# Build Debian's Mesa with the Gemini Mali-T880 panfrost patch (Hydra).
#
#   bash bin/build-mesa.sh          # ~30-60 min; -> out/mesa/*.deb
#
# Then rebuild as usual (bash bin/build-rootfs.sh): the image and the update
# bundle pick up out/mesa/*.deb automatically, replace whichever Mesa
# packages are installed, and hold them (bin/mesa-upgrade.sh).
#
# Why: stock panfrost on the T880 leaves stale tiler bins on reused
# polygon-list buffers -> parts of the screen are not redrawn (white
# "residue" when dragging a selection; confirmed 2026-10-02 by A/B with
# AccelMethod none). Patch: gemini-nixos patches/mesa-panfrost-geminipda-25.0.7.patch
# (whole-BO polygon-list clear + dma-buf caps; debug hooks are env-gated, off).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
source ./config.env
die() { echo "!! $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "run as your normal user (sudo is used only for podman)"
NIXOS=$(cd "$GEMINI_NIXOS_DIR" && pwd)
PATCH=$NIXOS/patches/mesa-panfrost-geminipda-25.0.7.patch
[ -f "$PATCH" ] || die "missing $PATCH"

mkdir -p build/mesa out
cp "$PATCH" build/mesa/gemini-panfrost-t880.patch
rm -rf out/mesa.new 2>/dev/null || sudo rm -rf out/mesa.new
echo "==> building Mesa in a debian:$DEBIAN_SUITE container (sudo for podman)"
sudo podman run --rm --security-opt label=disable \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$HERE:/work" \
    docker.io/library/debian:trixie \
    bash /work/bin/mesa-in-container.sh
rm -rf out/mesa && mv out/mesa.new out/mesa
echo
echo "==> done: out/mesa/"
ls -1 out/mesa
echo "Next: bash bin/build-rootfs.sh (image + bundle now include this Mesa)"
