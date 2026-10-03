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
chmod 600 "$R"/etc/NetworkManager/system-connections/*.nmconnection

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
sc() { if [ -z "$R" ]; then systemctl "$@"; else chroot "$R" systemctl "$@"; fi; }
list() { sed -e 's/#.*//' "$R/usr/share/gemini/$1" | xargs; }
[ -n "$R" ] || systemctl daemon-reload
# shellcheck disable=SC2046
sc enable $(list units.enable)
# shellcheck disable=SC2046
sc mask $(list units.mask)
echo "apply-files: units enabled/masked"
