# rocknix-turnip

**glibc-ARM64 Mesa Turnip (Vulkan) driver catalogue** for the **GPU Driver
Manager** in [DUCKTALE](https://github.com/aanze/distribution) (a personal
ROCKNIX fork for the AYN Odin 3 / Adreno 830).

On the device you swap the Turnip driver **per game/emulator** (RPCS3, Citron, …)
or globally — from **Perf Control → DRIVER** or the Steam/Decky panel — and
download drivers from here, **without rebuilding the OS**.

## The catalogue (release `catalog`)

The [`catalog`](../../releases/tag/catalog) release holds the drivers as raw
`libvulkan_freedreno-*.so` assets plus a `manifest.json`. The on-device
`/usr/bin/gpu-driver` CLI fetches `manifest.json`, then downloads + SHA-256-
verifies + dlopen-probes a driver before installing it. The manifest is
cumulative (publishing one driver never drops the others).

> ⚠️ These are **glibc / ARM64** builds for ROCKNIX (upstream MSM/DRM). They are
> **not** the Android/bionic AdrenoTools `.so` (those won't load here). When a
> community build is useful, we rebuild its **Mesa source** for glibc.

## Building & publishing drivers — [`builder/`](builder/)

The tools that build and publish the catalogue. They run on the **ROCKNIX build
host** (they reuse the warm ROCKNIX toolchain so the driver ABI matches the
image); the build engine itself is `packages/tools/gpu-driver/ci/build-turnip-catalog.sh`
in the [distribution repo](https://github.com/aanze/distribution/tree/aanze-next/projects/ROCKNIX/packages/tools/gpu-driver/ci).

- **`turnip-catalog.bat`** — 1-click (Windows→WSL): build + publish a plain
  version, e.g. `turnip-catalog.bat stable:26.2.0`, or a mesa-git snapshot.
- **`turnip-builder.bat`** — guided builder: pick a base, cherry-pick GitLab MRs
  or a contributor fork branch, or **search a published driver by name** (e.g.
  “Gen8 V30”) and it resolves + rebuilds that Mesa source for glibc.
- `catalog-sources.txt` / `turnip-forks.txt` / `turnip-android-repos.txt` — the
  editable source lists. Full walkthrough in [`builder/TURNIP-BUILDER.md`](builder/TURNIP-BUILDER.md).

## Credits

Turnip is [Mesa](https://gitlab.freedesktop.org/mesa/mesa). Community a8xx/Adreno
work by contributors such as **whitebelyash**, **mrpurple666**, **StevenMXZ** and
others — this repo just rebuilds their source for glibc/ROCKNIX.
