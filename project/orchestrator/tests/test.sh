#!/usr/bin/env bash
# Tests for scripts/status using gh and kubectl stubs on PATH.
#   bash project/orchestrator/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
skill="$here/.."
status="$skill/scripts/status"
schema="$skill/scripts/status.schema.json"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix" LOG="$work/log"

# gh stub, fixtures under $FIX/gh (repo owner/name is written owner_name):
#   pr list --repo R               -> <R>/prs.json      ($FIX/gh/<R>/fail-prs: exit 1 with $FIX/gh/<R>/fail-prs as stderr)
#   issue list --repo R --label L  -> <R>/issues-<L>.json  (missing: [])
#   api [--paginate] PATH --jq E   -> api/<PATH with / as _>.json filtered by jq -r E (missing: [])
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
if [ "$1" = api ]; then sub=api; shift; else sub="$1 $2"; shift 2; fi
repo=""; label=""; jqe=""; path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2//\//_}"; shift 2 ;;
    --label) label="${2//[:\/]/_}"; shift 2 ;;
    --jq) jqe="$2"; shift 2 ;;
    --json|--state|--limit) shift 2 ;;
    --paginate) shift ;;
    *) path="${1//\//_}"; shift ;;
  esac
done
case "$sub" in
  "pr list")
    [ -e "$FIX/gh/$repo/fail-prs" ] && { cat "$FIX/gh/$repo/fail-prs" >&2; exit 1; }
    cat "$FIX/gh/$repo/prs.json" ;;
  "issue list") f="$FIX/gh/$repo/issues-$label.json"; [ -e "$f" ] && cat "$f" || echo '[]' ;;
  api) f="$FIX/gh/api/$path.json"; { [ -e "$f" ] && cat "$f" || echo '[]'; } | jq -r "$jqe" ;;
  *) echo "unexpected gh $sub" >&2; exit 3 ;;
esac
STUB
# kubectl stub: -n NS get RES -o json -> $FIX/k8s/<RES>.json; $FIX/k8s/forbid-<RES> -> Forbidden.
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
echo "kubectl $*" >> "$LOG"
[ "$1" = -n ] && [ "$3" = get ] || { echo "unexpected kubectl $*" >&2; exit 3; }
res="$4"
[ -e "$FIX/k8s/forbid-$res" ] && { echo "Error from server (Forbidden): $res is forbidden: User \"system:serviceaccount:$2:knight\" cannot list resource" >&2; exit 1; }
cat "$FIX/k8s/$res.json" 2>/dev/null || echo '{"items":[]}'
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" KUBECTL="$work/bin/kubectl"

fails=0; n=0
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/stderr")"; rc=$?; printf '%s\n' "$out" > "$work/out.json"; }
q() { jq -e "$@" "$work/out.json" >/dev/null 2>&1; }
valid() { python3 -I "$here/validate.py" "$schema" "$work/out.json"; }
ago() { jq -nr --argjson s "$1" 'now - $s | todate'; }
logged() { grep -qF -- "$1" "$LOG"; }

fixtures() {
  rm -rf "$FIX" "$LOG"; mkdir -p "$FIX/gh/api" "$FIX/gh/example-org_service" "$FIX/gh/example-org_dashboard" "$FIX/k8s"; : > "$LOG"
  cat > "$FIX/gh/example-org_service/prs.json" <<'EOF'
[
 {"number":10,"title":"feat: a","author":{"login":"dunce-bot[bot]"},"isDraft":false,"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","labels":[],"autoMergeRequest":null,"headRefOid":"aaa"},
 {"number":11,"title":"fix: b","author":{"login":"someone"},"isDraft":true,"mergeStateStatus":"DIRTY","mergeable":"CONFLICTING","labels":[{"name":"hold"}],"autoMergeRequest":{"enabledAt":"2026-01-01T00:00:00Z"},"headRefOid":"bbb"},
 {"number":12,"title":"docs: c","author":{"login":"dunce-bot[bot]"},"isDraft":false,"mergeStateStatus":"BLOCKED","mergeable":"MERGEABLE","labels":[{"name":"protected-paths"}],"autoMergeRequest":null,"headRefOid":"ccc"}
]
EOF
  echo '[]' > "$FIX/gh/example-org_dashboard/prs.json"
  cat > "$FIX/gh/api/repos_example-org_service_pulls_10_reviews.json" <<'EOF'
[{"state":"COMMENTED","submitted_at":"2026-01-01T10:00:00Z","body":"Looks fine.\r\n\r\n**Verdict:** ship it"}]
EOF
  cat > "$FIX/gh/api/repos_example-org_service_pulls_11_reviews.json" <<'EOF'
[{"state":"COMMENTED","submitted_at":"2026-01-01T10:00:00Z","body":"Verdict: ship it"}]
EOF
  cat > "$FIX/gh/api/repos_example-org_service_issues_11_comments.json" <<'EOF'
[{"created_at":"2026-01-02T10:00:00Z","body":"Second look.\n> Verdict: needs changes — tests missing"}]
EOF
  cat > "$FIX/gh/api/repos_example-org_service_pulls_12_reviews.json" <<'EOF'
[{"state":"DISMISSED","submitted_at":"2026-01-01T10:00:00Z","body":"Verdict: ship it"}]
EOF
  echo '[{"number":5,"title":"ready one","labels":[{"name":"rt:ready"}]}]' > "$FIX/gh/example-org_dashboard/issues-rt_ready.json"
  echo '[{"number":6,"title":"busy one","labels":[{"name":"rt:in-progress"}]}]' > "$FIX/gh/example-org_dashboard/issues-rt_in-progress.json"
  echo '[{"number":7,"title":"stuck one","labels":[{"name":"needs-human"},{"name":"bug"}]}]' > "$FIX/gh/example-org_dashboard/issues-needs-human.json"

  jq -n --arg recent "$(ago 600)" --arg old "$(ago 7200)" --arg start "$(ago 3600)" '{items: [
    {metadata:{name:"pr-pipeline-service-3"}, status:{phase:"Failed", startedAt:$start, completedAt:$recent,
      stepStatuses:[{name:"plan",phase:"Succeeded"},
                    {name:"code",phase:"Failed",taskId:"t-3",error:"knight stopped before finishing",completedAt:$recent}]}},
    {metadata:{name:"pr-pipeline-service-4"}, status:{phase:"Running", startedAt:$start,
      stepStatuses:[{name:"plan",phase:"Running",taskId:"t-4"}]}},
    {metadata:{name:"pr-pipeline-dashboard-9"}, status:{phase:"Failed", completedAt:$old,
      stepStatuses:[{name:"review",phase:"Failed",taskId:"t-9",error:"plan: step timed out after 600s",completedAt:$old}]}},
    {metadata:{name:"pr-pipeline-dashboard-1"}, status:{}},
    {metadata:{name:"nightly-report"}, status:{phase:"Failed",
      stepStatuses:[{name:"gather",phase:"Failed",taskId:"t-n",error:"provider overloaded",completedAt:$recent}]}}
  ]}' > "$FIX/k8s/chains.ai.roundtable.io.json"
  cat > "$FIX/k8s/knights.ai.roundtable.io.json" <<'EOF'
{"items":[
 {"metadata":{"name":"rt-b"},"status":{"phase":"Ready","ready":true}},
 {"metadata":{"name":"rt-a"},"status":{"phase":"Ready","ready":true}},
 {"metadata":{"name":"rt-c"},"status":{"phase":"Degraded"}},
 {"metadata":{"name":"rt-new"}}
]}
EOF
  jq -n --arg now "$(ago 60)" '{items: [
    {metadata:{name:"table-a"}, status:{prFeedback:{activeRun:"run-1", lastPollTime:$now, pullRequests:[
      {repo:"example-org/service",number:10,phase:"Fixing",failureKind:"conflict",failureHeadSHA:"aaa",message:"rebasing",updatedAt:$now},
      {repo:"example-org/service",number:12,phase:"Watching"},
      {repo:"other-org/elsewhere",number:3,phase:"Queued",failureKind:"ci",failureHeadSHA:"zzz"}]}}},
    {metadata:{name:"table-b"}, status:{phase:"Ready"}}]}' > "$FIX/k8s/roundtables.ai.roundtable.io.json"
  jq -n --arg recent "$(ago 120)" --arg newer "$(ago 30)" --arg old "$(ago 3600)" '{items: [
    {reason:"IssuePickupHeld", involvedObject:{kind:"RoundTable",name:"table-a"}, count:7, lastTimestamp:$recent,
     message:"example-org/service: 4 ready issue(s) held, open breaking PR(s): #618 (rt/610-trigger-cronjobs)"},
    {reason:"IssuePickupHeld", involvedObject:{kind:"RoundTable",name:"table-c"}, lastTimestamp:$newer, message:"newer hold"},
    {reason:"IssuePickupHeld", involvedObject:{kind:"RoundTable",name:"table-b"}, count:2, lastTimestamp:$old, message:"old hold"},
    {reason:"Other", involvedObject:{kind:"RoundTable",name:"table-a"}, lastTimestamp:$newer, message:"unrelated"}]}' > "$FIX/k8s/events.json"
  cat > "$FIX/k8s/pods.json" <<'EOF'
{"items":[
 {"metadata":{"name":"ok-pod"},"status":{"phase":"Running","containerStatuses":[{"name":"main","ready":true,"restartCount":0}]}},
 {"metadata":{"name":"done-pod"},"status":{"phase":"Succeeded"}},
 {"metadata":{"name":"pull-pod"},"status":{"phase":"Pending","containerStatuses":[
    {"name":"main","ready":false,"restartCount":0,"state":{"waiting":{"reason":"ImagePullBackOff"}}},
    {"name":"sidecar","ready":true,"restartCount":0}]}},
 {"metadata":{"name":"evicted-pod"},"status":{"phase":"Failed","reason":"Evicted"}}
]}
EOF
}

# ---- usage and config ----
fixtures; run "$status"; [ $rc -eq 2 ]; check "no repositories or namespace exits 2" $?
run "$status" --bogus; [ $rc -eq 2 ]; check "unknown flag exits 2" $?
run "$status" --repo not-a-repo; [ $rc -eq 2 ]; check "bad repository exits 2" $?
echo '[1]' > "$work/bad.json"; run "$status" --config "$work/bad.json"; [ $rc -eq 2 ]; check "non-object config exits 2" $?
run "$status" --config "$work/missing.json"; [ $rc -eq 2 ]; check "missing config exits 2" $?
run "$status" --namespace x --dead-letter-minutes soon; [ $rc -eq 2 ]; check "bad --dead-letter-minutes exits 2" $?

# ---- full snapshot from config.example.json ----
fixtures
run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ]; check "example config: exits 0" $?
valid; check "example config: output validates against the schema" $?
q '.errors == []'; check "example config: no errors" $?
q '.config == {repositories:["example-org/service","example-org/dashboard"],
               labels:{ready:"rt:ready",inProgress:"rt:in-progress",needsHuman:"needs-human",hold:"hold"},
               namespace:"roundtable", chainPrefix:"pr-pipeline-"}'; check "example config: config echoed" $?
q '[.repositories[].repository] == ["example-org/service","example-org/dashboard"]'; check "repositories in config order" $?
S='.repositories[0].pullRequests'
q "[$S[].number] == [10,11,12]"; check "service: three open PRs" $?
q "$S[0] | .verdict == \"Verdict: ship it\" and .shipIt and (.autoMerge|not) and (.held|not) and .draft == false
          and .author == \"dunce-bot[bot]\" and .headSha == \"aaa\" and .mergeStateStatus == \"CLEAN\" and .mergeable == \"MERGEABLE\""
check "PR 10: markdown verdict normalised, ship it, not queued" $?
q "$S[1] | .verdict == \"Verdict: needs changes — tests missing\" and (.shipIt|not) and .held and .draft and .autoMerge
          and .labels == [\"hold\"] and .mergeable == \"CONFLICTING\""
check "PR 11: newer comment verdict wins over older review, held, draft, auto-merge on" $?
q "$S[2] | .verdict == null and (.shipIt|not) and .labels == [\"protected-paths\"]"; check "PR 12: dismissed review is ignored" $?
q '.repositories[1].pullRequests == []'; check "dashboard: no PRs" $?
q '.repositories[1].issues == {ready:[{number:5,title:"ready one",labels:["rt:ready"]}],
                              inProgress:[{number:6,title:"busy one",labels:["rt:in-progress"]}],
                              needsHuman:[{number:7,title:"stuck one",labels:["needs-human","bug"]}]}'
check "dashboard: ready / in progress / needs-human issues" $?
q '.repositories[0].issues == {ready:[],inProgress:[],needsHuman:[]}'; check "service: empty issue lists" $?
logged "issue list --repo example-org/dashboard --label rt:in-progress"; check "issues listed by configured label" $?

q '.cluster.namespace == "roundtable"'; check "cluster namespace" $?
logged "kubectl -n roundtable get chains.ai.roundtable.io -o json"; check "kubectl reads chains in the namespace" $?
q '.cluster.chains | keys == ["Failed","Running","Unknown"]'; check "chains grouped by phase, unprefixed excluded" $?
q '[.cluster.chains.Failed[].name] == ["pr-pipeline-dashboard-9","pr-pipeline-service-3"]'; check "failed chains listed" $?
q '.cluster.chains.Failed[1].failedSteps == [{name:"code",error:"knight stopped before finishing",taskId:"t-3"}]'
check "failed chain names the failed step and its error" $?
q '.cluster.chains.Running[0] | .name == "pr-pipeline-service-4" and .failedSteps == [] and .completedAt == null'; check "running chain" $?
q '.cluster.chains.Unknown[0].name == "pr-pipeline-dashboard-1"'; check "chain without status is Unknown" $?
q '.cluster.knights == {Ready:[{name:"rt-a",phase:"Ready",ready:true},{name:"rt-b",phase:"Ready",ready:true}],
                       Degraded:[{name:"rt-c",phase:"Degraded",ready:false}],
                       Unknown:[{name:"rt-new",phase:"Unknown",ready:false}]}'
check "knights grouped by phase" $?
q '.cluster.podsNotRunning == [
     {name:"evicted-pod",phase:"Failed",reason:"Evicted",containers:[]},
     {name:"pull-pod",phase:"Pending",reason:null,containers:[{name:"main",reason:"ImagePullBackOff",restarts:0}]}]'
check "pods not Running/Succeeded with unready containers" $?
q '.cluster.deadLettered | .windowMinutes == 60 and .source == "chain-steps"
     and ([.tasks[] | [.chain,.step,.taskId]] == [["nightly-report","gather","t-n"],["pr-pipeline-service-3","code","t-3"]]
          or [.tasks[] | [.chain,.step,.taskId]] == [["pr-pipeline-service-3","code","t-3"],["nightly-report","gather","t-n"]])'
check "dead-lettered: recent failed steps of all chains, old ones excluded" $?
run "$status" --config "$skill/config.example.json" --dead-letter-minutes 180
q '.cluster.deadLettered.windowMinutes == 180 and (.cluster.deadLettered.tasks | length) == 3'; check "--dead-letter-minutes widens the window" $?

q '.cluster.prFeedback | length == 1 and .[0].table == "table-a" and .[0].activeRun == "run-1"
     and (.[0].pullRequests | length) == 2
     and .[0].pullRequests[0] == {repo:"example-org/service",number:10,phase:"Fixing",failureKind:"conflict",headSha:"aaa",message:"rebasing",updatedAt:.[0].lastPollTime}
     and .[0].pullRequests[1].failureKind == null and .[0].pullRequests[1].headSha == null'
check "prFeedback: table with status.prFeedback, other repositories dropped, table without it omitted" $?
logged "kubectl -n roundtable get roundtables.ai.roundtable.io -o json"; check "kubectl reads roundtables" $?
q '.cluster.pickupHeld | map(.table) == ["table-c","table-a"] and .[1].count == 7 and .[0].count == 1
     and (.[1].message | startswith("example-org/service: 4 ready issue(s) held"))'
check "pickupHeld: recent events newest first, old and other reasons dropped" $?
logged "get events --field-selector reason=IssuePickupHeld"; check "kubectl reads IssuePickupHeld events" $?

# ---- roundtables / events unreadable ----
fixtures; touch "$FIX/k8s/forbid-roundtables.ai.roundtable.io"
run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ] && valid; check "roundtables forbidden: exits 0 and validates" $?
q '.cluster.prFeedback == null and (.cluster.pickupHeld | length) == 2 and (.cluster.chains.Running | length) == 1
   and (.errors | length) == 1 and .errors[0].section == "cluster.prFeedback" and (.errors[0].message | startswith("Error from server (Forbidden)"))'
check "roundtables forbidden: prFeedback null with an error, other sections read" $?
fixtures; touch "$FIX/k8s/forbid-events"
run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ] && valid; check "events forbidden: exits 0 and validates" $?
q '.cluster.pickupHeld == null and (.cluster.prFeedback | length) == 1 and (.errors | length) == 1 and .errors[0].section == "cluster.pickupHeld"'
check "events forbidden: pickupHeld null with an error, other sections read" $?
fixtures; echo '{"items":[]}' > "$FIX/k8s/events.json"; echo '{"items":[]}' > "$FIX/k8s/roundtables.ai.roundtable.io.json"
run "$status" --config "$skill/config.example.json"
valid && q '.cluster.pickupHeld == [] and .cluster.prFeedback == [] and .errors == []'; check "no events and no roundtables: empty arrays" $?

# ---- kubectl unavailable ----
fixtures
KUBECTL="$work/no-such-kubectl" run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ]; check "kubectl unavailable: exits 0" $?
valid; check "kubectl unavailable: output validates" $?
q '.cluster | .chains == null and .knights == null and .podsNotRunning == null and .deadLettered == null and .prFeedback == null and .pickupHeld == null'
check "kubectl unavailable: cluster sections are null" $?
q '.errors == [{section:"cluster",message:"kubectl not found"}]'; check "kubectl unavailable: one errors entry" $?
q '[.repositories[0].pullRequests[].number] == [10,11,12]'; check "kubectl unavailable: GitHub sections still read" $?

# ---- kubectl forbidden for one resource ----
fixtures; touch "$FIX/k8s/forbid-knights.ai.roundtable.io"
run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ] && valid; check "knights forbidden: exits 0 and validates" $?
q '.cluster.knights == null and (.cluster.chains.Running | length) == 1 and (.cluster.podsNotRunning | length) == 2'
check "knights forbidden: other cluster sections still read" $?
q '.errors | length == 1 and .[0].section == "cluster.knights" and (.[0].message | startswith("Error from server (Forbidden)"))'
check "knights forbidden: errors entry with the reason" $?

fixtures; touch "$FIX/k8s/forbid-chains.ai.roundtable.io"
run "$status" --config "$skill/config.example.json"
valid && q '.cluster.chains == null and .cluster.deadLettered == null and ([.errors[].section] == ["cluster.chains","cluster.deadLettered"])'
check "chains forbidden: chains and dead letters null with errors" $?

# ---- gh failure ----
fixtures
tok="gh""p_$(printf 'Q%.0s' $(seq 1 36))"  # fake token, assembled so no literal token is in the source
printf '%s\n' "" "HTTP 401: Bad credentials ($tok)" > "$FIX/gh/example-org_service/fail-prs"
run "$status" --config "$skill/config.example.json"
[ $rc -eq 0 ] && valid; check "gh failure: exits 0 and validates" $?
q '.repositories[0].pullRequests == null and .repositories[1].pullRequests == []'; check "gh failure: only that section is null" $?
q '.errors[0].section == "repositories[example-org/service].pullRequests" and (.errors[0].message | startswith("HTTP 401: Bad credentials"))'
check "gh failure: errors entry with the first line of the reason" $?
! grep -q "$tok" "$work/out.json"; check "gh failure: token-like strings are redacted" $?

# ---- arguments instead of a config ----
fixtures
echo '[{"number":8,"title":"t","labels":[{"name":"go"}]}]' > "$FIX/gh/example-org_dashboard/issues-go.json"
run "$status" --repo example-org/dashboard --namespace other --chain-prefix nightly-
[ $rc -eq 0 ] && valid; check "arguments only: exits 0 and validates" $?
q '.config.repositories == ["example-org/dashboard"] and .config.namespace == "other" and .config.labels.ready == "rt:ready"'
check "arguments only: default labels" $?
logged "kubectl -n other get" && q '.cluster.chains | keys == ["Failed"] and .Failed[0].name == "nightly-report"'
check "arguments only: namespace and chain prefix used" $?
jq '.labels.ready = "go"' "$skill/config.example.json" > "$work/cfg.json"
run "$status" --config "$work/cfg.json" --repo example-org/dashboard
q '.config.repositories == ["example-org/dashboard"] and .repositories[0].issues.ready[0].number == 8 and .config.labels.inProgress == "rt:in-progress"'
check "--repo overrides config repositories; configured label is used" $?

run "$status" --repo example-org/dashboard
[ $rc -eq 0 ] && valid && q '.cluster.namespace == null and .errors == [{section:"cluster",message:"no namespace configured"}]'
check "no namespace: cluster is reported as an error" $?

# ---- the schema rejects a broken snapshot ----
fixtures; run "$status" --config "$skill/config.example.json"
jq 'del(.repositories[0].pullRequests[0].verdict)' "$work/out.json" > "$work/bad1.json"
! python3 -I "$here/validate.py" "$schema" "$work/bad1.json" >/dev/null; check "schema: missing PR field is rejected" $?
jq '.cluster.knights.Ready[0].ready = "yes"' "$work/out.json" > "$work/bad2.json"
! python3 -I "$here/validate.py" "$schema" "$work/bad2.json" >/dev/null; check "schema: wrong type is rejected" $?
jq '.errors = [{section:"x"}]' "$work/out.json" > "$work/bad3.json"
! python3 -I "$here/validate.py" "$schema" "$work/bad3.json" >/dev/null; check "schema: incomplete errors entry is rejected" $?

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
