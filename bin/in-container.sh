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
echo "    used: $(du -sh --apparent-size "$ROOTFS" | cut -f1) of $IMAGE_SIZE"

echo "    packing update bundle"
# Everything a running Gemini needs to catch up with this image, offline:
# the files tree, the extra .debs (collected by customize.sh), the shared
# installer, and build-info. Not included: kernel modules/firmware (they only
# change with a new boot image -> full flash) or user/hostname/locale.
B=/work/build/bundle
BUNDLE=/work/out/gemini-update.tar.gz
rm -rf "$B/files"
cp -a /work/build/stage/files "$B/files"
cp /work/bin/apply-files.sh "$B/apply-files.sh"
cp /work/bin/bundle-install.sh "$B/install.sh"
cp /work/build/stage/build-info "$B/build-info"
tar -C "$B" --owner=0 --group=0 -czf "$BUNDLE" .
echo "    bundle: $(du -h "$BUNDLE" | cut -f1) ($(ls "$B/debs" | wc -l) debs)"

# Hand everything back to the host user (next run deletes build/).
chown -R "$HOST_UID:$HOST_GID" "$IMG" "$BUNDLE" /work/build
