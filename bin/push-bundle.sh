#!/usr/bin/env bash
# Copy out/gemini-update.tar.gz to the Gemini, VERIFY it arrived intact, then
# install it there. Run on Hydra:
#
#   bash bin/push-bundle.sh                    # uses GEMINI_HOST from config.env
#   bash bin/push-bundle.sh atzero@<gemini-ip>
#
# Set up an SSH key once (ssh-keygen; ssh-copy-id atzero@<ip>) so scp/ssh
# don't stop at password prompts. The Gemini's sudo password is still asked
# for the install step. Reboot afterwards: ssh <host> sudo reboot
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
source ./config.env
die() { echo "!! $*" >&2; exit 1; }

HOST=${1:-${GEMINI_HOST:-}}
[ -n "$HOST" ] || die "usage: push-bundle.sh atzero@<gemini-ip>  (or set GEMINI_HOST in config.env)"
B=out/gemini-update.tar.gz
[ -f "$B" ] || die "no $B — run bin/build-rootfs.sh first"
size=$(stat -c %s "$B")
built=$(tar -xzOf "$B" ./build-info 2>/dev/null | sed -n 's/^built: //p')

echo "==> copying bundle built $built ($(du -h "$B" | cut -f1)) to $HOST"
scp "$B" "$HOST:gemini-update.tar.gz"
rsize=$(ssh "$HOST" stat -c %s gemini-update.tar.gz)
[ "$rsize" = "$size" ] || die "copy incomplete: Hydra $size bytes, Gemini $rsize bytes"
echo "==> verified on the Gemini ($size bytes)"

echo "==> installing (the Gemini's sudo password may be asked)"
ssh -t "$HOST" 'rm -rf ~/update && mkdir ~/update && tar -xzf ~/gemini-update.tar.gz -C ~/update && sudo bash ~/update/install.sh'
echo
echo "==> done. Reboot the Gemini when ready:  ssh -t $HOST sudo reboot"
