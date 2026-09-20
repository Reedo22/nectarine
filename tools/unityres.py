#!/usr/bin/env python3
"""Force a Unity game's resolution through its PlayerPrefs in the Wine registry.

Run with wineserver stopped: it caches the registry in memory and flushes stale values
back over anything written while it is alive.

NOTE: every Unity game uses the SAME PlayerPrefs key-name hashes, so a plain grep for
'Screenmanager Resolution Width_h182942802' matches every game in the prefix. Always
edit inside one app's [Software\\Vendor\\App] block, never globally.

Usage: unityres.py <reg file> <Vendor\\App> <width> <height> [fullscreen 1|3]
"""
import re, sys

path, app, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
mode = int(sys.argv[5]) if len(sys.argv) > 5 else 3        # 3 = Windowed, 1 = Exclusive FS

WANT = {
    "Screenmanager Resolution Use Native_h1405027254": 0,
    "Screenmanager Resolution Use Native Default_h1405981789": 0,
    "Screenmanager Resolution Width_h182942802": w,
    "Screenmanager Resolution Height_h2627697771": h,
    "Screenmanager Resolution Width Default_h1580041936": w,
    "Screenmanager Resolution Height Default_h1380706816": h,
    "Screenmanager Resolution Window Width_h2524650974": w,
    "Screenmanager Resolution Window Height_h1684712807": h,
    "Screenmanager Fullscreen mode_h3630240806": mode,
    "Screenmanager Fullscreen mode Default_h401710285": mode,
}

s = open(path, encoding="utf-8", errors="surrogateescape").read()
key = "[Software\\\\" + app.replace("\\", "\\\\") + "]"
m = re.search(re.escape(key) + r"[^\[]*", s)
if not m:
    sys.exit("block not found: " + key)

block = m.group(0)
for name, val in WANT.items():
    line = '"%s"=dword:%08x' % (name, val)
    pat = re.compile(r'"%s"=dword:[0-9a-fA-F]{8}' % re.escape(name))
    block = pat.sub(line, block) if pat.search(block) else block.rstrip("\n") + "\n" + line + "\n"

open(path, "w", encoding="utf-8", errors="surrogateescape").write(s[:m.start()] + block + s[m.end():])
print("patched %s -> %dx%d mode %d" % (app, w, h, mode))
for l in block.splitlines():
    if "Screenmanager Resolution" in l or "Fullscreen mode" in l:
        print("  " + l)
