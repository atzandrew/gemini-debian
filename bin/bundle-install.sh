#!/usr/bin/env bash
# Gemini update bundle installer — shipped as install.sh inside
# out/gemini-update.tar.gz. Works offline. On the Gemini:
#
#   mkdir -p ~/update && tar -xzf gemini-update.tar.gz -C ~/update
#   sudo bash ~/update/install.sh
#   sudo reboot
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

echo "==> bundle"
cat build-info
KVER=$(sed -n 's/^kernel: //p' build-info)
if [ -n "$KVER" ] && [ "$KVER" != "$(uname -r)" ]; then
    echo "!! bundle is for kernel $KVER but this Gemini runs $(uname -r) — not installing" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive   # no debconf questions mid-install
if compgen -G "debs/*.deb" >/dev/null; then
    echo "==> packages ($(ls debs/*.deb | wc -l) .debs)"
    # apt orders a large set correctly (Pre-Depends, e.g. python3-minimal);
    # a bare `dpkg -i debs/*.deb` can try to configure a package before its
    # dependency (seen 2026-10-02 with the desktop bundle). Works offline:
    # every dependency is either installed already or in debs/.
    if ! apt-get install -y --no-install-recommends ./debs/*.deb; then
        echo "!! apt-get failed; falling back to dpkg" >&2
        dpkg -i --skip-same-version debs/*.deb || true
        dpkg --configure -a
    fi
fi

if compgen -G "mesa/*.deb" >/dev/null; then
    echo "==> Gemini Mesa"
    bash ./mesa-upgrade.sh "$PWD/mesa"
fi

echo "==> files + services"
bash ./apply-files.sh / ./files

echo
echo "==> installed. Reboot so everything starts in the right order:"
echo "    sudo reboot"
