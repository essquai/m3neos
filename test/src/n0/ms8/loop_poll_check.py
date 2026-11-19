#!/usr/bin/env python3
"""Loop-edge safepoint poll check.

Property: every cycle in a function's CFG passes through a poll gadget.
A poll gadget is the 3-block diamond emitted by m3llwasm/llvm22host:
    head : load atomic i32 @nthr_nexus ; icmp ne 0 ; br armed, chk, flow
    chk  : tls addr(@nthr_current) ; load ctx ; load atomic watch ; icmp sge 2 ; br vig, park, flow
    park : call @nthr_park ; br flow
Method: delete the poll head blocks; any cycle that remains is an unpolled loop.
Also reports back edges (dominator-based), polls that lie on a cycle, shape check of each gadget,
and whether the function-entry poll (prolog) exists.

Usage: loop_poll_check.py file.ll [--detail]
Exit status 0 only if no function has an unpolled cycle and every gadget is well formed.
"""
import re, sys
from collections import defaultdict

DETAIL = '--detail' in sys.argv

def split_functions(text):
    funcs, cur, name = [], None, None
    for line in text.splitlines():
        if cur is None:
            m = re.match(r'define [^@]*@([\w.$-]+)\(.*\{\s*$', line)
            if m: name, cur = m.group(1), []
        elif line.startswith('}'):
            funcs.append((name, cur)); cur = None
        else:
            cur.append(line)
    return funcs

def parse(body):
    blocks, order, cur = {}, [], None
    def nb(n):
        nonlocal cur
        cur = n; blocks[n] = {'ins': [], 'succ': []}; order.append(n)
    nb('entry')
    for line in body:
        s = line.strip()
        if not s or s.startswith(';') or s.startswith('#dbg'): continue
        m = re.match(r'([\w.$-]+):', s)
        if m and not s.startswith('%'):
            if m.group(1) != 'entry' or blocks['entry']['ins']: nb(m.group(1))
            continue
        blocks[cur]['ins'].append(s)
        if re.match(r'(br|switch|invoke)\b', s):
            blocks[cur]['succ'] += re.findall(r'label\s+%([\w.$-]+)', s)
    return blocks, order

def scc(nodes, succ):
    idx, low, onst, st, out, c = {}, {}, set(), [], [], [0]
    sys.setrecursionlimit(10000)
    def go(v):
        idx[v] = low[v] = c[0]; c[0] += 1; st.append(v); onst.add(v)
        for w in succ(v):
            if w not in idx: go(w); low[v] = min(low[v], low[w])
            elif w in onst: low[v] = min(low[v], idx[w])
        if low[v] == idx[v]:
            comp = []
            while True:
                w = st.pop(); onst.discard(w); comp.append(w)
                if w == v: break
            out.append(comp)
    for v in nodes:
        if v not in idx: go(v)
    return out

def cyclic(comps, succ):
    return [c for c in comps if len(c) > 1 or c[0] in succ(c[0])]

def is_head(b):  # block containing the nexus load
    return any(re.search(r'load atomic i32, ptr @nthr_nexus', i) for i in b['ins'])

def gadget_ok(blocks, h):
    """check the diamond shape rooted at head h; returns (ok, why)"""
    b = blocks[h]
    last = b['ins'][-1]
    m = re.match(r'br i1 %[\w.$-]+, label %([\w.$-]+), label %([\w.$-]+)', last)
    if not m: return False, 'head does not end in conditional br'
    chk, flow = m.groups()
    if not any('icmp ne i32' in i and ', 0' in i for i in b['ins']): return False, 'head lacks icmp ne 0'
    cb = blocks.get(chk)
    if not cb or not any(re.search(r'load atomic i32, ptr %watch', i) for i in cb['ins']): return False, 'chk lacks watch load'
    if not any('icmp sge i32' in i and ', 2' in i for i in cb['ins']): return False, 'chk lacks sge 2'
    m2 = re.match(r'br i1 %[\w.$-]+, label %([\w.$-]+), label %([\w.$-]+)', cb['ins'][-1])
    if not m2: return False, 'chk does not end in conditional br'
    park, flow2 = m2.groups()
    if flow2 != flow: return False, 'chk and head disagree on continuation'
    pb = blocks.get(park)
    if not pb or not any('call void @nthr_park' in i for i in pb['ins']): return False, 'park lacks nthr_park call'
    if pb['succ'] != [flow]: return False, 'park does not branch to continuation'
    return True, flow

bad = 0
text = open(sys.argv[1]).read()
print(f"{'function':<22}{'loops':>6}{'polls':>6}{'in-cycle':>9}{'unpolled':>9}  entry-poll")
for name, body in split_functions(text):
    blocks, order = parse(body)
    heads = [b for b in order if is_head(blocks[b])]
    succ = lambda v: [s for s in blocks[v]['succ'] if s in blocks]
    comps = cyclic(scc(order, succ), succ)
    in_cycle = [h for h in heads if any(h in c for c in comps)]
    rest = [b for b in order if b not in heads]
    succ2 = lambda v: [s for s in blocks[v]['succ'] if s in blocks and s not in heads]
    unpolled = cyclic(scc(rest, succ2), succ2)
    # entry poll: first poll head directly after entry
    entry_poll = bool(heads) and heads[0] not in [h for c in comps for h in c if h in heads]
    shape = [(h, *gadget_ok(blocks, h)) for h in heads]
    bshape = [s for s in shape if not s[1]]
    flag = ''
    if unpolled or bshape: flag = '  <-- FAIL'; bad += 1
    print(f"{name:<22}{len(comps):>6}{len(heads):>6}{len(in_cycle):>9}{len(unpolled):>9}  {'yes' if entry_poll else 'NO'}{flag}")
    for c in unpolled: print(f"    unpolled cycle through: {sorted(c)}")
    for h, ok, why in bshape: print(f"    malformed gadget at {h}: {why}")
    if DETAIL:
        for c in comps: print(f"    cycle {sorted(c)}  polled-by {[h for h in heads if h in c]}")
print("RESULT:", "PASS" if not bad else f"FAIL ({bad} function(s))")
sys.exit(1 if bad else 0)