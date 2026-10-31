#!/bin/bash
# Nectarine installer (alpha). Windows Steam and its games on Apple Silicon Macs.
#   curl -fsSL https://raw.githubusercontent.com/Reedo22/nectarine/main/release/install.sh | bash
# Installs into ~/Library/Application Support/Nectarine and ~/Applications/Nectarine Steam.app.
# No admin rights needed (except to install Rosetta 2 if it is missing). Re-running updates the engine
# and keeps your prefix (Steam, games, saves).
#   NECTARINE_ENGINE_TARBALL=/path/to/nectarine-engine-X.tar.xz   install from a local file
#   NECTARINE_VERSION=0.1.0-alpha                                 pick a release
set -euo pipefail
VERSION="${NECTARINE_VERSION:-0.1.2-alpha}"
REPO="Reedo22/nectarine"
URL="https://github.com/$REPO/releases/download/v$VERSION/nectarine-engine-$VERSION.tar.xz"
N="${NECTARINE_HOME:-$HOME/Library/Application Support/Nectarine}"
APP="$HOME/Applications/Nectarine Steam.app"
STEAM_SETUP="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

say "Checking this Mac"
[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || die "Nectarine needs an Apple Silicon Mac (M1 or later)."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || die "Nectarine needs macOS 26 or later (you have $(sw_vers -productVersion))."
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  say "Installing Rosetta 2 (Apple asks for an administrator password)"
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license || die "Rosetta 2 is required. Install it with: softwareupdate --install-rosetta"
fi
free_gb=$(df -g "$HOME" | awk 'NR==2{print $4}')
[ "$free_gb" -ge 8 ] || die "At least 8 GB free disk space is needed (plus room for games); you have ${free_gb} GB."
ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
[ "$ram_gb" -ge 16 ] || echo "Note: this Mac has ${ram_gb} GB of memory; 16 GB is recommended. Older/lighter games only."

mkdir -p "$N" "$N/logs"
export WINEPREFIX="$N/prefix"   # for the direct wineserver -w/-k calls below
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

say "Getting the Nectarine engine ($VERSION)"
if [ -n "${NECTARINE_ENGINE_TARBALL:-}" ]; then
  cp "$NECTARINE_ENGINE_TARBALL" "$tmp/engine.tar.xz"
else
  curl -fL --progress-bar "$URL" -o "$tmp/engine.tar.xz" || die "Download failed: $URL"
  expected=$(curl -fsSL "$URL.sha256" | awk '{print $1}')
  actual=$(shasum -a 256 "$tmp/engine.tar.xz" | awk '{print $1}')
  [ "$expected" = "$actual" ] || die "Checksum mismatch for the engine download."
fi
rm -rf "$N/engine.new"; mkdir -p "$N/engine.new"
tar -xJf "$tmp/engine.tar.xz" -C "$N/engine.new" --strip-components 1
xattr -dr com.apple.quarantine "$N/engine.new" 2>/dev/null || true
rm -rf "$N/engine.old"; [ -d "$N/engine" ] && mv "$N/engine" "$N/engine.old"
mv "$N/engine.new" "$N/engine"; rm -rf "$N/engine.old"
NEC="$N/engine/share/nectarine/nectarine"

if [ ! -f "$N/prefix/system.reg" ]; then
  say "Creating the Windows environment (takes a minute or two)"
  "$NEC" wine wineboot -u > "$N/logs/install-wineboot.log" 2>&1 || die "wineboot failed; see $N/logs/install-wineboot.log"
  "$N/engine/bin/wineserver" -w || true
fi

say "Configuring graphics (D3DMetal, DXMT, MetalFX)"
sys32="$N/prefix/drive_c/windows/system32"
cp -f "$N/engine/lib/dxmt/x86_64-windows/winemetal.dll" "$sys32/"
cp -f "$N/engine/lib/d3dmetal/x86_64-windows/nvapi64.dll" "$N/engine/lib/d3dmetal/x86_64-windows/nvngx-on-metalfx.dll" "$sys32/"
{
  "$NEC" wine reg add 'HKCU\Software\Wine\Mac Driver' /v AllowSetGamma /t REG_SZ /d n /f
  "$NEC" wine reg add 'HKCU\Software\Wine\DllOverrides' /v nvcuda /t REG_SZ /d disabled /f
  "$NEC" wine reg add 'HKCU\Software\Wine\DllOverrides' /v atiadlxx /t REG_SZ /d disabled /f
  "$NEC" wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
} > "$N/logs/install-reg.log" 2>&1
"$N/engine/bin/wineserver" -w || true

if [ ! -f "$N/prefix/drive_c/Program Files (x86)/Steam/steam.exe" ]; then
  say "Installing Windows Steam (from Valve)"
  curl -fL --progress-bar "$STEAM_SETUP" -o "$tmp/SteamSetup.exe" || die "Could not download Steam from Valve."
  "$NEC" wine "$tmp/SteamSetup.exe" /S > "$N/logs/install-steam.log" 2>&1 &
  # Valve's setup sometimes stays running after it has installed Steam: wait for Steam.exe to stop
  # changing, then end the setup ourselves (at most 5 minutes).
  steam_exe="$N/prefix/drive_c/Program Files (x86)/Steam/steam.exe"; last=""; stable=0
  for i in $(seq 1 150); do
    sleep 2
    jobs %1 >/dev/null 2>&1 || break
    cur=$(stat -f %z "$steam_exe" 2>/dev/null || true)
    if [ -n "$cur" ] && [ "$cur" = "$last" ]; then stable=$((stable + 1)); else stable=0; fi
    last=$cur
    [ "$stable" -ge 8 ] && break
  done
  "$N/engine/bin/wineserver" -k 2>/dev/null || true
  wait 2>/dev/null || true
  [ -f "$N/prefix/drive_c/Program Files (x86)/Steam/steam.exe" ] || die "Steam did not install; see $N/logs/install-steam.log"
fi

say "Creating $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/MacOS/nectarine-steam" <<EOF
#!/bin/bash
export NECTARINE_HOME="$N"
exec "$NEC"
EOF
chmod +x "$APP/Contents/MacOS/nectarine-steam"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Nectarine Steam</string>
<key>CFBundleDisplayName</key><string>Nectarine Steam</string>
<key>CFBundleIdentifier</key><string>io.github.reedo22.nectarine.steam</string>
<key>CFBundleExecutable</key><string>nectarine-steam</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
EOF
sed -i '' "s/VERSION_PLACEHOLDER/$VERSION/" "$APP/Contents/Info.plist"
codesign -f -s - "$APP" >/dev/null 2>&1 || true

say "Done"
cat <<EOF

  Open "Nectarine Steam" from ~/Applications (or Launchpad), sign in to Steam and install games
  as usual. The first start updates Steam and takes a few minutes.

  Command line:   "$NEC"            (Steam)
                  "$NEC" game.exe   (any Windows program)
                  "$NEC" crashes    (crash reports)
  Logs:           $N/logs
  Settings:       $N/user.env   (e.g. D3DM_ENABLE_METALFX=1)
  Uninstall:      rm -rf "$N" "$APP"

EOF
