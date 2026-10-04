#!/usr/bin/env bash
# Build the Gemini Debian rootfs image on Hydra.
#
#   bash bin/build-rootfs.sh
#
# Run as your normal user (atzero), NOT with sudo: it runs `nix build` as
# you (never `sudo nix` on Hydra) and calls sudo only for podman.
#
# Steps:
#   1. nix build the gemini-nixos system once, and copy the kernel modules,
#      firmware and console keymap out of it into build/stage/ (the kernel
#      itself stays in the boot image that is already flashed)
#   2. ask for the login password (hash only is kept)
#   3. in a Debian trixie container: mmdebstrap a fresh arm64 rootfs, apply
#      overlay/ + bin/customize.sh, and pack it into out/gemini-debian-rootfs.img
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
# shellcheck source=../config.env
source ./config.env

die() { echo "!! $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root (sudo is used only for podman)"
command -v nix >/dev/null    || die "nix not found"
command -v podman >/dev/null || die "podman not found — install it with: sudo dnf install podman"
command -v openssl >/dev/null || die "openssl not found"

NIXOS=$(cd "$HERE" && cd "$GEMINI_NIXOS_DIR" && pwd) || die "gemini-nixos not found at $GEMINI_NIXOS_DIR"
STAGE=$HERE/build/stage

# Previous runs leave read-only Nix copies behind; make them deletable.
# A failed container run can leave root-owned files in build/ (sudo fallback).
if [ -d build ]; then
    chmod -R u+w build 2>/dev/null || true
    rm -rf build 2>/dev/null || sudo rm -rf build
fi
mkdir -p "$STAGE" out

echo "==> 1/3 kernel modules + firmware from $NIXOS"
SYS=$(cd "$NIXOS" && nix build .#packages.aarch64-linux.toplevel --print-out-paths --no-link)
echo "    system: $SYS"
[ -d "$SYS/kernel-modules/lib/modules" ] || die "$SYS has no kernel-modules/lib/modules"
KVER=$(ls "$SYS/kernel-modules/lib/modules")
[ "$(echo "$KVER" | wc -w)" -eq 1 ] || die "expected one module tree, found: $KVER"
[ "$KVER" = "$EXPECT_KVER" ] || die "gemini-nixos built modules for $KVER but config.env expects $EXPECT_KVER (the flashed boot image)"
echo "    kernel: $KVER"

mkdir -p "$STAGE/modules" "$STAGE/firmware"
cp -rL "$SYS/kernel-modules/lib/modules/$KVER" "$STAGE/modules/"
# NixOS links $SYS/firmware straight to <hardware.firmware>/lib/firmware
# (nixos/modules/system/boot/kernel.nix), i.e. the firmware dir itself.
if [ -d "$SYS/firmware/lib/firmware" ]; then
    cp -rL "$SYS/firmware/lib/firmware/." "$STAGE/firmware/"
elif [ -d "$SYS/firmware" ]; then
    cp -rL "$SYS/firmware/." "$STAGE/firmware/"
else
    die "$SYS has no firmware link"
fi
# Debian's wireless-regdb package owns regulatory.db{,.p7s} (via
# alternatives symlinks); keep Debian's, drop the NixOS copies.
chmod -R u+w "$STAGE/firmware"
rm -f "$STAGE/firmware/regulatory.db" "$STAGE/firmware/regulatory.db.p7s"
echo "    kernel build: $(readlink -f "$SYS/kernel")"
# MT6351 fuel gauge (gemini-nixos devices/planet-geminipda/kernel/modules/
# mt6351-gauge): an out-of-tree module built against the same kernel
# derivation, so it lands in the module tree's extra/ (customize.sh runs
# depmod). Loaded at boot by etc/modules-load.d/gemini-gauge.conf.
GAUGE=$(cd "$NIXOS" && nix build .#packages.aarch64-linux.mt6351-gauge --print-out-paths --no-link)
[ -f "$GAUGE/mt6351-gauge.ko" ] || die "mt6351-gauge build has no mt6351-gauge.ko ($GAUGE)"
install -D -m 644 "$GAUGE/mt6351-gauge.ko" "$STAGE/modules/$KVER/extra/mt6351-gauge.ko"
echo "    fuel gauge module: $GAUGE"
chmod -R u+w "$STAGE"
echo "$KVER" > "$STAGE/kver"
{
    echo "built: $(date -Is) on $(hostname)"
    echo "gemini-nixos: $(git -C "$NIXOS" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "gemini-debian: $(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || echo uncommitted)"
    echo "nixos system (modules/firmware source): $SYS"
    echo "kernel: $KVER"
    echo "suite: $DEBIAN_SUITE"
} > "$STAGE/build-info"
echo "    modules: $(du -sh "$STAGE/modules" | cut -f1), firmware: $(du -sh "$STAGE/firmware" | cut -f1)"

# ---- the Gemini files tree (goes into the image AND the update bundle) ----
# overlay/ + device scripts, keymap and Wi-Fi NVRAM copied from gemini-nixos.
F=$STAGE/files
mkdir -p "$F"
cp -r overlay/. "$F/"
sed -i -e "s|@USB_ADDR@|$USB_ADDR|" -e "s|@USB_GW@|$USB_GW|" \
    "$F/etc/NetworkManager/system-connections/usb0.nmconnection"
# Device scripts, verbatim (gemini-nixos services/scripts/). They call
# busybox devmem, i2cset, iw, modprobe by name — all on Debian's PATH.
SCRIPTS="gemini-gpu-poweron.sh panfrost-load.sh wifi-internal battery-guard.sh
         backlight battstat bq25896-raw.sh cl2-up.sh cl2-down.sh gemini-wdt-reboot"
mkdir -p "$F/usr/local/sbin"
for s in $SCRIPTS; do
    [ -f "$NIXOS/services/scripts/$s" ] || die "missing $NIXOS/services/scripts/$s"
    cp "$NIXOS/services/scripts/$s" "$F/usr/local/sbin/$s"
done
install -D -m 644 "$NIXOS/config/keymaps/gemini-uk.map" "$F/usr/share/gemini/keymaps/gemini-uk.map"
# The "gemini" xkb layout for X (part 6), verbatim from gemini-nixos.
install -D -m 644 "$NIXOS/config/xkb/symbols/gemini" "$F/usr/share/X11/xkb/symbols/gemini"
install -D -m 644 "$STAGE/build-info" "$F/etc/gemini/build-info"
# Factory Wi-Fi NVRAM record (MAC + TX calibration) where wlan_gen3 reads it.
# NOTE: this is the record gemini-nixos ships (from the original author's
# unit); replace with this unit's own from the nvram backup (plan.md).
install -D -m 644 "$NIXOS/pkgs/gemini-firmware/WIFI_factory.bin" "$F/data/nvram/APCFG/APRDEB/WIFI"
# Kernel modules changed WITHOUT a new kernel/boot image (CONFIG_MODVERSIONS
# and module signing are off, so a rebuilt module loads into the flashed
# kernel). Shipped in the files tree so the update bundle refreshes them on a
# running Gemini; same path as in the module tree, so no depmod is needed.
#   geminipda-drm.ko: CPU cache sync before the scanout blit (2026-10-02;
#   fixes stale-pixel "residue" with GPU-accelerated X).
MODULE_OVERRIDES="kernel/drivers/gpu/drm/tiny/geminipda-drm.ko"
for m in $MODULE_OVERRIDES; do
    src="$STAGE/modules/$KVER/$m"
    [ -f "$src" ] || die "module override $m not in the module tree (find $STAGE/modules -name 'geminipda*')"
    install -D -m 644 "$src" "$F/usr/lib/modules/$KVER/$m"
done
echo "    files tree: $(find "$F" -type f | wc -l) files"

echo "==> 2/3 login"
: > "$STAGE/authorized_keys"
for k in $AUTHORIZED_KEYS; do
    if [ -f "$k" ]; then cat "$k" >> "$STAGE/authorized_keys"; echo "    ssh key: $k"
    else echo "    (skipping missing key $k)"; fi
done
if [ -n "${GEMINI_PASSWORD_HASH:-}" ]; then
    echo "$GEMINI_PASSWORD_HASH" > "$STAGE/password-hash"
else
    while :; do
        read -r -s -p "    password for $GEMINI_USER on the Gemini: " p1; echo
        read -r -s -p "    again: " p2; echo
        [ -n "$p1" ] && [ "$p1" = "$p2" ] && break
        echo "    (empty or mismatch — try again)"
    done
    printf '%s' "$p1" | openssl passwd -6 -stdin > "$STAGE/password-hash"
    unset p1 p2
fi
chmod 600 "$STAGE/password-hash"

echo "==> 3/3 Debian $DEBIAN_SUITE rootfs (container; sudo for podman)"
sudo podman run --rm --privileged --security-opt label=disable \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$HERE:/work" \
    docker.io/library/debian:trixie \
    bash /work/bin/in-container.sh

echo
echo "==> done:"
ls -lh out/gemini-debian-rootfs.img out/gemini-update.tar.gz
echo "Full flash: docs/flashing.md    Update a running Gemini: docs/updating.md"
