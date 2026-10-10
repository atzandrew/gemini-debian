# Debian for the Planet Gemini PDA

A modern Linux desktop for the Planet Gemini PDA: Debian 13 with KDE Plasma 6
on Wayland, running on a current mainline-based kernel.

![KDE Plasma on the Gemini PDA: System Settings and Konsole](screenshots/Screenshot_20261006_115128.png)

> **Beta.** It works well on our test unit, but expect rough edges. Back up
> your Gemini before installing (the [install guide](docs/install.md) shows
> how).
>
> **AI-assisted.** Most of the code here and in the kernel fork was written by
> Claude (Anthropic's AI), directed and tested on a real Gemini by a human.
> Read before you trust it, and flash at your own risk.

## Highlights

### A smooth, modern desktop

- **KDE Plasma 6 on Wayland**, GPU-accelerated and much smoother than Gemian.
- **Tear-free**, synced to the panel's refresh.
- **Everyday apps included:** Firefox, Dolphin (files), Konsole, Gwenview
  (images), Okular (PDF), Ark (archives), KWrite (text), KCalc, Haruna
  (video and music).

### Up to date and more secure

- **Debian 13 "trixie"** with Debian's regular security updates.
- **A much newer Linux kernel** (6.6) than Gemian's.

### Battery & power

- **Accurate battery percentage** from the power chip's charge counter, kept
  across power-offs.
- **Real power off:** switched off, the Gemini stays off and keeps its charge.
- **Charging mode:** plug a charger into a switched-off Gemini and it shows
  the battery level and charging speed instead of booting. Hold Esc/On to
  start Debian, or unplug to switch off again.
- **Faster charging** and **low-battery protection** (warning, then a safe
  shutdown).

<img src="screenshots/charging-mode.png" alt="Charging mode: battery circle at 63 %, charging at 1.4 A" width="320">

### Made for the Gemini

- **Keyboard:** UK and US layouts, with all function keys.
- **Wi-Fi and Bluetooth** working (see the limitations below).
- **Sound** through the speaker and headphone jack.
- **All ten CPU cores** with automatic clock speeds and overheat protection.
- **First-boot setup:** create your own user account on the first start.

## Download and install

Downloads will appear on the
[releases page](https://github.com/atzandrew/gemini-debian/releases) once the
first beta is out. To install, follow the **[install guide](docs/install.md)**.
**Back up first:** the backup is your way back to Android and holds your
unit's own radio data.

## Known limitations

- **No suspend yet:** with the screen off the battery still drains in hours,
  not days. Switch it off when you're not using it.
- No automatic headphone or lid-close detection
  (switch outputs with `sudo gemini-audio speaker|headphone`).
- WPA3-only Wi-Fi networks don't work (WPA2 and mixed WPA2/WPA3 do).
- Only the stock Android-only partition layout is supported (no multi-boot).
- Kernel updates come as new boot images from this project, not through
  Debian's updates.

## To do

- Faster graphics (GPU clock scaling)
- Faster storage
- Faster CPU cores
- Much longer standby (deep sleep)
- Lower power use with the screen off
- Headphone and lid-close detection
- Support for multi-boot partition layouts

## Credits

This port stands on [cjdell/gemini-nixos](https://github.com/cjdell/gemini-nixos):
the mainline kernel bring-up, device tree, drivers, and most of the device
scripts and hardware research reused here (each copied file names its
gemini-nixos source). Thank you!

The temperature sensor driver and the display pipeline notes build on
[ixoo/gemini-pda-mainline](https://github.com/ixoo/gemini-pda-mainline)'s
careful MT6797 research. Vendor behaviour was checked against Gemian's
[gemini-linux-kernel-3.18](https://github.com/gemian/gemini-linux-kernel-3.18).

The charging screen uses the [Nunito](https://github.com/googlefonts/nunito)
font (SIL Open Font License 1.1) and [stb](https://github.com/nothings/stb)
(public domain). First-boot setup uses [Calamares](https://calamares.io).

## For developers

This repo builds the Debian root filesystem; the kernel, device tree and boot
image come from the [atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos)
fork (what it changes: [docs/changes.md](docs/changes.md)).

- Build and flash: [docs/flashing.md](docs/flashing.md)
- Update a running Gemini without reflashing: [docs/updating.md](docs/updating.md)
- Test checklist for a new image: [docs/beta-test.md](docs/beta-test.md)
