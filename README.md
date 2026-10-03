# gemini-debian

Debian 13 (trixie) for the Planet Gemini PDA (MT6797X), built on Hydra and
flashed to the `userdata` partition, replacing NixOS.

The kernel, device tree and boot image come from the sibling
[gemini-nixos](../gemini-nixos) repo, which stays the single source for them.
This repo builds only the Debian root filesystem.

- **Plan and status:** [docs/plan.md](docs/plan.md)
- **Build + flash + first boot:** [docs/flashing.md](docs/flashing.md)

## Layout

| Path | What |
|---|---|
| `config.env` | user, hostname, timezone, locale, Debian suite, expected kernel |
| `packages/base.list` | Debian packages in the image |
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
