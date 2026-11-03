#!/usr/bin/env python3
"""SSA-across-safepoint audit.

For every function in an LLVM .ll file: find ptr-typed SSA values (incl. ptr params) that are LIVE ACROSS a
safepoint call, i.e. defined before the call and still needed after it.  On wasm32 such a value lives in a
wasm local, which a conservative scan of linear memory cannot see.  A value is 'homed' if it was also stored
to stack/static memory (alloca/global-rooted address) by a store that dominates the call.

Safepoint = any call/invoke except llvm.* intrinsics (conservative: includes the nthr_park poll call).
Usage: audit.py file.ll [--detail] [--main-only]
  Default: analyse EVERY function in the file.  --main-only restricts to Main__* and Loque* (the ms8 test program).
  The last line gives the totals; a gate passes only if 'not homed' is 0 and at least one function was analysed.
"""
import re, sys
from collections import defaultdict

NAME = re.compile(r'%[\w.$-]+')
DETAIL = '--detail' in sys.argv

def split_functions(text):
    funcs, cur, name, params = [], None, None, ''
    for line in text.splitlines():
        if cur is None:
            m = re.match(r'define [^@]*@([\w.$-]+)\((.*)\)[^{]*\{\s*$', line)
            if m:
                name, params, cur = m.group(1), m.group(2), []
        else:
            if line.startswith('}'):
                funcs.append((name, params, cur)); cur = None
            else:
                cur.append(line)
    return funcs

def result_type(rhs):
    if rhs.startswith('alloca'): return 'ptr'
    m = re.match(r'load\s+(?:atomic\s+|volatile\s+)*([\w{}\[\] ,*.%]+?),\s*ptr', rhs)
    if m: return m.group(1).strip()
    if rhs.startswith('getelementptr') or rhs.startswith('inttoptr') or rhs.startswith('addrspacecast'): return 'ptr'
    if rhs.startswith('ptrtoint'): return 'ptr'   # pointer bits held in an integer: track like a pointer
    m = re.match(r'(?:tail\s+|musttail\s+|notail\s+)?(?:call|invoke)\s+(?:[\w]+\s+)*?(ptr|void|i\d+|float|double|x86_fp80)\s+(?:\([^)]*\)\s+)?[@%]', rhs)
    if m: return m.group(1)
    m = re.match(r'(?:phi|select\s+i1\s+\S+,)\s*(ptr)', rhs)
    if m: return 'ptr'
    return 'other'

def parse(body, params):
    blocks, order, curb = {}, [], None
    def newblock(n):
        nonlocal curb
        curb = n; blocks[n] = {'ins': [], 'succ': []}; order.append(n)
    newblock('entry')
    for line in body:
        s = line.strip()
        if not s or s.startswith(';'): continue
        m = re.match(r'([\w.$-]+):', s)
        if m and not s.startswith('%'):
            if m.group(1) != 'entry' or blocks['entry']['ins']: newblock(m.group(1))
            continue
        d = re.match(r'(%[\w.$-]+)\s*=\s*(.*)', s)
        res, rhs = (d.group(1), d.group(2)) if d else (None, s)
        ins = {'res': res, 'rhs': rhs, 'type': result_type(rhs) if res else None, 'line': s}
        op = re.match(r'(?:tail\s+)?(\w+)', rhs).group(1)
        ins['op'] = op
        blocks[curb]['ins'].append(ins)
        if op in ('br', 'switch', 'invoke'):
            for l in re.findall(r'label\s+%([\w.$-]+)', rhs): blocks[curb]['succ'].append(l)
    pnames = [(m.group(2)) for m in re.finditer(r'(ptr)\s+(?:\w+\s+)*?(%[\w.$-]+)', params)]
    return blocks, order, pnames

def uses_of(ins):
    rhs = ins['rhs']
    if rhs.startswith('call') or rhs.startswith('tail call'):
        if re.search(r'@llvm\.dbg\.', rhs): return []
    rhs2 = re.sub(r'label\s+%[\w.$-]+', '', rhs)
    rhs2 = re.sub(r'![\w.]+', '', rhs2)
    return [n for n in NAME.findall(rhs2)]

def is_safepoint(ins):
    if ins['op'] not in ('call', 'invoke'): return False
    m = re.search(r'@([\w.$-]+)\(', ins['rhs'])
    if m and m.group(1).startswith('llvm.'): return False
    return True

def callee(ins):
    m = re.search(r'(@[\w.$-]+|%[\w.$-]+)\(', ins['rhs'])
    return m.group(1) if m else '?'

def analyse(fname, params, body):
    blocks, order, pnames = parse(body, params)
    deftab = {}          # name -> (block, idx, ins)
    for p in pnames: deftab[p] = ('param', -1, None)
    for b in order:
        for i, ins in enumerate(blocks[b]['ins']):
            if ins['res']: deftab[ins['res']] = (b, i, ins)
    ptrs = {n for n, (b, i, ins) in deftab.items() if b == 'param' or (ins and ins['type'] == 'ptr')}

    # liveness over ptr-typed names
    use, dfn = {}, {}
    for b in order:
        u, d = set(), set()
        for ins in blocks[b]['ins']:
            for n in uses_of(ins):
                if n in ptrs and n not in d: u.add(n)
            if ins['res'] in ptrs: d.add(ins['res'])
        use[b], dfn[b] = u, d
    live_in = {b: set() for b in order}; live_out = {b: set() for b in order}
    changed = True
    while changed:
        changed = False
        for b in reversed(order):
            out = set()
            for s in blocks[b]['succ']:
                if s in live_in: out |= live_in[s]
            inn = use[b] | (out - dfn[b])
            if out != live_out[b] or inn != live_in[b]:
                live_out[b], live_in[b] = out, inn; changed = True

    # dominators (iterative, for 'store dominates call')
    preds = defaultdict(list)
    for b in order:
        for s in blocks[b]['succ']:
            if s in blocks: preds[s].append(b)
    allb = set(order); dom = {b: set(allb) for b in order}; dom['entry'] = {'entry'}
    changed = True
    while changed:
        changed = False
        for b in order:
            if b == 'entry': continue
            ps = [dom[p] for p in preds[b]] or [set()]
            nd = set.intersection(*ps) | {b}
            if nd != dom[b]: dom[b] = nd; changed = True

    # origin classification
    def root(n, depth=0):
        """follow GEP/bitcast chains to a root kind"""
        if n.startswith('@'): return 'static'
        if depth > 12 or n not in deftab: return 'unknown'
        b, i, ins = deftab[n]
        if b == 'param': return 'param'
        if ins['op'] == 'alloca': return 'stack'
        if ins['op'] in ('getelementptr', 'addrspacecast'):
            m = re.search(r'getelementptr[^,]*,\s*(?:\S+\s+)*?ptr\s+(%[\w.$-]+|@[\w.$-]+)', ins['rhs'])
            if m: return root(m.group(1), depth + 1)
        if ins['op'] == 'load': return 'loaded'
        if ins['op'] == 'call': return 'call'
        return 'other'
    def origin(n):
        b, i, ins = deftab[n]
        if b == 'param': return 'param'
        op = ins['op']
        if op == 'alloca': return 'stack-address'
        if op == 'getelementptr':
            r = root(n)
            return {'stack': 'stack-address', 'static': 'static-address'}.get(r, 'interior-ptr(' + r + ')')
        if op == 'load':
            m = re.search(r'load\s+(?:atomic\s+|volatile\s+)*[^,]+,\s*ptr\s+(%[\w.$-]+|@[\w.$-]+)', ins['rhs'])
            src = m.group(1) if m else '?'
            r = root(src)
            if '@nthr_' in ins['rhs'] or src in ('%tla', '%cur'): return 'thread-ctx'
            return {'stack': 'slot-copy', 'static': 'global-load'}.get(r, 'heap/other-load')
        if op == 'call':
            return 'call-result:' + callee(ins)
        return op

    # stores of each ptr value: where, and to what kind of memory
    stores = defaultdict(list)
    for b in order:
        for i, ins in enumerate(blocks[b]['ins']):
            m = re.match(r'store\s+(?:atomic\s+|volatile\s+)*ptr\s+(%[\w.$-]+),\s*ptr\s+(%[\w.$-]+|@[\w.$-]+)', ins['rhs'])
            if m: stores[m.group(1)].append((b, i, root(m.group(2))))

    findings = []
    for b in order:
        live = set(live_out[b])
        for i in range(len(blocks[b]['ins']) - 1, -1, -1):
            ins = blocks[b]['ins'][i]
            if is_safepoint(ins):
                across = {n for n in live if n != ins['res']}
                for n in sorted(across):
                    og = origin(n)
                    if og in ('stack-address', 'static-address', 'thread-ctx'): continue
                    homed = 'NO'
                    for (sb, si, kind) in stores.get(n, []):
                        if kind in ('stack', 'static') and ((sb == b and si < i) or (sb != b and sb in dom[b])):
                            homed = 'yes'; break
                    if homed == 'NO' and any(k not in ('stack', 'static') for (_, _, k) in stores.get(n, [])): homed = 'heap-only'
                    findings.append((n, og, homed, b, i, callee(ins), ins['line']))
            for n in uses_of(ins):
                if n in ptrs: live.add(n)
            if ins['res'] in live: live.discard(ins['res'])
    nsafe = sum(1 for b in order for ins in blocks[b]['ins'] if is_safepoint(ins))
    return findings, nsafe, deftab

tot = defaultdict(int)
percat = defaultdict(lambda: defaultdict(int))
text = open(sys.argv[1]).read()
rows = []
for fname, params, body in split_functions(text):
    if '--main-only' in sys.argv and not fname.startswith('Main__') and not fname.startswith('Loque'): continue
    f, nsafe, deftab = analyse(fname, params, body)
    c = defaultdict(int)
    for (n, og, homed, b, i, cal, line) in f:
        c[(og.split(':')[0] if og.startswith('call-result') else og.split('(')[0], homed)] += 1
    rows.append((fname, nsafe, len(f), f, c))
    for k, v in c.items(): percat[k][fname] += v; tot[k] += v

print(f"{'function':<18}{'safepoints':>11}{'live-across pairs':>19}   not homed")
for fname, nsafe, nf, f, c in rows:
    nh = sum(1 for x in f if x[2] == 'NO')
    print(f"{fname:<18}{nsafe:>11}{nf:>19}   {nh}")
print("\n(value, safepoint) pairs by origin and memory home:")
for (og, homed), v in sorted(tot.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"   {og:<28} homed={homed:<10} {v}")
print()
for fname, nsafe, nf, f, c in rows:
    for (n, og, homed, b, i, cal, line) in f:
        if homed != 'yes' or DETAIL:
            print(f"{fname}: {n} [{og}] homed={homed}  live across call to {cal} (block {b})")
            if DETAIL: print("      ", line[:140])
if not rows:
    print("WARNING: no functions were analysed (wrong file, or --main-only matched nothing) -- this is NOT a pass")
tot_s = sum(r[1] for r in rows); tot_p = sum(r[2] for r in rows)
tot_n = sum(1 for r in rows for x in r[3] if x[2] == 'NO')
print(f"TOTAL: functions {len(rows)}  safepoint call sites {tot_s}  live-across pairs {tot_p}  not homed {tot_n}")
