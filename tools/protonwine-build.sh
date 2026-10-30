#!/bin/bash
# Build Valve's Proton 11 Wine (proton_11.0) as x86_64 for Rosetta, isolated from every live
# engine. Same recipe as ~/cxbuild7.sh (CrossOver 11.0) plus the autoreconf/make_requests
# step, because Proton's git tree does not ship a generated configure.
set -u
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
S="$HOME/protonbuild/wine"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$HOME/cxdeps"
VKLIB="$HOME/wine11/Contents/Resources/wine/lib"
BLD="$HOME/protonbuild/build"
PFX="$HOME/protonwine"
LOG="$HOME/protonbuild/build.log"
: > "$LOG"

echo "=== [1/3] generate configure ==="
cd "$S" || exit 1
if [ ! -x configure ] || [ ! -f include/wine/vulkan.h ]; then
  { (cd dlls/winevulkan && python3 ./make_vulkan -x vk.xml -X video.xml) && tools/make_requests && tools/make_specfiles && autoreconf -fi; } >>"$LOG" 2>&1 \
    || { echo "GENERATE FAILED"; tail -30 "$LOG"; exit 1; }
fi
echo "  configure generated"

echo "=== [2/3] configure ==="
if [ -n "${RECONF:-}" ] || [ ! -f "$BLD/Makefile" ]; then
rm -rf "$BLD"; mkdir -p "$BLD"; cd "$BLD" || exit 1
CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
CPPFLAGS="-I/opt/homebrew/include -I$DEPS/include -I$REPO/components/inotify" \
LDFLAGS="-L$VKLIB -L$DEPS/lib" \
PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" \
INOTIFY_CFLAGS="-I$REPO/components/inotify" INOTIFY_LIBS="-L$VKLIB -linotify" \
  ac_cv_lib_soname_vulkan=libvulkan.dylib \
  ac_cv_lib_soname_gnutls=libgnutls.30.dylib \
  ac_cv_lib_soname_vkd3d=libvkd3d.1.dylib \
  ac_cv_lib_soname_vkd3d_shader=libvkd3d-shader.1.dylib \
  ac_cv_lib_soname_freetype=libfreetype.6.dylib \
FREETYPE_CFLAGS="-I$DEPS/include/freetype2" \
FREETYPE_LIBS="-L$DEPS/lib -lfreetype" \
"$S/configure" \
  --prefix="$PFX" --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
  --enable-archs=i386,x86_64 --disable-tests --with-mingw \
  --without-x --without-oss --without-v4l2 --without-pulse --without-alsa \
  --without-gphoto --without-usb --without-sane --without-capi \
  --disable-amd_ags_x64 --disable-loader64 \
  >>"$LOG" 2>&1
[ $? -eq 0 ] || { echo "CONFIGURE FAILED:"; tail -30 "$LOG"; exit 1; }
echo "  configure ok"
else cd "$BLD" || exit 1; echo "  reusing configured tree"; fi

echo "=== [3/3] make -j8 ==="
make -k -j8 >>"$LOG" 2>&1
rc=$?
echo "make rc=$rc"
grep -nE 'error:' "$LOG" | sort -u -t: -k3 | head -60
[ $rc -eq 0 ] && make install >>"$LOG" 2>&1 && "$HOME/protonbuild/postinstall.sh" && echo "INSTALLED -> $PFX"
