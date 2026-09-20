#!/bin/bash
# Capture a Metal GPU timeline for a running Wine game.
export DEVELOPER_DIR=/Users/reed/Downloads/Xcode.app/Contents/Developer   # Xcode lives in ~/Downloads; avoids needing sudo xcode-select
#
# Everything cheap has already been ruled out for DSP (pixels, bandwidth, CPU threads,
# draw calls, attachment loads) while the GPU sits at 92-100%. What is left is either
# fixed per-render-pass cost or expensive shaders on targets that do not scale, and only
# a GPU timeline separates those: it shows which encoder consumes which microseconds.
#
# Usage: gputrace.sh [seconds] [process-name-fragment]
set -u
SECS="${1:-12}"
MATCH="${2:-DSPGAME}"
OUT="$HOME/gputrace-$(date +%H%M%S).trace"

if ! xcrun xctrace version >/dev/null 2>&1; then
  echo "xctrace not usable yet. After installing Xcode, run ONCE (needs your password):"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "  sudo xcodebuild -license accept"
  exit 1
fi

PID=$(pgrep -f "$MATCH" | head -1)
[ -n "$PID" ] || { echo "no process matching '$MATCH' is running"; exit 1; }
echo "attaching to pid $PID for ${SECS}s"

# Metal System Trace shows GPU encoder timing; the template name varies by Xcode version,
# so fall back through the likely ones.
for T in "Metal System Trace" "Game Performance" "Time Profiler"; do
  if xcrun xctrace list templates 2>/dev/null | grep -qi "^ *$T"; then
    echo "using template: $T"
    xcrun xctrace record --template "$T" --attach "$PID" --time-limit "${SECS}s" --output "$OUT" 2>&1 | tail -5
    echo "trace written: $OUT"
    exit 0
  fi
done
echo "none of the expected templates found. Available:"
xcrun xctrace list templates 2>/dev/null
