# Installing Debian on the Planet Gemini PDA (beta)

This replaces Android's data partition with Debian 13 + KDE Plasma. Android's
other partitions (bootloader, radio calibration, IMEI) stay untouched, and a
backup brings Android back. **Beta software, flashed at your own risk:** read
the whole guide once before you start.

You need:

- A Planet Gemini PDA (Wi-Fi or 4G) with the **stock partition layout** (step 3).
- A Linux PC (these steps; Windows works with mtkclient's drivers, see its README).
- A USB-C cable, the Gemini charged to at least 50 %.
- About 6 GB free on the PC for the backup and the images.
- From the release page: `boot-*.img`, `gemini-debian-*.img.zst` and `SHA256SUMS`.

## 1. Install mtkclient (PC)

[mtkclient](https://github.com/bkerler/mtkclient) talks to the Gemini's
MediaTek bootloader over USB.

```sh
sudo apt install python3-pip git libusb-1.0-0     # Fedora: sudo dnf install python3-pip git libusb1
git clone https://github.com/bkerler/mtkclient
cd mtkclient
pip3 install --user -r requirements.txt && pip3 install --user .
# Debian 12+/Ubuntu 23.04+ refuse --user installs: add --break-system-packages
# to both pip3 lines, or install into a venv (python3 -m venv ~/mtkvenv).
sudo cp mtkclient/Setup/Linux/*.rules /etc/udev/rules.d/
sudo udevadm control -R
sudo usermod -aG plugdev,dialout "$USER"          # then log out and back in
```

**How every `mtk` command works:** start the command first, with the Gemini
switched off and unplugged. When it says it is waiting for the device, plug
the Gemini in. It connects within a few seconds; if not, unplug, hold
**Esc/On for ~10 s** (hardware reset), and try again.

mtk wants **absolute paths** for files (`/home/you/gemini/boot.img`, not
`~/gemini/boot.img`).

## 2. Back up the Gemini (mandatory)

The backup is your only way back to Android, and it holds this unit's own
calibration data. **Keep it somewhere safe, off the PC too.**

```sh
mkdir -p ~/gemini-backup && cd ~/gemini-backup
mtk rl "$PWD" --skip userdata
ls -l nvdata.bin nvram.bin proinfo.bin            # all three must exist
```

This reads every partition except Android's (encrypted) user data, about
3–4 GB; it takes a while. `nvdata` holds the Wi-Fi record with your unit's own
MAC address, which Debian reads at every boot; `nvram` holds the IMEI.

## 3. Check the partition layout

```sh
mtk printgpt
```

This guide supports the **stock (Android-only) layout**: partition 29 is
`userdata`, and there are **no** partitions named `linux`, `boot2` or `boot3`.

If you see `linux`, `boot2` or `boot3`, the Gemini has a multi-boot layout
(Gemian/Sailfish). **Stop here:** restore the stock layout with Planet's
firmware tools first. Multi-boot isn't supported in this beta.

## 4. Check and unpack the images (PC)

```sh
cd ~/Downloads                                     # where the release files are
sha256sum -c SHA256SUMS                            # every line must say OK
zstd -d gemini-debian-*.img.zst                    # -> gemini-debian-*.img (6 GB)
```

## 5. Flash

One command writes the boot image and Debian, then restarts the Gemini
(adjust the file names and paths):

```sh
mtk multi "w boot /home/you/Downloads/boot-beta.img;w userdata /home/you/Downloads/gemini-debian-beta.img;reset"
```

Start it, then plug in the switched-off Gemini (step 1). Writing 6 GB takes
several minutes. **Erases everything on Android's data partition.**

## 6. First boot

1. When mtk says `Reset command was sent`: **unplug the USB cable from the PC
   right away.** Left on a PC's USB, the Gemini goes into its charging path
   and looks dead.
2. Power on with **Esc/On** (hold ~3 s). Boot messages appear, then the
   screen goes dark for up to ~40 s on the very first boot (see 8.).
3. **Setup starts by itself:** pick language, keyboard (Gemini US or UK),
   your user name and password. It finishes, and the Gemini restarts.
4. Log in at the login screen. Connect to Wi-Fi from the network icon in the
   panel; networks saved there also connect at boot, before you log in.

On the first boot Debian also grows its filesystem to fill the whole
partition (~55 GB) and copies your unit's Wi-Fi record from the `nvdata`
partition (read only; nothing is changed there).

## 7. Check it

Open Konsole and run:

```sh
sudo gemini-beta-check
```

Every line should say PASS (INFO lines are just numbers). If something
fails, include this output when you report it.

## 8. Optional: boot ~30 s faster

The boot image looks for an older system first and only then falls back to
Debian. Tell it to go straight to Debian (once; survives reflashing):

```sh
grep PARTNAME /sys/class/block/mmcblk0p2/uevent     # must say PARTNAME=para
printf 'boot-debian\0' | sudo dd of=/dev/mmcblk0p2 bs=32 count=1 conv=sync,fsync
```

Undo: `sudo dd if=/dev/zero of=/dev/mmcblk0p2 bs=32 count=1 conv=fsync`.

## If it doesn't start

- **Black screen, nothing happens:** unplug USB, hold **Esc/On ~10 s**
  (hardware reset), release, then press Esc/On ~3 s.
- **Don't press Esc/On together with the silver side button:** that combination
  boots the recovery partition.
- **Very low battery after a long flash:** charge from a wall charger for
  15–30 min, then try again.
- **Back to Android:** write your backup back, partition by partition, e.g.
  `mtk w boot /home/you/gemini-backup/boot.bin`, and for Android's data
  `mtk e userdata` (Android rebuilds it on first start).

## Using it

- **Switching off:** long-press Esc/On → Shut down. Switched off, it stays off
  and keeps its charge.
- **Charging while off** shows a battery screen; hold Esc/On to start Debian.
- **Speaker/headphones:** `sudo gemini-audio headphone|speaker|toggle`
  (no automatic headphone detection yet).
- Known limitations are listed in the [README](../README.md#known-limitations).
