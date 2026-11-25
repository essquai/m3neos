#!/bin/sh
# audit_all.sh - run audit.py (and optionally loop_poll_check.py) over every .mb/.bc/.ll under the given
# directories and print one summary line per module plus a final verdict.
#
#   AUDIT=../ms8/audit.py ./audit_all.sh [-p loop_poll_check.py] DIR...
#
# .mb/.bc files are disassembled with llvm-dis into a temporary directory first; .ll files are used as is.
# Gate per module: "not homed 0", "violations 0", and at least one function analysed (a module with no
# functions is reported as EMPTY, not as a failure).  Exit status 1 if any module fails.
AUDIT=${AUDIT:-$(dirname "$0")/audit.py}
POLL=
if [ "$1" = "-p" ]; then POLL=$2; shift 2; fi
[ $# -ge 1 ] || { echo "usage: $0 [-p loop_poll_check.py] DIR..." >&2; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0; empty=0; ok=0; i=0
for d in "$@"; do
  find "$d" \( -name '*.mb' -o -name '*.bc' -o -name '*.ll' \) -type f | sort | while read -r f; do
    echo "$f"
  done
done > "$T/list"
while read -r f; do
  i=$((i+1)); n=$((n+1))
  case "$f" in
    *.ll) ll=$f ;;
    *)    ll="$T/$i.ll"; llvm-dis "$f" -o "$ll" 2>"$T/err" || { echo "DISFAIL  $f: $(head -1 "$T/err")"; fail=$((fail+1)); continue; } ;;
  esac
  out=$(python3 -I "$AUDIT" "$ll" 2>&1); rc=$?
  tot=$(printf '%s\n' "$out" | grep '^TOTAL:' | tail -1)
  fn=$(printf '%s\n' "$tot" | sed -n 's/.*functions \([0-9]*\).*/\1/p')
  nh=$(printf '%s\n' "$tot" | sed -n 's/.*not homed \([0-9]*\).*/\1/p')
  vi=$(printf '%s\n' "$tot" | sed -n 's/.*violations \([0-9]*\).*/\1/p')
  if [ -z "$tot" ]; then echo "ERROR    $f: no TOTAL line (rc=$rc): $(printf '%s\n' "$out" | tail -1 | cut -c1-110)"; fail=$((fail+1)); continue; fi
  if [ "${fn:-0}" -eq 0 ]; then echo "EMPTY    $f"; empty=$((empty+1)); continue; fi
  pc=
  if [ -n "$POLL" ]; then
    python3 -I "$POLL" "$ll" >"$T/poll" 2>&1; prc=$?
    pc=" poll=$([ $prc -eq 0 ] && echo ok || echo FAIL)"
    [ $prc -eq 0 ] || fail=$((fail+1))
  fi
  if [ "${nh:-1}" -eq 0 ] && [ "${vi:-1}" -eq 0 ]; then
    echo "PASS     $f  $(printf '%s' "$tot" | sed 's/^TOTAL: //; s/  */ /g')$pc"; ok=$((ok+1))
  else
    echo "FAIL     $f  $(printf '%s' "$tot" | sed 's/^TOTAL: //; s/  */ /g')$pc"; fail=$((fail+1))
  fi
done < "$T/list"
echo "---- modules: $n  pass: $ok  empty: $empty  fail/error: $fail"
[ "$fail" -eq 0 ]
