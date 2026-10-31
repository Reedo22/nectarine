#!/usr/bin/env python3
"""Self-time profile from a macOS `sample` report: per thread, which binary the CPU was in.

  sample <pid> 10 1 -file out.txt      (10 s at 1 ms)
  sample-profile.py out.txt [--modules modules.txt] [--top 12]

`sample` prints a call tree per thread with an inclusive sample count on every node; a node's
self time is its count minus its children's. Frames are attributed to their binary ("in X").
Translated Windows code has no Mach-O image, so it shows up as "???": with --modules (lines of
"<start-hex> <end-hex> <name>", e.g. from winedbg's `info share`) those addresses are mapped to
their PE module. Idle waits (mach_msg, __psynch_cvwait, kevent, os_sync_wait_on_address, ...) are
reported separately so the busy part stands out.
"""
import argparse, collections, re, sys

NODE = re.compile(r"^(?P<indent>[ +!:|]*)(?P<count>\d+) (?P<frame>.+)$")
IN_BIN = re.compile(r"\(in ([^)]+)\)")
ADDR = re.compile(r"\[(0x[0-9a-f]+)")
THREAD = re.compile(r"^\s*\d+ Thread_(\d+)(?:[: ]+(.*))?$")
IDLE = ("mach_msg", "__psynch_cvwait", "kevent", "__workq_kernreturn", "os_sync_wait_on_address",
        "__semwait_signal", "__select", "poll", "__ulock_wait", "semaphore_wait", "read$NOCANCEL",
        "__psynch_mutexwait", "nanosleep", "usleep", "__wait4")


def load_modules(path):
    mods = []
    for line in open(path):
        p = line.split()
        if len(p) >= 3:
            try:
                mods.append((int(p[0], 16), int(p[1], 16), p[2]))
            except ValueError:
                pass
    return sorted(mods)


def binary_of(frame, mods):
    m = IN_BIN.search(frame)
    name = m.group(1) if m else "?"
    if name in ("???", "?") or frame.startswith("???"):
        a = ADDR.search(frame)
        if a and mods:
            x = int(a.group(1), 16)
            for lo, hi, n in mods:
                if lo <= x < hi:
                    return "PE:" + n
        return "translated/unknown"
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("report"); ap.add_argument("--modules"); ap.add_argument("--top", type=int, default=12)
    a = ap.parse_args()
    mods = load_modules(a.modules) if a.modules else []
    lines = open(a.report, errors="replace").read().split("\n")
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("Call graph:")) + 1
    except StopIteration:
        sys.exit("no call graph in report")

    threads = []           # (name, total, Counter(binary -> self), idle)
    stack = []             # [(depth, count, frame, child_sum)]
    cur = None

    def flush(upto_depth):
        while stack and stack[-1][0] >= upto_depth:
            d, c, f, kids = stack.pop()
            self_n = c - kids
            if self_n > 0 and cur is not None:
                b = binary_of(f, mods)
                fn = f.split("  (in")[0].strip()
                if "<unknown binary>" in f and not b.startswith("PE:"):
                    # Rosetta/kernel trampolines have no image: judge them by the nearest named caller.
                    named = next((x[2] for x in reversed(stack) if "<unknown binary>" not in x[2]), "")
                    fn = named.split("  (in")[0].strip()
                    b = "rosetta/kernel under " + (binary_of(named, mods) if named else "?")
                if any(fn.startswith(w) for w in IDLE):
                    cur[3] += self_n
                else:
                    cur[2][b] += self_n
            if stack:
                stack[-1][3] += c

    for l in lines[start:]:
        if not l.strip():
            continue
        if l.startswith("Total number in stack") or l.startswith("Sort by top of stack"):
            break
        t = THREAD.match(l)
        if t and not l.lstrip().startswith("+"):
            flush(0)
            m = NODE.match(l)
            cur = [("Thread_%s %s" % (t.group(1), t.group(2) or "")).strip(), int(m.group("count")),
                   collections.Counter(), 0]
            threads.append(cur)
            continue
        m = NODE.match(l)
        if not m or cur is None:
            continue
        depth = len(m.group("indent"))
        flush(depth)
        stack.append([depth, int(m.group("count")), m.group("frame"), 0])
    flush(0)

    total_busy = sum(sum(t[2].values()) for t in threads)
    overall = collections.Counter()
    for t in threads:
        overall.update(t[2])
    print("busy samples %d (idle waits excluded)\n" % total_busy)
    print("== by binary, all threads")
    for b, n in overall.most_common(a.top):
        print("%6.1f%%  %6d  %s" % (100.0 * n / max(total_busy, 1), n, b))
    print("\n== busiest threads")
    for t in sorted(threads, key=lambda t: -sum(t[2].values()))[:8]:
        busy = sum(t[2].values())
        if not busy:
            continue
        top = ", ".join("%s %d%%" % (b, 100 * n // busy) for b, n in t[2].most_common(4))
        print("%6d busy / %6d idle  %-40s %s" % (busy, t[3], t[0][:40], top))


if __name__ == "__main__":
    main()
