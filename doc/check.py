import glob, collections
ALLOWED={'## Consolidated open-items register','## Appendices (separate notes in the project)'}
def lines(p): return [l.rstrip() for l in open(p,encoding='utf-8').read().split('\n') if l.strip()]
v18=collections.Counter(lines('dev-plan18.md'))
new=collections.Counter()
FILES=['dev-plan19.md','phase-a.md','phase-b.md','phase-c.md','phase-d.md','phase-e.md','phase-l.md','phase-o.md','collector-cost.md','build-and-flags.md','wamr-record.md','dev-plan-changelog.md']
for p in FILES: new.update(lines(p))
miss={l:c-new[l] for l,c in v18.items() if new[l]<c}
bad={l:c for l,c in miss.items() if l not in ALLOWED}
print('v18 lines',sum(v18.values()),'| missing',sum(miss.values()),'| deliberate',len(miss)-len(bad),'| unexplained',sum(bad.values()))
for l in bad: print('  UNEXPLAINED:',l[:110])
