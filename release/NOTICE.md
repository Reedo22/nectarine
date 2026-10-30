# Nectarine — third-party components and licences

Nectarine is free and non-commercial. It bundles the components below. Licence texts ship inside the
engine (`share/licenses/`, `lib/external/D3DMetal.framework/Versions/A/Resources/LICENSE`) and in the
upstream projects linked here. Corresponding source for every LGPL/GPL component is published with
each release (see "Source" below); if anything is missing, open an issue and it will be provided.

| Component | Version | Licence | Source |
|---|---|---|---|
| Wine (Valve's Proton branch) + Nectarine patches | `experimental-wine-bleeding-edge-11.0-455321-20261021` + 57 commits | LGPL-2.1-or-later | release asset `nectarine-wine-source-<version>.tar.xz` (exact tree the engine was built from); patches in `patches/` |
| DXMT (Direct3D 10/11 on Metal) | 3Shain/dxmt `a148782d` + `patches/dxmt` | LGPL-2.1-or-later | https://github.com/3Shain/dxmt + `patches/dxmt/` |
| DXVK (Direct3D 9/10/11 on Vulkan) | 1.10.3 + `patches/dxvk-*.patch` | zlib/libpng | https://github.com/doitsujin/dxvk + patches |
| MoltenVK + SPIRV-Cross (Vulkan on Metal) | patched, `patches/moltenvk-*`, `patches/spirv-cross-*` | Apache-2.0 | https://github.com/KhronosGroup/MoltenVK |
| D3DMetal (Apple Game Porting Toolkit) | 4.0 beta 3 redistributable | Apple's licence (redistribution for non-commercial use only) | not open source; https://developer.apple.com/games/game-porting-toolkit/ |
| FFmpeg | 7.1.3, LGPL-only configuration | LGPL-2.1-or-later | `share/licenses/ffmpeg/` (full source tarball and build script included) |
| GStreamer + plugins | 1.28.8 SDK | LGPL-2.1-or-later (per-library texts in `share/licenses/gstreamer-sdk/`) | https://gstreamer.freedesktop.org/src/ |
| libinotify-kqueue | — | MIT | https://github.com/libinotify-kqueue/libinotify-kqueue |
| Runtime libraries (FreeType, GnuTLS, Nettle, GMP, libxml2, libxslt, ICU, SDL2, libpcap, zstd, lz4, brotli, …) | as bundled in `lib/` | their own (FreeType FTL/GPLv2, GnuTLS/Nettle/GMP LGPL, ICU Unicode, SDL2 zlib, others BSD/MIT) | upstream projects |

Nectarine's own code (launcher, installer, crash collector, tools) is under the licence in the
repository's `LICENSE`.

Nectarine is not affiliated with Valve, Apple, CodeWeavers or Microsoft. Steam is a trademark of Valve
Corporation. Nectarine does not ship Steam: the installer downloads Valve's Windows Steam installer
from Valve's servers.
