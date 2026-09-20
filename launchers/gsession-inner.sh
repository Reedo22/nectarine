#!/bin/bash
# Runs INSIDE one launchd job: optionally starts Steam, waits for logon, then execs the
# game as a sibling child of the SAME job. One job matters because msync registers the
# wineserver's port with Mach bootstrap and separate launchd jobs get separate bootstrap
# subsets -- a game in its own job exits 1 with an empty log.
set -u
GAME="$1"; EXE="$2"; APPID="$3"; shift 3

case "${ENGINE:-cxwine}" in
  cxwine) C="$HOME/cxwine";                          DEFPFX="$HOME/sat11-cx" ;;
  ws10)   C="$HOME/ws10/wswine.bundle";              DEFPFX="$HOME/msync-pfx" ;;
  wine11) C="$HOME/wine11/Contents/Resources/wine";  DEFPFX="$HOME/sat11" ;;
  *) echo "unknown ENGINE=${ENGINE:-}"; exit 1 ;;
esac
PFX="${PFX:-$DEFPFX}"
STEAMDIR="$PFX/drive_c/Program Files (x86)/Steam"
CLOG="$STEAMDIR/logs/connection_log.txt"

export WINEPREFIX="$PFX"
export WINEMSYNC="${MSYNC:-1}"
export WINEDEBUG="${WDEBUG:--all}"
export DYLD_FALLBACK_LIBRARY_PATH="$C/lib"
export DXVK_LOG_LEVEL="${DXVKLOG:-none}"
export SteamAppId="$APPID" SteamGameId="$APPID"
if [ "${DLLMODE:-b}" = n ]; then
  # our build ships only d3d11+dxgi (d3d10 was disabled), so d3d10core must stay builtin
  # DXVK's d3d10core and d3d11 share internals, so Gcenx's d3d10core + OUR d3d11 is a
  # version mismatch. Our build omits d3d10, so disable it rather than mixing.
  export WINEDLLOVERRIDES="d3d11,dxgi=n;d3d10core=disabled"
else
  export WINEDLLOVERRIDES="d3d11,d3d10core,dxgi=b"
fi
export MVK_X_DXVK_FEATURES=1 MVK_X_FAKE_DEPTH_BOUNDS=1
export MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS="${ARGBUF:-1}"
export MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1
export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0
export MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER=0
export MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1
export MVK_CONFIG_PERFORMANCE_TRACKING="${PERFTRACK:-0}"
export MVK_CONFIG_FAST_MATH_ENABLED="${FASTMATH:-1}"
export MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT=60
# 0 none 1 error 2 warn 3 INFO 4 debug -- below 3 hides the stats fps.py parses
export MVK_CONFIG_LOG_LEVEL="${MVKLOG:-3}"
export MVK_DIAG_PASS_AFTER="${PASSLOG:-999999}"
export ROSETTA_ADVERTISE_AVX=1
[ "${PASSSTATS:-0}" = 1 ] && export MVK_X_PASSSTATS=1
[ "${DISCARDDEPTH:-0}" = 1 ] && export MVK_X_TBDR_DISCARD_DEPTH=1
[ "${DISCARDLOADS:-0}" = 1 ] && export DXVK_X_DISCARD_LOADS=1
[ "${LABELENC:-0}" = 1 ] && export MVK_X_LABEL_ENCODERS=1

# Our own build does not bake in an ICD path; and DXVK 1.10.3 never sets
# VK_KHR_portability_enumeration, so the loader hides MoltenVK and DXVK finds no
# adapters. Loading MoltenVK directly sidesteps both. Prebuilt engines don't need it.
if [ -f "$C/lib/wine/x86_64-unix/vulkan/icd.d/MoltenVK_icd.json" ]; then
  export VK_ICD_FILENAMES="$C/lib/wine/x86_64-unix/vulkan/icd.d/MoltenVK_icd.json"
fi
if [ "${CXVK:-0}" = 1 ]; then
  export CX_LIBVULKAN="$C/lib/libMoltenVK.dylib"
  export CX_ACTIVE_GRAPHICS_BACKEND=wined3d
fi

echo "### engine=${ENGINE:-cxwine} prefix=$PFX msync=$WINEMSYNC argbuf=${ARGBUF:-1} cxvk=${CXVK:-0}"

if [ "$APPID" = none ]; then
  echo "### no steam needed"
else
  BEFORE=$(grep -c "Logged On" "$CLOG" 2>/dev/null || true); [ -n "$BEFORE" ] || BEFORE=0
  cd "$STEAMDIR" || exit 1
  "$C/bin/wine" steam.exe -no-cef-sandbox -cef-disable-gpu -cef-disable-gpu-sandbox -tcp &
  for i in $(seq 1 72); do
    sleep 5
    NOW=$(grep -c "Logged On" "$CLOG" 2>/dev/null || true); [ -n "$NOW" ] || NOW=0
    if [ "$NOW" -gt "$BEFORE" ]; then echo "### steam logged on after $((i*5))s"; break; fi
  done
  sleep 20
fi

echo "### launching $EXE"
cd "$GAME" || exit 1
exec "$C/bin/wine" "$EXE" "$@"
