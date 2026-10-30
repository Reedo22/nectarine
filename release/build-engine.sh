#!/bin/bash
# Package the live Nectarine engine as a release tarball. Run on bigpc (needs ssh to the Mac and
# x86_64-w64-mingw32-strip): stages an APFS clone of the engine on the Mac, strips debug info from
# the Windows DLLs here, adds the launcher/crash tool/licences and builds the .tar.xz on the Mac.
#   release/build-engine.sh 0.1.0-alpha
set -euo pipefail
VER=${1:?version}
MAC=${MAC:-mac}
SRC=${SRC:-protonwine-uni}                       # engine dir in the Mac home
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "== stage engine on the Mac"
ssh $MAC "rm -rf ~/nectarine-release/stage && mkdir -p ~/nectarine-release/stage && cp -c -R ~/$SRC ~/nectarine-release/stage/engine
cd ~/nectarine-release/stage/engine
find . \( -name '*.a' -o -name '*.before-*' -o -name '*.bak*' -o -name '*.orig' -o -name '*.wine-orig' -o -name '.DS_Store' \) -print -delete | head -20
rm -f lib/dxmt/source.txt
# Not needed at runtime, and they carry build-machine paths.
rm -rf include share/vulkan lib/gstreamer/GStreamer.framework/Versions/1.0/include lib/gstreamer/GStreamer.framework/Headers
sed -i '' -E \"s#\$HOME/#~/#g\" share/licenses/ffmpeg/configure-summary.txt share/licenses/ffmpeg/config.mak 2>/dev/null || true
# Same-length rewrite of the build user's home in compiled-in paths (assert/__FILE__ strings), then
# re-sign our own Mach-O files. Apple's D3DMetal (lib/external, lib/d3dmetal) is never modified.
u=\$(basename \"\$HOME\"); r=\$(printf '%*s' \${#u} '' | tr ' ' x)
for f in \$(grep -rlE \"/Users/\$u/\" . 2>/dev/null); do
  case \"\$f\" in ./lib/external/*|./lib/d3dmetal/*) continue;; esac
  perl -pi -e \"s#/Users/\$u/#/Users/\$r/#g\" \"\$f\"
  file \"\$f\" | grep -q Mach-O && codesign -f -s - \"\$f\" 2>/dev/null
done
mkdir -p share/nectarine"

echo "== strip debug info from the Windows DLLs (here)"
ssh $MAC "cd ~/nectarine-release/stage/engine/lib/wine && tar -cf - i386-windows x86_64-windows" | tar -xf - -C "$WORK"
before=$(du -sm "$WORK" | cut -f1)
find "$WORK" -type f -exec sh -c 'x86_64-w64-mingw32-strip --strip-debug "$1" 2>/dev/null || true' _ {} \;
echo "   ${before} MB -> $(du -sm "$WORK" | cut -f1) MB"
tar -cf - -C "$WORK" i386-windows x86_64-windows | ssh $MAC "cd ~/nectarine-release/stage/engine/lib/wine && rm -rf i386-windows x86_64-windows && tar -xf -"

echo "== add launcher, crash tool, licences"
scp -q "$REPO/release/nectarine" "$REPO/tools/nectarine-crash.py" "$REPO/release/NOTICE.md" $MAC:nectarine-release/stage/engine/share/nectarine/
ssh $MAC "cd ~/nectarine-release/stage/engine && chmod +x share/nectarine/nectarine && echo '$VER' > share/nectarine/VERSION
cd .. && tar -cJf nectarine-engine-$VER.tar.xz engine && shasum -a 256 nectarine-engine-$VER.tar.xz | tee nectarine-engine-$VER.tar.xz.sha256 && ls -la nectarine-engine-$VER.tar.xz"
