#!/usr/bin/env bash
# mmdebstrap --customize-hook: runs as root in the build container,
# OUTSIDE the chroot, with the finished rootfs path as $1.
set -euo pipefail
R=$1
source /work/config.env
S=/work/build/stage
B=/work/build/bundle
KVER=$(cat "$S/kver")
in_chroot() { chroot "$R" "$@"; }

echo "    customize: kernel $KVER modules + firmware"
mkdir -p "$R/usr/lib/modules" "$R/usr/lib/firmware"
cp -r --no-preserve=ownership "$S/modules/$KVER" "$R/usr/lib/modules/"
cp -r --no-preserve=ownership "$S/firmware/." "$R/usr/lib/firmware/"
in_chroot depmod -a "$KVER"

# ---- packages added after part 2 (packages/extra.list) --------------------
# Installed here from the part-2 baseline so the exact .debs it needed
# (packages + any missing dependencies) can also go into the update bundle
# for a running Gemini with no network.
EXTRA=$(sed -e 's/#.*//' /work/packages/extra.list | xargs)
mkdir -p "$B/debs"
if [ -n "$EXTRA" ]; then
    echo "    customize: extra packages: $EXTRA"
    rcbak=""
    if [ -e "$R/etc/resolv.conf" ] || [ -L "$R/etc/resolv.conf" ]; then
        mv "$R/etc/resolv.conf" "$R/etc/resolv.conf.gemini-bak"; rcbak=1
    fi
    cp /etc/resolv.conf "$R/etc/resolv.conf"
    printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 755 "$R/usr/sbin/policy-rc.d"
    # apt pins from the overlay must be in place BEFORE the installs (e.g.
    # no partitionmanager, which Plasma recommends); apply-files installs
    # the same files again later.
    if [ -d /work/overlay/etc/apt/preferences.d ]; then
        install -d "$R/etc/apt/preferences.d"
        install -m 644 /work/overlay/etc/apt/preferences.d/* "$R/etc/apt/preferences.d/"
    fi
    export DEBIAN_FRONTEND=noninteractive
    in_chroot apt-get clean
    in_chroot apt-get update -qq
    # shellcheck disable=SC2086
    in_chroot apt-get install -y -q --no-install-recommends --download-only $EXTRA
    cp "$R"/var/cache/apt/archives/*.deb "$B/debs/" 2>/dev/null || true
    # shellcheck disable=SC2086
    in_chroot apt-get install -y -q --no-install-recommends $EXTRA
    # ---- desktop (packages/desktop.list): WITH Recommends, as installed
    # by hand on the tested device (Plasma needs its recommended pieces,
    # e.g. plasma-pa = the volume applet + Sound settings page). Explicit
    # --install-recommends: the mmdebstrap chroot does not install them by
    # default (2026-10-04 image came up without plasma-pa).
    DESKTOP=$(sed -e 's/#.*//' /work/packages/desktop.list | xargs)
    if [ -n "$DESKTOP" ]; then
        echo "    customize: desktop packages (with recommends): $DESKTOP"
        # shellcheck disable=SC2086
        in_chroot apt-get install -y -q --install-recommends --download-only $DESKTOP
        cp "$R"/var/cache/apt/archives/*.deb "$B/debs/" 2>/dev/null || true
        # shellcheck disable=SC2086
        in_chroot apt-get install -y -q --install-recommends $DESKTOP
    fi
    in_chroot apt-get clean
    echo "      bundle debs: $(ls "$B/debs" | wc -l)"
    rm -f "$R/usr/sbin/policy-rc.d" "$R/etc/resolv.conf"
    [ -z "$rcbak" ] || mv "$R/etc/resolv.conf.gemini-bak" "$R/etc/resolv.conf"
fi

# ---- Gemini Mesa (optional: present after bin/build-mesa.sh) -------------
if compgen -G "/work/out/mesa/*.deb" >/dev/null; then
    echo "    customize: Gemini Mesa ($(ls /work/out/mesa/*.deb | wc -l) debs built)"
    mkdir -p "$R/tmp/gemini-mesa"
    cp /work/out/mesa/*.deb /work/bin/mesa-upgrade.sh "$R/tmp/gemini-mesa/"
    in_chroot bash /tmp/gemini-mesa/mesa-upgrade.sh /tmp/gemini-mesa
    rm -rf "$R/tmp/gemini-mesa"
fi

echo "    customize: gemini files + services"
bash /work/bin/apply-files.sh "$R" "$S/files"

echo "    customize: hostname, timezone, locale"
echo "$GEMINI_HOSTNAME" > "$R/etc/hostname"
cat > "$R/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$GEMINI_HOSTNAME
::1		localhost ip6-localhost ip6-loopback
EOF
ln -sf "/usr/share/zoneinfo/$GEMINI_TIMEZONE" "$R/etc/localtime"
echo "$GEMINI_TIMEZONE" > "$R/etc/timezone"
sed -i "s/^# *\($GEMINI_LOCALE UTF-8\)/\1/" "$R/etc/locale.gen"
in_chroot locale-gen >/dev/null
echo "LANG=$GEMINI_LOCALE" > "$R/etc/default/locale"

echo "    customize: fstab"
# The boot image's initrd rewrites the first field of the "/" line to the
# partition it actually mounted (mmcblk0 vs mmcblk1 varies), so the device
# name here is only a placeholder. Keep the "<dev> / " shape.
cat > "$R/etc/fstab" <<'EOF'
/dev/mmcblk0p29 / ext4 defaults,noatime,errors=remount-ro 0 1
EOF

echo "    customize: user $GEMINI_USER"
in_chroot useradd -m -s /bin/bash "$GEMINI_USER"
for g in sudo adm video render input audio plugdev netdev dialout bluetooth; do
    if in_chroot getent group "$g" >/dev/null; then in_chroot usermod -aG "$g" "$GEMINI_USER"; fi
done
printf '%s:%s\n' "$GEMINI_USER" "$(cat "$S/password-hash")" | in_chroot chpasswd -e
H=$R/home/$GEMINI_USER
install -d -m 700 "$H/.ssh"
install -m 600 "$S/authorized_keys" "$H/.ssh/authorized_keys"
in_chroot chown -R "$GEMINI_USER:$GEMINI_USER" "/home/$GEMINI_USER/.ssh"
# root stays locked (no password); use sudo.

echo "    customize: base services"
in_chroot systemctl enable ssh.service NetworkManager.service systemd-timesyncd.service

echo "    customize: boot-handoff checks"
# The initrd tests [ -x /newroot/sbin/init ] and [ -f /newroot/etc/os-release ]
# from OUTSIDE the new root, so absolute symlinks there would resolve against
# the initrd and fail (=> busybox shell). Make sure both are relative.
fix_rel() { # $1 = path in rootfs, $2 = relative target to use if absolute
    local t
    if [ -L "$R$1" ]; then
        t=$(readlink "$R$1")
        case "$t" in /*) ln -sfn "$2" "$R$1"; echo "      $1: absolute link $t -> $2" ;; esac
    fi
}
fix_rel /usr/sbin/init ../lib/systemd/systemd
fix_rel /etc/os-release ../usr/lib/os-release
[ -L "$R/sbin" ] || [ -d "$R/sbin" ] || { echo "!! no /sbin in rootfs"; exit 1; }
[ -x "$R/usr/sbin/init" ] || { echo "!! /usr/sbin/init missing (systemd-sysv)"; exit 1; }
[ -f "$R/etc/os-release" ] || { echo "!! /etc/os-release missing"; exit 1; }
[ -d "$R/usr/lib/modules/$KVER/kernel" ] || { echo "!! modules not installed"; exit 1; }
[ -f "$R/usr/lib/modules/$KVER/extra/mt6351-gauge.ko" ] || { echo "!! mt6351-gauge.ko missing (fuel gauge)"; exit 1; }
in_chroot modinfo -k "$KVER" -n mt6351_gauge >/dev/null 2>&1 || { echo "!! mt6351_gauge not in modules.dep"; exit 1; }
# Core directories must be world-readable/traversable or nothing but root works.
for d in / /etc /usr /usr/bin /usr/sbin /usr/lib /usr/local /usr/local/sbin /usr/share /var /home; do
    m=$(stat -c %a "$R$d")
    [ "$m" = 755 ] || { echo "!! $d has mode $m (want 755)"; exit 1; }
done
m=$(stat -c %a "$R/usr/bin/bash"); [ "$m" = 755 ] || { echo "!! /usr/bin/bash mode $m"; exit 1; }
for t in busybox i2cset iw debugfs nmcli sddm firefox-esr \
         startplasma-wayland kwin_wayland Xwayland perf wpctl \
         gwenview ark kwrite okular unzip; do
    in_chroot sh -c "command -v $t" >/dev/null || { echo "!! $t missing (device scripts / beta app set)"; exit 1; }
done
in_chroot systemctl is-enabled sddm.service >/dev/null 2>&1 || { echo "!! sddm.service not enabled"; exit 1; }
dm=$(readlink "$R/etc/systemd/system/display-manager.service" || :)
[ "${dm##*/}" = sddm.service ] || { echo "!! display-manager.service is not SDDM: '$dm'"; exit 1; }
! in_chroot dpkg -s partitionmanager >/dev/null 2>&1 || { echo "!! partitionmanager got installed"; exit 1; }
[ -f "$R/usr/share/plasma/plasmoids/org.kde.plasma.volume/metadata.json" ] || [ -d "$R/usr/share/plasma/plasmoids/org.kde.plasma.volume" ] || { echo "!! plasma-pa (volume applet) missing"; exit 1; }
[ -f "$R/usr/share/X11/xkb/symbols/gemini" ] || { echo "!! gemini xkb symbols missing"; exit 1; }
# Wi-Fi NVRAM: each unit's own record is copied from its nvdata at boot;
# the image carries only the fallback template, never a record.
[ ! -e "$R/data/nvram/APCFG/APRDEB/WIFI" ] || { echo "!! the image must not ship a Wi-Fi NVRAM record (one unit's MAC + calibration)"; exit 1; }
[ -f "$R/usr/share/gemini/wifi/WIFI.template" ] || { echo "!! Wi-Fi NVRAM template missing"; exit 1; }
[ -x "$R/usr/local/sbin/gemini-wifi-nvram" ] || { echo "!! gemini-wifi-nvram missing"; exit 1; }
[ -f "$R/usr/lib/firmware/WIFI_RAM_CODE_6797" ] || { echo "!! WIFI_RAM_CODE_6797 missing"; exit 1; }
echo "    customize: ok"
