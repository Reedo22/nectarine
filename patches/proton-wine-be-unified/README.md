# Live unified engine patch series (on top of the unified branch)
0001 winecoreaudio: skip unresponsive capture devices (waveOut start-up hang)
0002 ntdll/winemac: automatic D3DMetal -> DXMT -> DXVK fallback
0003 ntdll: treat a backend trial whose owner is gone/stuck exiting as failed
0004 ws2_32/ntdll: macOS socket semantics fixes
0005 server/ntdll: macOS socket hangs (send/recv unconnected, recv into write-watched memory, reconnect after failed connect)
Build note: configure with `-I<repo>/components/inotify` in CPPFLAGS so HAVE_SYS_INOTIFY_H is set and
wineserver/winebus link the engine's bundled libinotify (kqueue-backed) — file change notifications.
