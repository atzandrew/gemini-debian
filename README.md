# gemini-debian

Debian 13 (trixie) with KDE Plasma for the Planet Gemini PDA (MT6797X), built on Hydra and
flashed to the `userdata` partition, replacing NixOS.

This repo builds only the Debian root filesystem. The kernel, device tree
and boot image come from
[atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos) (a fork
of cjdell's project), checked out next to this repo as `../gemini-nixos`
(`GEMINI_NIXOS_DIR` in `config.env`). Flash its boot image first; the rootfs
must match its kernel version (`EXPECT_KVER`).

> **AI-generated work.** Most of this repo, and most of the gemini-nixos fork
> changes listed below (kernel rebase, driver fixes, build scripts, docs), was
> written by Claude (Anthropic's AI coding agent), directed and tested on a real device by a
> human. Treat it accordingly: read the code before you trust it, expect
> mistakes, and flash at your own risk.

![KDE Plasma on the Gemini PDA: System Settings and Konsole](screenshots/Screenshot_20261006_115128.png)

## Road to the first beta image

**Beta readiness: 50 %** (8 of 16 checklist items done, as of 2026-10-06)

```
██████████░░░░░░░░░░  50 %
```

The goal of the beta is a downloadable image that someone other than us can
flash safely and set up for themselves.

### Done

- [x] **Kernel 6.6.157 + boot image** with a quiet boot and a custom boot logo
- [x] **KDE Plasma 6 on Wayland** with GPU acceleration, touch, rotation and scaling
- [x] **Wi-Fi, Bluetooth and sound**
- [x] **Accurate battery gauge** and low-battery protection
- [x] **Real power off**: a switched-off Gemini no longer drains its battery
- [x] **Charging screen** when a charger is plugged into a switched-off Gemini
- [x] **Faster charging** (2.5 A input instead of 500 mA)
- [x] **Correct clock at boot** and a **power menu on a long press of Esc/On**

### Still to do before the beta

- [ ] **Clean build and test**: an image built purely from the repos, flashed
      from scratch, plus an overnight power-off test on battery
- [ ] **Each unit's own Wi-Fi identity**: read the Wi-Fi calibration (NVRAM)
      record and MAC address from the device instead of shipping one unit's copy
- [ ] **First-boot setup**: create your own user and password, pick a desktop,
      keyboard layout and Wi-Fi network (no built-in account)
- [ ] **Wi-Fi fixes in the image**: WPA2/WPA3 mixed networks, and connecting
      before login
- [ ] **Storage speed decision**: soak-test the faster eMMC mode (HS200) or ship
      the proven slower one
- [ ] **Install guide**: mandatory full backup (including NVRAM), partition
      layout check, flashing steps
- [ ] **Release packaging**: compressed image, boot image and checksums on
      GitHub Releases
- [ ] **Licence notices** for firmware, fonts and artwork

## Features

### Desktop

- **KDE Plasma 6 (Wayland)** as the default desktop, with labwc as a lighter
  alternative. Plasma runs at about 60 frames per second.
- **GPU acceleration** on the Mali-T880 (panfrost, OpenGL ES 3.1).
- **Touchscreen and rotation** set up for the landscape keyboard position,
  scaled 2× for the 5.99" 2160×1080 panel.
- **Keyboard** with the Gemini's US and UK layouts and working brightness keys.
- **Long press of Esc/On** opens the power menu (shut down, restart, log out).
- **Screen off turns the backlight fully off.**

### Battery and power

- **Real battery percentage** from the MT6351 PMIC's coulomb counter: charge
  in and out is counted, not guessed from voltage. Shows charge rate, time to
  full or empty, and learns the battery's real capacity over time.
- **Low-battery protection**: desktop warnings, then a safe shutdown before
  the battery is damaged.
- **Real power off**: switched off, the Gemini stays off and keeps its charge.
- **Faster charging**: the charger's input limit is raised from 500 mA to 2.5 A
  (about 1.5 A into the battery while using Plasma).
- **Correct time at boot** from the PMIC's real-time clock, before the network
  is up.

### Charging screen

Plug a charger into a switched-off Gemini and it shows the battery level
instead of booting the whole system:

![Charging screen: battery circle at 63 %, "Charging at 1.4 A", hold power button to boot, unplug charger to power off](screenshots/charging-mode.png)

- The circle fills with the charge level and turns red below 15 %. The line
  under it shows what is happening: charging current, "Charged" or "Fully
  charged", or a warning when the battery is very low.
- **Hold Esc/On** to boot into Debian; **unplug** the charger to switch off.
- The screen turns itself off after 15 seconds; any key turns it back on.
- No Linux boot text before it. Normal power-ons still show the boot messages.

### Hardware

- **Wi-Fi** (MT6630) with NetworkManager, and **Bluetooth**.
- **Sound** through the speaker and the headphone jack (switch with
  `sudo gemini-audio speaker|headphone|toggle`).
- **USB network link** for development (`10.15.19.82`).
- **Updates without reflashing** a running Gemini ([docs/updating.md](docs/updating.md)).

### Known limitations

- No suspend yet, so the battery drains at about 150–250 mA with the screen off.
- The CPUs run at the clocks the bootloader leaves (no frequency scaling).
  The two fast A72 cores come online about 5 minutes after boot.
- No temperature sensor.
- Some screen tearing (the display has no vertical sync).
- Wi-Fi connects only after you log in, and WPA2/WPA3 mixed networks need a
  manual fix (both are on the beta list).
- Headphone plug-in detection isn't automatic yet.

## Changes in the gemini-nixos fork

What [atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos) adds
on top of cjdell's work (kernel source changes live in
[`devices/planet-geminipda/kernel/delta/`](https://github.com/atzandrew/gemini-nixos/tree/main/devices/planet-geminipda/kernel/delta)):

- **Kernel 6.6 → 6.6.157 stable rebase**
  ([567ed73](https://github.com/atzandrew/gemini-nixos/commit/567ed73)); config adds exFAT + NLS_UTF8
  ([d343495](https://github.com/atzandrew/gemini-nixos/commit/d343495)).
- **Display performance:** the scanout driver
  [`geminipda-drm.c`](https://github.com/atzandrew/gemini-nixos/blob/main/devices/planet-geminipda/kernel/delta/drivers/gpu/drm/tiny/geminipda-drm.c)
  now copies each frame in a single pass and syncs the CPU cache only for the damaged area
  ([e90dd06](https://github.com/atzandrew/gemini-nixos/commit/e90dd06)), with a software vblank at `refresh_hz`, default 60
  ([064cda8](https://github.com/atzandrew/gemini-nixos/commit/064cda8)).
  Screen off now also switches the backlight off.
- **Audio:** the mt6797 AFE again registers its sub-DAI widgets and routes
  ([f4c9f84](https://github.com/atzandrew/gemini-nixos/commit/f4c9f84)).
- **Keyboard:** `matrix_keypad` polls at a runtime `poll_ms` (default 20 ms)
  instead of fast device-tree polling ([0f076a2](https://github.com/atzandrew/gemini-nixos/commit/0f076a2),
  [6488c32](https://github.com/atzandrew/gemini-nixos/commit/6488c32)); zram built in.
- **Battery:** an MT6351 fuel-gauge driver (coulomb counter, capacity
  learning) and a gauge-aware battery guard.
- **Power:** a real power off (the PMIC power-down now runs while interrupts
  are still on), an MT6351 real-time clock driver, and Esc/On long press as the
  power key.
- **Charging screen:** the initrd recognises the bootloader's off-mode-charging
  boot and shows a battery screen (`devices/planet-geminipda/charger.sh`,
  `charger-ui/`). The kernel stays quiet until that decision.
- **eMMC HS200** support for the MT6797 (in testing).
- **Groundwork before the rebase** ([6724b54](https://github.com/atzandrew/gemini-nixos/commit/6724b54)): charger driver,
  device tree, initrd and greeter changes.

## Credit

This port stands on [cjdell/gemini-nixos](https://github.com/cjdell/gemini-nixos):
the mainline kernel bring-up, device tree, drivers, and most of the device
scripts and hardware research reused here (each copied file names its
gemini-nixos source). Thank you!

The charging screen uses the [Nunito](https://github.com/googlefonts/nunito)
font (SIL Open Font License 1.1) and [stb](https://github.com/nothings/stb)
(public domain).

## Docs

- **Plan and status:** [docs/plan.md](docs/plan.md)
- **Build + flash + first boot:** [docs/flashing.md](docs/flashing.md)
- **Update a running Gemini (no reflash):** [docs/updating.md](docs/updating.md)

## Layout

| Path | What |
|---|---|
| `config.env` | user, hostname, timezone, locale, Debian suite, expected kernel |
| `packages/base.list`, `packages/extra.list`, `packages/desktop.list` | Debian packages in the image (extra = also shipped in the update bundle) |
| `overlay/` | files copied as-is into the rootfs (owned by root) |
| `bin/build-rootfs.sh` | entry point (run on Hydra as your user) |
| `bin/in-container.sh` | mmdebstrap + ext4 packing, inside a debian:trixie podman container |
| `bin/customize.sh` | modules/firmware, user, locale, services, boot-handoff checks |
| `screenshots/` | images used in this README |
| `build/`, `out/` | scratch and output (git-ignored) |

## Build

```sh
cd ~/Build/gemini-debian
bash bin/build-rootfs.sh        # -> out/gemini-debian-rootfs.img
```

Needs: `nix` (to build gemini-nixos for modules/firmware), `podman`,
`openssl`, sudo for podman. Internet access for deb.debian.org.
