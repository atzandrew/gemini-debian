#!/usr/bin/env bash
# Run ON THE TARGET (inside the image chroot, or on the live Gemini):
# replace the installed Mesa packages with the Gemini build in DIR, then
# hold them so `apt upgrade` cannot bring back stock Mesa.
#   mesa-upgrade.sh DIR
# To go back to stock: sudo apt-mark unhold <pkgs> && sudo apt install --reinstall <pkgs>=<stock version>
set -euo pipefail
D=${1:?usage: mesa-upgrade.sh DIR}
debs=(); pkgs=()
for deb in "$D"/*.deb; do
    [ -e "$deb" ] || continue
    pkg=$(dpkg-deb -f "$deb" Package)
    if [ "$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null)" = installed ]; then
        debs+=("$deb"); pkgs+=("$pkg")
    fi
done
if [ ${#debs[@]} -eq 0 ]; then echo "mesa-upgrade: nothing to replace"; exit 0; fi
apt-get install -y --no-install-recommends --allow-downgrades "${debs[@]}"
apt-mark hold "${pkgs[@]}" >/dev/null
echo "mesa-upgrade: ${pkgs[*]} -> $(dpkg-deb -f "${debs[0]}" Version) (held)"
