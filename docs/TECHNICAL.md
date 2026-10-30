# Nectarine — technical notes (September 2026)

> Early measurements and patch notes from the DXVK + MoltenVK stage of the project (macOS 15). The
> current engine and results are described in the [README](../README.md) and [RESULTS.md](RESULTS.md).

Running Windows games on Apple Silicon with a **free, open stack** — Wine + msync + DXVK
+ a patched MoltenVK — on a MacBook Pro (M1 Pro) that was never meant for gaming.

Tested on macOS 15.1.1, Apple M1 Pro. Everything here is x86-64 Wine under Rosetta 2.

## Contents

- `patches/moltenvk-nectarine.patch` — MoltenVK patches, all **opt-in via environment
  variables** so the honest Vulkan path is unchanged. Includes `MVK_X_FAKE_DEPTH_BOUNDS`
  (without it DOOM 2016 will not create a device at all), `MVK_X_DXVK_FEATURES`
  (D3D11 feature levels 11_0/11_1), `MVK_X_KEEP_COMPUTE_ENCODER` and
  `MVK_X_FAST_TRANSCENDENTALS` (see Benchmark), `MVK_X_PASSSTATS` (tile load/store
  accounting) and `MVK_X_LABEL_ENCODERS` (makes GPU traces attributable).
- `patches/spirv-cross-nectarine.patch` — the SPIRV-Cross half of `MVK_X_FAST_TRANSCENDENTALS`
  (applies inside MoltenVK's `External/SPIRV-Cross`).
- `patches/dxvk-discard-loads.patch` — optional, unvalidated (see Known issues).
- `launchers/` — `gsession.sh` (the one-job Steam+game launcher), `gpu-guard.sh`
  (bounded startup/runtime and GPU-fault guard), `gputrace.sh`
  (Metal System Trace), `shot.sh` (screenshot via launchd, for on-screen errors that
  never reach a log).
- `tools/` — `fps.py`, `gpujoin2.py` (attribute GPU time to named passes), `gpuunion.py`
  (GPU busy-union + encoder duration percentiles), `cbtimeline.py` (CPU→GPU command-buffer
  pipeline), `cpuprof.py` (Time Profiler by thread/binary), `gmwine.sh`/`gmstats.py`
  (GravityMark runner + stats), `syscost.c` (Win32 call cost under Rosetta), `d3d11probe.c`,
  `unityres.py`.
- `PROTON-COMPAT-ROADMAP.md` — compatibility-first inventory and staged Proton-parity plan.

## Benchmark: GravityMark (native Metal vs. this stack)

[GravityMark](https://gravitymark.tellusim.com/) is the yardstick because it ships a native
macOS **Metal** build *and* Windows D3D11/Vulkan builds of the identical scene, with a scored
167-second benchmark — so it measures distance from the hardware ceiling, not just fps.
M1 Pro (14-core GPU), 1920x1080, 200k asteroids, vsync off:

| path | score | fps | vs. native |
|---|---|---|---|
| native Metal build | 9896 | 59.2 | 100% |
| Wine + DXVK 1.10.3 + stock-behaviour MoltenVK | 5251 | 31.4 | 53% |
| + `MVK_X_KEEP_COMPUTE_ENCODER=1` | 6886 | 41.2 | 70% |
| + `MVK_X_FAST_TRANSCENDENTALS=1` | **7283** | **43.6** | **74%** |

For scale: on an RTX 4080 SUPER under Linux, the same D3D11 build through Proton/DXVK
reaches 75% of the native Vulkan build at 4K — so the stack is now at the relative
efficiency DXVK gets on a first-class Vulkan driver.

What the two new switches do (both in `patches/moltenvk-nectarine.patch` /
`patches/spirv-cross-nectarine.patch`, both opt-in):

- **`MVK_X_KEEP_COMPUTE_ENCODER`** — on macOS 15 with Metal argument buffers, MoltenVK ends the
  compute encoder on every `vkCmdPipelineBarrier`; DXVK emits one between every UAV dispatch,
  so each dispatch became its own Metal encoder (300+ per frame here). The patch defers the
  barrier (a serial compute encoder already orders its dispatches) and routes small buffer
  copies/updates through the open encoder instead of a blit encoder.
- **`MVK_X_FAST_TRANSCENDENTALS`** — SPIRV-Cross emits `precise::` rsqrt/exp2/log2/sin/cos/sqrt
  for every transcendental because DXVK's SPIR-V carries no fast-math flags, and `precise::`
  overrides MoltenVK's fast-math compile option. HLSL never guaranteed NaN preservation
  there, so the fast versions match D3D semantics.

Also learned along the way: GravityMark requests feature level 11_1 only, which DXVK gates on
`logicOp` + `variableMultisampleRate` (now covered by `MVK_X_DXVK_FEATURES`); Wine syscalls
cost ~0.9 µs under Rosetta and `QueryPerformanceCounter` is one of them (0.63 µs); the
per-frame call trace, GPU timeline and CPU profile tooling is in `tools/`.

## Known issues

- Building DXVK from source produces binaries that run our synthetic probe but **fail to
  host real games**. Unresolved, so `dxvk-discard-loads.patch` is unvalidated in practice.
- OpenGL titles are untested/unsupported.
- Source engine could not be evaluated (our Steam library had Linux depots only).
- Satisfactory's main-menu scene looked nearly black under D3D11; gameplay has not
  yet been visually checked. Auto-exposure and eye-adaptation defaults were restored
  for the next in-world test.
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
