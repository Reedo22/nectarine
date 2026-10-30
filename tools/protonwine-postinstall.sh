#!/bin/bash
# Make a self-built engine runnable after every `make install` (which overwrites all of this).
# Usage: postinstall.sh [engine dir]   (default ~/protonwine)
# Mirrors the known-good Gcenx wine11 layout: Vulkan loader + MoltenVK ICD, with the engine
# carrying the host portability-enumeration patch so the loader exposes MoltenVK.
set -u
NECTARINE_SOURCE_ROOT=$(cd "$(dirname "$0")/.." && pwd)
P="${1:-$HOME/protonwine}"; CX="$HOME/cxwine"; B="$HOME/wine11/Contents/Resources/wine/lib"
cd "$P" || exit 1
mkdir -p lib
# Runtime dylibs (freetype, gnutls, ...) as APFS clones of the cxwine set. Not its MoltenVK or
# loader: cxwine carries an experimental MoltenVK that corrupts 3D.
for f in "$CX"/lib/*.dylib; do
  n=$(basename "$f"); case "$n" in libMoltenVK.dylib|libvulkan*) continue ;; esac
  [ -e "lib/$n" ] || cp -c -P "$f" lib/
done
cp -c -f "$B/libMoltenVK.dylib" lib/libMoltenVK.dylib
cp -c -f "$B/libvulkan.1.4.350.dylib" lib/libvulkan.1.4.350.dylib
ln -sf libvulkan.1.4.350.dylib lib/libvulkan.1.dylib
ln -sf libvulkan.1.dylib lib/libvulkan.dylib
rm -f lib/libvulkan.dylib.loader-link
mkdir -p lib/wine/x86_64-unix/vulkan/icd.d
cp -f "$B/wine/x86_64-unix/vulkan/icd.d/MoltenVK_icd.json" lib/wine/x86_64-unix/vulkan/icd.d/
# configure linked inotify/pcap by bare name from the wine11 bundle.
[ -f lib/libinotify.0.dylib ] || cp "$B/libinotify.0.dylib" lib/
install_name_tool -change libinotify.dylib @executable_path/../lib/libinotify.0.dylib bin/wineserver 2>/dev/null
install_name_tool -change libinotify.dylib @loader_path/../../libinotify.0.dylib lib/wine/x86_64-unix/winebus.so 2>/dev/null
install_name_tool -change libpcap.dylib /usr/lib/libpcap.A.dylib lib/wine/x86_64-unix/wpcap.so 2>/dev/null
for f in lib/libinotify.0.dylib bin/wineserver lib/wine/x86_64-unix/winebus.so lib/wine/x86_64-unix/wpcap.so; do
  [ -f "$f" ] && codesign -f -s - "$f" 2>/dev/null; done
# DXVK 1.10.3 (macOS) as builtins; Wine's own kept as *.wined3d.
W=lib/wine/x86_64-windows
for d in d3d11 dxgi d3d10core; do
  if ! strings "$W/$d.dll" | grep -q "v1.10.3"; then cp "$W/$d.dll" "$W/$d.dll.wined3d"; fi
  cp "$CX/lib/wine/x86_64-windows/$d.dll" "$W/"; done
bad=$(for f in bin/wine bin/wineserver lib/wine/x86_64-unix/*.so; do otool -L "$f" | tail -n +2 | awk '$1 !~ /^(\/|@)/'; done | sort -u)
[ -z "$bad" ] && echo "postinstall ok ($P)" || { echo "postinstall: unresolved bare dylib refs:"; echo "$bad"; exit 1; }

# Optional source-built D3DMetal workaround; install outside the engine so Apple's
# binaries and the protected runtime remain untouched.
if [ "${NECTARINE_BUILD_D3DMETAL_ICB:-0}" = 1 ]; then
  bash "$NECTARINE_SOURCE_ROOT/components/d3dmetal-shim/build.sh" \
    "$HOME/nectarine-runtime/d3dmetal-shim" || exit 1
fi
