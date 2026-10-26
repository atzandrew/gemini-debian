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
# Gemini only: the Cosmo image is headless for now (devices/cosmo.env).
EXTRA=
[ "$DEVICE" != gemini ] || EXTRA=$(sed -e 's/#.*//' /work/packages/extra.list | xargs)
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
if [ "$DEVICE" = gemini ] && compgen -G "/work/out/mesa/*.deb" >/dev/null; then
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
if [ "$DEVICE" = cosmo ]; then
# Cosmo: the initramfs mounts userdata itself; name it by GPT label.
cat > "$R/etc/fstab" <<'EOF'
PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro 0 1
EOF
else
cat > "$R/etc/fstab" <<'EOF'
/dev/mmcblk0p29 / ext4 defaults,noatime,errors=remount-ro 0 1
EOF
fi

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

if [ "${GEMINI_FIRST_SETUP:-0}" = 1 ]; then
    echo "    customize: first-boot setup (autologin $GEMINI_USER -> Calamares)"
    # greetd has one config file: append the [initial_session] block
    # (gemini-first-setup finish deletes it again).
    cat "$S/firstboot/greetd-initial-session.toml" >> "$R/etc/greetd/config.toml"
    grep -q '^\[initial_session\]' "$R/etc/greetd/config.toml" || { echo "!! greetd initial_session not added"; exit 1; }
fi
# Default avatar for new accounts (~/.face.icon; gemini-first-setup finish
# also sets it in AccountsService). A real file, not a link: Plasma replaces
# it when the user picks another picture.
if [ "$DEVICE" = gemini ]; then
    install -m 644 "$R/usr/share/plasma/avatars/gemini-astronaut-render.png" "$R/etc/skel/.face.icon"
fi

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
if [ "$DEVICE" = cosmo ]; then
    for d in / /etc /usr /usr/bin /usr/sbin /usr/lib /usr/local /usr/local/sbin /usr/share /var /home; do
        m=$(stat -c %a "$R$d"); [ "$m" = 755 ] || { echo "!! $d has mode $m (want 755)"; exit 1; }
    done
    for t in sshd nmcli dnsmasq resize2fs; do
        in_chroot sh -c "command -v $t" >/dev/null || { echo "!! $t missing"; exit 1; }
    done
    for u in ssh.service NetworkManager.service cosmo-boot-ok.service gemini-growfs.service; do
        in_chroot systemctl is-enabled "$u" >/dev/null 2>&1 || { echo "!! $u not enabled"; exit 1; }
    done
    grep -qx "RuntimeWatchdogSec=30s" "$R/etc/systemd/system.conf.d/cosmo-watchdog.conf" || { echo "!! systemd watchdog (timer failsafe) not configured"; exit 1; }
    grep -qx "method=shared" "$R/etc/NetworkManager/system-connections/usb0.nmconnection" || { echo "!! usb0 not in shared mode"; exit 1; }
    grep -q "PARTLABEL=userdata / " "$R/etc/fstab" || { echo "!! fstab root is not PARTLABEL=userdata"; exit 1; }
    [ -f "$R/usr/share/X11/xkb/symbols/cosmo" ] || { echo "!! cosmo xkb symbols missing"; exit 1; }
    grep -qx "XKBLAYOUT=\"cosmo\"" "$R/etc/default/keyboard" || { echo "!! keyboard layout is not cosmo"; exit 1; }
    in_chroot sh -c "command -v setupcon" >/dev/null || { echo "!! console-setup missing"; exit 1; }
    [ -s "$R/home/$GEMINI_USER/.ssh/authorized_keys" ] || { echo "!! no SSH key for $GEMINI_USER"; exit 1; }
    echo "    customize: ok (cosmo)"
    exit 0
fi
[ -f "$R/usr/lib/modules/$KVER/extra/mt6351-gauge.ko" ] || { echo "!! mt6351-gauge.ko missing (fuel gauge)"; exit 1; }
in_chroot modinfo -k "$KVER" -n mt6351_gauge >/dev/null 2>&1 || { echo "!! mt6351_gauge not in modules.dep"; exit 1; }
in_chroot modinfo -k "$KVER" -n mt6797_suspend >/dev/null 2>&1 || { echo "!! mt6797_suspend not in modules.dep (system suspend)"; exit 1; }
# Core directories must be world-readable/traversable or nothing but root works.
for d in / /etc /usr /usr/bin /usr/sbin /usr/lib /usr/local /usr/local/sbin /usr/share /var /home; do
    m=$(stat -c %a "$R$d")
    [ "$m" = 755 ] || { echo "!! $d has mode $m (want 755)"; exit 1; }
done
m=$(stat -c %a "$R/usr/bin/bash"); [ "$m" = 755 ] || { echo "!! /usr/bin/bash mode $m"; exit 1; }
# Debian's imv has no /usr/bin/imv: only imv-wayland/imv-x11 and its own
# chooser /usr/libexec/imv/imv (what imv.desktop runs). Put "imv" on PATH.
if ! in_chroot sh -c "command -v imv" >/dev/null && [ -x "$R/usr/libexec/imv/imv" ]; then
    install -d "$R/usr/local/bin"
    ln -sfn ../../libexec/imv/imv "$R/usr/local/bin/imv"
    echo "      imv -> /usr/libexec/imv/imv (/usr/local/bin/imv)"
fi
for t in busybox i2cset iw debugfs nmcli greetd tuigreet firefox-esr \
         startplasma-wayland kwin_wayland Xwayland perf wpctl \
         gwenview ark kwrite okular unzip \
         pcmanfm-qt alacritty mpv featherpad imv; do
    in_chroot sh -c "command -v $t" >/dev/null || { echo "!! $t missing (device scripts / beta app set)"; exit 1; }
done
in_chroot systemctl is-enabled greetd.service >/dev/null 2>&1 || { echo "!! greetd.service not enabled"; exit 1; }
dm=$(readlink "$R/etc/systemd/system/display-manager.service" || :)
[ "${dm##*/}" = greetd.service ] || { echo "!! display-manager.service is not greetd: '$dm'"; exit 1; }
# etc/greetd/config.toml + tmpfiles run the greeter as Debian's _greetd user.
in_chroot getent passwd _greetd >/dev/null || { echo "!! no _greetd user (fix user= in etc/greetd/config.toml and etc/tmpfiles.d/gemini-tuigreet.conf)"; exit 1; }
grep -q 'tuigreet' "$R/etc/greetd/config.toml" || { echo "!! greetd config is not the Gemini one (tuigreet)"; exit 1; }
! in_chroot dpkg -s sddm >/dev/null 2>&1 || { echo "!! sddm got installed"; exit 1; }
# KWallet unlock at login (apply-files.sh edits greetd's PAM file).
compgen -G "$R/usr/lib/*/security/pam_kwallet5.so" >/dev/null || { echo "!! pam_kwallet5.so missing (libpam-kwallet5)"; exit 1; }
[ "$(grep -c 'pam_kwallet5' "$R/etc/pam.d/greetd")" = 2 ] || { echo "!! /etc/pam.d/greetd: want pam_kwallet5 auth + session lines"; exit 1; }
grep -qE '^-?session.*pam_kwallet5\.so.*force_run' "$R/etc/pam.d/greetd" || { echo "!! /etc/pam.d/greetd: pam_kwallet5 session needs force_run (greetd = tty session)"; exit 1; }
grep -qx 'First Use=false' "$R/etc/xdg/kwalletrc" || { echo "!! etc/xdg/kwalletrc missing (KWallet first-use wizard)"; exit 1; }
# Console colours for tuigreet (gemini-console-palette.service).
[ "$(grep -c ',' "$R/usr/share/gemini/vtrgb")" = 3 ] || { echo "!! usr/share/gemini/vtrgb malformed"; exit 1; }
in_chroot sh -c "command -v setvtrgb" >/dev/null || { echo "!! setvtrgb missing (kbd)"; exit 1; }
for m in packagechooser contextualprocess; do
    # (the first-boot Software page and the step that applies it)
    compgen -G "$R/usr/lib/*/calamares/modules/$m" >/dev/null || { echo "!! Calamares module $m missing"; exit 1; }
done
[ -f "$R/etc/skel/.face.icon" ] || { echo "!! default avatar missing"; exit 1; }
! in_chroot dpkg -s partitionmanager >/dev/null 2>&1 || { echo "!! partitionmanager got installed"; exit 1; }
! in_chroot dpkg -s plasma-welcome >/dev/null 2>&1 || { echo "!! plasma-welcome got installed"; exit 1; }
[ -f "$R/usr/share/plasma/plasmoids/org.kde.plasma.volume/metadata.json" ] || [ -d "$R/usr/share/plasma/plasmoids/org.kde.plasma.volume" ] || { echo "!! plasma-pa (volume applet) missing"; exit 1; }
[ -f "$R/usr/share/X11/xkb/symbols/gemini" ] || { echo "!! gemini xkb symbols missing"; exit 1; }
# Wi-Fi NVRAM: each unit's own record is copied from its nvdata at boot;
# the image carries only the fallback template, never a record.
[ ! -e "$R/data/nvram/APCFG/APRDEB/WIFI" ] || { echo "!! the image must not ship a Wi-Fi NVRAM record (one unit's MAC + calibration)"; exit 1; }
[ -f "$R/usr/share/gemini/wifi/WIFI.template" ] || { echo "!! Wi-Fi NVRAM template missing"; exit 1; }
[ -x "$R/usr/local/sbin/gemini-wifi-nvram" ] || { echo "!! gemini-wifi-nvram missing"; exit 1; }
# SPM suspend firmware (2026-10-19): mt6797-suspend loads exactly this blob
# (MediaTek pcm_suspend_v20 from the Gemini's Android /vendor/firmware, the
# revision the driver was developed and tested with). Only that revision.
SPM=$R/usr/lib/firmware/mt6797-spm/pcm_suspend.bin
[ -f "$SPM" ] || { echo "!! $SPM missing (overlay/usr/lib/firmware/mt6797-spm/; system suspend needs it)"; exit 1; }
echo "d6e8a0b8851e78e95891c995605ffbf210eade56583b14cf6b4a67e7d770f4e0  $SPM" | sha256sum -c --quiet - \
    || { echo "!! pcm_suspend.bin is not the tested pcm_suspend_v20 blob"; exit 1; }
[ -f "$R/usr/lib/firmware/WIFI_RAM_CODE_6797" ] || { echo "!! WIFI_RAM_CODE_6797 missing"; exit 1; }
echo "    customize: ok"
