#!/usr/bin/env bash
# Runs INSIDE the debian:trixie build container (started by
# bin/build-rootfs.sh). /work is this repo.
set -euo pipefail
source /work/config.env

ROOTFS=/rootfs
IMG=/work/out/gemini-debian-rootfs.img

echo "    installing build tools"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    mmdebstrap e2fsprogs ca-certificates >/dev/null

INCLUDE=$(sed -e 's/#.*//' /work/packages/base.list | xargs | tr ' ' ',')
COMP="main contrib non-free non-free-firmware"

rm -rf "$ROOTFS"
mmdebstrap --mode=root --variant=minbase --architectures=arm64 \
    --include="$INCLUDE" \
    --customize-hook='bash /work/bin/customize.sh "$1"' \
    "$DEBIAN_SUITE" "$ROOTFS" \
    "deb http://deb.debian.org/debian $DEBIAN_SUITE $COMP" \
    "deb http://deb.debian.org/debian $DEBIAN_SUITE-updates $COMP" \
    "deb http://security.debian.org/debian-security $DEBIAN_SUITE-security $COMP"

echo "    packing ext4 image ($IMAGE_SIZE)"
rm -f "$IMG"
# no_copy_xattrs: don't carry host SELinux labels into the image (the same
# Asahi problem gemini-nixos fixed in pkgs/make-ext4fs-shim.nix).
mke2fs -q -t ext4 -L gemini-debian -E no_copy_xattrs -d "$ROOTFS" "$IMG" "$IMAGE_SIZE"
e2fsck -fn "$IMG" >/dev/null
chown "$HOST_UID:$HOST_GID" "$IMG"
echo "    used: $(du -sh --apparent-size "$ROOTFS" | cut -f1) of $IMAGE_SIZE"
