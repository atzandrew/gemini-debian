#!/usr/bin/env bash
# Install the Gemini files tree onto a root filesystem, then enable/mask the
# listed units. Used in two places, so both paths stay identical:
#   - image build:    bin/customize.sh  ->  apply-files.sh /rootfs build/stage/files
#   - update bundle:  install.sh        ->  apply-files.sh / ./files   (on the Gemini)
#
# FILES mirrors the root filesystem (built by bin/build-rootfs.sh from
# overlay/ + scripts/keymap/NVRAM template copied out of gemini-nixos).
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

for f in "$R"/usr/local/sbin/* "$R"/usr/local/bin/*; do [ ! -f "$f" ] || chmod 755 "$f"; done
chmod 600 "$R"/etc/NetworkManager/system-connections/*.nmconnection
# sudoers drop-ins: sudo wants 0440
for f in "$R"/etc/sudoers.d/gemini-*; do [ ! -e "$f" ] || chmod 440 "$f"; done

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

# KWallet (2026-10-19): unlock the user's wallet with the login password, as
# SDDM's PAM file did. Lines go right after greetd's common-auth and
# common-session includes, the same spots Debian's sddm PAM file uses. Only
# the "greetd" service (the user's login), not "greetd-greeter" (_greetd).
PG="$R/etc/pam.d/greetd"
if [ -f "$PG" ] && ! grep -q 'pam_kwallet5' "$PG"; then
    if grep -q '^@include common-auth' "$PG" && grep -q '^@include common-session' "$PG"; then
        sed -i -e '/^@include common-auth/a auth    optional    pam_kwallet5.so' \
               -e '/^@include common-session/a session optional    pam_kwallet5.so auto_start force_run' "$PG"
        echo "apply-files: pam_kwallet5 added to /etc/pam.d/greetd"
    else
        echo "apply-files: warning: /etc/pam.d/greetd has no common-auth/common-session include; KWallet not added" >&2
    fi
fi
# Debian's greetd PAM file already has "-session optional pam_kwallet5.so
# auto_start", but greetd sessions register as tty, so the module logs "not
# a graphical session, skipping" and never hands over the password (no
# wallet -> KWallet's first-use wizard, 2026-10-19). force_run skips that
# test; greetd only runs Plasma (Wayland) sessions here.
if [ -f "$PG" ] && grep -qE '^-?session.*pam_kwallet5\.so' "$PG" && ! grep -qE '^-?session.*pam_kwallet5\.so.*force_run' "$PG"; then
    sed -i -E '/^-?session.*pam_kwallet5\.so/ s/$/ force_run/' "$PG"
    echo "apply-files: pam_kwallet5 session: force_run"
fi

sc() { if [ -z "$R" ]; then systemctl "$@"; else chroot "$R" systemctl "$@"; fi; }
list() { [ -f "$R/usr/share/gemini/$1" ] || return 0; sed -e 's/#.*//' "$R/usr/share/gemini/$1" | xargs; }
[ -n "$R" ] || systemctl daemon-reload
# Replaced units first (e.g. sddm, which also claims display-manager.service);
# a unit that isn't installed is fine.
for u in $(list units.disable); do sc disable "$u" >/dev/null 2>&1 || :; done
u=$(list units.enable)
# shellcheck disable=SC2086
[ -z "$u" ] || sc enable $u
# Masked by an older release but wanted now (mask below wins if listed in both).
for u in $(list units.unmask); do sc unmask "$u" >/dev/null 2>&1 || :; done
u=$(list units.mask)
# shellcheck disable=SC2086
[ -z "$u" ] || sc mask $u
# Per-user units for every user (systemctl --global).
u=$(list units.user.disable)
# shellcheck disable=SC2086
[ -z "$u" ] || sc --global disable $u >/dev/null 2>&1 || :
u=$(list units.user.enable)
# shellcheck disable=SC2086
[ -z "$u" ] || sc --global enable $u
echo "apply-files: units enabled/disabled/unmasked/masked"

# Files left behind by older releases (their units are disabled above).
n=0
for f in $(list files.remove); do
    case "$f" in /*|*..*) echo "apply-files: skipping bad path $f" >&2; continue ;; esac
    [ -e "$R/$f" ] || [ -L "$R/$f" ] || continue
    rm -f "$R/$f"; n=$((n + 1))
done
echo "apply-files: $n obsolete files removed"
[ -n "$R" ] || [ "$n" = 0 ] || systemctl daemon-reload
