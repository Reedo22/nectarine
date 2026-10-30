#!/bin/bash
# Make a self-built engine runnable after every `make install` (which overwrites all of this).
# Usage: postinstall.sh [engine dir]   (default ~/protonwine)
# Mirrors the known-good Gcenx wine11 layout: Vulkan loader + MoltenVK ICD, with the engine
# carrying the host portability-enumeration patch so the loader exposes MoltenVK.
set -u
P="${1:-$HOME/protonwine}"; CX="$HOME/cxwine"; B="$HOME/wine11/Contents/Resources/wine/lib"
cd "$P" || exit 1
mkdir -p lib
# Runtime dylibs (freetype, gnutls, ...) as APFS clones of the cxwine set. Not its MoltenVK or
# loader: cxwine carries an experimental MoltenVK that corrupts 3D.
for f in "$CX"/lib/*.dylib; do
  n=$(basename "$f"); case "$n" in libMoltenVK.dylib|libvulkan*) continue ;; esac
  [ -e "lib/$n" ] || cp -c -P "$f" lib/
done
# MoltenVK comes from the consolidated Nectarine tree (~/mvk-nectarine, branch nectarine; patch
# series in ~/nectarine/patches/moltenvk-nectarine). Override with MVK=/path/libMoltenVK.dylib.
MVK="${MVK:-$HOME/mvk-nectarine/MoltenVK/build-nect/MoltenVK/libMoltenVK.dylib}"
[ -f "$MVK" ] || { echo "postinstall: MoltenVK not found at $MVK" >&2; exit 1; }
cp -c -f -L "$MVK" lib/libMoltenVK.dylib
echo "$MVK $(git -C "$(dirname "$MVK")/../.." rev-parse --short HEAD 2>/dev/null) $(shasum -a 256 "$MVK" | cut -c1-16)" > lib/libMoltenVK.source
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
# Arial/Courier/Times/Microsoft YaHei replacements: wine-staging ships them, Proton ships its own
# font pack instead; without them Steam UI font measurement fails and the window never appears.
for f in arial.ttf cour.ttf msyh.ttf times.ttf; do cp -f "$B/../share/wine/fonts/$f" "$P/share/wine/fonts/"; done
# Sign everything with the stable local identity (see ~/nectarine-signing) so macOS privacy
# decisions (camera, microphone, ...) persist across rebuilds instead of re-prompting.
KC="$HOME/Library/Keychains/nectarine-signing.keychain-db"
if [ -f "$KC" ]; then
  security unlock-keychain -p nectarine-local "$KC" 2>/dev/null
  find bin lib -path lib/external -prune -o -path lib/d3dmetal -prune -o -path lib/dxmt -prune -o -type f \( -perm -u+x -o -name "*.so" -o -name "*.dylib" \) 2>/dev/null | while read -r f; do
    file -b "$f" | grep -q Mach-O && codesign -f -s "Nectarine Local Signing" --keychain "$KC" "$f" 2>/dev/null
  done
  echo "signed with Nectarine Local Signing"
fi

bad=$(for f in bin/wine bin/wineserver lib/wine/x86_64-unix/*.so; do otool -L "$f" | tail -n +2 | awk '$1 !~ /^(\/|@)/'; done | sort -u)
[ -z "$bad" ] && echo "postinstall ok ($P)" || { echo "postinstall: unresolved bare dylib refs:"; echo "$bad"; exit 1; }

# Optional third backend; build only when explicitly requested.
if [ "${BUILD_DXMT:-0}" = 1 ]; then
  bash "${NECTARINE_REPO:-$HOME/nectarine}/tools/build-dxmt.mac.sh" "$P" || exit 1
fi
