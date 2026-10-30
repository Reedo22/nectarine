#!/bin/bash
set -euo pipefail

ROOT="${DXMT_ROOT:-$HOME/nectarine-candidates/dxmt}"
WINE_INSTALL="${WINE_INSTALL:-$HOME/protonwine}"
export PATH="/opt/homebrew/bin:$PATH"
if test -d "$HOME/Downloads/Xcode.app/Contents/Developer"; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
fi
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
export CFLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23 ${CFLAGS:-}"
export CXXFLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23 ${CXXFLAGS:-}"

cmake -B "$ROOT/llvm-build" -S "$ROOT/llvm-project/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ROOT/llvm" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
  -DLLVM_ENABLE_ASSERTIONS=On \
  -DLLVM_ENABLE_ZSTD=Off \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
  -DLLVM_TARGETS_TO_BUILD="" \
  -DLLVM_BUILD_TOOLS=Off \
  -DLLVM_INCLUDE_BENCHMARKS=Off \
  -DBUG_REPORT_URL="https://github.com/3Shain/dxmt" \
  -DPACKAGE_VENDOR="DXMT" \
  -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off \
  -G Ninja
cmake --build "$ROOT/llvm-build"
cmake --install "$ROOT/llvm-build"

SETUP_MODE=()
if test -d "$ROOT/build/meson-private"; then SETUP_MODE=(--wipe); fi
meson setup "${SETUP_MODE[@]}" "$ROOT/build" "$ROOT/src" \
  --cross-file "$ROOT/src/build-win64.txt" \
  --native-file "$ROOT/macos-native.ini" \
  --buildtype release \
  --prefix "$ROOT/install" \
  --strip \
  -Dwine_builtin_dll=false \
  -Dnative_llvm_path="$ROOT/llvm" \
  -Dwine_install_path="$WINE_INSTALL"
meson compile -C "$ROOT/build"
meson install -C "$ROOT/build"

find "$ROOT/install" -type f -print
