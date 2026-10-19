#!/usr/bin/env bash
# Collect what was changed BY HAND on the running Gemini since its image was
# built, so it can be folded into this repo before a full reflash.
#
#   bash bin/collect-device-state.sh            (on Hydra; asks for sudo on the Gemini)
#
# Result: out/devstate-<date>/ (gitignored) with
#   packages/  apt-mark showmanual / showhold / full dpkg list
#   etc/       every /etc file modified after /etc/gemini/build-info
#              (secrets excluded: shadow, gshadow, ssh host keys, NM Wi-Fi
#              profiles -> names only)
#   usrlocal/  /usr/local files modified after the image build
#   modules.txt  module files newer than the image (swapped .ko's)
#   home/      ~/.config (minus caches), ~/.local/share/applications, ~/*.sh
#   home-backup.tgz  only with HOME_BACKUP=1: full backup of
#                    /home/$GEMINI_USER (a full reflash wipes userdata)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
source "$HERE/config.env"
D="$HERE/out/devstate-$(date +%Y%m%d-%H%M)"
mkdir -p "$D"

REMOTE_SCRIPT=$(cat <<'RS'
set -eu
U=$(id -un)
T=$(mktemp -d /tmp/devstate.XXXXXX)
REF=/etc/gemini/build-info
mkdir -p "$T/packages" "$T/etc" "$T/usrlocal" "$T/home"
apt-mark showmanual > "$T/packages/manual.txt"
apt-mark showhold   > "$T/packages/hold.txt"
dpkg-query -W -f '${Package}\t${Version}\n' > "$T/packages/all.txt"
cp "$REF" "$T/build-info" 2>/dev/null || true
uname -a > "$T/uname.txt"
# /etc changes (as root), secrets excluded
sudo find /etc -xdev -type f -newer "$REF" \
    ! -path '/etc/shadow*' ! -path '/etc/gshadow*' ! -path '/etc/ssh/ssh_host_*' \
    ! -path '/etc/NetworkManager/system-connections/*' ! -path '/etc/.pwd.lock' \
    ! -path '/etc/ld.so.cache' ! -path '/etc/machine-id' \
    -print0 | sudo xargs -0 -r cp --parents -t "$T/etc"
sudo ls /etc/NetworkManager/system-connections > "$T/etc/nm-connection-names.txt" 2>/dev/null || true
sudo find /usr/local -xdev -type f -newer "$REF" -print0 | sudo xargs -0 -r cp --parents -t "$T/usrlocal"
sudo find /usr/lib/modules -type f -newer "$REF" -printf '%TY-%Tm-%Td %TH:%TM  %p\n' > "$T/modules.txt"
systemctl list-unit-files --state=enabled --no-pager > "$T/units-enabled.txt" || true
systemctl --user list-unit-files --state=enabled --no-pager > "$T/user-units-enabled.txt" 2>/dev/null || true
cat /etc/environment > "$T/environment.txt" 2>/dev/null || true
# user config (no caches)
cd "$HOME"
tar cf - --exclude='.config/*cache*' --exclude='.config/chromium' \
    .config .local/share/applications ./*.sh 2>/dev/null | tar xf - -C "$T/home" || true
# full home backup (opt-in)
if [ "$HOME_BACKUP" = 1 ]; then tar czf "$T/home-backup.tgz" -C /home "$U" 2>/dev/null || true; fi
sudo chown -R "$U" "$T"
tar czf /tmp/devstate.tgz -C "$T" .
sudo rm -rf "$T"
echo "devstate: $(du -h /tmp/devstate.tgz | cut -f1)"
RS
)
echo "==> collecting on $GEMINI_HOST (sudo password may be asked)"
ssh -t "$GEMINI_HOST" "HOME_BACKUP=${HOME_BACKUP:-0} bash -c $(printf '%q' "$REMOTE_SCRIPT")"
scp "$GEMINI_HOST:/tmp/devstate.tgz" "$D/devstate.tgz"
tar xzf "$D/devstate.tgz" -C "$D" && rm "$D/devstate.tgz"
ssh "$GEMINI_HOST" rm -f /tmp/devstate.tgz
echo "==> $D"
ls "$D"
[ ! -f "$D/home-backup.tgz" ] || echo "Home backup: $D/home-backup.tgz (copy it somewhere safe before reflashing)"
