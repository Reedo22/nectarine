# Measurements

These are summaries of the testing behind the 0.1.0 alpha. All of it was run on one machine: M1 Pro
with a 14-core GPU, 16 GB RAM and macOS 27.0.1. The comparison runs used Proton on Linux
(RTX 4080). Raw logs are not published. They contain machine-specific detail and add little beyond
these tables.

## 1. Graphics backends: performance

Each game was run on the same scene and settings on each backend. FPS and GPU time come from the
Metal HUD over the final 20 s of each run.

| Game | Resolution | Native Metal | DXVK (Vulkan→Metal) | D3DMetal |
|---|---:|---:|---:|---:|
| Poly Bridge 2 | 1280×720 | 59.6 fps | 29.9 fps | **69.0 fps** |
| Gang Beasts | 1920×1080 | — | 37.6 fps | **60.0 fps** (vsync) |
| The Long Drive | 1920×1080 | — | 5.6 fps | **59.9 fps** |

- D3DMetal is 1.6× to 10× faster than DXVK across the tested Unity games. That's why D3D10/11/12 run on
  D3DMetal first.
- DXMT is about 33% faster than DXVK in GravityMark D3D11. It is the first fallback when a game faults
  on D3DMetal.
- GravityMark (native Metal build vs Windows build): native 59 fps; DXVK + our MoltenVK patches 48 fps.
- Satisfactory (UE5, D3D11, medium): about 47 fps, GPU-bound (99–100% utilisation). Its D3D12 path is
  slower, because UE5 turns on Nanite and virtual shadow maps there.

## 2. Graphics backends: correctness

Wine's own D3D9/10/11/12 test suites and vkd3d-proton's D3D12 suite were run once per backend, each
test routine in its own process. One crash therefore can't hide the rest.

| API suite | Backend | Pass | Fail | Crash/timeout |
|---|---|---:|---:|---:|
| d3d9 (wine) | wined3d | 389,596 | 43 | 0 |
| d3d9 (wine) | DXVK | 347,057 | 18,931 | 12 |
| d3d11 (wine) | DXVK | 4,476,067 | 5,299 | 15 |
| d3d11 (wine) | D3DMetal | 514,212 | 5,407 | 33 |
| d3d11 (wine) | DXMT | 175,251 | 10,495 | 22 |
| d3d12 (vkd3d-proton) | D3DMetal | 43,357,486 | 290,073 | 26 |
| d3d12 (vkd3d-proton) | vkd3d + MoltenVK | 24,537,240 | 122,485 | 43 |
| d3d11 (wine), Linux reference | Proton | 4,485,106 | 4,141 | 9 |

Lower pass totals mostly mean coverage the backend doesn't advertise. They aren't defects. The main
defects found, in priority order:
1. DXVK D3D9: the RESZ depth resolve loses the Vulkan device. wined3d and Linux are fine.
2. DXMT: cube-map array sampling returns the wrong slice.
3. DXVK D3D9: signed texture formats produce wrong pixels.
4. D3D12 indirect execution leaves incorrect command state, on both D3DMetal and vkd3d.
5. D3D12 depth readback / multisample resolve formats are wrong.
6. D3DMetal returns stale data after tiled-resource remapping.
7. Rasterizer-ordered views produce wrong pixels.
8. DXVK D3D11 logic operations render incorrectly.
9. D3DMetal violates CPU-signalled fence waits.

## 3. Wine conformance: Mac vs Linux

These are Wine's own test groups for the APIs that games use most, ranked by how many games in a
67-game sample import each DLL.

| Area | Before | After | Linux reference |
|---|---|---|---|
| ws2_32 `sock` (networking) | hung (timeout) | 2.67M pass / 170 fail, no hang | 2.68M pass / 1 fail |
| ws2_32 `protocol` | timeout, 32 fail | 8,286 pass / 0 fail | — |
| ws2_32 `afd` | 12 fail | 10–13 fail | 0 fail |
| kernel32 `change` (file notifications) | 82 fail | 1 fail | 0 fail |

What we fixed, as general macOS fixes to Wine in `patches/`:
- **Sockets:**
  - send/recv on an unconnected TCP socket waited forever;
  - recv into write-watched memory lost TCP data, because macOS dequeues the data before
    copying it;
  - reconnecting after a refused connect failed forever, because the macOS socket stays unusable.
- **Audio:** start-up hung because an unresponsive microphone hung CoreAudio.
- **File-change notifications:** inotify, provided through kqueue.

Still open: Mac-only crashes in some kernel32/user32 test groups, and socket options or
out-of-band data behaviour that macOS lacks.

## 4. Media (cutscenes)

Media Foundation, DirectShow and Windows Media Format probes (H.264 MP4, WMV, audio formats) all failed
or hung before the codec work. They all pass with the bundled GStreamer + LGPL FFmpeg runtime.

## 5. Game smoke test

See the compatibility table in the [README](../README.md). A sweep of about 90 games covering most
engines and APIs is running, and its results will be added here.

## 6. Where the CPU goes (Rosetta + Wine)

Measured with `tools/perf/` (per-thread CPU time joined to `sample` stacks) on the alpha engine:

| Game (scene) | fps | GPU busy | What is busy |
|---|---:|---:|---|
| Poly Bridge 2 (D3D11 → D3DMetal, 1280×720) | 130–183 | ~75% | Main thread ~0.7 core, render thread ~0.3. Busy-thread time is mostly Apple framework/driver code (78%) plus D3DMetal (22%). Neither CPU nor GPU is saturated, so the limit is CPU↔GPU hand-off. |
| Portal (D3D9 → wined3d → OpenGL, menu) | 42 | 25% | Three threads at 70–100%. Busy time: ~65% translated game and Windows code, ~20% Wine's native side, ~14% Apple frameworks. The clearest CPU bottleneck. |

- **Spin loops:** wined3d's command thread, Wine's audio timer and Unity's job workers busy-yield. Each yield
  is a translated syscall.
- **Window compositing:** macOS's WindowServer spends ~0.4–0.5 core compositing a windowed game.
- **DirectSound mixing:** costs ~0.2 core in Portal.

## 7. QueryPerformanceCounter was a syscall (fixed in 0.1.1)

About 70% of all Wine syscalls in Poly Bridge 2 (~90,000/s) were `QueryPerformanceCounter`. Under Rosetta,
x86's `rdtsc` returns exactly `mach_continuous_time()` in nanoseconds, the clock Wine's syscall reports in
100 ns units (0 ns difference over 1 M bracketed reads). It costs 10 ns versus ~0.9 µs for a Wine syscall.
Patch 0006 reads it in user mode, after a self-check that the two clocks agree. Syscalls dropped from 128,000/s
to 52,000/s. Frame rate was within noise for this game, whose main thread isn't saturated; it saves CPU and power.
Upstream Wine has the same always-syscall implementation.

## 8. Hardware x86 memory ordering without Rosetta (research)

Rosetta runs translated code with the CPU's TSO (x86-style memory ordering) bit set by the kernel. That bit is
not available to ordinary processes, but Apple's public Hypervisor.framework lets a virtual CPU set it
(`HV_SYS_REG_ACTLR_EL1`, macOS 15+). See [research/hv-tso](../research/hv-tso/README.md):

- **It works and is shippable:** ad-hoc signed with the hypervisor entitlement. A message-passing litmus test
  gives 85–91 M reorderings per 200 M reads with TSO off, and 0 per 400 M with it on.
- **Hardware TSO costs 0–3%.** Software ordering (acquire/release on every access, a translator's fallback)
  costs +108–134% on memory-streaming loops.
- **Exits are affordable:** an exit from the virtual CPU costs 0.92 µs. After the QPC fix, a game makes
  ~52,000 Windows→native crossings per second, about 0.05 core of exits.
- **Limit:** 64 virtual CPUs per process.

This is the basis for a planned translator design: native ARM64 Wine and drivers, with x86 game code translated
and run inside TSO virtual CPUs. Rosetta's general availability ends after macOS 27.
