#!/usr/bin/env bash
# Build Debian's trixie-backports Mesa (the Astro's and the Cosmo's Mesa)
# with the Astro panfrost patch (Hydra, rootless podman).
#
#   bash bin/build-mesa-astro.sh     # ~30-60 min; -> out/mesa-astro/*.deb
#
# Patch: patches/mesa-panfrost-keep-transcendental-branches-26.1.6.patch
# (Bifrost/Valhall peephole-select keeps branches holding pow/exp/log/...;
# KWin's colour shader ran 18 pow per pixel where 6 are taken, 2.6x the
# fragment time on the Astro's Mali-G57; astro-linux618 docs/frame-pacing.md).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
source ./config.env
die() { echo "!! $*" >&2; exit 1; }
PATCH=patches/mesa-panfrost-keep-transcendental-branches-26.1.6.patch
[ -f "$PATCH" ] || die "missing $PATCH"
mkdir -p build/mesa-astro out
cp "$PATCH" build/mesa-astro/astro-panfrost.patch
rm -rf out/mesa-astro.new
echo "==> building Mesa in a debian:$DEBIAN_SUITE container (rootless podman)"
podman run --rm --security-opt label=disable \
    -v "$HERE:/work" \
    docker.io/library/debian:trixie \
    bash /work/bin/mesa-astro-in-container.sh
rm -rf out/mesa-astro && mv out/mesa-astro.new out/mesa-astro
echo "==> done: out/mesa-astro/"
ls -1 out/mesa-astro
