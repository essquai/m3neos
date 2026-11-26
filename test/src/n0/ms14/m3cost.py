#!/usr/bin/env python3
"""m3cost.py: collector-cost comparison for ms14 (milestone M6).

usage:  python3 m3cost.py [RUNS] [WASM] [NATIVE]
        python3 m3cost.py --reparse m3cost.out     (re-read saved logs, no runs)
        defaults: RUNS=5  WASM=wasm32/ms14  NATIVE=x86_64/ms14 (skipped if missing)

Runs ms14 RUNS times on every Wasmer backend this build offers (found from
`wasmer run --help`), plus the default (no flag), plus the native program if
present.  Runs are interleaved (backend A, B, C, A, B, C ...) so slow drift hits
all of them equally.  Each run has a 300 s limit enforced here; stdin is
/dev/null.  Raw output goes to m3cost.out/, a table to stdout.
Ctrl-C stops everything.
"""
import os, re, subprocess, sys, time, statistics

runs = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] != "--reparse" else 5
wasm = sys.argv[2] if len(sys.argv) > 2 else "wasm32/ms14"
native = sys.argv[3] if len(sys.argv) > 3 else "x86_64/ms14"
LIMIT = 300

# Reference values from the v18 record (one run each, microseconds): W32 = WAMR
# classic interpreter, Px86 = native x86_64.  Key: (label, pass).
REF = {
    ("make50", 1):           (126328, 5),
    ("down+catch+scrub", 1): (1336, 20),   ("down+catch+scrub", 2): (3777, 38),
    ("collect#1", 1):        (245683, 367), ("collect#2", 1): (513207, 2502),
    ("collect#1", 2):        (485249, 1528), ("collect#2", 2): (485983, 1229),
    ("churn", 1):            (36874, 1346),  ("churn", 2): (35814, 346),
}
ORDER = [("make50", 1), ("down+catch+scrub", 1), ("collect#1", 1), ("churn", 1),
         ("collect#2", 1), ("make50", 2), ("down+catch+scrub", 2), ("collect#1", 2),
         ("churn", 2), ("collect#2", 2)]

def backends():
    try:
        h = subprocess.run(["wasmer", "run", "--help"], capture_output=True,
                           text=True, stdin=subprocess.DEVNULL, timeout=60)
        text = h.stdout + h.stderr
    except Exception as e:
        sys.exit(f"cannot run `wasmer run --help`: {e}")
    found = [b for b in ("singlepass", "cranelift", "llvm") if f"--{b}" in text]
    return found

def parse(out):
    seen, vals = {}, {}
    for m in re.finditer(r"^(\S+) us=(-?\d+)\s*$", out, re.M):
        lab = m.group(1)
        seen[lab] = seen.get(lab, 0) + 1
        vals[(lab, seen[lab])] = int(m.group(2))
    return vals

def run_one(cmd):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=LIMIT)
        return p.returncode, p.stdout, p.stderr, time.time() - t0
    except subprocess.TimeoutExpired as e:
        return "TIMEOUT", (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), "", time.time() - t0

REPARSE = len(sys.argv) > 2 and sys.argv[1] == "--reparse"
cfgs = []   # (name, command)
if not REPARSE:
    for b in backends():
        cfgs.append((b, ["wasmer", "run", f"--{b}", wasm]))
    cfgs.append(("default", ["wasmer", wasm]))
    if os.path.exists(native):
        cfgs.append(("native", [native]))
    print("backends found in this wasmer:", ", ".join(c[0] for c in cfgs if c[0] not in ("default", "native")) or "none listed")
    print("configurations:", ", ".join(c[0] for c in cfgs), f"| {runs} runs each\n")


def load_logs(d):
    names = []
    for f in sorted(os.listdir(d)):
        m = re.match(r"(.+)-(\d+)\.txt$", f)
        if m and m.group(1) not in names: names.append(m.group(1))
    R = {n: [] for n in names}; F = {n: [] for n in names}; W = {n: [] for n in names}
    for f in sorted(os.listdir(d)):
        m = re.match(r"(.+)-(\d+)\.txt$", f)
        if not m: continue
        t = open(os.path.join(d, f), errors="replace").read()
        hm = re.search(r"^exit (\S+)\s+secs ([\d.]+)", t, re.M)
        rc = hm.group(1) if hm else "?"; secs = float(hm.group(2)) if hm else 0.0
        v = parse(t)
        if rc == "0" and len(v) >= 9: R[m.group(1)].append(v); W[m.group(1)].append(secs)
        else:
            err = t.split("--- stderr", 1)[-1].strip().splitlines()
            F[m.group(1)].append((rc, "\n      ".join(err[:6] + (["..."] + err[-3:] if len(err) > 9 else err[6:]))))
    return names, R, F, W

if len(sys.argv) > 2 and sys.argv[1] == "--reparse":
    d = sys.argv[2]
    names, res, fail, wall = load_logs(d)
    class C: pass
    cfgs = [(n, None) for n in names]
    runs = max(len(res[n]) + len(fail[n]) for n in names)
    print(f"re-reading {d}: configurations {', '.join(names)}\n")
else:
    os.makedirs("m3cost.out", exist_ok=True)

    res = {c[0]: [] for c in cfgs}
    fail = {c[0]: [] for c in cfgs}
    wall = {c[0]: [] for c in cfgs}
    for n in range(1, runs + 1):
        for name, cmd in cfgs:
            rc, out, err, secs = run_one(cmd)
            open(f"m3cost.out/{name}-{n}.txt", "w").write(f"$ {' '.join(cmd)}\nexit {rc}  secs {secs:.2f}\n--- stdout\n{out}\n--- stderr\n{err}\n")
            v = parse(out + "\n" + err)
            if rc == 0 and len(v) >= 9:
                res[name].append(v); wall[name].append(secs)
                note = f"collect#1 p1 = {v.get(('collect#1',1),'?')} us"
            else:
                first = (err.strip().splitlines() or ["(no stderr)"])[-1][:100]
                fail[name].append((rc, first))
                note = f"FAILED exit={rc}: {first}"
            print(f"run {n}/{runs}  {name:<10} {secs:6.1f} s   {note}", flush=True)


def med(l): return int(statistics.median(l))
print("\n=== medians over the runs, in microseconds (every run is in m3cost.out/) ===")
cols = [c[0] for c in cfgs if res[c[0]]]
print(f"{'item':<24}" + "".join(f"{c:>13}" for c in cols) + f"{'WAMR ref':>13}{'native ref':>12}")
for key in ORDER:
    row = f"{key[0]+' p'+str(key[1]):<24}"
    for c in cols:
        xs = [r[key] for r in res[c] if key in r]
        row += f"{med(xs):>13,}" if xs else f"{'-':>13}"
    ref = REF.get(key)
    row += f"{ref[0]:>13,}{ref[1]:>12,}" if ref else f"{'':>13}{'':>12}"
    print(row)
print(f"{'wall seconds (whole run)':<24}" + "".join(f"{statistics.median(wall[c]):>13.2f}" for c in cols))

collects = [("collect#1",1),("collect#2",1),("collect#1",2),("collect#2",2)]
def cmean(c):
    xs = [r[k] for r in res[c] for k in collects if k in r]
    return statistics.median(xs) if xs else None
print("\n=== median single collect, and how many times the native one ===")
base = cmean("native") if "native" in cols else None
for c in cols:
    m = cmean(c)
    s = f"{c:<12} {int(m):>10,} us"
    if base and c != "native": s += f"   about {m/base:,.0f}x native"
    print(s)
print(f"{'WAMR (v18)':<12} {int(statistics.median([REF[k][0] for k in collects])):>10,} us")

bad = [(c, f) for c in fail for f in fail[c]]
if bad:
    print("\n=== failures ===")
    for c in fail:
        if fail[c]:
            print(f"{c}: {len(fail[c])} of {runs} runs failed")
            seen = set()
            for rc, txt in fail[c]:
                if (rc, txt) in seen: continue
                seen.add((rc, txt)); print(f"    exit {rc}:\n      {txt}")
print("\nraw logs: m3cost.out/")
