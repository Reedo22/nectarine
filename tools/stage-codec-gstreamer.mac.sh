#!/bin/bash
# Extract official packages without running their installers. No system changes.
set -euo pipefail
scratch=${GST_SCRATCH:-$HOME/nectarine-deps/gst-sdk}
runtime=${GST_RUNTIME:-$HOME/nectarine-deps/gstreamer-codec}
mkdir -p "$scratch" "$runtime/GStreamer.framework/Versions/1.0"
fetch() {
    local name=$1 target=$2 checksum=$3
    [ -f "$target" ] || curl -fLsS "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.8/$name" -o "$target"
    echo "$checksum  $target" | shasum -a 256 -c -
}
fetch gstreamer-1.0-1.28.8-universal.pkg "$scratch/runtime.pkg" d371ab04a7632713626836c2fc234e863cc98484c74c473eba99b0fbd9b3a3fe
fetch gstreamer-1.0-devel-1.28.8-universal.pkg "$scratch/devel.pkg" e6d380bc17be7eccf13e0154567d4718fc9321da822408c7ca0cd808b3d4a3f7
[ -d "$scratch/runtime-expanded" ] || pkgutil --expand-full "$scratch/runtime.pkg" "$scratch/runtime-expanded"
[ -d "$scratch/expanded" ] || pkgutil --expand-full "$scratch/devel.pkg" "$scratch/expanded"
cp -c -R "$scratch/runtime-expanded/osx-framework-1.28.8-universal.pkg/Payload/" "$runtime/GStreamer.framework/"
# Same non-GPL component set as the existing staged runtime, plus libav/ASF.
for component in base-system-1.0 base-crypto gstreamer-1.0-core gstreamer-1.0-system \
    gstreamer-1.0-playback gstreamer-1.0-codecs gstreamer-1.0-effects gstreamer-1.0-net \
    gstreamer-1.0-visualizers gstreamer-1.0-analytics gstreamer-1.0-libav gstreamer-1.0-codecs-restricted; do
    cp -c -R "$scratch/runtime-expanded/$component-1.28.8-universal.pkg/Payload/" \
        "$runtime/GStreamer.framework/Versions/1.0/"
done
echo "GST_RUNTIME=$runtime"
echo "GST_SDK=$scratch/expanded"
