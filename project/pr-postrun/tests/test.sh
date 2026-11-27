#!/usr/bin/env bash
# Tests for rt-verify, rt-close-parent and rt-handback using a gh stub on PATH.
#   bash project/pr-postrun/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/../scripts"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix" LOG="$work/log"

# gh stub: reads fixtures from $FIX, logs every mutating call to $LOG.
# pr view <url>  -> $FIX/pr-<num>.json      issue view <n> -> $FIX/issue-<n>.json[.<call#>]
# $FIX/fail-<sub> (e.g. fail-issue-view) makes that subcommand exit 1.
# pr merge prints $FIX/merge-out (if present) to its output, and exits 1 if fail-pr-merge exists.
# api repos/<r>/issues/<n>/timeline prints $FIX/timeline-<n>.json (if present); not logged.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  [ -e "$FIX/fail-api" ] && exit 1
  n="$(sed -E 's#.*/issues/([0-9]+)/timeline.*#\1#' <<<"$2")"; cat "$FIX/timeline-$n.json" 2>/dev/null; exit 0
fi
sub="$1 $2"; shift 2
if [ "$sub" = "pr merge" ]; then
  echo "pr merge $*" >> "$LOG"
  [ -e "$FIX/merge-out" ] && cat "$FIX/merge-out"
  [ -e "$FIX/fail-pr-merge" ] && exit 1
  exit 0
fi
[ -e "$FIX/fail-${sub// /-}" ] && exit 1
case "$sub" in
  "pr view") n="${1##*/}"; cat "$FIX/pr-$n.json" || exit 1 ;;
  "issue view")
    n="$1"; c="$FIX/count-$n"; k=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$c"
    f="$FIX/issue-$n.json.$k"; [ -e "$f" ] || f="$FIX/issue-$n.json"
    cat "$f" || exit 1 ;;
  *) echo "$sub $*" >> "$LOG" ;;
esac
STUB
cat > "$work/bin/rt-review-stub" <<'STUB'
#!/usr/bin/env bash
echo "rt-review $*" >> "$LOG"
[ -e "$FIX/fail-review" ] && { echo "rt-review: boom"; exit 1; }
echo "rt-review: posted"
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" RT_REVIEW="$work/bin/rt-review-stub" RT_POLL_SECONDS=0

fails=0; n=0
reset() { rm -rf "$FIX" "$LOG"; mkdir -p "$FIX"; : > "$LOG"; }
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
logged() { grep -qF -- "$1" "$LOG"; }
last() { tail -n 1 <<<"$out"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
issue() { # n labels(csv) state reason comments-json
  local l; l="$(jq -nc --arg l "$2" '[($l|split(",")[]|select(length>0))|{name:.}]')"
  jq -nc --argjson l "$l" --arg s "${3:-OPEN}" --arg r "${4:-}" --argjson c "${5:-[]}" \
    '{state:$s,stateReason:$r,labels:$l,comments:$c}' > "$FIX/issue-$1.json"
}
pr() { # n state draft labels(csv) auto(true|false) reviews-json
  local l; l="$(jq -nc --arg l "$4" '[($l|split(",")[]|select(length>0))|{name:.}]')"
  jq -nc --argjson l "$l" --arg s "$2" --argjson d "$3" --argjson a "$5" --argjson r "${6:-[]}" \
    '{state:$s,isDraft:$d,labels:$l,autoMergeRequest:(if $a then {} else null end),reviews:$r}' > "$FIX/pr-$1.json"
}
U=https://github.com/o/r/pull
echo "review body" > "$work/review.md"; echo "it broke" > "$work/summary.md"
V=("$scripts/rt-verify" o/r 7)

# ---- usage ----
for s in rt-verify rt-close-parent rt-handback; do
  reset; run "$scripts/$s"; [ $rc -eq 2 ]; check "$s: no args exits 2" $?
done
reset; run "${V[@]}" bogus "$work/review.md" $U/1; [ $rc -eq 2 ]; check "rt-verify: bad verdict exits 2" $?
reset; run "$scripts/rt-handback" o/r x "$work/summary.md"; [ $rc -eq 2 ]; check "rt-handback: bad issue exits 2" $?
reset; run "$scripts/rt-close-parent" o/r 5 x; [ $rc -eq 2 ]; check "rt-close-parent: bad sub-issue exits 2" $?

# ---- rt-verify ----
reset; issue 7 rt:in-progress; pr 1 MERGED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && [[ "$(last)" == "rt-verify: ok $U/1 merged" ]]; check "verify: merged is ok" $?
[ ! -s "$LOG" ]; check "verify: merged touches nothing" $?

reset; issue 7 rt:in-progress; pr 1 CLOSED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && [[ "$(last)" == "rt-verify: needs-human"* ]]; check "verify: closed unmerged is a problem" $?
logged "issue edit 7 --repo o/r --add-label needs-human" && logged "--remove-label rt:in-progress"; check "verify: labels needs-human, removes in-progress" $?
[ "$(tail -n 1 "$LOG" | cut -c1-30)" = "issue edit 7 --repo o/r --remo" ]; check "verify: in-progress removed last" $?

reset; issue 7 rt:in-progress; pr 1 OPEN true "" false
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && grep -q draft <<<"$(last)"; check "verify: draft is a problem" $?
reset; issue 7 rt:in-progress; pr 1 OPEN false "hold" false
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && grep -q hold <<<"$(last)"; check "verify: hold label is a problem" $?
reset; issue 7 rt:in-progress; pr 1 OPEN false "needs-human" false
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ]; check "verify: needs-human PR is a problem" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"lgtm\n\nVerdict: ship it"}]'
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && [[ "$(last)" == "rt-verify: ok $U/1 queued" ]]; check "verify: ship-it verdict present, enables auto-merge" $?
logged "pr merge $U/1 --auto --squash"; check "verify: ran gh pr merge --auto --squash" $?
! logged "rt-review"; check "verify: no duplicate review when verdict matches" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" true '[{"body":"**Verdict:** ship it"}]'
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && ! logged "pr merge"; check "verify: auto-merge already on is ok, no merge call" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"x\nVerdict: needs changes"}]'
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && logged "rt-review $U/1 ship_it $work/review.md"; check "verify: newest verdict differs, posts review via rt-review" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"},{"body":"Verdict: needs changes"}]'
run "${V[@]}" ship_it "$work/review.md" $U/1
logged "rt-review"; check "verify: only the newest verdict counts" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[]'
run "${V[@]}" needs_changes "$work/review.md" $U/1
[ $rc -eq 1 ] && grep -q "no ship-it verdict; not queued" <<<"$(last)" && ! logged "pr merge"; check "verify: needs_changes is a problem, never queued" $?
logged "rt-review $U/1 needs_changes"; check "verify: needs_changes review is posted" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[]'; touch "$FIX/fail-review"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && grep -q "rt-review failed" <<<"$(last)"; check "verify: rt-review failure is a problem" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && grep -q "could not enable auto-merge" <<<"$(last)"; check "verify: auto-merge failure is a problem" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
printf '%s\n' "GraphQL: Pull request is not mergeable: base branch policy prohibits the merge;" "  see https://docs" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && [[ "$(last)" == *"could not enable auto-merge (GraphQL: Pull request is not mergeable: base branch policy prohibits the merge,)"* ]]; check "verify: auto-merge failure includes first line of the reason" $?
logged "could not enable auto-merge (GraphQL: Pull request is not mergeable" && logged "--add-label needs-human"; check "verify: reason is posted in the issue comment" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
tok="gh""p_$(printf 'Q%.0s' $(seq 1 36))"  # fake token, assembled so no literal token is in the source
printf '%s\n' "failed: token $tok rejected" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && ! grep -q "$tok" <<<"$(last)" && grep -q "failed: token \[redacted\] rejected" <<<"$(last)"; check "verify: token-like strings are redacted from the reason" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
printf '%s\n' "Pull request is already in the merge queue" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && [[ "$(last)" == "rt-verify: ok $U/1 queued" ]] && ! logged "issue comment"; check "verify: already queued is success" $?

reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
printf '%s\n' "Pull request #1 is already merged" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 0 ] && [[ "$(last)" == "rt-verify: ok $U/1 merged" ]] && ! logged "issue comment"; check "verify: already merged is success" $?

reset; issue 7 rt:in-progress
run "${V[@]}" ship_it "$work/review.md"; [ $rc -eq 1 ] && grep -q "no PR URL" <<<"$(last)"; check "verify: no PR URL is a problem" $?

reset; issue 7 rt:in-progress; pr 1 MERGED false "" false; pr 2 CLOSED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1 $U/2
[ $rc -eq 1 ] && grep -q "$U/2" <<<"$(last)" && ! grep -q "$U/1" <<<"$(last)"; check "verify: multiple PRs, one problem fails and names it" $?

reset; issue 7 rt:in-progress; pr 1 MERGED false "" false; pr 2 MERGED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1 $U/2
[ $rc -eq 0 ] && [[ "$(last)" == "rt-verify: ok $U/1 merged $U/2 merged" ]]; check "verify: multiple merged PRs" $?

# idempotent re-run: comment already present is not posted twice
reset; pr 1 CLOSED false "" false
body="<!-- rt-postrun:rt-verify -->"$'\n'"PR verification found problems:"$'\n'"- $U/1: closed without merging"
issue 7 rt:in-progress OPEN "" "$(jq -nc --arg b "$body" '[{body:$b}]')"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && ! logged "issue comment"; check "verify: re-run posts no duplicate comment" $?
logged "--remove-label rt:in-progress"; check "verify: re-run still removes in-progress" $?

# URLs survive redaction, tokens do not
reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
tok="gh""p_$(printf 'Q%.0s' $(seq 1 36))"
printf '%s\n' "could not merge: see https://github.com/roundtable-k8s/roundtable/pull/123/checks $tok" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[[ "$(last)" == *"could not merge: see https://github.com/roundtable-k8s/roundtable/pull/123/checks [redacted])"* ]] && ! grep -q "$tok" <<<"$out"; check "verify: URL kept, ghp_ token redacted" $?
logged "https://github.com/roundtable-k8s/roundtable/pull/123/checks"; check "verify: URL is in the posted comment" $?
reset; issue 7 rt:in-progress; pr 1 OPEN false "" false '[{"body":"Verdict: ship it"}]'; touch "$FIX/fail-pr-merge"
long="$(printf 'a%.0s' $(seq 1 40))"
printf '%s\n' "bad $long done" > "$FIX/merge-out"
run "${V[@]}" ship_it "$work/review.md" $U/1
[[ "$(last)" == *"bad [redacted] done)"* ]]; check "verify: long non-URL token is redacted" $?

# same problem set posts once across two runs; changed set posts a new, different comment
reset; pr 1 CLOSED false "" false; issue 7 rt:in-progress
run "${V[@]}" ship_it "$work/review.md" $U/1
posted="$(grep -c '^issue comment' "$LOG")"
body="$(sed -n 's/^issue comment 7 --repo o\/r --body //p' "$LOG")"
[ "$posted" -eq 1 ] && [[ "$body" == "<!-- rt-postrun:rt-verify -->"* ]]; check "verify: first run posts a marker comment" $?
: > "$LOG"; issue 7 rt:in-progress OPEN "" "$(jq -nc --arg b "<!-- rt-postrun:rt-verify -->"$'\n'"PR verification found problems:"$'\n'"- $U/1: closed without merging" '[{body:$b}]')"
run "${V[@]}" ship_it "$work/review.md" $U/1
! logged "issue comment"; check "verify: second run with same problems posts nothing" $?
pr 2 CLOSED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1 $U/2
[ "$(grep -c '^issue comment' "$LOG")" -eq 1 ] && logged "$U/2: closed without merging"; check "verify: changed problem set posts one new comment" $?
issue 7 rt:in-progress OPEN "" "$(jq -nc --arg b "<!-- rt-postrun:rt-verify -->"$'\n'"PR verification found problems:"$'\n'"- $U/1: closed without merging"$'\n'"- $U/2: closed without merging" '[{body:$b}]')"
: > "$LOG"; run "${V[@]}" ship_it "$work/review.md" $U/1
! logged "issue comment"; check "verify: problems already covered by a marker comment are not re-posted" $?

# failed comment read posts nothing, result line unchanged
reset; pr 1 CLOSED false "" false; touch "$FIX/fail-issue-view"
run "${V[@]}" ship_it "$work/review.md" $U/1
[ $rc -eq 1 ] && [[ "$(last)" == "rt-verify: needs-human $U/1: closed without merging" ]] && ! logged "issue comment" && grep -q "could not read comments" <<<"$out"; check "verify: failed comment read posts nothing, same result line" $?
logged "--remove-label rt:in-progress"; check "verify: failed comment read still removes in-progress" $?

# custom labels
reset; issue 7 wip; pr 1 CLOSED false "" false
run "${V[@]}" ship_it "$work/review.md" $U/1 --in-progress-label wip --needs-human-label stuck
logged "--add-label stuck" && logged "--remove-label wip"; check "verify: custom labels" $?

# ---- rt-handback ----
H=("$scripts/rt-handback" o/r 9)
reset; issue 9 rt:in-progress
run "${H[@]}" "$work/summary.md"
[ $rc -eq 0 ] && [[ "$(last)" == "rt-handback: ok labelled o/r#9" ]]; check "handback: labels in-progress issue" $?
logged "--add-label needs-human" && logged "PR pipeline run failed:" && logged "it broke" && logged "rt:ready"; check "handback: needs-human + comment with summary" $?
[ "$(tail -n 1 "$LOG" | grep -c remove-label)" = 1 ]; check "handback: in-progress removed last" $?
reset; issue 9 rt:in-progress CLOSED completed
run "${H[@]}" "$work/summary.md"
[ $rc -eq 0 ] && [[ "$(last)" == "rt-handback: ok left-alone o/r#9" ]] && [ ! -s "$LOG" ]; check "handback: closed is left alone" $?
reset; issue 9 "needs-human"
run "${H[@]}" "$work/summary.md"
[[ "$(last)" == "rt-handback: ok left-alone o/r#9" ]] && [ ! -s "$LOG" ]; check "handback: not in progress is left alone" $?
reset; body="<!-- rt-postrun:rt-handback -->"$'\n'"PR pipeline run failed:"$'\n\n'"it broke"$'\n\n'"Add \`rt:ready\` again to re-run it."
issue 9 "rt:in-progress,needs-human" OPEN "" "$(jq -nc --arg b "$body" '[{body:$b}]')"
run "${H[@]}" "$work/summary.md"
[ $rc -eq 0 ] && ! logged "issue comment" && logged "--remove-label rt:in-progress"; check "handback: re-run posts no duplicate comment" $?
reset; issue 9 wip
run "${H[@]}" "$work/summary.md" --in-progress-label wip --needs-human-label stuck
logged "--add-label stuck" && logged "--remove-label wip"; check "handback: custom labels" $?
reset; touch "$FIX/fail-issue-view"
run "${H[@]}" "$work/summary.md"
[ $rc -ne 0 ]; check "handback: gh error exits non-zero" $?

# ---- rt-close-parent ----
C=("$scripts/rt-close-parent" o/r 5)
reset; issue 5 ""; issue 11 "" CLOSED completed
run "${C[@]}" 11
[[ "$(last)" == "rt-close-parent: ok left-alone 5" ]] && [ $rc -eq 0 ] && [ ! -s "$LOG" ]; check "close-parent: parent not in progress is left alone" $?

reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed; issue 12 "" CLOSED completed
run "${C[@]}" 11 12
[ $rc -eq 0 ] && [[ "$(last)" == "rt-close-parent: ok closed 5" ]]; check "close-parent: all completed closes parent" $?
logged "issue close 5 --repo o/r --reason completed" && logged "All sub-issues"; check "close-parent: closed with comment" $?
[ "$(tail -n 1 "$LOG" | grep -c remove-label)" = 1 ]; check "close-parent: in-progress removed last" $?

reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed; issue 12 "" CLOSED NOT_PLANNED
run "${C[@]}" 11 12
[ $rc -eq 0 ] && [[ "$(last)" == "rt-close-parent: ok handed-back 5" ]]; check "close-parent: not planned hands back" $?
logged "--add-label needs-human" && logged "#12" && ! logged "issue close"; check "close-parent: needs-human, names #12, parent stays open" $?

reset; issue 5 rt:in-progress; issue 11 needs-human; 
run "${C[@]}" 11
[[ "$(last)" == "rt-close-parent: ok handed-back 5" ]] && logged "#11"; check "close-parent: needs-human sub-issue hands back without waiting" $?

reset; issue 5 rt:in-progress; issue 11 "" OPEN
run "${C[@]}" --wait-minutes 0 11
[[ "$(last)" == "rt-close-parent: ok handed-back 5" ]] && logged "#11"; check "close-parent: still open at timeout hands back" $?

reset; issue 5 rt:in-progress; issue 11 "" OPEN; issue 11 "" OPEN
cp "$FIX/issue-11.json" "$FIX/issue-11.json.1"; cp "$FIX/issue-11.json" "$FIX/issue-11.json.2"
issue 11 "" CLOSED completed
run "${C[@]}" 11
[[ "$(last)" == "rt-close-parent: ok closed 5" ]] && [ "$(cat "$FIX/count-11")" -ge 3 ]; check "close-parent: polls until sub-issue closes" $?

reset; issue 5 rt:in-progress OPEN "" "$(jq -nc '[{body:"<!-- rt-postrun:rt-close-parent -->\nAll sub-issues (#11) closed as completed; closing this parent."}]')"; issue 11 "" CLOSED completed
run "${C[@]}" 11
[[ "$(last)" == "rt-close-parent: ok closed 5" ]] && ! logged "issue comment"; check "close-parent: re-run posts no duplicate comment" $?

reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed; issue 12 "" CLOSED completed
jq -nc '[{event:"cross-referenced",source:{issue:{number:30,repository:{full_name:"o/r"},pull_request:{merged_at:"2026-01-01T00:00:00Z"}}}},
         {event:"cross-referenced",source:{issue:{number:31,repository:{full_name:"o/r"},pull_request:{merged_at:null}}}},
         {event:"labeled"}]' > "$FIX/timeline-11.json"
jq -nc '[{event:"cross-referenced",source:{issue:{number:30,repository:{full_name:"o/r"},pull_request:{merged_at:"2026-01-01T00:00:00Z"}}}},
         {event:"cross-referenced",source:{issue:{number:32,repository:{full_name:"o/x"},pull_request:{merged_at:"2026-01-02T00:00:00Z"}}}},
         {event:"cross-referenced",source:{issue:{number:33,repository:{full_name:"o/r"}}}}]' > "$FIX/timeline-12.json"
run "${C[@]}" 11 12
[ $rc -eq 0 ] && logged "Merged PRs: o/r#30, o/x#32" && ! logged "o/r#31" && ! logged "o/r#33"; check "close-parent: lists merged PRs from the timelines" $?
reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed; touch "$FIX/fail-api"
run "${C[@]}" 11
[ $rc -eq 0 ] && [[ "$(last)" == "rt-close-parent: ok closed 5" ]] && logged "All sub-issues" && ! logged "Merged PRs"; check "close-parent: failed timeline lookup omits the line" $?
reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed
run "${C[@]}" 11
[ "$(sed -n 's/^issue comment 5 --repo o\/r --body //p' "$LOG" | head -n 1)" = "<!-- rt-postrun:rt-close-parent -->" ]; check "close-parent: comment starts with marker" $?
# a repo name with a double quote must not break the jq program
reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed
jq -nc '[{event:"cross-referenced",source:{issue:{number:30,pull_request:{merged_at:"2026-01-01T00:00:00Z"}}}}]' > "$FIX/timeline-11.json"
run "$scripts/rt-close-parent" 'o"x/r' 5 11
[ $rc -eq 0 ] && logged 'Merged PRs: o"x/r#30'; check "close-parent: repo name with a double quote is passed to jq safely" $?
# timeline lookup failed on the first run, the marker comment lacks the Merged PRs line; the re-run
# finds the merged PR and must not post a second close comment
reset; issue 5 rt:in-progress OPEN "" "$(jq -nc '[{body:"<!-- rt-postrun:rt-close-parent -->\nAll sub-issues (#11) closed as completed; closing this parent."}]')"; issue 11 "" CLOSED completed
jq -nc '[{event:"cross-referenced",source:{issue:{number:30,repository:{full_name:"o/r"},pull_request:{merged_at:"2026-01-01T00:00:00Z"}}}}]' > "$FIX/timeline-11.json"
run "${C[@]}" 11
[[ "$(last)" == "rt-close-parent: ok closed 5" ]] && ! logged "issue comment" && logged "issue close 5"; check "close-parent: re-run with a new Merged PRs line posts no second comment" $?
# comment read fails on the parent's second view only: nothing posted
reset; issue 5 rt:in-progress; issue 11 "" CLOSED completed
printf 'not json' > "$FIX/issue-5.json.3"
run "${C[@]}" 11
[ $rc -eq 0 ] && [[ "$(last)" == "rt-close-parent: ok closed 5" ]] && ! logged "issue comment" && grep -q "could not read comments" <<<"$out"; check "close-parent: failed comment read posts nothing, same result line" $?

reset; issue 5 wip; issue 11 "" CLOSED completed
run "${C[@]}" --in-progress-label wip 11
logged "--remove-label wip"; check "close-parent: custom in-progress label" $?
reset; touch "$FIX/fail-issue-view"
run "${C[@]}" 11
[ $rc -ne 0 ]; check "close-parent: gh error exits non-zero" $?

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
