# Flashing the Debian rootfs (replaces NixOS on userdata)

This **erases NixOS** on the Gemini's `userdata` partition. The boot image in
`boot` (kernel 6.6.157) stays as it is — it already knows how to boot Debian:
its initrd looks for NixOS first and, finding none, falls back to the first
ext4 partition that has `/etc/os-release`, fixes the `/` line in fstab and
runs `/sbin/init`. No boot-image flash is needed.

## 0. Before you wipe NixOS (once)

Save anything on the NixOS install you want to keep. Over Wi-Fi from Hydra:

```sh
cd ~/Build/gemini-nixos
ssh -i keys/gemini_ed25519 root@10.0.20.215 \
  'tar -C / -czf - home/cjdell etc/NetworkManager/system-connections var/lib/gemini' \
  > ~/gemini-nixos-state-$(date +%F).tgz
```

NixOS itself can always be rebuilt from the gemini-nixos repo (its rootfs
image is a Nix build output), so only personal files need saving.
The partition backups on Dragon (`~/gemini-backup/`) don't include userdata.

## 1. Build (Hydra)

```sh
cd ~/Build/gemini-debian
bash bin/build-rootfs.sh
```

Asks for your sudo password (podman) and the new login password for the
Gemini. Result: `out/gemini-debian-rootfs.img` (3 GiB, mostly empty).

## 2. Copy to Dragon (Hydra)

```sh
zstd -T0 -f out/gemini-debian-rootfs.img -o out/gemini-debian-rootfs.img.zst
scp out/gemini-debian-rootfs.img.zst atzero@192.168.0.146:/home/atzero/   # Dragon
```

## 3. Flash (Dragon, Gemini on USB)

```sh
cd ~
unzstd -f gemini-debian-rootfs.img.zst
mtk w userdata /home/atzero/gemini-debian-rootfs.img
# while it waits: reboot / power on the Gemini (preloader appears ~9 s in)
mtk reset
```

(`mtk multi "w userdata /home/atzero/gemini-debian-rootfs.img;reset"` does
both in one session, like the boot-image flash.)

**After `mtk` says "Reset command was sent" (2026-10-04):** unplug the USB
cable from Dragon right away and power on with **Esc/On alone**. Left on a
PC's USB, LK takes the power-off-charging path (gemini-nixos
docs/disaster-recovery "POC trap") and the Gemini can look dead, while
Dragon's dmesg loops on `device descriptor read/64, error -110`. If it
doesn't start: hold **Esc/On alone ~10 s** (PMIC hardware reset), release,
then press Esc/On ~3 s. Don't use Esc/On + the silver side button: that
combo is RTC FAC_RESET and boots RECOVERY. A low battery after a long flash
can also keep it dark; charge from a wall brick for 15-30 min, then retry.

## 4. First boot

- The console shows the initrd saying the NixOS rootfs was not found and it
  is falling back to the Debian rootfs, then normal Debian boot messages.
- `gemini-growfs` grows the filesystem to the whole ~55 GiB partition on
  the first boot (a few seconds).
- Log in on the built-in keyboard at the tty1 prompt, or over USB from
  Dragon:

  ```sh
  ssh atzero@10.15.19.82
  ```

After the first flash, later changes don't need a reflash: see
[updating.md](updating.md).

## 5. Once: set the boot selector to Debian (saves ~30 s per boot)

The boot image's initrd defaults to "look for NixOS"; with no NixOS it
rescans every partition for 30 s before falling back to Debian. Tell it to
look for Debian directly (the `para` boot-selector marker; LK ignores
anything but `boot-recovery`):

```sh
grep PARTNAME /sys/class/block/mmcblk0p2/uevent     # must say PARTNAME=para
printf 'boot-debian\0' | sudo dd of=/dev/mmcblk0p2 bs=32 count=1 conv=sync,fsync
sudo od -c -N 32 /dev/mmcblk0p2                     # b o o t - d e b i a n \0 ...
```

Measured 2026-10-02: kernel+initrd 44 s -> 3.7 s (`systemd-analyze`).
Undo: `sudo dd if=/dev/zero of=/dev/mmcblk0p2 bs=32 count=1 conv=fsync`.
The marker lives outside userdata, so it survives reflashing userdata.

## Quick checks once logged in

```sh
cat /etc/gemini/build-info
uname -r                       # 6.6.157
lsmod | head -20               # sramldo_smc, mt6351_keys, ...
df -h /                        # ~55G after growfs
ip -br addr                    # usb0 10.15.19.82
journalctl -b -p warning       # anything odd
```

## If it doesn't boot

- **Drops to a busybox shell in the initrd:** it didn't find or accept the
  rootfs. `ls /dev/mmcblk*`, `mount /dev/mmcblkXp29 /newroot` and check for
  `/newroot/etc/os-release` and `/newroot/sbin/init`.
- **Back to NixOS:** rebuild the NixOS rootfs image in gemini-nixos and flash
  it to userdata the same way, or flash the Debian image again after fixing
  the build.
- The boot image is untouched, so the boot fallbacks in the gemini-nixos
  handoff (`~/boot-new.img`, stock `~/gemini-backup/boot.bin`) still apply.
