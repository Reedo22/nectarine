#!/bin/bash
# Run after build-ffmpeg.mac.sh. Uses APFS clones, never edits unified/live files.
# Prerequisites: matching GStreamer 1.28.8 runtime (with libav/ASF), expanded
# official development SDK (pkgutil --expand-full), and the existing unified build.
set -euo pipefail
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
src="$HOME/protonbuild/wine-codec"
build="$HOME/protonbuild/build-codec"
engine="$HOME/protonwine-codec"
ffmpeg=${FFMPEG_PREFIX:-$HOME/nectarine-deps/ffmpeg}
runtime=${GST_RUNTIME:-$HOME/nectarine-deps/gstreamer-codec}
sdk=${GST_SDK:-$HOME/nectarine-deps/gst-sdk/expanded}
gst="$engine/lib/gstreamer/GStreamer.framework/Versions/1.0"
df -h "$HOME"
for pair in wine-uni:wine-codec build-uni:build-codec; do
    [ -d "$HOME/protonbuild/${pair#*:}" ] || cp -c -R "$HOME/protonbuild/${pair%:*}" "$HOME/protonbuild/${pair#*:}"
done
[ -d "$engine" ] || cp -c -R "$HOME/protonwine-uni" "$engine"
patch_dir=${CODEC_PATCH_DIR:-$(cd "$(dirname "$0")/.." && pwd)/patches/codecs}
for patch_file in "$patch_dir"/000*.patch; do
    if git -C "$src" apply --check "$patch_file" 2>/dev/null; then
        git -C "$src" apply "$patch_file"
    else
        git -C "$src" apply --reverse --check "$patch_file"
    fi
done
mkdir -p "$engine/lib/gstreamer"
[ -d "$gst" ] || cp -c -R "$runtime/GStreamer.framework" "$engine/lib/gstreamer/"
python3 - "$gst" <<'PY'
import pathlib, sys
plugins = pathlib.Path(sys.argv[1]) / 'lib/gstreamer-1.0'
keep = set('app asf audiobuffersplit audioconvert audioparsers audioresample avi coreelements debug deinterlace isomp4 libav matroska ogg opus playback typefindfunctions videobox videoconvertscale videofilter videoparsersbad vorbis wavparse'.split())
for plugin in plugins.glob('libgst*.dylib'):
    if plugin.name[6:-6] not in keep:
        plugin.unlink()
PY
# Only development headers/pkg-config data from these LGPL SDK components.
python3 - "$sdk" "$gst" <<'PY'
import pathlib, shutil, sys
sdk, gst = map(pathlib.Path, sys.argv[1:])
for component in ('base-system-1.0', 'gstreamer-1.0-core'):
    payload = sdk / (component + '-devel-1.28.8-universal.pkg') / 'Payload'
    for root in ('include', 'lib'):
        for source in (payload / root).rglob('*'):
            if source.is_file() and source.suffix in ('.h', '.pc'):
                target = gst / source.relative_to(payload)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
PY
# Replace bundled FFmpeg with our explicit LGPL build for BOTH Wine and gst-libav.
cp -R "$ffmpeg/lib/"*.dylib "$gst/lib/"
mkdir -p "$engine/share/licenses"
cp -R "$ffmpeg/share/licenses/ffmpeg" "$engine/share/licenses/"
mkdir -p "$engine/share/licenses/gstreamer-sdk"
for component in base-system-1.0 gstreamer-1.0-core gstreamer-1.0-codecs gstreamer-1.0-codecs-restricted gstreamer-1.0-libav; do
    licenses="$sdk/$component-devel-1.28.8-universal.pkg/Payload/share/licenses"
    [ ! -d "$licenses" ] || cp -R "$licenses/" "$engine/share/licenses/gstreamer-sdk/"
done
# Cloned generated files still name the old source/build/installation paths.
python3 - "$build" <<'PY'
import pathlib, sys
build = pathlib.Path(sys.argv[1])
for name in ('Makefile', 'config.status'):
    p = build / name
    p.write_text(p.read_text().replace('/wine-uni', '/wine-codec').replace('/build-uni', '/build-codec').replace('/protonwine-uni', '/protonwine-codec'))
PY
export PKG_CONFIG_PATH="$ffmpeg/lib/pkgconfig:$gst/lib/pkgconfig:$HOME/cxdeps/lib/pkgconfig"
export DYLD_LIBRARY_PATH="$gst/lib"
export x86_64_CC='ccache x86_64-w64-mingw32-gcc' i386_CC='ccache i686-w64-mingw32-gcc'
# Preserve the unified build's intentional soname overrides and compiler flags.
python3 - "$build" "$src" <<'PY'
import os, pathlib, shlex, subprocess, sys
build, src = map(pathlib.Path, sys.argv[1:])
env = os.environ.copy()
for line in (build / 'config.log').read_text().splitlines():
    if line.startswith('ac_cv_lib_soname_'):
        key, value = line.split('=', 1)
        env[key] = value.strip("'")
args = shlex.split(subprocess.check_output([str(build / 'config.status'), '--config'], text=True))
args += ['--with-ffmpeg', '--with-gstreamer']
with (build / 'codec-configure.log').open('w') as log:
    subprocess.run([str(src / 'configure'), *args], cwd=build, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
PY
grep '^#define HAVE_FFMPEG' "$build/include/config.h"
cd "$build"
make -j"${JOBS:-6}" dlls/winedmo/all dlls/winegstreamer/all > codec-build.log 2>&1
# Wine's generated Makefile has only aggregate install targets. Use its installer
# with the same destinations, restricted to the newly built multimedia modules.
{
    for arch in i386 x86_64; do
        tools/install -m 644 -t "$engine/lib/wine/$arch-windows" \
            "dlls/winedmo/$arch-windows/winedmo.dll" \
            "dlls/winegstreamer/$arch-windows/winegstreamer.dll"
    done
    tools/install -m 755 -t "$engine/lib/wine/x86_64-unix" \
        dlls/winedmo/winedmo.so dlls/winegstreamer/winegstreamer.so
} > codec-install.log 2>&1
# The cloned engine already has its graphics layout. Installing only these six
# media files needs no graphics postinstall; sign just the codecs we changed.
python3 "${CODEC_RELOCATOR:-$HOME/protonbuild/relocate-codecs.mac.py}" "$engine" "$ffmpeg"
echo "Candidate installed: $engine"
