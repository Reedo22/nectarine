# Nectarine

Running Windows games on Apple Silicon with a **free, open stack** — Wine + msync + DXVK
+ a patched MoltenVK — on a MacBook Pro (M1 Pro) that was never meant for gaming.

Tested on macOS 15.1.1, Apple M1 Pro. Everything here is x86-64 Wine under Rosetta 2.

## What it achieves

| game | engine / API | result |
|---|---|---|
| ULTRAKILL | Unity / DXVK D3D11 | **127–151 fps** @ 3440×1440 |
| DOOM 2016 | id Tech 6, native Vulkan | **52 fps** |
| ASTRONEER | UE4 / DXVK | **52 fps** |
| Doom 64 | KEX / Vulkan | ~60 fps (vsync-capped) |
| Dyson Sphere Program | Unity / DXVK | ~30 fps (tessellation-limited, see below) |
| Satisfactory | UE5 | runs, but the scene renders black |
| The Outer Worlds | UE4 | does not start |
| DOOM 3 BFG | id Tech 4, OpenGL | starts, never presents |

## The three findings worth your time

**1. msync is the big CPU win.** Stock Wine sends every kernel-object operation to the
wineserver over IPC — under Rosetta that costs ~13 µs per operation. msync (Mach
semaphores) cuts it to **0.83 µs, roughly 16×**. ULTRAKILL went from 47 to 151 fps.

*Trap:* msync registers the wineserver's port with **Mach bootstrap**, and bootstrap
names are per-namespace. Steam and the game must run as children of **one** launchd job,
or the game exits with status 1 and an empty log. A game launched over ssh can never join
a launchd-started wineserver. `launchers/gsession.sh` does this correctly.

**2. Tessellation is disproportionately expensive on Metal.** Metal has no tessellation
stage, so MoltenVK ends the render pass, runs tess control as a compute dispatch, and
restarts the pass — which on tile-based hardware means a full attachment store + reload.
In DSP that was **13% of all GPU time**, with ~80% of the cost being the restart rather
than the tessellation. **If a game exposes a tessellation setting, turn it off first.**
Note `d3d11.maxTessFactor` does *not* help — it caps the factor, not the restart.

**3. Per-game settings genuinely differ; there is no global config.** Metal argument
buffers are a win for ULTRAKILL, ASTRONEER and DOOM, and a disaster for DSP (1.7 fps with
them on, ~49 without). A per-game profile system is the right shape for this project.

## Contents

- `patches/moltenvk-nectarine.patch` — MoltenVK patches, all **opt-in via environment
  variables** so the honest Vulkan path is unchanged. Includes `MVK_X_FAKE_DEPTH_BOUNDS`
  (without it DOOM 2016 will not create a device at all), `MVK_X_DXVK_FEATURES`
  (D3D11 feature levels), `MVK_X_PASSSTATS` (tile load/store accounting) and
  `MVK_X_LABEL_ENCODERS` (makes GPU traces attributable).
- `patches/dxvk-discard-loads.patch` — optional, unvalidated (see Known issues).
- `launchers/` — `gsession.sh` (the one-job Steam+game launcher), `gputrace.sh`
  (Metal System Trace), `shot.sh` (screenshot via launchd, for on-screen errors that
  never reach a log).
- `tools/` — `fps.py`, `gpujoin2.py` (attribute GPU time to named passes),
  `d3d11probe.c` (deterministic render-pass benchmark), `syncbench.c` (Win32 sync
  microbenchmark), `unityres.py`.

## Measurement gotchas that will waste your day

- **MoltenVK's reported "avg FPS" is cumulative**, so a warming shader cache drags it up
  forever and makes any A/B look better the longer it runs. Use `tools/fps.py`.
- **Check `Execute a MTLCommandBuffer on GPU` against `Frame interval` before optimising
  anything CPU-side.** Several of our GPU-bound games were completely unaffected by CPU work.
- **`MVK_CONFIG_LOG_LEVEL` is 0 none / 1 error / 2 warning / 3 info** — below 3 silently
  hides the performance stats.
- **A Wine virtual desktop costs ~40%.** Useful to force a resolution, never for speed.
- GPU utilisation without Xcode: `ioreg -r -d 1 -w 0 -c AGXAccelerator | grep 'Device Utilization'`.

## Known issues

- Building DXVK from source produces binaries that run our synthetic probe but **fail to
  host real games**. Unresolved, so `dxvk-discard-loads.patch` is unvalidated in practice.
- OpenGL titles are untested/unsupported.
- Source engine could not be evaluated (our Steam library had Linux depots only).
- Satisfactory renders a black scene on both Vulkan and D3D11 — a lighting bug, not a
  backend issue.
- **Rosetta 2 has an end date.** Apple supports it fully through macOS 27; macOS 28 (2027)
  scopes it to legacy game support only. This whole stack depends on it.

## Credits and honesty

Built collaboratively with an LLM (Claude) over a series of long debugging sessions. The
measurements here are real — taken on the hardware described — but the project is an
enthusiast effort, not a polished product. Several conclusions in early drafts were wrong
and corrected by later measurement; expect rough edges.

Stands on the work of [Wine](https://winehq.org), [MoltenVK](https://github.com/KhronosGroup/MoltenVK),
[DXVK](https://github.com/doitsujin/dxvk), [Gcenx](https://github.com/Gcenx) (macOS Wine
and DXVK-macOS builds), and [marzent/wine-msync](https://github.com/marzent/wine-msync).
Wine and DXVK are LGPL; MoltenVK is Apache 2.0.
