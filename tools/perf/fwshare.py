import re, sys, collections
"""fwshare.py sample.txt : share of busy (non-wait) samples by category, for threads that are mostly busy."""
NODE = re.compile(r"^(?P<i>[ +!:|]*)(?P<n>\d+) (?P<f>.+)$"); TH = re.compile(r"^\s*\d+ (Thread_\d+.*)$")
IDLE = ("os_sync_wait_on_address", "_pthread_wqthread", "mach_msg2_internal", "__psynch_cvwait", "_pthread_cond_wait",
        "kevent", "__workq_kernreturn", "caulk::", "_dispatch_sema4_wait", "semaphore_wait", "__semwait_signal",
        "read_reply_data", "NtDelayExecution", "cthread_yield", "__wine_reserve", "wait_select_reply")
WINE = ("ntdll.so", "win32u.so", "winemac.so", "wine", "winecoreaudio.so", "opengl32.so", "winevulkan.so", "dsound.so")
GFX = ("D3DMetal", "libd3dshared.dylib", "libMoltenVK.dylib", "winemetal.so")
def cat(b):
    if b in ("translated", "?"): return "translated game/Windows code"
    if b in WINE or b.endswith(".so") and "wine" in b: return "Wine native side"
    if b in GFX: return "D3DMetal / MoltenVK / DXMT"
    return "Apple system frameworks + kernel"
L = open(sys.argv[1], errors="replace").read().split("\n")
s = next(i for i, l in enumerate(L) if l.startswith("Call graph:")) + 1
threads = []; st = []
def binof(f):
    m = re.search(r"\(in ([^)]+)\)", f); return m.group(1) if m else "?"
def flush(d):
    while st and st[-1][0] >= d:
        dd, n, f, kids = st.pop(); self_n = n - kids
        if self_n > 0 and threads:
            unk = "<unknown binary>" in f or f.startswith("???")
            named = f
            if unk: named = next((x[2] for x in reversed(st) if "<unknown binary>" not in x[2] and not x[2].startswith("???")), "")
            fn = named.split("  (in")[0].strip()
            if not named or named.startswith("Thread_"): threads[-1][1]["translated"] += self_n
            elif any(fn.startswith(w) for w in IDLE): threads[-1][1]["WAIT"] += self_n
            else: threads[-1][1][binof(named)] += self_n
        if st: st[-1][3] += n
for l in L[s:]:
    if l.startswith("Total number"): break
    t = TH.match(l)
    if t and "+" not in l.split("Thread_")[0]:
        flush(0); threads.append((t.group(1), collections.Counter())); continue
    m = NODE.match(l)
    if not m: continue
    d = len(m.group("i")); flush(d); st.append([d, int(m.group("n")), m.group("f"), 0])
flush(0)
tot = collections.Counter()
for name, c in threads:
    busy = sum(c.values()) - c["WAIT"]
    if busy < 0.3 * sum(c.values()) or "rosetta" in name: continue
    for b, n in c.items():
        if b != "WAIT": tot[cat(b)] += n
T = sum(tot.values())
for k, v in tot.most_common(): print("%5.1f%%  %s" % (100.0 * v / T, k))
