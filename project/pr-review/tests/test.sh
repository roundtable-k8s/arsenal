#!/usr/bin/env bash
# Tests for rt-review using a gh stub on PATH.
#   bash project/pr-review/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/rt-review"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix" LOG="$work/log"

# gh stub: fixtures in $FIX, every call logged to $LOG.
#   pr view <url>    -> $FIX/pr.json
#   pr review <url>  appends {submitted_at, body} to $FIX/reviews.json
#   api ... --jq E   -> reviews.json filtered by E
#   pr edit / pr merge / ... exit 1 when $FIX/fail-<sub> exists (e.g. fail-pr-edit)
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
if [ "$1" = api ]; then
  jqe=""; while [ $# -gt 0 ]; do case "$1" in --jq) jqe="$2"; shift 2 ;; *) shift ;; esac; done
  jq -r "$jqe" "$FIX/reviews.json"; exit $?
fi
sub="$1 $2"; shift 2
[ -e "$FIX/fail-${sub// /-}" ] && exit 1
case "$sub" in
  "pr view") cat "$FIX/pr.json" ;;
  "pr review")
    body=""; while [ $# -gt 0 ]; do case "$1" in --body-file) body="$(cat "$2")"; shift 2 ;; *) shift ;; esac; done
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -nc --arg t "$now" --arg b "$body" '{submitted_at:$t, body:$b}' >> "$FIX/reviews.jsonl"
    jq -s '.' "$FIX/reviews.jsonl" > "$FIX/reviews.json" ;;
esac
exit 0
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

fails=0; n=0
reset() { rm -rf "$FIX" "$LOG"; mkdir -p "$FIX"; : > "$LOG"; echo '[]' > "$FIX/reviews.json"; }
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
logged() { grep -qF -- "$1" "$LOG"; }
last() { tail -n 1 <<<"$out"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
U=https://github.com/o/r/pull/7
echo "it is fine" > "$work/review.md"
open_pr() { echo '{"state":"OPEN","isDraft":false,"labels":[]}' > "$FIX/pr.json"; }

# ---- usage and validation ----
reset; run "$script"; [ $rc -eq 2 ]; check "no args exits 2" $?
reset; run "$script" $U bogus "$work/review.md"; [ $rc -eq 2 ]; check "bad verdict exits 2" $?
reset; run "$script" https://example.com/x ship_it "$work/review.md"; [ $rc -eq 2 ]; check "bad URL exits 2" $?
reset; run "$script" $U ship_it "$work/missing.md"; [ $rc -eq 2 ]; check "missing body file exits 2" $?
reset; run "$script" $U ship_it "$work/missing.md"; ! logged "pr review"; check "validation failure posts nothing" $?

# ---- --no-queue ship_it: hold label, review posted, not queued ----
reset; open_pr; run "$script" --no-queue $U ship_it "$work/review.md"
[ $rc -eq 0 ]; check "no-queue ship_it exits 0" $?
logged "gh pr edit $U --add-label hold"; check "no-queue ship_it adds hold label" $?
logged "gh pr review $U --comment"; check "no-queue ship_it posts the review" $?
[ "$(jq -r '.[-1].body' "$FIX/reviews.json")" = "$(printf 'it is fine\n\nVerdict: ship it')" ]; check "no-queue ship_it review ends with ship-it verdict" $?
! logged "pr merge"; check "no-queue ship_it does not queue" $?
[[ "$(last)" == "rt-review: posted 'Verdict: ship it' on $U; queued: no (--no-queue; hold label added)" ]]; check "no-queue ship_it output line says hold added" $?
logged "pr edit" && [ "$(grep -n 'pr edit' "$LOG" | cut -d: -f1)" -lt "$(grep -n 'pr review' "$LOG" | cut -d: -f1)" ]; check "hold label is added before the review" $?

# ---- --no-queue needs_changes: no hold label ----
reset; open_pr; run "$script" --no-queue $U needs_changes "$work/review.md"
[ $rc -eq 0 ]; check "no-queue needs_changes exits 0" $?
! logged "pr edit"; check "no-queue needs_changes adds no hold label" $?
[[ "$(last)" == "rt-review: posted 'Verdict: needs changes' on $U; queued: no" ]]; check "no-queue needs_changes output line" $?

# ---- ship_it without --no-queue: no hold label, queued ----
reset; open_pr; run "$script" $U ship_it "$work/review.md"
[ $rc -eq 0 ]; check "queued ship_it exits 0" $?
! logged "pr edit"; check "queued ship_it adds no hold label" $?
logged "pr merge $U --auto"; check "queued ship_it enables auto-merge" $?
[[ "$(last)" == "rt-review: posted 'Verdict: ship it' on $U; queued: yes (merge queue)" ]]; check "queued ship_it output line" $?

# ---- hold label failure: nothing posted, nothing queued ----
reset; open_pr; touch "$FIX/fail-pr-edit"; run "$script" --no-queue $U ship_it "$work/review.md"
[ $rc -eq 1 ] && grep -q "could not add the hold label" <<<"$out"; check "hold label failure exits 1 with a message" $?
! logged "pr review"; check "hold label failure posts no review" $?
! logged "pr merge"; check "hold label failure does not queue" $?

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
