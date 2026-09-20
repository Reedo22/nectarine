# Nectarine

Running Windows games on Apple Silicon with a **free, open stack** — Wine + msync + DXVK
+ a patched MoltenVK — on a MacBook Pro (M1 Pro) that was never meant for gaming.

Tested on macOS 15.1.1, Apple M1 Pro. Everything here is x86-64 Wine under Rosetta 2.

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

## Known issues

- Building DXVK from source produces binaries that run our synthetic probe but **fail to
  host real games**. Unresolved, so `dxvk-discard-loads.patch` is unvalidated in practice.
- OpenGL titles are untested/unsupported.
- Source engine could not be evaluated (our Steam library had Linux depots only).
- Satisfactory renders a black scene on both Vulkan and D3D11 — a lighting bug, not a
  backend issue.
- **Rosetta 2 has an end date.** Apple supports it fully through macOS 27; macOS 28 (2027)
  scopes it to legacy game support only. This whole stack depends on it.

## Credits

Built collaboratively with an LLM (Claude) over a series of long debugging sessions. The
measurements here are real — taken on the hardware described — but the project is an
enthusiast effort, not a polished product. Several conclusions in early drafts were wrong
and corrected by later measurement; expect rough edges.

Stands on the work of [Wine](https://winehq.org), [MoltenVK](https://github.com/KhronosGroup/MoltenVK),
[DXVK](https://github.com/doitsujin/dxvk), [Gcenx](https://github.com/Gcenx) (macOS Wine
and DXVK-macOS builds), and [marzent/wine-msync](https://github.com/marzent/wine-msync).
Wine and DXVK are LGPL; MoltenVK is Apache 2.0.
