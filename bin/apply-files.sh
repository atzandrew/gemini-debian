#!/usr/bin/env bash
# Install the Gemini files tree onto a root filesystem, then enable/mask the
# listed units. Used in two places, so both paths stay identical:
#   - image build:    bin/customize.sh  ->  apply-files.sh /rootfs build/stage/files
#   - update bundle:  install.sh        ->  apply-files.sh / ./files   (on the Gemini)
#
# FILES mirrors the root filesystem (built by bin/build-rootfs.sh from
# overlay/ + scripts/keymap/NVRAM copied out of gemini-nixos).
set -euo pipefail
ROOT=${1:?usage: apply-files.sh ROOT FILES}
FILES=${2:?usage: apply-files.sh ROOT FILES}
R=${ROOT%/}                      # "" when installing onto the running system
[ -d "$FILES" ] || { echo "apply-files: no such dir $FILES" >&2; exit 1; }

# Files only, root-owned, 0644. Never copy directory entries: their modes
# depend on how the repo was checked out and once turned / /etc /usr into
# 0700 ("No shell: Permission denied"). install -D makes missing parents
# 0755 and leaves existing directories alone.
n=0
while IFS= read -r -d '' f; do
    install -D -o 0 -g 0 -m 644 "$FILES/$f" "$R/${f#./}"
    n=$((n + 1))
done < <(cd "$FILES" && find . -type f -print0)
echo "apply-files: $n files installed"

chmod 755 "$R"/usr/local/sbin/*
[ ! -d "$R/usr/local/bin" ] || chmod 755 "$R"/usr/local/bin/*
chmod 600 "$R"/etc/NetworkManager/system-connections/*.nmconnection
# sudoers drop-ins: sudo wants 0440 (gemini-audio amp switch, 2026-10-03)
chmod 440 "$R"/etc/sudoers.d/gemini-*

# Bluetooth: Privacy=off. bluetoothd's boot-time auto power-on runs
# set-privacy, which the MT6630 rejects, leaving hci0 unpowered
# (gemini-nixos services/bluetooth.nix).
MC="$R/etc/bluetooth/main.conf"
if [ -f "$MC" ]; then
    if grep -qE '^#? *Privacy *=' "$MC"; then
        sed -i -E 's/^#? *Privacy *=.*/Privacy = off/' "$MC"
    else
        echo "apply-files: warning: no Privacy line in $MC" >&2
    fi
fi

# Image build: use the target's own systemctl inside its chroot (the build
# container has none). Live system: plain systemctl.
# UPower (from gemini-nixos services/plumbing.nix): the % is a VOLTAGE-based
# estimate (no fuel gauge), so never let UPower act on "critical" -- its
# default (hibernate/suspend) hangs this device. gemini-battery-guard is the
# only trusted poweroff (3.50 V). Thresholds match the NixOS tuning.
UP="$R/etc/UPower/UPower.conf"
if [ -f "$UP" ]; then
    setkey() { if grep -qE "^#?$1=" "$UP"; then sed -i -E "s|^#?$1=.*|$1=$2|" "$UP"; else echo "$1=$2" >> "$UP"; fi; }
    setkey UsePercentageForPolicy true
    setkey PercentageLow 15
    setkey PercentageCritical 5
    setkey PercentageAction 2
    setkey AllowRiskyCriticalPowerAction true
    setkey CriticalPowerAction Ignore
fi

sc() { if [ -z "$R" ]; then systemctl "$@"; else chroot "$R" systemctl "$@"; fi; }
list() { sed -e 's/#.*//' "$R/usr/share/gemini/$1" | xargs; }
[ -n "$R" ] || systemctl daemon-reload
# shellcheck disable=SC2046
sc enable $(list units.enable)
# shellcheck disable=SC2046
sc mask $(list units.mask)
echo "apply-files: units enabled/masked"
