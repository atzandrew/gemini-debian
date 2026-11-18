#!/bin/sh
# Cosmo Debian beta1: fix sleep that ends after about a second.
#
# The beta1 image installed the Wi-Fi sleep hook without its execute bit.
# systemd skips such hooks without a message, so the Wi-Fi chip stayed
# powered during sleep and woke the Cosmo straight away. This script sets
# the execute bit on the sleep hooks. It changes nothing else, needs no
# reboot and is safe to run more than once.
#
#   sudo sh cosmo-sleep-fix.sh
set -eu

D=/usr/lib/systemd/system-sleep
HOOK=$D/cosmo-wifi-sleep

if [ "$(id -u)" != 0 ]; then
    echo "Run it as root: sudo sh $0" >&2
    exit 1
fi
if [ ! -f "$HOOK" ]; then
    echo "$HOOK not found. This fix is for Cosmo Debian only." >&2
    exit 1
fi

for f in "$D"/*; do
    [ -f "$f" ] || continue
    chmod 755 "$f"
done

if [ -x "$HOOK" ]; then
    echo "Fixed: the Wi-Fi sleep hook is executable. Sleep works from now on (no reboot needed)."
else
    echo "Failed: $HOOK is still not executable." >&2
    exit 1
fi
