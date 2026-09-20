#!/bin/bash
# Capture the Mac's screen. screencapture needs a real GUI session, so it has to run as a
# launchd job in the gui domain like the games do -- straight over ssh it fails.
# On-screen error dialogs (Wine crash boxes, game popups) never reach the logs, so this is
# the only way to read them.
set -u
LABEL=com.reed.shot
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OUT="${1:-$HOME/screen.png}"
rm -f "$OUT"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/sbin/screencapture</string>
    <string>-x</string>
    <string>$OUT</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST_EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null
sleep 4
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
[ -f "$OUT" ] && echo "captured: $(ls -la "$OUT" | awk '{print $5}') bytes" || echo "capture FAILED"
