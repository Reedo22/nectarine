#!/usr/bin/env python3
"""Nectarine crash collector: run after a game session; files a local crash report if anything broke.

Signals: Wine unhandled exceptions/page faults (+ winedbg --auto backtrace, AeDebug is on in our
prefixes), assertions/fatal errors, GPU faults (Metal command-buffer errors, VK_ERROR_DEVICE_LOST,
gpu-guard kills), backend-fallback demotions ($WINEPREFIX/nectarine/backends/*.state) and macOS
crash reports (*.ips) written during the session.

Reports go to ~/nectarine-crashes/<time>-<appid>-<signature>/ (report.json, report.md, log excerpt,
copied .ips); one line per report in ~/nectarine-crashes/index.tsv. Usernames and home paths are
scrubbed. Nothing is uploaded: report.md is ready to paste into an issue.

  nectarine-crash.py --log LOG --exe EXE [--appid N] [--start EPOCH] [--end EPOCH] [--engine-root DIR] [--prefix DIR]
  nectarine-crash.py --summary          # crash signatures grouped across all reports
Stdlib only, Python 3.9 (macOS CommandLineTools).
"""
import argparse, glob, hashlib, json, os, platform, re, shutil, subprocess, sys, time

HOME = os.path.expanduser("~")
OUT = os.environ.get("NECTARINE_CRASH_DIR") or os.path.join(HOME, "nectarine-crashes")
USER = os.path.basename(HOME)

WINE_CRASH = re.compile(r"(wine: Unhandled (?:page fault|exception)[^\n]*|Unhandled exception: [^\n]*)")
FATAL = re.compile(r"(Assertion failed[^\n]*|Fatal error[^\n]*|terminate called[^\n]*|"
                   r"abnormal program termination[^\n]*|err:seh:[^\n]*(?:RaiseException|unhandled)[^\n]*)", re.I)
GPU = re.compile(r"(VK_ERROR_DEVICE_LOST[^\n]*|MTLCommandBufferError[^\n]*|kIOGPUCommandBufferCallbackError\w*[^\n]*|"
                 r"IOGPUCommandQueue[^\n]*(?:timeout|error)[^\n]*|GPU (?:hang|restart|timeout)[^\n]*|"
                 r"\[gpu-guard\][^\n]*KILL: (?!runtime cap)[^\n]*)")
# winedbg --auto backtrace frames: "=>0 0x... in module (+0x1234) symbol"
FRAME = re.compile(r"^\s*=?>?\s*\d+ 0x[0-9a-f]+ (?:in|\w+ in) ([\w.\-]+) \(\+?(0x[0-9a-f]+)\)", re.M | re.I)


def scrub(text):
    return text.replace(HOME, "~").replace("/Users/%s" % USER, "~").replace(USER, "<user>")


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def system_info():
    return {
        "chip": sh(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "gpu_cores": sh(["sh", "-c", "ioreg -rc AGXAccelerator | grep -m1 gpu-core-count | grep -oE '[0-9]+$'"]),
        "ram_gb": round(int(sh(["sysctl", "-n", "hw.memsize"]) or 0) / 2**30),
        "macos": sh(["sw_vers", "-productVersion"]) + " (" + sh(["sw_vers", "-buildVersion"]) + ")",
        "machine": platform.machine(),
    }


def engine_info(root):
    if not root or not os.path.isdir(root):
        return {}
    info = {"root": scrub(root), "wine": sh([os.path.join(root, "bin", "wine"), "--version"])}
    for name in ("lib/wine/x86_64-unix/ntdll.so", "bin/wineserver"):
        p = os.path.join(root, name)
        if os.path.exists(p):
            info[name + ".sha256"] = hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]
    return info


def manifest(text):
    """The '### key=value' header gsession-inner writes at the top of every log."""
    m = {}
    for line in text.splitlines()[:40]:
        if line.startswith("### ") and "=" in line:
            for kv in line[4:].split():
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    m[k] = scrub(v)
    return m


def backend_events(prefix, start):
    ev = []
    for f in glob.glob(os.path.join(prefix or "", "nectarine", "backends", "*.state")):
        if os.path.getmtime(f) >= start - 5:
            ev.append(open(f, errors="replace").read().strip())
    return ev


def ips_reports(start, end, exe):
    """macOS crash/GPU reports written since the session started that concern Wine, the game or the GPU."""
    found = []
    exe_l = (exe or "").lower()
    for d in ("/Library/Logs/DiagnosticReports", os.path.join(HOME, "Library/Logs/DiagnosticReports")):
        for f in glob.glob(os.path.join(d, "*.ips")):
            if not start - 5 <= os.path.getmtime(f) <= end + 30:
                continue
            base = os.path.basename(f).lower()
            head = open(f, errors="replace").read(4096).lower()
            if (base.startswith(("wine", "gpuevent", "preloader", "windowserver")) or
                    (exe_l and exe_l.split(".")[0] in head) or "/wine" in head):
                found.append(f)
    return found


def ips_summary(path):
    """First crashed-thread frames from a .ips (JSON after a one-line header)."""
    try:
        head, body = open(path, errors="replace").read().split("\n", 1)
        d = json.loads(body)
        exc = d.get("exception", {})
        imgs = d.get("usedImages", [])
        th = next((t for t in d.get("threads", []) if t.get("triggered")), None)
        frames = []
        for fr in (th or {}).get("frames", [])[:8]:
            img = imgs[fr["imageIndex"]].get("name", "?") if fr.get("imageIndex", -1) < len(imgs) else "?"
            frames.append("%s %s+%s" % (img, fr.get("symbol", "?"), fr.get("symbolLocation", fr.get("imageOffset", "?"))))
        return {"process": scrub(d.get("procPath", json.loads(head).get("name", "?"))),
                "exception": "%s %s" % (exc.get("type", ""), exc.get("signal", "")), "frames": frames}
    except Exception:
        return None


def signature(kind, detail, frames):
    """Stable across runs: crash kind + first non-system faulting module/offset or the error text."""
    key = kind + "|"
    if frames:
        key += "%s+%s" % frames[0]
    else:
        key += re.sub(r"0x[0-9a-f]+|\d+", "#", detail)[:120]
    return hashlib.sha1(key.encode()).hexdigest()[:10]


def collect(a):
    text = open(a.log, errors="replace").read() if os.path.exists(a.log) else ""
    findings = []
    for kind, rx in (("wine-crash", WINE_CRASH), ("fatal", FATAL), ("gpu", GPU)):
        for m in rx.finditer(text):
            findings.append((kind, m.start(), m.group(1).strip()))
    backends = backend_events(a.prefix, a.start)
    demoted = [b for b in backends if not b.startswith("good")]
    ips = ips_reports(a.start, a.end, a.exe)
    if not findings and not demoted and not ips:
        return None

    findings.sort(key=lambda f: f[1])
    kind, pos, detail = findings[0] if findings else (("backend-fallback", 0, demoted[0]) if demoted else ("macos-crash", 0, os.path.basename(ips[0])))
    frames = FRAME.findall(text[pos:pos + 20000]) if kind == "wine-crash" else []
    if kind == "macos-crash" and ips:
        s = ips_summary(ips[0]) or {}
        detail = "%s: %s" % (s.get("process"), s.get("exception"))
        frames = [tuple(f.split(" ", 1)) for f in s.get("frames", [])[:1]]
    sig = signature(kind, detail, frames)

    lines = text.splitlines()
    at = text[:pos].count("\n") if findings else len(lines)
    excerpt = "\n".join(lines[max(0, at - 60):at + 80])
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(a.start))
    d = os.path.join(OUT, "%s-%s-%s" % (stamp, a.appid or "none", sig))
    os.makedirs(d, exist_ok=True)
    for f in ips:
        shutil.copy2(f, os.path.join(d, os.path.basename(f)))
    report = {
        "signature": sig, "kind": kind, "detail": scrub(detail),
        "frames": ["%s+%s" % f for f in frames[:12]],
        "all_findings": [{"kind": k, "text": scrub(t)} for k, _, t in findings[:20]],
        "backend_states": backends, "macos_reports": [r for r in map(ips_summary, ips) if r],
        "game": {"appid": a.appid, "exe": a.exe, "session_start": time.strftime("%F %T", time.localtime(a.start))},
        "launcher": manifest(text), "engine": engine_info(a.engine_root), "system": system_info(),
    }
    json.dump(report, open(os.path.join(d, "report.json"), "w"), indent=1)
    open(os.path.join(d, "log-excerpt.txt"), "w").write(scrub(excerpt))
    md = ["## Crash: %s in %s (appid %s)" % (kind, a.exe, a.appid),
          "", "**Signature** `%s`  \n**What** `%s`" % (sig, scrub(detail)),
          "**Mac** %(chip)s, %(ram_gb)s GB, macOS %(macos)s" % report["system"],
          "**Engine** %s, backend states: %s" % (report["engine"].get("wine", "?"), ", ".join(backends) or "-"),
          "", "<details><summary>Backtrace / reports</summary>", "", "```",
          "\n".join(report["frames"]) or "(no Wine backtrace)",
          *["%s: %s\n  %s" % (r.get("process"), r.get("exception"), "\n  ".join(r.get("frames", []))) for r in report["macos_reports"]],
          "```", "</details>", "", "<details><summary>Log excerpt</summary>", "", "```",
          scrub("\n".join(lines[max(0, at - 15):at + 40])), "```", "</details>"]
    open(os.path.join(d, "report.md"), "w").write("\n".join(md) + "\n")
    with open(os.path.join(OUT, "index.tsv"), "a") as idx:
        idx.write("\t".join([time.strftime("%F %T", time.localtime(a.start)), str(a.appid), a.exe, kind, sig,
                             scrub(detail)[:140], scrub(d)]) + "\n")
    return d


def summary():
    rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(OUT, "index.tsv"))] if os.path.exists(os.path.join(OUT, "index.tsv")) else []
    groups = {}
    for r in rows:
        if len(r) >= 6:
            groups.setdefault(r[4], []).append(r)
    for sig, rs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        games = sorted({r[2] for r in rs})
        print("%s  %3dx  %-16s %s  [%s]" % (sig, len(rs), rs[-1][3], rs[-1][5][:70], ", ".join(games)[:80]))
    if not groups:
        print("no crash reports")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log"); ap.add_argument("--exe", default="")
    ap.add_argument("--appid", default=""); ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--end", type=float, default=0)
    ap.add_argument("--engine-root", default=""); ap.add_argument("--prefix", default="")
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    if a.summary:
        return summary()
    if not a.log:
        ap.error("--log is required")
    if not a.start:
        a.start = os.path.getctime(a.log) if os.path.exists(a.log) else time.time() - 3600
    if not a.end:
        a.end = os.path.getmtime(a.log) if os.path.exists(a.log) else time.time()
    d = collect(a)
    print("crash report: %s" % scrub(d) if d else "no crash")


if __name__ == "__main__":
    sys.exit(main())
