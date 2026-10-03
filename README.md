# gemini-debian

Debian 13 (trixie) for the Planet Gemini PDA (MT6797X), built on Hydra and
flashed to the `userdata` partition, replacing NixOS.

This repo builds only the Debian root filesystem. The kernel, device tree
and boot image come from
[atzandrew/gemini-nixos](https://github.com/atzandrew/gemini-nixos) (a fork
of cjdell's project, with a 6.6.157 rebase and audio/display fixes), checked
out next to this repo as `../gemini-nixos` (`GEMINI_NIXOS_DIR` in
`config.env`). Flash its boot image first; the rootfs must match its kernel
version (`EXPECT_KVER`).

> **AI-generated work.** Most of this repo, and most of the gemini-nixos fork
> changes listed below (kernel rebase, driver fixes, build scripts, docs), was
> written by Claude (Anthropic's AI coding agent), directed and tested on a real device by a
> human. Treat it accordingly: read the code before you trust it, expect
> mistakes, and flash at your own risk.

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
- **Audio:** the mt6797 AFE again registers its sub-DAI widgets and routes
  ([f4c9f84](https://github.com/atzandrew/gemini-nixos/commit/f4c9f84)).
- **Keyboard:** `matrix_keypad` polls at a runtime `poll_ms` (default 20 ms)
  instead of fast device-tree polling ([0f076a2](https://github.com/atzandrew/gemini-nixos/commit/0f076a2),
  [6488c32](https://github.com/atzandrew/gemini-nixos/commit/6488c32)); zram built in.
- **Groundwork before the rebase** ([6724b54](https://github.com/atzandrew/gemini-nixos/commit/6724b54)): charger driver,
  device tree, initrd and greeter changes.

## Credit

This port stands on [cjdell/gemini-nixos](https://github.com/cjdell/gemini-nixos):
the mainline kernel bring-up, device tree, drivers, and most of the device
scripts and hardware research reused here (each copied file names its
gemini-nixos source). Thank you!

## Status

Working on Debian 13 + KDE Plasma (Wayland) or labwc: GPU (panfrost, patched
Mesa), Wi-Fi, Bluetooth, keyboard (US/UK), touch + rotation, battery/charger,
sound (speakers + jack; `sudo gemini-audio speaker|headphone|toggle`). Not yet:
headphone jack detection, suspend, CPU frequency scaling. Details:
[docs/plan.md](docs/plan.md).

- **Plan and status:** [docs/plan.md](docs/plan.md)
- **Build + flash + first boot:** [docs/flashing.md](docs/flashing.md)
- **Update a running Gemini (no reflash):** [docs/updating.md](docs/updating.md)

## Layout

| Path | What |
|---|---|
| `config.env` | user, hostname, timezone, locale, Debian suite, expected kernel |
| `packages/base.list`, `packages/extra.list` | Debian packages in the image (extra = also shipped in the update bundle) |
| `overlay/` | files copied as-is into the rootfs (owned by root) |
| `bin/build-rootfs.sh` | entry point (run on Hydra as your user) |
| `bin/in-container.sh` | mmdebstrap + ext4 packing, inside a debian:trixie podman container |
| `bin/customize.sh` | modules/firmware, user, locale, services, boot-handoff checks |
| `build/`, `out/` | scratch and output (git-ignored) |

## Build

```sh
cd ~/Build/gemini-debian
bash bin/build-rootfs.sh        # -> out/gemini-debian-rootfs.img
```

Needs: `nix` (to build gemini-nixos for modules/firmware), `podman`,
`openssl`, sudo for podman. Internet access for deb.debian.org.
