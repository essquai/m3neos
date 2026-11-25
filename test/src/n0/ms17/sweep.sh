#!/bin/bash
# usage: sweep.sh "<command that runs ms17>" [live_KiB] [churn_MiB] [runs] [timeout_s] [caps...]
# e.g.   sweep.sh "wasmer wasm32/ms17" 4096 64 3 30 12 16 20
#        sweep.sh "x86_64/ms17"
# Every run is printed as it finishes: exit status and seconds.
#   exit 124 = timed out and ended by SIGTERM;  137 = had to be killed (SIGKILL, 5 s after the timeout)
# stdin is /dev/null: a run that touches the terminal from a background group would be stopped (SIGTTIN/SIGTTOU).
# Each run is in its own session, so Ctrl-C ends the sweep and kills a run that ignores signals.
# The traced arena is claimed whole at startup, so a cap plus about 9 MiB must fit in the link's
# --max-memory; on wasm32 build with -DMAX_MEMORY=134217728.
cmd=${1:?command}; live=${2:-4096}; churn=${3:-64}; runs=${4:-3}; tmo=${5:-30}
shift $(( $# < 5 ? $# : 5 ))
caps=${@:-8 10 12 14 16 18 20 24 32}
pid=
trap '[ -n "$pid" ] && pkill -KILL -s $pid 2>/dev/null; echo "interrupted"; exit 130' INT TERM
for cap in $caps; do
  for mode in "" "@M3noincremental"; do
    ok=0
    for r in $(seq $runs); do
      t0=$(date +%s.%N)
      setsid bash -c 'timeout -k 5 "$@" >/dev/null 2>&1; exit $?' _ $tmo $cmd $live $churn @M3traced=${cap}M $mode </dev/null 2>/dev/null &
      pid=$!
      wait $pid; rc=$?
      pkill -KILL -s $pid 2>/dev/null; pid=
      t1=$(date +%s.%N)
      [ $rc -eq 0 ] && ok=$((ok+1))
      printf "  cap=%sM mode=%s run=%s exit=%s secs=%.1f\n" $cap "${mode:-incremental}" $r $rc $(echo "$t1 - $t0" | bc)
    done
    echo "cap=${cap}M mode=${mode:-incremental} pass=$ok/$runs"
  done
done
