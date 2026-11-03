#!/usr/bin/env python3
"""m3poll_check.py - verify safepoint polls in textual LLVM IR (.ll) from m3llwasm.

Checks, per defined function:
  1. PROLOGUE  Starting at the entry block, the first thing that happens (apart
               from stores, allocas and llvm.* intrinsics such as llvm.gcroot)
               is a well-formed poll.  No calls and no branches may come first.
  2. LOOPS     Every cycle in the control-flow graph passes through a
               well-formed poll block.  (Test: delete the poll blocks; what
               remains must be acyclic.)  This is independent of loop shape,
               so FOR / WHILE / REPEAT / LOOP, EXIT, nesting all fall out.
  3. POLL SHAPE (heuristic) A poll block loads  nthr_nexus.safePoint  with an
               atomic load, ends in a two-way conditional branch, and within a
               few blocks there is a compare against the vigilant threshold
               and a call to nthr_park.
  4. GCROOT    (warning) llvm.gcroot calls outside the entry block.

Text-only: no LLVM installation needed.  Python 3.8+.

Exit status: 0 all good, 1 at least one function failed, 2 usage/parse problem.

Examples:
  m3poll_check.py ms2.ll
  m3poll_check.py -v *.ll
  m3poll_check.py --vigilant 2 --skip '^Main__Debug$' build/*.ll
"""
import argparse
import re
import sys
from collections import OrderedDict

TERMS = {'br', 'switch', 'ret', 'unreachable', 'resume', 'indirectbr',
         'invoke', 'callbr', 'cleanupret', 'catchret', 'catchswitch'}
INSTR_RE = re.compile(
    r'^(?:%[^\s=]+\s*=\s*)?(?:(?:tail|musttail|notail)\s+)?([a-z_]+)\b')
LABEL_DEF = re.compile(r'^("[^"]+"|[\w.$-]+):')
LABEL_REF = re.compile(r'label\s+%("[^"]+"|[\w.$-]+)')
DEFINE = re.compile(r'^define\b[^@]*@("[^"]+"|[\w.$-]+)\s*\(')
DBG_REF = re.compile(r'!dbg\s+!(\d+)')
DILOC = re.compile(r'^!(\d+)\s*=\s*(?:distinct\s+)?!DILocation\(line:\s*(\d+)')
CALLEE = re.compile(r'@("[^"]+"|[\w.$-]+)\s*\(')
CMP = re.compile(r'\bicmp\s+(sge|sgt|uge|ugt|eq)\s+i32\s+[^,]+,\s*(-?\d+)')


def unq(s):
    return s[1:-1] if s.startswith('"') else s


class Block:
    def __init__(self, name):
        self.name = name
        self.lines = []      # instruction texts
        self.succ = []       # successor block names
        self.term = None
        self.dbg = None      # first !dbg metadata id seen

    def add(self, ins):
        self.lines.append(ins)
        if self.dbg is None:
            m = DBG_REF.search(ins)
            if m:
                self.dbg = int(m.group(1))
        m = INSTR_RE.match(ins)
        op = m.group(1) if m else ''
        if op in TERMS:
            self.term = op
            seen = []
            for x in LABEL_REF.findall(ins):
                x = unq(x)
                if x not in seen:
                    seen.append(x)
            self.succ = seen


class Func:
    def __init__(self, name):
        self.name = name
        self.blocks = OrderedDict()

    def new_block(self, name):
        b = Block(name)
        self.blocks[name] = b
        return b


def parse(text):
    funcs, dil = [], {}
    cur = blk = pending = None
    for raw in text.splitlines():
        if cur is None:
            m = DEFINE.match(raw)
            if m and raw.rstrip().endswith('{'):
                cur, blk, pending = Func(unq(m.group(1))), None, None
                continue
            m = DILOC.match(raw)
            if m:
                dil[int(m.group(1))] = int(m.group(2))
            continue
        if raw.startswith('}'):
            funcs.append(cur)
            cur = blk = pending = None
            continue
        line = raw.split(';', 1)[0].rstrip()
        if not line.strip():
            continue
        if not line[0].isspace():
            m = LABEL_DEF.match(line)
            if m:
                blk = cur.new_block(unq(m.group(1)))
                continue
        if blk is None:
            blk = cur.new_block('<entry>')
        t = line.strip()
        if pending is not None:            # multi-line switch
            pending += ' ' + t
            if ']' in t:
                blk.add(pending)
                pending = None
            continue
        m = INSTR_RE.match(t)
        if m and m.group(1) == 'switch' and ']' not in t:
            pending = t
            continue
        blk.add(t)
    return funcs, dil


def back_edges(blocks, starts, removed):
    """Iterative DFS over the graph minus `removed`, started from each block in
    `starts` (so blocks cut off from the entry by the removal are still
    examined).  Returns the list of back edges (src, dst)."""
    color = {}
    edges = []
    for start in starts:
        if start in removed or start not in blocks or start in color:
            continue
        color[start] = 1
        stack = [(start, iter(blocks[start].succ))]
        while stack:
            node, it = stack[-1]
            for nxt in it:
                if nxt in removed or nxt not in blocks:
                    continue
                c = color.get(nxt, 0)
                if c == 1:
                    edges.append((node, nxt))
                elif c == 0:
                    color[nxt] = 1
                    stack.append((nxt, iter(blocks[nxt].succ)))
                    break
            else:
                color[node] = 2
                stack.pop()
    return edges


def reachable(blocks, start):
    seen, todo = {start}, [start]
    while todo:
        for s in blocks[todo.pop()].succ:
            if s in blocks and s not in seen:
                seen.add(s)
                todo.append(s)
    return seen


def op_of(ins):
    m = INSTR_RE.match(ins)
    return m.group(1) if m else ''


def analyze(fn, a, dil):
    r = {'fail': [], 'warn': [], 'blocks': len(fn.blocks), 'loops': 0, 'polls': 0}
    if not fn.blocks:
        r['fail'].append('function has no blocks')
        return r
    blocks = fn.blocks
    entry = next(iter(blocks))
    reach = reachable(blocks, entry)

    safe_re = re.compile(r'\bload\s+atomic\s+i32,\s*ptr\s+@%s\b' % re.escape(a.nexus))
    park_re = re.compile(r'\bcall\s+void\s+@%s\s*\(' % re.escape(a.park))

    def has(b, rx):
        return any(rx.search(i) for i in b.lines)

    def line_of(name):
        b = blocks.get(name)
        if b is not None and b.dbg in dil:
            return ' (Modula-3 line %d)' % dil[b.dbg]
        return ''

    poll_sites = [n for n in blocks if n in reach and has(blocks[n], safe_re)]
    r['polls'] = len(poll_sites)

    # ---- poll shape (heuristic) -------------------------------------------
    def shape_problem(name):
        b = blocks[name]
        if b.term != 'br' or len(b.succ) != 2:
            return 'does not end in a two-way conditional branch'
        seen, level, found_park, thresh = {name}, [name], False, []
        for _ in range(3):
            nxt = []
            for n in level:
                for s in blocks[n].succ:
                    if s in blocks and s not in seen and s not in poll_sites:
                        seen.add(s)
                        nxt.append(s)
            for n in nxt:
                if has(blocks[n], park_re):
                    found_park = True
                for ins in blocks[n].lines:
                    m = CMP.search(ins)
                    if m:
                        k, v = m.group(1), int(m.group(2))
                        thresh.append(v + 1 if k in ('sgt', 'ugt') else v)
                        if k == 'eq':
                            thresh[-1] = None
            level = nxt
        if not found_park:
            return 'no call to @%s within 3 blocks' % a.park
        if a.vigilant not in thresh:
            return ('no compare of watch against vigilant threshold %d '
                    '(found %s)' % (a.vigilant, thresh or 'none'))
        return None

    good = set()
    for n in poll_sites:
        p = shape_problem(n)
        if p:
            r['fail'].append('malformed poll in block %%%s: %s%s'
                             % (n, p, line_of(n)))
        else:
            good.add(n)

    # ---- prologue ---------------------------------------------------------
    cur, seen = entry, set()
    while True:
        if cur in good:
            break
        if cur in poll_sites:
            r['fail'].append('prologue poll (block %%%s) is malformed' % cur)
            break
        if cur in seen:
            r['fail'].append('no prologue poll (cycle before any poll)')
            break
        seen.add(cur)
        b = blocks[cur]
        bad = None
        for ins in b.lines:
            op = op_of(ins)
            if op in ('call', 'invoke', 'callbr'):
                m = CALLEE.search(ins)
                name = unq(m.group(1)) if m else None
                if name is None or not name.startswith('llvm.'):
                    bad = 'call to %s before prologue poll (block %%%s)' % (
                        ('@' + name) if name else 'indirect function', cur)
                    break
        if bad:
            r['fail'].append(bad)
            break
        if len(b.succ) != 1:
            r['fail'].append('no prologue poll: block %%%s %s' % (
                cur, 'branches' if b.succ else 'returns'))
            break
        cur = b.succ[0]
        if cur not in blocks:
            r['fail'].append('no prologue poll: unknown label %%%s' % cur)
            break

    # ---- loops ------------------------------------------------------------
    order = [n for n in blocks if n in reach]
    # loops = distinct loop headers (targets of back edges)
    r['loops'] = len({d for _, d in back_edges(blocks, [entry], set())})
    for src, dst in back_edges(blocks, order, good):
        r['fail'].append('unpolled loop: back-edge %%%s -> %%%s%s'
                         % (src, dst, line_of(dst) or line_of(src)))

    # ---- gcroot placement (warning) ---------------------------------------
    for n, b in blocks.items():
        if n != entry and any('@llvm.gcroot' in i and
                              op_of(i) in ('call', 'invoke') for i in b.lines):
            r['warn'].append('llvm.gcroot call outside entry block (%%%s)' % n)
    return r


def main():
    ap = argparse.ArgumentParser(
        description='Check prologue and loop-edge safepoint polls in LLVM IR.')
    ap.add_argument('files', nargs='+', help='.ll files')
    ap.add_argument('-v', '--verbose', action='store_true',
                    help='list every function, not just failures')
    ap.add_argument('--vigilant', type=int, default=2,
                    help='lowest recce_t value that must park (default 2)')
    ap.add_argument('--nexus', default='nthr_nexus',
                    help='global whose first i32 is safePoint (default nthr_nexus)')
    ap.add_argument('--park', default='nthr_park',
                    help='park function (default nthr_park)')
    ap.add_argument('--skip', metavar='REGEX',
                    help='skip functions whose name matches REGEX')
    a = ap.parse_args()
    skip = re.compile(a.skip) if a.skip else None

    status = 0
    for path in a.files:
        try:
            with open(path, encoding='utf-8', errors='replace') as f:
                funcs, dil = parse(f.read())
        except OSError as e:
            print('%s: %s' % (path, e), file=sys.stderr)
            status = max(status, 2)
            continue
        if not funcs:
            print('%s: no function definitions found' % path, file=sys.stderr)
            status = max(status, 2)
            continue
        tot = {'f': 0, 'bad': 0, 'loops': 0, 'polls': 0, 'warn': 0}
        lines = []
        for fn in funcs:
            if skip and skip.search(fn.name):
                continue
            r = analyze(fn, a, dil)
            tot['f'] += 1
            tot['loops'] += r['loops']
            tot['polls'] += r['polls']
            tot['warn'] += len(r['warn'])
            tag = 'FAIL' if r['fail'] else 'ok'
            if r['fail']:
                tot['bad'] += 1
            if r['fail'] or a.verbose or r['warn']:
                lines.append('  %-4s  %-32s blocks=%-4d loops=%-3d polls=%d'
                             % (tag, fn.name, r['blocks'], r['loops'], r['polls']))
                for m in r['fail']:
                    lines.append('          - ' + m)
                for m in r['warn']:
                    lines.append('          ~ warning: ' + m)
        print('%s: %d functions, %d loops, %d polls, %d failing, %d warnings'
              % (path, tot['f'], tot['loops'], tot['polls'], tot['bad'], tot['warn']))
        for l in lines:
            print(l)
        if tot['bad']:
            status = max(status, 1)
    return status


if __name__ == '__main__':
    sys.exit(main())
