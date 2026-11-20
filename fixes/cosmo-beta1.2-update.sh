#!/bin/sh
# Cosmo Debian Beta1 / Beta1.1 -> Beta1.2 (kernel part), without reinstalling.
#
# Installs the Beta1.2 kernel modules (cosmo-modules-beta1.2.tar.zst, in the
# same folder as this script), the SCP firmware (firmware-mediatek, needs an
# internet connection) and the new default display scale for accounts made
# from now on. Then flash cosmo-boot-beta1.2.img and restart: the modules
# belong to that kernel.
#
#   sudo sh cosmo-beta1.2-update.sh
#
# The previous modules are kept in /usr/lib/modules/6.18.58-cosmo.before-beta1.2.
# Safe to run more than once.
set -eu

KVER=6.18.58-cosmo
TAR=cosmo-modules-beta1.2.tar.zst
TAR_SHA256=f21156b251d7af7a719b78c2c9b254efc34aee900f9597f7d823f2986550a910
M=/usr/lib/modules
SKEL=/etc/skel/.config/kwinoutputconfig.json

if [ "$(id -u)" != 0 ]; then
    echo "Run it as root: sudo sh $0" >&2
    exit 1
fi
if ! grep -qx 'device: cosmo' /etc/gemini/build-info 2>/dev/null; then
    echo "This update is for Cosmo Debian only (/etc/gemini/build-info)." >&2
    exit 1
fi
cd "$(dirname "$0")"
if [ ! -f "$TAR" ]; then
    echo "$TAR not found. Put it in the same folder as this script." >&2
    exit 1
fi
if ! echo "$TAR_SHA256  $TAR" | sha256sum -c --status; then
    echo "$TAR is damaged (checksum mismatch). Download it again." >&2
    exit 1
fi
command -v zstd >/dev/null || { echo "zstd is missing: sudo apt install zstd" >&2; exit 1; }

# 1. Kernel modules
T=$(mktemp -d "$M/.beta1.2.XXXXXX")
trap 'rm -rf "$T"' EXIT
zstd -dc "$TAR" | tar -C "$T" -xf -
[ -d "$T/$KVER/kernel" ] || { echo "Failed: $TAR has no $KVER modules." >&2; exit 1; }
if [ -d "$M/$KVER" ] && [ ! -e "$M/$KVER.before-beta1.2" ]; then
    mv "$M/$KVER" "$M/$KVER.before-beta1.2"
else
    rm -rf "$M/$KVER"
fi
mv "$T/$KVER" "$M/$KVER"
depmod "$KVER"
echo "Installed: Beta1.2 kernel modules ($KVER)."

# 2. SCP firmware
if [ -f /usr/lib/firmware/mediatek/mt8183/scp.img ] && dpkg -s firmware-mediatek >/dev/null 2>&1; then
    echo "Installed: SCP firmware (firmware-mediatek, already present)."
elif apt-get update -q >/dev/null && apt-get install -y -q firmware-mediatek >/dev/null; then
    echo "Installed: SCP firmware (firmware-mediatek)."
else
    echo "Not installed: firmware-mediatek (no internet?). Later: sudo apt install firmware-mediatek" >&2
fi

# 3. Display scale for accounts made from now on (existing accounts keep theirs)
if [ -f "$SKEL" ] && grep -q '"scale": 2,' "$SKEL"; then
    sed -i 's/"scale": 2,/"scale": 2.25,/' "$SKEL"
fi
grep -q '"scale": 2.25,' "$SKEL" 2>/dev/null && echo "Set: new accounts start at display scale 2.25."

echo
echo "Done. Now flash cosmo-boot-beta1.2.img (see the release notes) and restart."
