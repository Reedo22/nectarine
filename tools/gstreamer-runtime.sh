#!/bin/bash
# Run a candidate command against the isolated macOS GStreamer runtime.
# Example: tools/gstreamer-runtime.sh /path/to/wine media-source-reader.exe ...
set -euo pipefail
runtime="${NECTARINE_GSTREAMER_ROOT:-$HOME/nectarine-runtime/gstreamer-1.28.8}"
framework="$runtime/GStreamer.framework"
version="$framework/Versions/1.0"
target_arch="${NECTARINE_GST_ARCH:-x86_64}"
case "$target_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $target_arch" >&2; exit 2 ;; esac
if [ "$#" -eq 0 ] || [ ! -d "$version/lib/gstreamer-1.0" ]; then
    echo "Usage: $0 COMMAND [ARGS...]; set NECTARINE_GSTREAMER_ROOT for another staged runtime" >&2
    exit 2
fi
# Set DYLD variables after launching Apple's arch/env binaries, which can clear
# inherited DYLD variables. Each architecture gets its own plugin registry.
exec /usr/bin/arch "-$target_arch" /usr/bin/env \
    DYLD_FRAMEWORK_PATH="$runtime${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}" \
    DYLD_LIBRARY_PATH="$version/Libraries:$version/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$version/lib/gstreamer-1.0" \
    GST_PLUGIN_SYSTEM_PATH="$version/lib/gstreamer-1.0" \
    GST_PLUGIN_PATH_1_0= GST_PLUGIN_PATH= \
    GST_PLUGIN_SCANNER_1_0="$version/libexec/gstreamer-1.0/gst-plugin-scanner" \
    GST_REGISTRY_1_0="$runtime/registry-$target_arch.bin" \
    "$@"
