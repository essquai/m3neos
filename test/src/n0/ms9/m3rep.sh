#!/bin/bash
# m3rep.sh [N] [BACKEND] [WASM]   repeat one wasm program N times under wasmer
# pass = exit 0, no assert/trap text, and the END marker seen once
# Run 1 is reported in full, and the batch stops there if run 1 fails.
N=${1:-100}; B=${2:-cranelift}; W=${3:-wasm32/ms9}
END=${END:-mainMS9 END}
D=rep-$B; rm -rf "$D"; mkdir -p "$D"
pass=0; fail=0; lines=(); t0=$SECONDS
for i in $(seq "$N"); do
  timeout -k 5 120 wasmer run "$W" --"$B" > "$D/$i.out" 2> "$D/$i.err" < /dev/null
  rc=$?
  cat "$D/$i.out" "$D/$i.err" > "$D/$i.txt"
  n=$(wc -l < "$D/$i.txt")
  bad=$(grep -ci 'assert\|trap\|unreachable\|out of bounds\|runtime error' "$D/$i.txt")
  e=$(grep -c "$END" "$D/$i.txt")
  if [ "$rc" -eq 0 ] && [ "$bad" -eq 0 ] && [ "$e" -eq 1 ]; then
    pass=$((pass+1)); lines+=("$n"); rm -f "$D/$i.out" "$D/$i.err" "$D/$i.txt"
  else
    fail=$((fail+1)); rm -f "$D/$i.out" "$D/$i.err"
    echo "run $i FAILED: exit $rc  lines $n  bad-words $bad  END-markers $e  (kept $D/$i.txt)"
  fi
  if [ "$i" -eq 1 ]; then
    echo "run 1: exit $rc  lines $n  bad-words $bad  END-markers $e  -> $([ $fail -eq 0 ] && echo pass || echo FAIL)"
    [ $fail -ne 0 ] && { echo "run 1 failed the pass test; stopping."; exit 1; }
  fi
done
sorted=($(printf '%s\n' "${lines[@]}" | sort -n))
echo "$B $W: $pass passed, $fail failed of $N   wall $((SECONDS-t0)) s"
[ "${#sorted[@]}" -gt 0 ] && echo "lines per passing run: min ${sorted[0]}  median ${sorted[$(( ${#sorted[@]} / 2 ))]}  max ${sorted[-1]}"
