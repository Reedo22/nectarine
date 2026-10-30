#!/bin/bash
# Build unmodified DXMT using the existing LLVM 15 toolchain and candidate Wine.
# Run after S=wine-dxmt BLD=build-dxmt PFX=protonwine-dxmt build-be.sh.
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
D="${DXMT_ROOT:-$HOME/nectarine-candidates/dxmt}"
P="${1:-$HOME/protonwine-dxmt}"
[ "$P" != "$HOME/protonwine-uni" ] || { echo 'refusing protected engine' >&2; exit 1; }
df -h "$HOME" | tail -n 1
[ -d "$D/llvm/lib" ] && [ -f "$P/lib/wine/x86_64-unix/ntdll.so" ]
export DEVELOPER_DIR="${DEVELOPER_DIR:-$HOME/Downloads/Xcode.app/Contents/Developer}"
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
unset CFLAGS CXXFLAGS
cat > "$D/uni-native.ini" <<'INI'
[binaries]
c = '/Library/Developer/CommandLineTools/usr/bin/clang'
cpp = '/Library/Developer/CommandLineTools/usr/bin/clang++'
[built-in options]
c_args = ['-arch', 'x86_64', '-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23']
cpp_args = ['-arch', 'x86_64', '-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23']
INI
mode=(); [ ! -d "$D/build-uni/meson-private" ] || mode=(--reconfigure)
meson setup "${mode[@]}" "$D/build-uni" "$D/src" \
  --cross-file "$D/src/build-win64.txt" --native-file "$D/uni-native.ini" \
  --buildtype release --prefix "$P/lib/dxmt" --strip \
  -Dwine_builtin_dll=true -Dnative_llvm_path="$D/llvm" -Dwine_install_path="$P"
meson compile -C "$D/build-uni" -j 6
meson install -C "$D/build-uni"
# Resolve Wine dependencies inside this engine, including after relocation.
U="$P/lib/dxmt/x86_64-unix/winemetal.so"
if ! otool -l "$U" | grep -F '@loader_path/../../wine/x86_64-unix' >/dev/null; then
  install_name_tool -add_rpath @loader_path/../../wine/x86_64-unix "$U"
fi
codesign -f -s - "$U"
codesign --verify --strict "$U"
{ git -C "$D/src" rev-parse HEAD; shasum -a 256 "$P/lib/dxmt/x86_64-windows/"{d3d11,dxgi,d3d10core,winemetal}.dll "$U"; } > "$P/lib/dxmt/source.txt"

# Wine 11 does not discover a new builtin name outside prefix bootstrap.
# Provide its PE placeholder only in an explicitly selected experimental prefix.
if [ -n "${DXMT_PREFIX:-}" ]; then
  test -d "$DXMT_PREFIX/drive_c/windows/system32"
  cp -f "$P/lib/dxmt/x86_64-windows/winemetal.dll" "$DXMT_PREFIX/drive_c/windows/system32/winemetal.dll"
fi
