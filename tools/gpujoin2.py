#!/usr/bin/env python3
"""Attribute GPU time to named encoders -- correctly this time.

Gotcha: xctrace XML names elements after the column's ENGINEERING TYPE, not its mnemonic.
So `encoder-label` appears as <metal-object-label> and `encoder-id` as
<metal-command-buffer-id>, several per row, distinguished only by ORDER:

  encoders-list: metal-object-label x4 = [cmdbuf, cmdbuf-indexed, ENCODER, encoder-indexed]
                 metal-command-buffer-id x2 = [cmdbuffer-id, ENCODER-ID]
  gpu-intervals: metal-command-buffer-id x2 = [cmdbuffer-id, ENCODER-ID]

Values are interned: first use carries id="N" + text, later uses are ref="N".
"""
import sys, xml.etree.ElementTree as ET
from collections import defaultdict

def rows(path):
    vals = {}
    def val(el):
        r = el.get("ref")
        if r is not None: return vals.get(r, "")
        i = el.get("id"); t = el.text or ""
        if i is not None: vals[i] = t
        return t
    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag != "row": continue
        seq = defaultdict(list)
        for c in el.iter():
            if c is el: continue
            seq[c.tag].append(val(c))
        yield seq
        el.clear()

enc_path, gpu_path = sys.argv[1], sys.argv[2]

labels = {}
for s in rows(enc_path):
    ids = s.get("metal-command-buffer-id", [])
    labs = s.get("metal-object-label", [])
    if len(ids) >= 2 and len(labs) >= 3:
        labels[ids[1]] = labs[2]
print("encoder labels found: %d" % len(labels))

by = defaultdict(lambda: [0, 0.0]); tot = 0.0
for s in rows(gpu_path):
    d = 0.0
    for x in s.get("duration", [])[:1]:
        try: d = float(x)
        except ValueError: d = 0.0
    chan = (s.get("gpu-channel-name") or [""])[0]
    ids = s.get("metal-command-buffer-id", [])
    eid = ids[1] if len(ids) >= 2 else ""
    lab = labels.get(eid, "(unmatched)")
    # strip MoltenVK's boilerplate prefix so our size/format tag is readable
    lab = lab.replace("vkCmdBeginRenderPass RenderEncoder & ", "").replace("vkCmdBeginRenderPass RenderEncoder", "RenderPass")
    by[(chan, lab)][0] += 1; by[(chan, lab)][1] += d; tot += d

print("total GPU interval time: %.1f ms\n" % (tot/1e6))
print("=== GPU time by pass (label = attachment size/format) ===")
for (c, l), (n, d) in sorted(by.items(), key=lambda x: -x[1][1])[:20]:
    print("  %-9s %-40s %6d x %8.1f ms (%4.1f%%) avg %7.1f us" %
          (c[:9], l[:40], n, d/1e6, 100*d/max(tot,1), d/max(n,1)/1000))
