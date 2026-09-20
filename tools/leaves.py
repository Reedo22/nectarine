#!/usr/bin/env python3
"""Rank leaf frames in a macOS `sample` call tree. A frame is a leaf when the next line
is not deeper than it, so its count is time actually ON that frame rather than in a
callee. Blocking primitives are reported separately -- threads parked in ulock/mach_msg
are idle, not cost."""
import re, sys
from collections import defaultdict

BLOCK = ("__ulock_wait", "__psynch_cvwait", "mach_msg", "__workq_kernreturn",
         "kevent", "__semwait_signal", "read", "select", "poll", "__wait4",
         "accept", "recvfrom", "start_wqthread", "thread_start")

lines = []
for raw in open(sys.argv[1], errors="replace"):
    m = re.match(r"^(\s*)(?:[+!|: ]*\s)?(\d+)\s+(.*)$", raw.rstrip("\n"))
    if not m:
        continue
    indent, cnt, sym = len(raw) - len(raw.lstrip()), int(m.group(2)), m.group(3)
    lines.append((indent, cnt, sym.strip()))

busy, idle = defaultdict(int), defaultdict(int)
for i, (ind, cnt, sym) in enumerate(lines):
    deeper = i + 1 < len(lines) and lines[i + 1][0] > ind
    if deeper:
        continue                      # not a leaf
    name = re.sub(r"\s+\[0x[0-9a-f]+\]$", "", sym)
    name = re.sub(r"\s+\+\s+\d+$", "", name)
    (idle if any(b in name for b in BLOCK) else busy)[name] += cnt

tot = sum(busy.values()) + sum(idle.values())
print("total leaf samples: %d   on-CPU: %d (%.1f%%)   blocked: %d" %
      (tot, sum(busy.values()), 100.0 * sum(busy.values()) / max(tot, 1), sum(idle.values())))
print("\n--- ON-CPU leaves (where time is actually spent) ---")
for name, c in sorted(busy.items(), key=lambda x: -x[1])[:25]:
    print("%7d  %5.1f%%  %s" % (c, 100.0 * c / max(sum(busy.values()), 1), name[:100]))
print("\n--- blocked (idle waits, for reference) ---")
for name, c in sorted(idle.items(), key=lambda x: -x[1])[:6]:
    print("%7d  %s" % (c, name[:80]))
