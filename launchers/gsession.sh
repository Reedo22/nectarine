#!/bin/bash
# One launchd job holding Steam + the game so they share a Mach bootstrap namespace.
# Usage: [ENGINE=..] [PFX=..] [MSYNC=..] [ARGBUF=..] [CXVK=..] [MVKLOG=..] [DXVKLOG=..]
#        gsession.sh <label> <gamedir> <exe> <appid|none> [args...]
set -u
LABEL_S="$1"; GAME="$2"; EXE="$3"; APPID="$4"; shift 4
LABEL="com.reed.$LABEL_S"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/$LABEL_S.log"
ENGINE="${ENGINE:-cxwine}"

case "$ENGINE" in
  cxwine) C="$HOME/cxwine";                         DEFPFX="$HOME/sat11-cx" ;;
  ws10)   C="$HOME/ws10/wswine.bundle";             DEFPFX="$HOME/msync-pfx" ;;
  wine11) C="$HOME/wine11/Contents/Resources/wine"; DEFPFX="$HOME/sat11" ;;
  *) echo "unknown ENGINE=$ENGINE"; exit 1 ;;
esac
PFXV="${PFX:-$DEFPFX}"

pkill -f -i "$EXE" 2>/dev/null; pkill -f -i steam.exe 2>/dev/null
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
sleep 5
env WINEPREFIX="$PFXV" DYLD_FALLBACK_LIBRARY_PATH="$C/lib" "$C/bin/wineserver" -k 2>/dev/null
sleep 4
rm -f "$LOG"; mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$HOME/gsession-inner.sh</string>
    <string>$GAME</string>
    <string>$EXE</string>
    <string>$APPID</string>
$(for a in "$@"; do printf '    <string>%s</string>\n' "$a"; done)
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ENGINE</key><string>$ENGINE</string>
    <key>PFX</key><string>$PFXV</string>
    <key>MSYNC</key><string>${MSYNC:-1}</string>
    <key>ARGBUF</key><string>${ARGBUF:-1}</string>
    <key>CXVK</key><string>${CXVK:-0}</string>
    <key>MVKLOG</key><string>${MVKLOG:-3}</string>
    <key>DXVKLOG</key><string>${DXVKLOG:-none}</string>
    <key>WDEBUG</key><string>${WDEBUG:--all}</string>
    <key>PASSSTATS</key><string>${PASSSTATS:-0}</string>
    <key>DISCARDDEPTH</key><string>${DISCARDDEPTH:-0}</string>
    <key>PERFTRACK</key><string>${PERFTRACK:-0}</string>
    <key>FASTMATH</key><string>${FASTMATH:-1}</string>
    <key>PASSLOG</key><string>${PASSLOG:-999999}</string>
    <key>DISCARDLOADS</key><string>${DISCARDLOADS:-0}</string>
    <key>DLLMODE</key><string>${DLLMODE:-b}</string>
    <key>LABELENC</key><string>${LABELENC:-0}</string>
  </dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
</dict>
</plist>
PLIST_EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "$LABEL_S [$ENGINE] -> $LOG"
