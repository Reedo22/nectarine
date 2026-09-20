#!/usr/bin/env python3
"""Aggregate Instruments' metal-gpu-intervals export: where does GPU time actually go?

xctrace XML interns repeated values: the first occurrence carries id="N" and the text,
later ones are <tag ref="N"/>. So we keep an id->value map as we stream.

The question this answers: is DSP's GPU time spread evenly across ~32 passes/frame
(fixed per-pass cost) or concentrated in a few expensive encoders (shader cost on
targets that don't scale)?
"""
import sys, xml.etree.ElementTree as ET
from collections import defaultdict

path = sys.argv[1]
vals = {}

def val(el):
    r = el.get("ref")
    if r is not None:
        return vals.get(r, "")
    i = el.get("id")
    t = (el.text or "")
    if i is not None:
        vals[i] = t
    return t

rows = 0
by_channel = defaultdict(lambda: [0, 0.0])   # count, total ns
by_label   = defaultdict(lambda: [0, 0.0])
durations  = []

for ev, el in ET.iterparse(path, events=("end",)):
    if el.tag != "row":
        continue
    rows += 1
    dur = 0.0; chan = ""; label = ""
    # first <duration> in a row is the interval's own duration
    seen_dur = False
    for child in el:
        if child.tag == "duration" and not seen_dur:
            try: dur = float(val(child) or 0)
            except ValueError: dur = 0.0
            seen_dur = True
        elif child.tag == "gpu-channel-name":
            chan = val(child)
        elif child.tag == "event-label":
            if not label: label = val(child)
        elif child.tag == "channel-subtitle":
            # the encoder's MTLLabel lives here (engineering-type metal-object-label),
            # NOT in event-label -- that column is empty for these rows
            v = val(child)
            if v: label = v
        else:
            val(child)   # keep the intern table complete
    by_channel[chan][0] += 1; by_channel[chan][1] += dur
    key = (chan, label[:60])
    by_label[key][0] += 1; by_label[key][1] += dur
    durations.append(dur)
    el.clear()

total = sum(v[1] for v in by_channel.values())
print("rows: %d   total GPU interval time: %.1f ms" % (rows, total / 1e6))
print()
print("=== by GPU channel ===")
for k, (n, d) in sorted(by_channel.items(), key=lambda x: -x[1][1]):
    print("  %-22s %7d intervals  %9.1f ms  (%5.1f%%)  avg %8.1f us" %
          (k or "(none)", n, d/1e6, 100*d/max(total,1), d/max(n,1)/1000))
print()
print("=== top encoders by total GPU time ===")
for (c, l), (n, d) in sorted(by_label.items(), key=lambda x: -x[1][1])[:15]:
    print("  %-10s %-46s %6d x  %8.1f ms  avg %7.1f us" % (c[:10], l or "(unlabelled)", n, d/1e6, d/max(n,1)/1000))
print()
durations.sort()
if durations:
    def pct(p): return durations[min(len(durations)-1, int(len(durations)*p))]/1000.0
    print("=== interval duration distribution (us) ===")
    print("  p50 %.1f   p90 %.1f   p99 %.1f   max %.1f" % (pct(.5), pct(.9), pct(.99), durations[-1]/1000.0))
