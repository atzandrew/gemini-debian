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
if [ -d build ]; then chmod -R u+w build 2>/dev/null || true; rm -rf build; fi
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
if [ -d "$SYS/firmware/lib/firmware" ]; then
    cp -rL "$SYS/firmware/lib/firmware/." "$STAGE/firmware/"
else
    die "$SYS has no firmware/lib/firmware"
fi
cp "$NIXOS/config/keymaps/gemini-uk.map" "$STAGE/gemini-uk.map"
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
echo "==> done: $HERE/out/gemini-debian-rootfs.img"
ls -lh out/gemini-debian-rootfs.img
echo "Next: docs/flashing.md"
