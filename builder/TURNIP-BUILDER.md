# Turnip driver catalogue — how to build & ship your own variants

Two tools, both 1-click from the Windows desktop. Both build glibc-ARM64 Turnip
in the ROCKNIX toolchain and publish to your catalogue repo
**`aanze/rocknix-turnip`** (release tag `catalog`). Your Odin 3 fetches that
catalogue from **Perf Control → DRIVER → Refresh catalog** (or the Decky GPU
Driver section).

| Tool | Use it when |
|------|-------------|
| **`turnip-catalog.bat`** | you just want a plain Mesa version (a release tag, or latest mesa-git) |
| **`turnip-builder.bat`** | you want a *patched* variant: a base + cherry-picked Merge Requests + local patches (the KIMCHI / Mr.Turnip workflow) |

> KEY POINT: publishing a driver to the catalogue does **NOT** require reflashing
> the OS. You build it on the PC, it lands in the catalogue, and the device
> installs it over the network. You only reflash when changing the OS itself.

---

## 0. One-time prerequisites (already done on this machine)

- WSL Ubuntu with the ROCKNIX build tree at `/home/marc/src/rocknix`, toolchain
  already built (a normal `build.sh` run leaves it warm).
- `gh` authenticated as `aanze` (`gh auth status`).
- The repo `aanze/rocknix-turnip` exists (public).

---

## A. Plain version (no patches) — `turnip-catalog.bat`

1. Double-click `turnip-catalog.bat` with an argument, e.g.:
   - `turnip-catalog.bat stable:26.2.0`  → builds Mesa release 26.2.0
   - `turnip-catalog.bat git:origin/main:nightly` → builds the current mesa-git main
2. It builds (~2-5 min on a warm toolchain), then uploads `.so` + `manifest.json`
   to the `catalog` release.
3. No argument = rebuild every entry already listed in `catalog-sources.txt`.

The argument is also appended to `catalog-sources.txt`, so it stays in the set
for future rebuilds.

---

## B. Patched variant — `turnip-builder.bat` (guided)

Double-click `turnip-builder.bat`. First run clones Mesa (partial clone,
~1-2 min); later runs just fetch updates. Then it asks **what to build**:

```
1) A contributor's branch, as-is   (pick a fork & search its branches)
2) Find a driver by NAME across published repos   (e.g. 'Gen8 V30')
3) Official Mesa release (a stable tag)
4) Latest mesa-git (main, bleeding edge)
5) Advanced: a base + cherry-pick MRs / fork branches / patches
```

**Mode 1 — a contributor's branch, as-is (the common case).** Pick a **fork**
from `turnip-forks.txt` (Official Mesa, mrpurple666, **whitebelyash mesa (gen8)**,
**StevenMXZ mesa-tu8**, …) or `c` for a custom URL, **search its branches by
keyword** (`gen8`, `a830`, a game name), pick one → it's built **as-is** for
glibc. This reproduces a driver someone published (e.g. whitebelyash's
`turnip/gen8` = their "Turnip Gen8" releases).

**Mode 2 — find a driver by NAME (when you don't know the author).** Type a name
like `Gen8 V30` or `a830`. It searches the published **driver-release repos**
(`turnip-android-repos.txt`: StevenMXZ, whitebelyash, …), and — because those
release notes say `build from: <git>/tree/<branch>` — resolves the **Mesa source**
behind each match and builds THAT for glibc. (Those repos themselves ship Android
`.so` that can't run on ROCKNIX; we rebuild their source instead.) If a release
doesn't state its source, pick a newer one of the same driver (they usually do),
or use mode 1 on the fork.

**Mode 3 — official stable.** Pick a `mesa-XX.Y.Z` tag → fast build.

**Mode 4 — latest mesa-git main.** Bleeding edge, where a830 fixes land first.

**Mode 5 — advanced compose.** Pick a base, then layer on top: *MRs* by number,
*fork branches* (pick+search, cherry-picked), local `.patch` files.

**Then:** name it (a sensible id is proposed), confirm, and it builds in the
ROCKNIX toolchain and uploads to the `catalog` release. If a cherry-pick/patch
doesn't apply cleanly it stops and says which one — pick a closer base (usually
latest mesa-git) and retry.

> whitebelyash's freedesktop fork URL is a placeholder in `turnip-forks.txt`
> (the guessed one 404s) — add their real fork URL there to see it in the picker.

---

## C. Get it onto the device (no reflash)

On the Odin 3:
1. **Perf Control** (Main Menu → System Settings → Performance) → **DRIVER** tab
   (or the Decky **GPU Driver** section in Steam).
2. Press **X — Refresh catalog**. Your new build appears, tagged `[catalog]`.
3. Highlight it, press **A** — it downloads, checksum-verifies, dlopen-probes,
   and installs.
4. Assign it:
   - **L/R** to pick the **scope**: `Default (all games)`, `RPCS3 (ps3)`,
     `Citron (switch)`, `PCSX2 (ps2)`, `Cemu (wiiu)`, `Dolphin`…
   - **A** to assign the highlighted driver to that scope.
   - **Select** clears a per-system override (back to default).
   - **Y** marks a favourite.

Launch RPCS3 / Citron / etc. → it runs on the driver you pinned. The compositor
always stays on the stock driver, so a bad experimental build only crashes that
game, never the UI; and the boot guard reverts the *default* to stock if it ever
fails to load after an update.

---

## D. Files (all under `~/scripts/rocknix-aanze/`, i.e. `\\wsl$\Ubuntu\home\marc\scripts\rocknix-aanze\`)

| File | Role |
|------|------|
| `turnip-catalog.bat` / `turnip-builder.bat` | the Windows launchers (also on the Desktop) |
| `catalog-sources.txt` | the plain-version source list |
| `turnip-builder.sh` | the guided builder (clone/cherry-pick/patch/build) |
| `publish-turnip-catalog.sh` | wrapper for the plain flow |
| `.mesa-src/` | cached Mesa clone (created on first builder run) |
| `.turnip-build/` | prepared patched source tarballs |

The actual build/publish engine lives in the repo at
`projects/ROCKNIX/packages/tools/gpu-driver/ci/build-turnip-catalog.sh`
(specs: `stable:<tag>`, `git:<ref>[:<label>]`, `local:<.so>`, `src:<label>:<tarball>`).

Repo + URL are configured there and in `/usr/bin/gpu-driver`
(`GPU_DRIVER_MANIFEST_URL`). Override the publish target any time with
`--repo owner/name`.

---

## KGSL vs DRM — which branch to pick

ROCKNIX uses the **upstream MSM/DRM** GPU driver, **not KGSL** (the Android kernel
GPU interface). So when a fork has both:
- branches/patches with **`kgsl`** or **`hacks`** in the name → **Android-only, skip them** (inert at best, broken at worst on ROCKNIX).
- **`clean`** / plain DRM branches (e.g. `gen8-clean`) → **use these**.

Example: whitebelyash's "Mesa 26.1 KGSL hacks" release is `gen8-clean` + KGSL
patches (git am). On ROCKNIX you want **`gen8-clean` as-is** — not the KGSL
patches. The builder prints this reminder at the branch picker.

## Following the build live

Every build (either tool) mirrors its output to a fixed log, like `build.sh`
does. Follow it from any shell while the `.bat` runs:

```
wsl tail -f /tmp/turnip-build.log        # from a Windows cmd/PowerShell
tail -f /tmp/turnip-build.log            # from inside WSL
```

## E. Troubleshooting

- **"MR does not apply cleanly"** → choose *Latest mesa-git (main)* as the base;
  most open MRs are written against main.
- **Build fails** → run once with the toolchain warm (do a normal `build.sh`
  first); read the tail it prints.
- **Device says catalogue empty / offline** → it needs network for *Refresh*;
  the stock driver always works offline regardless.
- **gh not authenticated** → `gh auth login` in WSL, or run with `--no-publish`
  to build without uploading (artifacts left in a temp dir).
