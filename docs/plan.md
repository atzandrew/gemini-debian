# Plan: Debian on the Gemini PDA

Goal: Debian 13 (trixie) replacing NixOS on `userdata`, with greetd +
tuigreet, LXQt and Firefox, porting as much of gemini-nixos as possible.

## Ground rules

- **gemini-nixos stays the source of the kernel and boot image.** This repo
  never builds a kernel; it copies modules + firmware out of a gemini-nixos
  build whose kernel version must match what is flashed in `boot`
  (`EXPECT_KVER` in config.env).
- **Copy, don't move.** Scripts and configs from gemini-nixos are copied in
  (with a comment naming where they came from), so the NixOS repo keeps
  working on its own.
- **Debian packages first.** Only rebuild something (Mesa, gemcli) when the
  stock package can't do the job.

## Parts

| # | Part | Status |
|---|---|---|
| 1 | Decisions + repo skeleton | done (2026-10-02): trixie, replace userdata, separate repo |
| 2 | Headless base rootfs: build script, modules/firmware, user, SSH, USB network, console keymap, growfs | **written, not built yet** |
| 3 | Boot integration | **not needed**: the flashed boot image's initrd already falls back to a Debian rootfs |
| 4 | Hardware services: GPU power-on, panfrost load, A72 up (opt-in), battery guard, backlight default, Wi-Fi (MT6630 CONSYS + NVRAM + NM), Bluetooth (hci_stp), WDT safe reboot, charger current | todo |
| 5 | Graphics: confirm card0 + kmsro with stock Mesa 25.0.7; rebuild Mesa with `mesa-panfrost-geminipda-25.0.7.patch` (T880 polygon-list fix) | todo |
| 6 | Desktop: greetd + tuigreet, LXQt (X11 first on trixie; Wayland session package is only in testing), panel rotation, touch mapping, `gemini` xkb layout, Firefox ESR | todo |
| 7 | gemcli (Rust): silver-button sleep (with the SSD2092 touch fix), speaker switching | todo |
| 8 | Polish: kernel + gemini support files as .debs, apt-safe | later |

## Part 2 contents (what the first image has)

- trixie minbase + `packages/base.list` (systemd, NetworkManager, OpenSSH,
  sudo, kbd, i2c-tools, evtest, …)
- kernel 6.6.157 modules and NixOS's firmware set in `/usr/lib/modules`,
  `/usr/lib/firmware`
- `/etc/modprobe.d/gemini.conf` — panfrost blacklisted (GPU must be powered
  first)
- `/etc/modules-load.d/gemini.conf` — sramldo-smc, drm, drm_shmem_helper,
  gpu-sched, mt6351-keys
- udev: USB host autosuspend off; backlight writable
- NetworkManager: usb0 static 10.15.19.82/24 via 10.15.19.1 (metric 1000)
- `gemini-keymap.service` — loads gemini-nixos' `gemini-uk.map` on tty1
- `gemini-growfs.service` — first-boot resize to the full partition
- user from config.env (sudo), password hash + SSH keys; root locked

## Known gaps / risks

- Wi-Fi only arrives in part 4 → first boot is USB/console only.
- Battery guard (orderly poweroff at 3.50 V) is part 4 — until then, don't
  run the Gemini flat on Debian.
- NixOS's firmware set includes the author's factory Wi-Fi NVRAM (his MAC);
  replace with this unit's own record from the nvram backup (part 4).
- Audio has never worked on this unit; out of scope.
- `systemctl suspend` must stay off (s2idle hangs, no wake source) — mask
  `sleep.target`/`suspend.target` in part 4.
