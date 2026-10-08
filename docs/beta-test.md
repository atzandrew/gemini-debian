# Beta test: clean build, full flash, overnight power-off

Goal: an image built **only from the committed repos** boots and behaves
like the hand-tuned development Gemini. Until it does, nothing else on the
beta list can be trusted. Folded in: each unit's own Wi-Fi record, the two
Wi-Fi fixes (WPA2/WPA3 mixed networks, connecting before login), the new
login screen and apps, and the eMMC (HS200) cold-boot soak.

Commands use the session helpers (`gemini-nixos/bin/gemini-env.sh`). Hydra =
build machine, Dragon = flashing machine, Gemini = the device.

## 0. Before wiping the current install

**a. Wi-Fi record dry run (Gemini, read-only, 1 min).** Shows whether this
unit's own record can be read from the Android `nvdata` partition, which is
what the new image does at boot. `debugfs` without `-w` never writes.

```sh
ls -l /dev/disk/by-partlabel/ | grep -wE 'nvdata|nvram|proinfo'
sudo debugfs -R 'ls -l /APCFG/APRDEB' /dev/disk/by-partlabel/nvdata
sudo debugfs -R 'dump /APCFG/APRDEB/WIFI /tmp/WIFI.nvdata' /dev/disk/by-partlabel/nvdata
stat -c '%s %n' /tmp/WIFI.nvdata /data/nvram/APCFG/APRDEB/WIFI
od -A d -t x1 -N 16 /tmp/WIFI.nvdata                    # this unit's (bytes 4-9 = MAC)
od -A d -t x1 -N 16 /data/nvram/APCFG/APRDEB/WIFI       # in use now (gemini-nixos author's)
cat /sys/class/net/wlan0/address                        # 00:09:34:5a:af:c1 today
```

**b. Package names (Gemini).** Prints nothing when every new package exists:

```sh
sudo apt update -qq
for p in sddm sddm-theme-breeze kde-config-sddm gwenview ark zip unzip 7zip unar \
         xz-utils bzip2 zstd kwrite okular kcalc haruna vim-tiny htop wget lsof xdg-user-dirs; do
  apt-cache show "$p" >/dev/null 2>&1 || echo "MISSING $p"
done
```

**c. nvdata backup exists (Dragon).** The Gemini's own record must survive
anything that goes wrong: `ls -l ~/gemini-backup/ | grep -iE 'nvdata|nvram'`.

**d. Last drift check + home backup (Hydra).** A full flash wipes userdata.

```sh
cd ~/Build/gemini-debian
HOME_BACKUP=1 bash bin/collect-device-state.sh
```

Compare `out/devstate-*/` with the repo (or hand it to Claude): anything in
`etc/`, `usrlocal/` or `modules.txt` that the repo doesn't produce is drift.

## 1. Commit and push both repos

`build-rootfs.sh` writes both commits into `/etc/gemini/build-info` and warns
**"uncommitted changes"** if a tracked file differs from its commit. A release
image must not have that warning.

## 2. Build (Hydra)

```sh
cd ~/Build/gemini-nixos
IMG=$(nix build .#packages.aarch64-linux.bootimg --print-out-paths --no-link)
to_dragon "$IMG" boot-beta1-20261008.img

cd ~/Build/gemini-debian
bash bin/build-rootfs.sh
zstd -T0 -f out/gemini-debian-rootfs.img -o out/gemini-debian-rootfs.img.zst
to_dragon out/gemini-debian-rootfs.img.zst gemini-debian-beta1.img.zst
```

## 3. Flash both partitions (Dragon, Gemini on USB)

```sh
cd /home/atzero/readytoflash && unzstd -f gemini-debian-beta1.img.zst
flash_all boot-beta1-20261008.img gemini-debian-beta1.img
```

Then unplug from Dragon and power on with Esc/On (docs/flashing.md §3). The
`para` boot selector lives outside userdata and stays set to Debian.

## 4. First boot

1. SDDM's login screen appears rotated and at 2x, the keyboard types the
   Gemini layout, touch works. Log in.
2. `sudo gemini-beta-check | tee ~/beta-check-1.txt` — every line PASS.
   It checks what was once fixed by hand: vsync1 display module, cpufreq on
   all three clusters, thermal zone, A72 workqueue mask, UHID/FUSE, gauge,
   IR-compensated battery-guard, 2.5 A charger rule, SDDM, apps, the Wi-Fi
   record, and eMMC errors.
3. **Wi-Fi record:** `sudo gemini-wifi-nvram status` — source `nvdata`, MAC
   = this unit's, not `00:09:34:5a:af:c1`.
4. **Wi-Fi before login:** join the home network from the Plasma applet.
   `gemini-wifi-fixup --list` must show `psk-flags=0`. Reboot, **don't log
   in**, and from Hydra: `ping -c3 $GEMINI_IP` and `gssh`. Then log in and
   re-run the check: "Wi-Fi connected before login" PASS.
5. **WPA2/WPA3 mixed network** (LogosWiFi, next time you're on it): join from
   Plasma; it connects within a few seconds of the first failure, and
   `journalctl -b -u gemini-wifi-fixup` shows `WPA3 (sae) -> WPA2`.
6. Spot checks by hand: no tearing while scrolling, a Bluetooth LE mouse,
   speaker + headphones (`sudo gemini-audio toggle`), the charging screen
   (power off, plug in).

## 5. eMMC cold boots (HS200, three times)

A cold boot = a real power-off on battery, then Esc/On. After each:

```sh
sudo gemini-beta-check | grep -A6 '== eMMC'
bash ~/emmc-check.sh 1024 1        # once per boot; from gemini-nixos bin/ (to_gemini)
```

| Boot | Bus (want HS200, 192 MHz) | Bus errors | Block/ext4 errors | emmc-check |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 (after the overnight test) | | | | |

Three clean boots → ship HS200 (what every current boot image runs). Any bus
or block error → ship the proven HS52 setting for the beta and keep HS200 as
a project.

## 6. Overnight power-off on battery

Evening, charger unplugged and **left unplugged** (a charger would start the
charging screen):

```sh
cat /sys/class/power_supply/mt6351-battery/capacity; date
sudo poweroff
```

Morning: power on with Esc/On, then `sudo gemini-beta-check`. Read the
`gauge at boot` line:

- **"N s since PMIC power-on" ≈ the uptime printed next to it** (within a
  minute) → the PMIC really was off all night. Pass.
- N ≈ hours → the PMIC stayed on (the old "limbo"). Fail; the drop in charge
  shows how much it drained.

Also: `journalctl --list-boots` shows no boot during the night,
`/var/log/battery-history.csv` has no rows between the power-off and the
morning, and the battery is cold. The percentage is re-estimated from voltage
after a real power-off, so expect a few % of difference, not a large drop.

## 7. Report

`~/beta-check-1.txt`, the cold-boot table, the overnight result and the dry
run from step 0a. Anything FAIL goes back into the repos, not onto the
device.
