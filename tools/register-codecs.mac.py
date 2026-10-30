#!/usr/bin/env python3
"""Register only unified-codec; preserve other agents' launcher changes."""
import difflib
import pathlib

home = pathlib.Path.home()
out = home / 'nectarine-codec-results/launcher-patches'
out.mkdir(parents=True, exist_ok=True)
for name in ('gsession.sh', 'gsession-inner.sh'):
    path = home / name
    old = path.read_text()
    new = old
    if 'unified-codec)' not in new:
        new = new.replace('  unified) C=', '  unified-codec) C="$HOME/protonwine-codec"; DEFPFX="$HOME/nectarine-candidates/codec-pfx" ;;\n  unified) C=', 1)
    if name == 'gsession.sh':
        marker = '  old_label=$(basename "$old_plist" .plist)\n'
        block = '''  if [[ "$ENGINE" = unified-codec ]]; then
    case "$old_label" in io.github.nectarine.codecs-*) ;; *) continue ;; esac
  fi
'''
        if block not in new:
            new = new.replace(marker, marker + block, 1)
        new = new.replace('"$ENGINE" != unified-dxmt && "$ENGINE" != unified-fallback ]]',
                          '"$ENGINE" != unified-dxmt && "$ENGINE" != unified-fallback && "$ENGINE" != unified-codec ]]')
    if name == 'gsession-inner.sh':
        lines = new.splitlines(True)
        for i, line in enumerate(lines):
            if '"${ENGINE:-}" = unified ||' in line and '= unified-codec ||' not in line:
                lines[i] = line.replace('"${ENGINE:-}" = unified ||', '"${ENGINE:-}" = unified-codec || "${ENGINE:-}" = unified ||')
            if 'if [[' in line and 'NECTARINE_TEST_INPUT_SCRIPT:-' in line and '= unified-codec ||' not in line:
                lines[i] = line.replace('if [[ ', 'if [[ "${ENGINE:-}" = unified-codec || ', 1)
        new = ''.join(lines)
        marker = '# XENV="K=V K2=V2"'
        pos = new.index(marker)
        block = '''# The isolated codec candidate carries its GStreamer/FFmpeg runtime.
if [ "${ENGINE:-}" = unified-codec ]; then
  codec_gst="$C/lib/gstreamer/GStreamer.framework/Versions/1.0"
  export GST_PLUGIN_SYSTEM_PATH_1_0="$codec_gst/lib/gstreamer-1.0"
  export GST_PLUGIN_SYSTEM_PATH="$GST_PLUGIN_SYSTEM_PATH_1_0"
  export GST_PLUGIN_PATH_1_0= GST_PLUGIN_PATH=
  export GST_PLUGIN_SCANNER_1_0="$codec_gst/libexec/gstreamer-1.0/gst-plugin-scanner"
  export GST_REGISTRY_1_0="$PFX/codec-gst-registry.bin"
fi
'''
        if block not in new:
            new = new[:pos] + block + new[pos:]
    if new == old:
        continue
    baseline = out / (name + '.before')
    if not baseline.exists():
        # Preserve the original launcher even across incremental registrations.
        baseline.write_text(old)
    (out / (name + '.patch')).write_text(''.join(difflib.unified_diff(baseline.read_text().splitlines(True), new.splitlines(True), fromfile='a/' + name, tofile='b/' + name)))
    path.write_text(new)
    print('Registered unified-codec in', path)
