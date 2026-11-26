#!/usr/bin/env bash
# Checks project/orchestrator/SKILL.md and reference/issue-format.md: frontmatter,
# the procedure order, the limits (word for word from the orchestrator epic),
# the issue format sections, and no environment-specific names.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
skill="$here/SKILL.md"; fmt="$here/reference/issue-format.md"
review="$here/reference/review-owner-questions.md"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

[ -r "$skill" ] && [ -r "$fmt" ] || { echo "missing SKILL.md or reference/issue-format.md"; exit 1; }

# Frontmatter: the fields validate-skills reads.
front="$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$skill")"
check "frontmatter name is orchestrator" grep -qx 'name: orchestrator' <<<"$front"
check "frontmatter has a description" grep -q '^description:' <<<"$front"

# Procedure steps in order.
steps="$(grep -E '^### [0-9]+\. ' "$skill" | sed -E 's/^### [0-9]+\. //')"
check "procedure: status, tend, dispatch, feed, decide, log" \
  test "$(tr '\n' ',' <<<"$steps")" = "Status,Tend,Dispatch follow-ups,Feed,Decide,Log,"

# Rules the procedure must state.
check "feed threshold (about eight)" grep -q 'fewer than about eight' "$skill"
check "feed writes two to four issues" grep -q 'two to four' "$skill"
check "feed links the issue format" grep -q 'reference/issue-format.md' "$skill"
check "decide comment format" grep -q 'Decided <YYYY-MM-DD> (orchestrator)' "$skill"
check "decide leaves taste to the owner" grep -q 'product-direction and taste questions' "$skill"
check "decide names the decision register path" grep -q 'docs/decisions.md' "$skill"
check "one-off section links the review procedure" grep -q 'reference/review-owner-questions.md' "$skill"
check "log is 3-8 lines" grep -q '3–8 plain lines' "$skill"

# One-off owner-question review: the reference file covers the six points.
check "review reference exists" [ -r "$review" ]
check "review reads both sources from the operator repo" \
  bash -c 'grep -q "docs/principles.md" "$1" && grep -q "docs/decisions.md" "$1"' _ "$review"
check "review uses the step 5 comment format" grep -q 'Decided <YYYY-MM-DD> (orchestrator)' "$review"
for n in 1 2 3 4 5 6; do
  check "review has point $n" grep -qE "^$n\. \*\*" "$review"
done
check "review never decides product-direction or taste" grep -q 'Never decide' "$review"
for s in status tend dispatch alert; do
  check "names scripts/$s" grep -q "\$S/$s" "$skill"
done
for s in project/pr-review project/pr-postrun project/github-pm; do
  check "points to $s" grep -q "$s" "$skill"
done

# github-pm: no hard-coded milestone names (they were retired; read them live).
gpm="$here/../github-pm/SKILL.md"
check "github-pm exists" [ -r "$gpm" ]
check "github-pm names no retired v1.0/v2.0/v3.0 milestones" \
  bash -c '! grep -qE "v[123]\.0" "$1"' _ "$gpm"

# Limits: word for word from the epic's "What it must never do".
limits="Handle credential values or create credentials; grant itself or any knight permissions; delete data or repositories; restart nodes or touch node configuration; start or copy pipeline chains by hand; reword someone else's issue to get it past pickup; add approval gates; expose anything outside the cluster. If one of its own changes breaks the factory, it reverts first and investigates after."
check "limits verbatim" grep -qxF "$limits" "$skill"

# Issue format: the three rules and the sections, in order.
for r in 'One pull request, testable, no human decision needed.' \
         'Verified against the code:' 'Additive and safe:'; do
  check "issue rule: $r" grep -qF "$r" "$fmt"
done
sections="$(sed -n '/^```$/,/^```$/p' "$fmt" | grep -E '^## ' | tr '\n' ',')"
check "issue sections in order" \
  test "$sections" = "## Goal,## Context,## Tasks,## Acceptance criteria,## Out of scope,"
check "issue format starts with Part of #<epic>" grep -q '^Part of #<epic>' "$fmt"
check "conventional titles" grep -q 'feat(scope)' "$fmt"

# Nothing environment-specific: no workstation paths, cluster or personal names.
for f in "$skill" "$fmt" "$review"; do
  check "no workstation paths in ${f#$here/}" bash -c '! grep -qE "(/home/|/Users/|~/)" "$1"' _ "$f"
  check "no cluster or person names in ${f#$here/}" bash -c '! grep -qiE "dapper|derek|merlin|nats-box" "$1"' _ "$f"
done

# Groom procedure for one-off tasks: linked from SKILL.md, names the issue
# format and the groomed label, and never adds rt:ready by default.
groom="$here/reference/groom.md"
check "groom procedure exists" [ -r "$groom" ]
check "SKILL.md links the groom procedure" grep -q 'reference/groom.md' "$skill"
check "SKILL.md has a one-off tasks section" grep -qx '## One-off tasks' "$skill"
check "one-off tasks heading appears once" bash -c '[ "$(grep -cx "## One-off tasks" "$1")" = 1 ]' _ "$skill"
check "groom names issue-format.md" grep -q 'issue-format.md' "$groom"
check "groom adds the groomed label" grep -q '`groomed`' "$groom"
check "groom adds rt:ready only when the task says so" \
  grep -q 'Add `rt:ready` only when' "$groom"
check "groom has the report fields" \
  bash -c 'grep -q "tracker rows already fixed:" "$1" && grep -q "needs the owner:" "$1"' _ "$groom"
for f in "$groom"; do
  check "no workstation paths in ${f#$here/}" bash -c '! grep -qE "(/home/|/Users/|~/)" "$1"' _ "$f"
  check "no cluster or person names in ${f#$here/}" bash -c '! grep -qiE "dapper|derek|merlin|nats-box" "$1"' _ "$f"
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
