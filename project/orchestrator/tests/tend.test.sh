#!/usr/bin/env bash
# Tests for scripts/tend using gh and kubectl stubs on PATH.
#   bash project/orchestrator/tests/tend.test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tend="$here/../scripts/tend"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix" LOG="$work/log"

# gh stub: reads fixtures from $FIX, logs every call to $LOG.
#   pr list -R o/r          -> $FIX/prs-o_r.json
#   api repos/o/r/pulls/N/reviews  -> $FIX/reviews-o_r-N.json (default [])
#   api repos/o/r/issues/N/comments -> $FIX/comments-o_r-N.json (default [])
#   issue view N -R o/r     -> $FIX/issue-o_r-N.json
#   run list -R o/r         -> $FIX/runs-o_r.json (default [])
#   run view ID ... --log-failed -> $FIX/log-ID.txt
#   $FIX/net-run-view: every run view fails with a network error; $FIX/slow-run-view: it hangs
#   $FIX/net-run-ID: the run view of that one run fails with a network error
#   pr merge / issue edit / issue comment / run rerun: logged; $FIX/fail-<a>-<b> fails it.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
sub="$1 $2"
[ -e "$FIX/fail-${1}-${2}" ] && { echo "boom" >&2; exit 1; }
repo=""; prev=""
for a in "$@"; do [ "$prev" = -R ] && repo="${a//\//_}"; prev="$a"; done
case "$1" in
  api)
    path="${*: -1}"; path="${path%%\?*}"
    if [[ "$path" =~ ^repos/([^/]+)/([^/]+)/pulls/([0-9]+)/reviews$ ]]; then
      f="$FIX/reviews-${BASH_REMATCH[1]}_${BASH_REMATCH[2]}-${BASH_REMATCH[3]}.json"
    elif [[ "$path" =~ ^repos/([^/]+)/([^/]+)/issues/([0-9]+)/comments$ ]]; then
      f="$FIX/comments-${BASH_REMATCH[1]}_${BASH_REMATCH[2]}-${BASH_REMATCH[3]}.json"
    else echo "unexpected api $path" >&2; exit 1; fi
    if [ -e "$f" ]; then cat "$f"; else echo '[]'; fi ;;
  *)
    case "$sub" in
      "pr list") cat "$FIX/prs-$repo.json" ;;
      "issue view") cat "$FIX/issue-$repo-$3.json" ;;
      "run list") if [ -e "$FIX/runs-$repo.json" ]; then cat "$FIX/runs-$repo.json"; else echo '[]'; fi ;;
      "run view")
        [ -e "$FIX/net-run-view" ] && { echo "error downloading logs: dial tcp 140.82.112.6:443: i/o timeout" >&2; exit 1; }
        [ -e "$FIX/net-run-$3" ] && { echo "error downloading logs: dial tcp 140.82.112.6:443: i/o timeout" >&2; exit 1; }
        [ -e "$FIX/slow-run-view" ] && exec sleep 5
        cat "$FIX/log-$3.txt" ;;
      "pr merge"|"issue edit"|"issue comment"|"run rerun") : ;;
      *) echo "unexpected gh $*" >&2; exit 1 ;;
    esac ;;
esac
STUB
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
echo "kubectl $*" >> "$LOG"
[ -e "$FIX/fail-kubectl" ] && { echo "forbidden" >&2; exit 1; }
if [ -e "$FIX/chains.json" ]; then cat "$FIX/chains.json"; else echo '{"items":[]}'; fi
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
unset ORCHESTRATOR_STATE_DIR ORCHESTRATOR_CONFIG

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; echo "$out" | sed 's/^/#   /'; fails=$((fails+1)); fi; }
logged() { grep -qF -- "$1" "$LOG"; }
lines() { grep -c '^tend: ' <<<"$out"; }
cfg="$work/config.json"
cat > "$cfg" <<'JSON'
{"repos": ["o/r"], "namespace": "ns", "chainPrefix": "pr-pipeline-",
 "labels": {"ready": "rt:ready", "inProgress": "rt:in-progress", "needsHuman": "needs-human", "hold": "hold"},
 "knights": {"o/r": "coder-knight"}}
JSON
ST="$work/state/tend-state.json"
reset() { rm -rf "$FIX" "$LOG" "$work/state"; mkdir -p "$FIX" "$work/state"; : > "$LOG"; echo '[]' > "$FIX/prs-o_r.json"; }
run() { out="$("$tend" --config "$cfg" --state "$ST" "$@" 2>&1)"; rc=$?; : > "$LOG"; }
again() { out="$("$tend" --config "$cfg" --state "$ST" "$@" 2>&1)"; rc=$?; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
prs() { # json array of {number, draft, labels csv, auto, mss, sha, bot}
  jq -c 'map({number, url: "https://github.com/o/r/pull/\(.number)", isDraft: (.draft // false),
      labels: [(.labels // "" | split(",")[] | select(length > 0) | {name: .})],
      autoMergeRequest: (if .auto then {} else null end), mergeStateStatus: (.mss // "CLEAN"),
      headRefOid: (.sha // "abcdef1234567"), author: {login: (if .bot then "app/coder" else "someone" end), is_bot: (.bot // false)}})' \
    <<<"$1" > "$FIX/prs-o_r.json"
}
reviews() { jq -nc --arg b "$2" '[{state: "COMMENTED", submitted_at: "2026-01-01T00:00:00Z", body: $b}]' > "$FIX/reviews-o_r-$1.json"; }
issue() { # repo n state labels-csv
  jq -nc --arg s "$3" --arg l "${4:-}" '{state: $s, labels: [($l | split(",")[] | select(length > 0) | {name: .})]}' \
    > "$FIX/issue-${1//\//_}-$2.json"
}
chain() { # name phase started error-lines-json [step]
  jq -nc --arg n "$1" --arg p "$2" --arg s "$3" --arg e "$4" --arg st "${5:-implement}" '{items: [{
    metadata: {name: $n, annotations: {"ai.roundtable.io/pickup-repo": "o/r", "ai.roundtable.io/pickup-issue": "5"}},
    status: {phase: $p, startedAt: $s, stepStatuses: [{name: "plan", phase: "Succeeded"}, {name: $st, phase: $p, error: $e}]}}]}' \
    > "$FIX/chains.json"
}

# ---- usage ----
reset; out="$("$tend" --config "$cfg" 2>&1)"; rc=$?
[ $rc -eq 2 ] && grep -q "ORCHESTRATOR_STATE_DIR" <<<"$out"; check "no state file or dir: clear error, exit 2" $?
reset; out="$(ORCHESTRATOR_STATE_DIR="$work/state" "$tend" --config "$cfg" 2>&1)"; rc=$?
[ $rc -eq 0 ]; check "ORCHESTRATOR_STATE_DIR is used" $?
reset; out="$("$tend" --config "$work/missing.json" --state "$ST" 2>&1)"; rc=$?
[ $rc -eq 2 ]; check "missing config exits 2" $?
reset; out="$("$tend" --bogus 2>&1)"; rc=$?; [ $rc -eq 2 ]; check "unknown argument exits 2" $?
reset; run; [ $rc -eq 0 ] && [ -z "$out" ]; check "nothing to do prints nothing" $?

# ---- queue ----
reset; prs '[{"number":1,"bot":true}]'; reviews 1 $'Looks good.\n\n**Verdict:** ship it'
run; [ $rc -eq 0 ] && [ "$out" = "tend: queued o/r#1 (ship it, head abcdef1)" ]; check "queue: ship-it PR queued with one line" $?
again; [ $rc -eq 0 ] && [ -z "$out" ] && ! logged "pr merge"; check "queue: second run does nothing" $?

reset; prs '[{"number":1}]'; reviews 1 'Verdict: ship it'
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"
logged "gh pr merge https://github.com/o/r/pull/1 --auto"; check "queue: uses gh pr merge --auto" $?

reset; prs '[{"number":1,"auto":true}]'; reviews 1 'Verdict: ship it'
run; [ -z "$out" ]; check "queue: already queued (auto-merge on) does nothing" $?
reset; prs '[{"number":1,"draft":true}]'; reviews 1 'Verdict: ship it'
run; [ -z "$out" ]; check "queue: draft skipped" $?
reset; prs '[{"number":1,"labels":"hold"}]'; reviews 1 'Verdict: ship it'
run; [ -z "$out" ]; check "queue: hold label skipped" $?
reset; prs '[{"number":1}]'; reviews 1 'Verdict: needs changes'
run; [ -z "$out" ]; check "queue: needs-changes verdict not queued" $?
reset; prs '[{"number":1}]'
run; [ -z "$out" ]; check "queue: no verdict not queued" $?
reset; prs '[{"number":1}]'; reviews 1 'Verdict: ship it'
jq -nc '[{created_at: "2026-02-01T00:00:00Z", body: "Verdict: needs changes"}]' > "$FIX/comments-o_r-1.json"
run; [ -z "$out" ]; check "queue: newest verdict (a later PR comment) wins" $?
reset; prs '[{"number":1}]'; reviews 1 'Verdict: needs changes'
jq -nc '[{created_at: "2026-02-01T00:00:00Z", body: "> Verdict: Ship it"}]' > "$FIX/comments-o_r-1.json"
run; [ "$out" = "tend: queued o/r#1 (ship it, head abcdef1)" ]; check "queue: ship-it in a newer comment counts" $?
reset; prs '[{"number":1}]'; jq -nc '[{state: "DISMISSED", submitted_at: "2026-01-01T00:00:00Z", body: "Verdict: ship it"}]' > "$FIX/reviews-o_r-1.json"
run; [ -z "$out" ]; check "queue: dismissed review does not count" $?
reset; prs '[{"number":1}]'; reviews 1 'Verdict: ship it'; touch "$FIX/fail-pr-merge"
run; [ $rc -eq 1 ] && grep -q "error: could not queue" <<<"$out" && ! grep -q "queued o/r" <<<"$out"; check "queue: merge failure is an error, not recorded" $?
rm "$FIX/fail-pr-merge"; again; [ "$out" = "tend: queued o/r#1 (ship it, head abcdef1)" ]; check "queue: retried after a failure" $?
reset; prs '[{"number":1}]'; reviews 1 'Verdict: ship it'
run --dry-run; [ "$out" = "tend: (dry-run) queued o/r#1 (ship it, head abcdef1)" ] && [ ! -e "$ST" ]; check "queue: dry-run prints, writes no state" $?
out="$("$tend" --config "$cfg" --state "$ST" --dry-run 2>&1)"; ! logged "pr merge"; check "queue: dry-run calls no gh mutation" $?

# ---- rebase ----
reset; prs '[{"number":2,"bot":true,"mss":"DIRTY","sha":"1234567890"}]'; reviews 2 'Verdict: ship it'
run; [ $rc -eq 0 ] && [ "$(lines)" = 1 ] && [[ "$out" == 'tend: dispatch-needed {"kind":"rebase","knight":"coder-knight","taskId":"rebase-r-2-1234567"'* ]]; check "rebase: dirty bot PR -> one dispatch-needed line" $?
j="${out#tend: dispatch-needed }"; jq -e '.task | contains("https://github.com/o/r/pull/2") and contains("--force-with-lease")' <<<"$j" >/dev/null; check "rebase: task text names the PR" $?
jq -e '.rebase["o/r#2@1234567890"].knight == "coder-knight"' "$ST" >/dev/null; check "rebase: recorded in state" $?
! logged "pr merge"; check "rebase: conflicted PR is not queued" $?
again; [ -z "$out" ]; check "rebase: second run on the same head does nothing" $?
prs '[{"number":2,"bot":true,"mss":"DIRTY","sha":"fedcba9876"}]'
again; [ "$(lines)" = 1 ] && grep -q '"taskId":"rebase-r-2-fedcba9"' <<<"$out"; check "rebase: a new head commit asks again" $?
reset; prs '[{"number":2,"mss":"DIRTY"}]'
run; [ -z "$out" ]; check "rebase: human PR not asked" $?
reset; prs '[{"number":2,"bot":true,"draft":true,"mss":"DIRTY"}]'
run; [ -z "$out" ]; check "rebase: draft skipped" $?
reset; prs '[{"number":2,"bot":true,"mss":"DIRTY"}]'
jq '.knights = {}' "$cfg" > "$work/nok.json"
out="$("$tend" --config "$work/nok.json" --state "$ST" 2>&1)"
[ "$(lines)" = 1 ] && grep -q "no knight configured" <<<"$out"; check "rebase: no knight configured says so once" $?
out="$("$tend" --config "$work/nok.json" --state "$ST" 2>&1)"; [ -z "$out" ]; check "rebase: ...and not again" $?
reset; prs '[{"number":2,"mss":"DIRTY"}]'
jq '.botAuthor = "^someone$"' "$cfg" > "$work/bot.json"
out="$("$tend" --config "$work/bot.json" --state "$ST" 2>&1)"; grep -q dispatch-needed <<<"$out"; check "rebase: botAuthor regex from config" $?
reset; prs '[{"number":2,"bot":true,"mss":"DIRTY"}]'
jq '.rebase = "off"' "$cfg" > "$work/off.json"
out="$("$tend" --config "$work/off.json" --state "$ST" 2>&1)"; [ $? -eq 0 ] && [ -z "$out" ]; check "rebase: off -> dirty bot PR gives no output" $?
[ ! -e "$ST" ] || ! jq -e 'has("rebase")' "$ST" >/dev/null; check "rebase: off -> no rebase entry in state" $?
reset; prs '[{"number":2,"bot":true,"mss":"DIRTY"},{"number":3,"mss":"CLEAN"}]'; reviews 3 'Verdict: ship it'
out="$("$tend" --config "$work/off.json" --state "$ST" 2>&1)"; [ "$out" = "tend: queued o/r#3 (ship it, head abcdef1)" ]; check "rebase: off -> ship-it queueing unchanged, DIRTY still not queued" $?
reset; prs '[{"number":2,"bot":true,"mss":"DIRTY"}]'
jq '.rebase = "dispatch"' "$cfg" > "$work/dispatch.json"
out="$("$tend" --config "$work/dispatch.json" --state "$ST" 2>&1)"; grep -q '^tend: dispatch-needed {"kind":"rebase"' <<<"$out"; check "rebase: explicit dispatch -> asks as before" $?
jq '.rebase = "maybe"' "$cfg" > "$work/bad.json"
out="$("$tend" --config "$work/bad.json" --state "$ST" 2>&1)"; rc=$?; [ $rc -eq 2 ] && grep -q "field 'rebase'" <<<"$out"; check "rebase: unknown value -> exit 2 naming the field" $?
jq '.rebase = false' "$cfg" > "$work/bad2.json"
out="$("$tend" --config "$work/bad2.json" --state "$ST" 2>&1)"; rc=$?; [ $rc -eq 2 ]; check "rebase: non-string value -> exit 2" $?

# ---- requeue transient chain failures ----
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "Task was delivered to a knight that stopped before finishing it"
issue o/r 5 OPEN needs-human
run; [ $rc -eq 0 ] && [ "$(lines)" = 1 ] && grep -q "^tend: re-queued o/r#5 (chain pr-pipeline-r-5 failed transiently: implement: Task was delivered" <<<"$out"; check "requeue: knight replaced mid-task re-queued" $?
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"
grep -q "kubectl -n ns get chains.ai.roundtable.io -o json" "$LOG"; check "requeue: chains read from the configured namespace" $?
again; [ -z "$out" ] && ! logged "issue edit"; check "requeue: second run does nothing" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "Task was delivered to a knight that stopped before finishing it"
issue o/r 5 OPEN needs-human
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"
logged "issue edit 5 -R o/r --add-label rt:ready --remove-label needs-human" && logged "issue comment 5 -R o/r --body Re-queued automatically"; check "requeue: removes needs-human, adds ready, comments why" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "step timed out after 900s" plan; issue o/r 5 OPEN needs-human
run; grep -q "re-queued o/r#5" <<<"$out"; check "requeue: plan step timeout" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "model provider: overloaded_error"; issue o/r 5 OPEN needs-human
run; grep -q "re-queued o/r#5" <<<"$out"; check "requeue: provider overload" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "step timed out after 900s" implement; issue o/r 5 OPEN needs-human
run; [ -z "$out" ] && ! logged "issue edit"; check "requeue: non-plan timeout is not transient" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "tests failed: 3 failures"; issue o/r 5 OPEN needs-human
run; [ -z "$out" ] && ! logged "issue"; check "requeue: real failure left alone" $?
reset; chain pr-pipeline-r-5 Succeeded 2026-01-01T00:00:00Z "stopped before finishing"; issue o/r 5 OPEN needs-human
run; [ -z "$out" ]; check "requeue: only Failed chains" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "stopped before finishing"; issue o/r 5 CLOSED needs-human
run; [ -z "$out" ] && ! logged "issue edit"; check "requeue: closed issue left alone" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "stopped before finishing"; issue o/r 5 OPEN rt:in-progress
run; [ -z "$out" ] && ! logged "issue edit"; check "requeue: issue already in progress left alone" $?
reset; chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "stopped before finishing"; issue o/r 5 OPEN needs-human
run; chain pr-pipeline-r-5 Failed 2026-01-02T00:00:00Z "stopped before finishing"
again; grep -q "re-queued o/r#5" <<<"$out"; check "requeue: a later run of the same chain counts again" $?
reset; touch "$FIX/fail-kubectl"
run; [ $rc -eq 1 ] && grep -q "could not list chains" <<<"$out"; check "requeue: kubectl failure reported, not a crash" $?

# ---- deps feeder ----
D="$work/state/deps.json"
reset; echo '{"o/r#12": ["o/r#10", "x/y#3"]}' > "$D"
issue o/r 12 OPEN needs-human; issue o/r 10 CLOSED; issue x/y 3 CLOSED
run; [ $rc -eq 0 ] && [ "$out" = "tend: dependencies closed (o/r#10 x/y#3) -> queued o/r#12" ]; check "deps: all closed -> queued with one line" $?
again; [ -z "$out" ] && ! logged "issue edit"; check "deps: second run does nothing" $?
reset; echo '{"o/r#12": ["o/r#10", "x/y#3"]}' > "$D"
issue o/r 12 OPEN needs-human; issue o/r 10 CLOSED; issue x/y 3 OPEN
run; [ -z "$out" ]; check "deps: one still open -> waits" $?
issue x/y 3 CLOSED; again; grep -q "queued o/r#12" <<<"$out"; check "deps: queued once the last one closes" $?
reset; echo '{"o/r#12": ["o/r#10"]}' > "$D"; issue o/r 12 OPEN rt:ready; issue o/r 10 CLOSED
run; [ -z "$out" ] && ! logged "issue edit"; check "deps: already ready does nothing" $?
reset; echo '{"o/r#12": ["o/r#10"]}' > "$D"; issue o/r 12 OPEN; issue o/r 10 CLOSED
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"
logged "issue edit 12 -R o/r --add-label rt:ready" && ! logged "remove-label"; check "deps: no needs-human -> only adds ready" $?
reset; echo '{"o/r#12": ["o/r#10"]}' > "$work/other-deps.json"; issue o/r 12 OPEN; issue o/r 10 CLOSED
run --deps "$work/other-deps.json"; grep -q "queued o/r#12" <<<"$out"; check "deps: --deps file" $?
reset; echo '[1]' > "$D"
run; [ $rc -eq 1 ] && grep -q "not a JSON object" <<<"$out"; check "deps: malformed file is an error" $?

# ---- CI re-runs ----
runs() { jq -nc --arg t "${2:-$(now)}" --arg e "${3:-pull_request}" --argjson id "$1" \
  '[{databaseId: $id, workflowName: "CI", event: $e, createdAt: $t, headBranch: "b"}]' > "$FIX/runs-o_r.json"; }
logline() { printf 'build\tSet up job\t2026-01-01T00:00:00.0000000Z %s\n' "$@" > "$FIX/log-$id.txt"; }
id=101
reset; runs $id; logline "Pulling image" "Error response from daemon: Get \"https://ghcr.io/v2/\": net/http: TLS handshake timeout"
run; [ $rc -eq 0 ] && [ "$(lines)" = 1 ] && grep -q "^tend: re-ran failed jobs of o/r run 101 (CI: " <<<"$out"; check "rerun: registry error re-run with one line" $?
again; [ -z "$out" ] && ! logged "run rerun" && ! logged "run view"; check "rerun: second run does nothing" $?
reset; runs $id; logline "curl: (6) Could not resolve host: dl.example.org"
run; grep -q "re-ran" <<<"$out"; check "rerun: download error re-run" $?
reset; runs $id; logline "The runner has received a shutdown signal."
run; grep -q "re-ran" <<<"$out"; check "rerun: runner failure re-run" $?
reset; runs $id; logline "--- FAIL: TestReconcile (0.01s)" "    reconcile_test.go:42: expected 2, got 3" "FAIL	example.com/pkg	0.1s"
run; [ -z "$out" ] && ! logged "run rerun"; check "rerun: test failure never re-run" $?
reset; runs $id; logline "Error: connection reset by peer" "--- FAIL: TestDial (0.01s)"
run; [ -z "$out" ] && ! logged "run rerun"; check "rerun: test failure with network noise not re-run" $?
reset; runs $id; logline "npm ERR! 3 tests failed"
run; [ -z "$out" ] && ! logged "run rerun"; check "rerun: npm test failure not re-run" $?
reset; runs $id; logline "Process completed with exit code 1."
run; [ -z "$out" ]; check "rerun: unknown failure not re-run" $?
: > "$LOG"; again; ! logged "run view"; check "rerun: a run judged not infra is not read again" $?
reset; runs $id "$(now)" merge_group; logline "Could not resolve host: x"
run; [ -z "$out" ] && ! logged "run view"; check "rerun: merge-queue runs skipped" $?
reset; runs $id "2020-01-01T00:00:00Z"; logline "Could not resolve host: x"
run; [ -z "$out" ] && ! logged "run view"; check "rerun: old runs skipped" $?
reset; runs $id; logline "Could not resolve host: x"; touch "$FIX/fail-run-rerun"
run; [ $rc -eq 1 ] && grep -q "could not re-run" <<<"$out"; check "rerun: rerun failure is an error" $?
rm "$FIX/fail-run-rerun"; again; grep -q "re-ran" <<<"$out"; check "rerun: retried after a failure" $?
reset; runs $id; logline "Could not resolve host: x"
run --dry-run; [[ "$out" == "tend: (dry-run) re-ran"* ]] && [ ! -e "$ST" ]; check "rerun: dry-run" $?
# one unreadable log among readable ones: the others are still classified and re-run
reset; jq -nc '[201,202,203] | map({databaseId: ., workflowName: "CI", event: "pull_request", createdAt: "'"$(now)"'", headBranch: "b"})' > "$FIX/runs-o_r.json"
id=201; logline "Could not resolve host: x"; id=203; logline "Could not resolve host: y"
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -qF "could not read the failed log of o/r run 202" <<<"$out" \
  && grep -qF "re-ran failed jobs of o/r run 201" <<<"$out" && grep -qF "re-ran failed jobs of o/r run 203" <<<"$out"
check "rerun: one unreadable log, the others still re-run, exit 1" $?
[ "$(grep -c "run view" "$LOG")" -eq 3 ]; check "rerun: every log read once" $?

# every read fails on the network: two attempts, one summary line, exit 1, no re-run
reset; jq -nc '[range(1;11)] | map({databaseId: ., workflowName: "CI", event: "pull_request", createdAt: "'"$(now)"'", headBranch: "b"})' > "$FIX/runs-o_r.json"
touch "$FIX/net-run-view"
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"; rc=$?
[ "$(grep -c "run view" "$LOG")" -eq 2 ]; check "rerun: unreachable logs: two attempts only" $?
[ $rc -eq 1 ] && [ "$(grep -c "tend: error:" <<<"$out")" -eq 1 ] \
  && grep -qF "failed-run logs are not reachable from here; skipped CI re-runs (10 runs not checked)" <<<"$out"
check "rerun: unreachable logs: one summary line, exit 1" $?
! logged "run rerun"; check "rerun: nothing re-run when logs are unreachable" $?
rm "$FIX/net-run-view"; : > "$LOG"; again
[ "$(grep -c "run view" "$LOG")" -eq 10 ] && [ "$(grep -c "could not read the failed log" <<<"$out")" -eq 10 ]
check "rerun: nothing recorded, so the runs are read again next check" $?

# a read that hits the time bound counts as a network failure
reset; jq -nc '[range(1;11)] | map({databaseId: ., workflowName: "CI", event: "pull_request", createdAt: "'"$(now)"'", headBranch: "b"})' > "$FIX/runs-o_r.json"
touch "$FIX/slow-run-view"
out="$(TEND_LOG_TIMEOUT=1 "$tend" --config "$cfg" --state "$ST" 2>&1)"; rc=$?
[ $rc -eq 1 ] && [ "$(grep -c "run view" "$LOG")" -eq 2 ] && grep -qF "skipped CI re-runs (10 runs not checked)" <<<"$out"
check "rerun: two reads hitting the time bound stop the section" $?

# exactly the last two pending runs fail on the network: same summary line
reset; jq -nc '[1,2,3,4] | map({databaseId: ., workflowName: "CI", event: "pull_request", createdAt: "'"$(now)"'", headBranch: "b"})' > "$FIX/runs-o_r.json"
for i in 1 2; do printf 'build\tSet up job\t2026-01-01T00:00:00.0000000Z real failure\n' > "$FIX/log-$i.txt"; done
touch "$FIX/net-run-3" "$FIX/net-run-4"
out="$("$tend" --config "$cfg" --state "$ST" 2>&1)"; rc=$?
[ $rc -eq 1 ] && [ "$(grep -c "tend: error:" <<<"$out")" -eq 1 ] \
  && grep -qF "failed-run logs are not reachable from here; skipped CI re-runs (2 runs not checked)" <<<"$out"
check "rerun: last two runs unreachable: 'not reachable' line once, exit 1" $?
! logged "run rerun"; check "rerun: last two runs unreachable: no run rerun call" $?

# rebase off must not skip the rest of the repository loop
reset; jq -n '{repos: ["o/r", "o/s"], rebase: "off", knights: {"*": "coder-knight"}}' > "$work/off2.json"
echo '[]' > "$FIX/prs-o_r.json"
jq -c '[{number: 7, url: "https://github.com/o/s/pull/7", isDraft: false, labels: [], autoMergeRequest: null, mergeStateStatus: "CLEAN", headRefOid: "abcdef1234567", author: {login: "someone", is_bot: false}}]' <<<null > "$FIX/prs-o_s.json"
jq -nc '[{state: "COMMENTED", submitted_at: "2026-01-01T00:00:00Z", body: "Verdict: ship it"}]' > "$FIX/reviews-o_s-7.json"
out="$("$tend" --config "$work/off2.json" --state "$ST" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "tend: queued o/s#7 (ship it, head abcdef1)" ]; check "rebase: off -> a ship-it PR in a later repository is still queued" $?

# ---- all at once ----
reset; prs '[{"number":1},{"number":2,"bot":true,"mss":"DIRTY"}]'; reviews 1 'Verdict: ship it'
chain pr-pipeline-r-5 Failed 2026-01-01T00:00:00Z "stopped before finishing"; issue o/r 5 OPEN needs-human
echo '{"o/r#12": ["o/r#10"]}' > "$D"; issue o/r 12 OPEN; issue o/r 10 CLOSED
runs $id; logline "Could not resolve host: x"
run; [ $rc -eq 0 ] && [ "$(lines)" = 5 ]; check "all actions: five lines" $?
again; [ -z "$out" ]; check "all actions: second run prints nothing" $?
jq -e 'keys == ["deps","queue","rebase","requeue","rerun"]' "$ST" >/dev/null; check "all actions: state keyed per action" $?

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
