#!/bin/bash
# The Sikarugir wine binaries link their bundled dylibs as @rpath/libfoo.dylib but ship
# with no LC_RPATH at all -- the .app bundle must have supplied one at build/sign time.
# Copied out of the bundle they are unloadable ("no LC_RPATH's found"), and
# DYLD_FALLBACK_LIBRARY_PATH does not apply to @rpath, so the child loader died on exec
# and the parent only reported "failed to start wineboot 1".
#
# Add an absolute rpath plus a relocatable one, then re-adhoc-sign (editing load
# commands invalidates the existing signature).
set -u
ROOT="$HOME/wine-msync"
n=0
find "$ROOT/bin" "$ROOT/lib" -type f 2>/dev/null | while read -r F; do
  file "$F" | grep -q 'Mach-O' || continue
  otool -L "$F" 2>/dev/null | grep -q '@rpath/' || continue
  # relative hop from this file's dir up to $ROOT/lib
  D=$(dirname "$F")
  REL=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$ROOT/lib" "$D")
  install_name_tool -add_rpath "$ROOT/lib" "$F" 2>/dev/null
  install_name_tool -add_rpath "@loader_path/$REL" "$F" 2>/dev/null
  codesign -f -s - "$F" >/dev/null 2>&1
  echo "  rpath+sign: ${F#$ROOT/}  (@loader_path/$REL)"
done
echo "--- verify ---"
otool -l "$ROOT/bin/wineserver" | grep -A2 LC_RPATH | grep path
