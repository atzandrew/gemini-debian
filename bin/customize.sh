#!/usr/bin/env bash
# mmdebstrap --customize-hook: runs as root in the build container,
# OUTSIDE the chroot, with the finished rootfs path as $1.
set -euo pipefail
R=$1
source /work/config.env
S=/work/build/stage
KVER=$(cat "$S/kver")
in_chroot() { chroot "$R" "$@"; }

echo "    customize: overlay"
# Copy overlay/ owned by root (the repo files are owned by the host user).
tar -C /work/overlay --owner=0 --group=0 -cf - . | tar -C "$R" -xf -
chmod 755 "$R"/usr/local/sbin/*
chmod 600 "$R"/etc/NetworkManager/system-connections/*.nmconnection

echo "    customize: kernel $KVER modules + firmware"
mkdir -p "$R/usr/lib/modules" "$R/usr/lib/firmware"
cp -r --no-preserve=ownership "$S/modules/$KVER" "$R/usr/lib/modules/"
cp -r --no-preserve=ownership "$S/firmware/." "$R/usr/lib/firmware/"
in_chroot depmod -a "$KVER"

echo "    customize: console keymap + build info"
install -D -m 644 "$S/gemini-uk.map" "$R/usr/share/gemini/keymaps/gemini-uk.map"
install -D -m 644 "$S/build-info" "$R/etc/gemini/build-info"

echo "    customize: USB network ($USB_ADDR via $USB_GW)"
sed -i -e "s|@USB_ADDR@|$USB_ADDR|" -e "s|@USB_GW@|$USB_GW|" \
    "$R/etc/NetworkManager/system-connections/usb0.nmconnection"

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

echo "    customize: services"
in_chroot systemctl enable gemini-keymap.service gemini-growfs.service \
    ssh.service NetworkManager.service systemd-timesyncd.service

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
echo "    customize: ok"
