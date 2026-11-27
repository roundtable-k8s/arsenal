#!/usr/bin/env bash
# Tests for the run-report script (render-run). Fixtures inline, temp dirs only, no network.
#   bash shared/run-report/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
R="$here/../scripts/render-run"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc
has() { grep -qF -- "$1" <<<"$out"; }            # output contains the fixed string $1

succeeded='{"run":"run-1","chain":"nightly","phase":"Succeeded","done":true,"createdAt":"2026-11-27T08:00:00Z","startedAt":"2026-11-27T08:00:00Z","completedAt":"2026-11-27T08:03:10Z","steps":[{"name":"plan","phase":"Succeeded","error":"","output":"ok"},{"name":"build","phase":"Succeeded","error":"","output":"ok"}],"output":"All green.","outputTruncated":false}'
failed='{"run":"run-2","chain":"nightly","phase":"Failed","done":true,"startedAt":"2026-11-27T08:00:00Z","completedAt":"2026-11-27T08:00:30Z","steps":[{"name":"plan","phase":"Succeeded","error":""},{"name":"test","phase":"Failed","error":"exit status 1: FAIL pkg/x"}],"output":"Tests failed."}'
running='{"run":"run-3","chain":"weekly","phase":"Running","done":false,"createdAt":"2026-11-27T08:00:00Z","startedAt":"2026-11-27T08:00:00Z","steps":[{"name":"plan","phase":"Succeeded","error":""}]}'
tricky='{"run":"run-4","chain":"docs","phase":"Succeeded","done":true,"startedAt":"2026-11-27T08:00:00Z","completedAt":"2026-11-27T08:00:05Z","steps":[{"name":"a|b","phase":"Failed","error":"bad `tick` and $HOME"}],"output":"Run `echo $HOME` then ```block``` done."}'

# ---- usage and invalid input ----
run "$R" "$work/none.json"; [ $rc -eq 2 ]; check "render-run: unreadable file exits 2" $?
run "$R" a b; [ $rc -eq 2 ]; check "render-run: two arguments exit 2" $?
run bash -c "printf 'not json' | '$R'"; [ $rc -eq 2 ]; check "render-run: invalid JSON exits 2" $?
[ "$(cat "$work/err")" = "render-run: input is not a JSON object" ]; check "render-run: invalid JSON prints a reason" $?
run bash -c "printf '[1,2]' | '$R'"; [ $rc -eq 2 ]; check "render-run: JSON array exits 2" $?
run bash -c "printf '{\"chain\":\"x\"}' | '$R'"; [ $rc -eq 2 ]; check "render-run: missing run field exits 2" $?
grep -qF "run record has no run field" "$work/err"; check "render-run: missing run field prints a reason" $?
run bash -c "printf '{\"run\":\"\"}' | '$R'"; [ $rc -eq 2 ]; check "render-run: empty run field exits 2" $?

# ---- succeeded run from a file ----
printf '%s' "$succeeded" > "$work/ok.json"
run "$R" "$work/ok.json"; [ $rc -eq 0 ]; check "render-run: succeeded run exits 0" $?
has "# Run report: nightly (run-1)"; check "render-run: title has chain and run" $?
has "- Status: succeeded"; check "render-run: status is succeeded" $?
has "- Duration: 3m 10s"; check "render-run: duration computed from startedAt and completedAt" $?
has "| plan | Succeeded | ok |" && has "| build | Succeeded | ok |"; check "render-run: steps table lists each step" $?
has "## Errors"; [ $? -ne 0 ]; check "render-run: no errors section without a failed step" $?
has "All green."; check "render-run: final output is printed" $?
has "truncated"; [ $? -ne 0 ]; check "render-run: no truncation note when output is complete" $?

# ---- stdin and dash behave the same ----
run bash -c "cat '$work/ok.json' | '$R' -"; [ $rc -eq 0 ] && has "- Status: succeeded"; check "render-run: dash reads stdin" $?
run bash -c "cat '$work/ok.json' | '$R'"; [ $rc -eq 0 ] && has "- Status: succeeded"; check "render-run: no argument reads stdin" $?

# ---- failed step shows its error ----
printf '%s' "$failed" > "$work/fail.json"
run "$R" "$work/fail.json"; [ $rc -eq 0 ]; check "render-run: failed run exits 0" $?
has "- Status: failed"; check "render-run: status is failed" $?
has "- **test**: exit status 1: FAIL pkg/x"; check "render-run: failed step error appears under Errors" $?
has "- Duration: 30s"; check "render-run: duration under a minute uses seconds" $?

# ---- failed phase without a step error (cancel or timeout) ----
nostep='{"run":"run-7","chain":"nightly","phase":"Failed","done":true,"startedAt":"2026-11-27T08:00:00Z","completedAt":"2026-11-27T08:01:00Z","steps":[{"name":"plan","phase":"Succeeded","error":""}],"output":""}'
printf '%s' "$nostep" > "$work/nostep.json"
run "$R" "$work/nostep.json"; [ $rc -eq 0 ]; check "render-run: failed run without step errors exits 0" $?
has "- Phase: Failed" && has "- Status: failed"; check "render-run: Failed phase gives status failed without step errors" $?
has "## Errors"; [ $? -ne 0 ]; check "render-run: no errors section when no step has an error" $?

# ---- PartiallySucceeded and step errors under a Succeeded phase ----
partial='{"run":"run-8","chain":"nightly","phase":"PartiallySucceeded","done":true,"steps":[{"name":"a","phase":"Failed","error":"x"}],"output":"o"}'
run bash -c "printf '%s' '$partial' | '$R'"; has "- Status: partially succeeded"; check "render-run: PartiallySucceeded phase gives partially succeeded" $?
odd='{"run":"run-9","phase":"Succeeded","done":true,"steps":[{"name":"a","phase":"Failed","error":"x"}]}'
run bash -c "printf '%s' '$odd' | '$R'"; has "- Status: partially succeeded"; check "render-run: step error under Succeeded phase is flagged" $?

# ---- multi-line step error stays inside its list item ----
multi='{"run":"run-10","phase":"Failed","done":true,"steps":[{"name":"t","phase":"Failed","error":"line one\nline two"}]}'
run bash -c "printf '%s' '$multi' | '$R'"; has "- **t**: line one" && grep -qF -- "  line two" <<<"$out"; check "render-run: multi-line error is indented under its item" $?

# ---- still running run ----
printf '%s' "$running" > "$work/run.json"
run "$R" "$work/run.json"; [ $rc -eq 0 ]; check "render-run: running run exits 0" $?
has "- Status: running"; check "render-run: status is running" $?
has "- Duration: still running" && has "- Finished: still running"; check "render-run: unfinished run says still running" $?
has "- Phase: Running"; check "render-run: phase is shown" $?
has "_No final output._"; check "render-run: missing output is stated" $?

# ---- truncation at 2000 characters ----
jq -n '{run:"run-5", chain:"big", phase:"Succeeded", done:true, startedAt:"2026-11-27T08:00:00Z", completedAt:"2026-11-27T09:02:03Z", steps:[], output: ("x" * 2500)}' > "$work/big.json"
run "$R" "$work/big.json"; [ $rc -eq 0 ]; check "render-run: long output exits 0" $?
[ "$(grep -o 'x' <<<"$out" | wc -l)" -eq 2000 ]; check "render-run: output is cut to 2000 characters" $?
has "showing the first 2000 of 2500 characters"; check "render-run: cut output has a truncated note" $?
has "- Duration: 1h 2m"; check "render-run: duration over an hour uses hours" $?
has "_No steps recorded._"; check "render-run: empty steps are stated" $?

jq -n '{run:"run-6", phase:"Succeeded", done:true, output:"short", outputTruncated:true}' > "$work/gw.json"
run "$R" "$work/gw.json"; has "_Output truncated by the gateway._"; check "render-run: gateway outputTruncated gets a note" $?

# ---- backticks, pipes and dollar signs are printed literally ----
printf '%s' "$tricky" > "$work/tricky.json"
run "$R" "$work/tricky.json"; [ $rc -eq 0 ]; check "render-run: tricky record exits 0" $?
has 'Run `echo $HOME` then ```block``` done.'; check "render-run: output with backticks and dollar signs is literal" $?
has '````'; check "render-run: fence is longer than any backtick run in output" $?
has '| a\|b | Failed | failed |'; check "render-run: pipe in step name is escaped" $?
has 'bad `tick` and $HOME'; check "render-run: error text is printed literally" $?

echo "# $n tests, $fails failed"
[ "$fails" -eq 0 ]
