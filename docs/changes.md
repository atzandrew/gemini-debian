# Kernel and device changes (gemini-nixos fork)

Debian for the Gemini gets its kernel, device tree, boot image and device
scripts from [atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos),
a fork of [cjdell/gemini-nixos](https://github.com/cjdell/gemini-nixos). This
page lists what the fork adds. It moved here from the README on 2026-10-09.

What [atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos) adds
on top of cjdell's work (kernel source changes live in
[`devices/planet-geminipda/kernel/delta/`](https://github.com/atzandrew/gemini-nixos/tree/main/devices/planet-geminipda/kernel/delta)):

- **Kernel 6.6 → 6.6.157 stable rebase**
  ([567ed73](https://github.com/atzandrew/gemini-nixos/commit/567ed73)); config adds exFAT + NLS_UTF8
  ([d343495](https://github.com/atzandrew/gemini-nixos/commit/d343495)).
- **Display:** the scanout driver
  [`geminipda-drm.c`](https://github.com/atzandrew/gemini-nixos/blob/main/devices/planet-geminipda/kernel/delta/drivers/gpu/drm/tiny/geminipda-drm.c)
  copies each frame in a single pass and syncs the CPU cache only for the damaged area
  ([e90dd06](https://github.com/atzandrew/gemini-nixos/commit/e90dd06)), with a software vblank at `refresh_hz`, default 60
  ([064cda8](https://github.com/atzandrew/gemini-nixos/commit/064cda8)).
  Since 2026-10-07 it uses the display engine's real frame interrupt as vblank
  and starts each copy at the start of the panel's blanking period, which
  removes tearing ("vsync1"; [docs/display.md](https://github.com/atzandrew/gemini-nixos/blob/main/docs/display.md)).
  Screen off also switches the backlight off.
- **CPU clocks:** frequency scaling for all three MT6797 clusters with mainline
  `mediatek-cpufreq` (new clock and SRAM-regulator drivers,
  [2f20db6](https://github.com/atzandrew/gemini-nixos/commit/2f20db6)); the A72
  cluster is powered on by the kernel at boot
  ([c028f86](https://github.com/atzandrew/gemini-nixos/commit/c028f86)) and clocked
  through the firmware's frequency call
  ([929fd27](https://github.com/atzandrew/gemini-nixos/commit/929fd27)).
  Details: [docs/cpu-dvfs.md](https://github.com/atzandrew/gemini-nixos/blob/main/docs/cpu-dvfs.md).
- **Thermal:** the MT6797 SoC temperature sensor with factory calibration,
  cooling maps and trip points
  ([6225e23](https://github.com/atzandrew/gemini-nixos/commit/6225e23);
  [docs/thermal.md](https://github.com/atzandrew/gemini-nixos/blob/main/docs/thermal.md)).
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
- **eMMC HS200** at 192 MHz for the MT6797
  ([196af1d](https://github.com/atzandrew/gemini-nixos/commit/196af1d); final soak pending).
- **Config:** FUSE ([4645cba](https://github.com/atzandrew/gemini-nixos/commit/4645cba))
  and UHID/HIDRAW/UINPUT for Bluetooth LE input devices
  ([01425eb](https://github.com/atzandrew/gemini-nixos/commit/01425eb)).
- **Groundwork before the rebase** ([6724b54](https://github.com/atzandrew/gemini-nixos/commit/6724b54)): charger driver,
  device tree, initrd and greeter changes.

