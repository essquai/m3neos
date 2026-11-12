p=0; for i in $(seq 40); do
  out=$(perl -e 'alarm 10; exec @ARGV' iwasm --max-threads=16 eh_thread.wasm 1 200 2>&1)
  echo "$out" | grep -q 'RESULT: PASS' && p=$((p+1))
done; echo "pass=$p of 40"
