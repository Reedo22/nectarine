import re, sys, collections
"""threadtop.py sample.txt [N] : per thread, top self functions (Rosetta trampolines -> named caller), waits excluded."""
NODE = re.compile(r"^(?P<i>[ +!:|]*)(?P<n>\d+) (?P<f>.+)$"); TH = re.compile(r"^\s*\d+ (Thread_\d+.*)$")
IDLE = ("os_sync_wait_on_address", "_pthread_wqthread", "mach_msg2_internal", "__psynch_cvwait", "_pthread_cond_wait",
        "kevent", "__workq_kernreturn", "caulk::", "_dispatch_sema4_wait", "semaphore_wait", "__semwait_signal", "read_reply_data")
L = open(sys.argv[1], errors="replace").read().split("\n"); N = int(sys.argv[2]) if len(sys.argv) > 2 else 4
s = next(i for i, l in enumerate(L) if l.startswith("Call graph:")) + 1
threads = []; st = []
def name(f): return f.split("  (in")[0].strip()[:70] + ("  [" + f.split("(in ")[1].split(")")[0] + "]" if "(in " in f else "")
def flush(d):
    while st and st[-1][0] >= d:
        dd, n, f, kids = st.pop(); self_n = n - kids
        if self_n > 0 and threads:
            if "<unknown binary>" in f or f.startswith("???"):
                named = next((x[2] for x in reversed(st) if "<unknown binary>" not in x[2] and not x[2].startswith("???")), "(translated code)")
                f = named
            fn = f.split("  (in")[0].strip()
            key = "WAIT" if any(fn.startswith(w) for w in IDLE) else name(f)
            threads[-1][1][key] += self_n
        if st: st[-1][3] += n
for l in L[s:]:
    if l.startswith("Total number"): break
    t = TH.match(l)
    if t and "+" not in l.split("Thread_")[0]:
        flush(0); threads.append((t.group(1)[:60], collections.Counter())); continue
    m = NODE.match(l)
    if not m: continue
    d = len(m.group("i")); flush(d); st.append([d, int(m.group("n")), m.group("f"), 0])
flush(0)
busy = sorted(threads, key=lambda t: -(sum(t[1].values()) - t[1]["WAIT"]))
if len(sys.argv) > 3:
    want = sys.argv[3].split(",")
    busy = [next(t for t in threads if t[0].split()[0] == "Thread_" + w) for w in want if any(t[0].split()[0] == "Thread_" + w for t in threads)]
for tn, c in busy[:N]:
    tot = sum(c.values()); b = tot - c["WAIT"]
    print("== %s  busy %d/%d" % (tn, b, tot))
    for k, v in c.most_common(14):
        if k != "WAIT": print("   %5.1f%%  %s" % (100.0 * v / tot, k))
