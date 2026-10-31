# Nectarine

**Windows Steam and Windows games on Apple Silicon Macs. Free, non-commercial, open source.**

Nectarine is a Wine engine built from Valve's Proton branch and tuned for macOS. It runs the
Windows Steam client and its games under Rosetta 2. DirectX 10/11/12 runs on Apple's D3DMetal;
if a game faults there, Nectarine switches it to DXMT and then DXVK on its next launch, with no
setting to change.

> **Alpha.** Tested on one machine: M1 Pro (14-core GPU), 16 GB RAM, macOS 27.0.1. Expect rough edges and
> please report what you find.

## Install

Requirements: Apple Silicon Mac (M1 or later), **macOS 26 or later**,
16 GB RAM recommended, about 8 GB free disk space plus your games.

```sh
curl -fsSL https://raw.githubusercontent.com/Reedo22/nectarine/main/release/install.sh | bash
```

The installer downloads the engine (from this repository's releases) and Valve's Windows Steam
installer (from Valve). It sets everything up in `~/Library/Application Support/Nectarine` and
creates **Nectarine Steam** in `~/Applications`. It needs no administrator rights, except to install
Rosetta 2 if it is missing. Open Nectarine Steam, sign in, and install games as you would on Windows.

Uninstall: `rm -rf ~/Library/Application\ Support/Nectarine ~/Applications/Nectarine\ Steam.app`

## What's in the engine

- **Graphics:** a backend is chosen for each process. D3D10/11/12 games use Apple's D3DMetal,
  with DLSS answered by MetalFX. If a game faults there, its next launch uses DXMT, then DXVK.
  D3D9 and older use DXVK or wined3d. OpenGL uses Apple's GL. Vulkan uses a patched MoltenVK.
- **Video cutscenes:** Media Foundation and DirectShow go through bundled GStreamer + FFmpeg
  (LGPL builds), covering H.264, VP8/9, MPEG, WMV/VC-1, AAC, MP3, Vorbis and Opus.
- **macOS fixes in Wine**, all general rather than per game:
  - sockets that hung or lost data on macOS (multiplayer);
  - an audio start-up hang caused by unresponsive microphones;
  - Steam's window drawing;
  - msync (fast synchronisation primitives);
  - file-change notifications.
- **Protection and diagnostics:**
  - a GPU-fault guard that stops a misbehaving game before macOS's GPU watchdog can freeze the
    desktop;
  - a crash collector: every crash produces a report with a Wine backtrace, the macOS crash
    report and system details. Run `nectarine crashes`.

## Compatibility (automated smoke test, 2026-10-29)

Each game was launched from Steam on the alpha engine and run for two minutes. "Renders" means a
frame was captured from the game's GPU output. This is a smoke test, not a play-through.

| Game | Engine / API | Result |
|---|---|---|
| Besiege | Unity | Renders |
| FTL: Faster Than Light | OpenGL | Renders |
| Gang Beasts | Unity | Renders |
| Half-Life | GoldSrc OpenGL, 32-bit | Renders |
| Lethal Company | Unity D3D11 | Renders (dark menu, 4% non-black) |
| My Summer Car | Unity (old) | Renders |
| Poly Bridge 2 | Unity | Renders |
| Raft | Unity | Renders |
| Sonic Mania | D3D9 | Renders |
| The Henry Stickmin Collection | Unity | Renders |
| The Long Drive | Unity | Renders |
| The Stanley Parable: Ultra Deluxe | Unity | Launches; captured frame was black, to be checked |
| Totally Accurate Battle Simulator | Unity | Renders |
| Undertale | GameMaker, D3D9 32-bit | Renders |
| Fallout, Fallout 2 | DirectDraw, 32-bit | Launches (launcher window; frame capture does not see GDI) |
| Fallout 3, Fallout: New Vegas | Gamebryo D3D9, 32-bit | Launches (launcher window) |
| Portal | Source D3D9 | Launches; no frame captured, to be checked |

Sweep, also launched from Steam with two-minute runs: Half-Life: Opposing Force, Half-Life: Blue Shift,
Half-Life 2: Lost Coast, Half-Life 2: Deathmatch, Half-Life Deathmatch: Source, FAITH: The Unholy Trinity,
Aviassembly, Stardeus and From the Depths all render. Fallout Tactics launches (launcher window).

Earlier, longer sessions on the same machine: Satisfactory (UE5, D3D11, ~47 fps at medium),
ULTRAKILL, Dyson Sphere Program, DOOM 64 and GravityMark. The sweep continues, and more results will be added.

**Known broken:** native Vulkan games (for example DOOM 2016, or Source games started with `-vulkan`) stall after
creating their window. Vulkan through DXVK works. Under investigation.

**Won't work:** games with kernel-level anti-cheat (Easy Anti-Cheat in kernel mode, BattlEye,
Vanguard, …).

## Known issues

- Tested on macOS 27 only. Since 0.1.1 the engine is built for macOS 26, but no macOS 26 machine has run it yet. Reports welcome.
- Steam's own interface uses about one CPU core while it is in the foreground. Minimise Steam
  while you play.
- Settings → Storage → Add Drive in Steam opens a file picker instead of a folder picker.
- Performance depends on the GPU. On an M1 Pro, most D3D11 games are GPU-bound. See
  [docs/TECHNICAL.md](docs/TECHNICAL.md) for measurements.

## Documentation

- [docs/RESULTS.md](docs/RESULTS.md): performance, backend correctness and Wine conformance measurements
- [docs/TECHNICAL.md](docs/TECHNICAL.md): earlier technical notes (MoltenVK/DXVK patches, msync)
- [patches/](patches/): every change to Wine, DXMT, DXVK, MoltenVK and SPIRV-Cross

## Reporting problems

Open an issue with the game name, your Mac (chip, memory, macOS version) and what happened. If
Nectarine saved a crash report (`nectarine crashes`), paste its `report.md`. It has already been
stripped of your username and home path.

## Related projects

[NotProton](https://github.com/NotProtonNot/NotProton) and
[Bridgeplay](https://github.com/raymondchins/Bridgeplay) take a different approach. They run
Windows games from the *native* Mac Steam client, on CodeWeavers' Wine. Nectarine's engine work is
meant to be useful there too: packaging it as a Steam Play compatibility tool is the next step.
If you can, support [CodeWeavers](https://www.codeweavers.com/crossover), who do most of the work
on Wine for macOS.

## Licence

Nectarine's own code is under the MIT licence ([LICENSE](LICENSE)). Bundled components keep their
own licences. See [release/NOTICE.md](release/NOTICE.md), which also lists where each component's
source is.
Nectarine is not affiliated with Valve, Apple, CodeWeavers or Microsoft.
