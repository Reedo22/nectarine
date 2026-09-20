#!/usr/bin/env python3
"""MoltenVK's "avg FPS" is cumulative over the whole session, so a warming shader
cache drags it up forever. Recover the instantaneous rate between two reports from
(cumulative frames, cumulative average): t = n/avg, so fps = (n2-n1)/(t2-t1)."""
import re, sys

for path in sys.argv[1:]:
    pts = []
    avg = None
    for line in open(path, errors="replace"):
        m = re.search(r"avg FPS: ([\d.]+)", line)
        if m:
            avg = float(m.group(1)); continue
        m = re.search(r"Frame interval\s+avg:.*count: (\d+)", line)
        if m and avg:
            pts.append((int(m.group(1)), avg)); avg = None
    print("==", path.split("/")[-1], "--", len(pts), "reports")
    if len(pts) < 3:
        print("   too few samples"); continue
    inst = []
    for (n1, a1), (n2, a2) in zip(pts, pts[1:]):
        t1, t2 = n1 / a1, n2 / a2
        if t2 > t1 and n2 > n1:
            inst.append((n2 - n1) / (t2 - t1))
    tail = inst[-8:]
    print("   first 3 instantaneous: %s" % ", ".join("%.1f" % f for f in inst[:3]))
    print("   LAST 8 instantaneous : %s" % ", ".join("%.1f" % f for f in tail))
    print("   steady-state mean    : %.1f fps  (%.2f ms/frame)" % (sum(tail)/len(tail), 1000*len(tail)/sum(tail)))
