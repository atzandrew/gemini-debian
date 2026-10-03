# Updating a running Gemini (no reflash)

Every build also writes `out/gemini-update.tar.gz`: the Gemini files tree
(services, scripts, settings), any new Debian packages with their missing
dependencies as `.deb`s, and an installer. It works **offline**.

It does not change: kernel modules/firmware (those only change with a new
boot image → full flash), your user, password, hostname or locale, or
anything you installed yourself.

## 1. Build (Hydra)

```sh
cd ~/Build/gemini-debian
bash bin/build-rootfs.sh
```

## 2. Get the bundle onto the Gemini — pick one

**Over the network** (once Wi-Fi works, or over USB via Dragon):

```sh
scp out/gemini-update.tar.gz atzero@<gemini-ip>:
```

**USB stick** (no network needed): copy `out/gemini-update.tar.gz` to a stick
(ext4 or FAT), plug it into the Gemini with a USB-C adapter, then on the
Gemini:

```sh
lsblk                                   # find the stick, e.g. sda1
sudo mount /dev/sda1 /mnt
cp /mnt/gemini-update.tar.gz ~ && sudo umount /mnt
```

## 3. Install (on the Gemini)

```sh
rm -rf ~/update && mkdir ~/update && tar -xzf ~/gemini-update.tar.gz -C ~/update
sudo bash ~/update/install.sh
sudo reboot
```

`install.sh` refuses to run if the bundle was built for a different kernel
than the one running.

## After the part 4 update: Wi-Fi

```sh
systemctl status gemini-gpu-poweron gemini-wifi-internal --no-pager
nmcli device                            # wlan0 should be listed
nmtui                                   # pick a network (or below)
nmcli device wifi list
nmcli device wifi connect "<SSID>" --ask
```

Other checks:

```sh
ls /dev/dri                             # card0 + renderD128 once panfrost loaded
journalctl -t battery-guard -n 5        # battery guard running
bluetoothctl show                       # Powered: yes
```
