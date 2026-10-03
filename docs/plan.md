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
| 2 | Headless base rootfs: build script, modules/firmware, user, SSH, USB network, console keymap, growfs | **done** — booted + logged in 2026-10-02 (second flash; first had /etc,/usr at 0700) |
| 3 | Boot integration | **done / not needed**: the flashed boot image's initrd falls back to the Debian rootfs (verified) |
| 4 | Hardware services: GPU power-on, panfrost load, A72 up (opt-in), battery guard, backlight default, Wi-Fi (MT6630 CONSYS + NVRAM + NM), Bluetooth (hci_stp), WDT safe reboot, suspend masked | **written, not built** — ships as image + `out/gemini-update.tar.gz` (docs/updating.md) |
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

- NixOS's firmware set includes the author's factory Wi-Fi NVRAM (his MAC);
  replace with this unit's own record from the nvram backup (part 4).
- Audio has never worked on this unit; out of scope.
- Charger input current (wall brick detected as a 500 mA PC port) not automated yet.

## How changes reach the device

- `overlay/` + scripts/keymap/NVRAM copied from gemini-nixos are assembled
  into `build/stage/files/`; `bin/apply-files.sh` installs that tree (files
  only, 0644 root, then units.enable / units.mask) — the SAME script runs in
  the image build and in the update bundle on the device.
- `packages/extra.list` = packages added after part 2; the build collects the
  exact .debs (plus missing deps) into the bundle so it installs offline.
