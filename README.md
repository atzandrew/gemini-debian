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
