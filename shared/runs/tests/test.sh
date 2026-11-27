#!/usr/bin/env bash
# Tests for runs/scripts/report: fixtures with known counts, an empty list, a stuck
# run, a pickup run, bad arguments and a malformed file. Temp dirs only, no network.
#   bash shared/runs/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/report"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }
run() { out="$("$@" 2>"$work/err")"; rc=$?; }
has() { grep -qF -- "$1" <<<"$out"; }

cat > "$work/r.json" <<'JSON'
{"runs":[
 {"run":"run-a1","chain":"morning-brief","phase":"Running","source":"trigger","ageSeconds":9000,"runningSeconds":9000,"traceId":"t1"},
 {"run":"run-b2","chain":"pickup-fix","phase":"Running","source":"pickup","ageSeconds":300,"runningSeconds":120,"traceId":"t2","issue":{"repo":"roundtable-k8s/arsenal","number":122}},
 {"run":"run-c3","chain":"pickup-fix","phase":"Succeeded","source":"pickup","ageSeconds":5000,"traceId":"t3","issue":{"repo":"roundtable-k8s/arsenal","number":122}},
 {"run":"run-d4","namespace":"fleet","chain":"fleet-check","phase":"Failed","source":"gateway","ageSeconds":800,"traceId":"t4"},
 {"run":"run-e5","chain":"fleet-check","phase":"Succeeded","source":"gateway","ageSeconds":100,"traceId":"t5"},
 {"run":"run-f6","chain":"pickup-fix","phase":"Running","source":"pickup","ageSeconds":50,"runningSeconds":50,"traceId":"t6","issue":{"repo":"roundtable-k8s/roundtable","number":7}}
]}
JSON
echo '{"runs":[]}' > "$work/empty.json"
echo '{"runs":[' > "$work/bad.json"
echo '{"items":[]}' > "$work/shape.json"

nsrun='{"runs":[{"run":"run-n1","namespace":"fleet","chain":"c","phase":"Running","source":"gateway","runningSeconds":9000}]}'
echo "$nsrun" > "$work/ns.json"
run bash "$S" --runs "$work/ns.json"
has "  fleet/run-n1  c  Running  running 9000s"; check "namespace/run on active line" $?
has "  fleet/run-n1  c  running 9000s"; check "namespace/run on stuck line" $?

run bash "$S" --runs "$work/r.json"
check "exit 0" "$([ "$rc" -eq 0 ]; echo $?)"
has "Runs: 6  active: 3"; check "total and active counts" $?
has "by source: gateway=2  pickup=3  trigger=1"; check "counts by source" $?
has "by phase: Failed=1  Running=3  Succeeded=2"; check "counts by phase" $?
has "  run-a1  morning-brief  Running  running 9000s"; check "active run listed" $?
has "  run-b2  pickup-fix  Running  running 120s"; check "short active run listed" $?
! has "run-c3  pickup-fix  Succeeded  running"; check "finished run not in active list" $?
has "Active over 7200s: 1"; check "stuck count" $?
has "  run-a1  morning-brief  running 9000s"; check "stuck run listed" $?
has "Pickup runs by issue:"; check "pickup section" $?
has "  roundtable-k8s/arsenal#122  runs 2  latest run-b2"; check "pickup grouped by issue" $?
has "  roundtable-k8s/roundtable#7  runs 1  latest run-f6"; check "second issue" $?

run bash "$S" --runs "$work/r.json" --stuck-after 100
check "custom threshold exit 0" "$([ "$rc" -eq 0 ]; echo $?)"
has "Active over 100s: 2"; check "threshold applied" $?

run bash "$S" --runs "$work/empty.json"
check "empty exit 0" "$([ "$rc" -eq 0 ]; echo $?)"
has "Runs: 0  active: 0"; check "empty counts" $?
has "No active runs"; check "empty no active" $?
has "No pickup runs"; check "empty no pickup" $?
has "by source: -"; check "empty source dash" $?

run bash "$S"; check "no args exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --runs; check "missing value exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --runs "$work/nope.json"; check "unreadable exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --runs "$work/bad.json"; check "bad JSON exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --runs "$work/shape.json"; check "wrong shape exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --runs "$work/r.json" --stuck-after abc; check "non-numeric threshold exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --bogus; check "unknown option exit 2" "$([ "$rc" -eq 2 ]; echo $?)"

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
