#!/bin/bash
set -euo pipefail

ROOT="${DXMT_ROOT:-$HOME/nectarine-candidates/dxmt}"
INSTALL="$ROOT/install"
ENGINE="$ROOT/wine"
PREFIX="$ROOT/prefix"
SYSTEM32="$PREFIX/drive_c/windows/system32"

for file in \
  "$INSTALL/system32/d3d11.dll" \
  "$INSTALL/system32/d3d10core.dll" \
  "$INSTALL/system32/dxgi.dll" \
  "$INSTALL/x86_64-windows/winemetal.dll" \
  "$INSTALL/x86_64-unix/winemetal.so"; do
  test -f "$file" || { echo "missing DXMT artifact: $file" >&2; exit 1; }
done

for dll in d3d11 d3d10core dxgi; do
  if test -f "$SYSTEM32/$dll.dll" && test ! -f "$SYSTEM32/$dll.dll.wine-original"; then
    cp -p "$SYSTEM32/$dll.dll" "$SYSTEM32/$dll.dll.wine-original"
  fi
  cp -f "$INSTALL/system32/$dll.dll" "$SYSTEM32/$dll.dll"
done

if test -f "$SYSTEM32/winemetal.dll" && test ! -f "$SYSTEM32/winemetal.dll.wine-original"; then
  cp -p "$SYSTEM32/winemetal.dll" "$SYSTEM32/winemetal.dll.wine-original"
fi
cp -f "$INSTALL/x86_64-windows/winemetal.dll" "$SYSTEM32/winemetal.dll"
cp -f "$INSTALL/x86_64-windows/winemetal.dll" "$ENGINE/lib/wine/x86_64-windows/winemetal.dll"
cp -f "$INSTALL/x86_64-unix/winemetal.so" "$ENGINE/lib/wine/x86_64-unix/winemetal.so"

shasum -a 256 \
  "$SYSTEM32/d3d11.dll" \
  "$SYSTEM32/dxgi.dll" \
  "$SYSTEM32/winemetal.dll" \
  "$ENGINE/lib/wine/x86_64-unix/winemetal.so"
