#!/usr/bin/env bash
# Tests for check-brief. Temp files only, no network.
#   bash project/handoff/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-brief"
T="$here/../assets/brief-template.md"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
# report NAME STATUS: STATUS 0 = pass, anything else = fail
report() {
  n=$((n+1))
  if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc
last() { tail -n 1 <<<"$out"; }

# expect NAME WANT_RC NEEDLE: the last run must exit WANT_RC; NEEDLE (may be empty) must
# appear on stderr; for exit 1 the last stdout line must be "check-brief: incomplete".
expect() {
  local st=0
  [ "$rc" -eq "$2" ] || st=1
  if [ -n "$3" ] && ! grep -qF -- "$3" "$work/err"; then st=1; fi
  if [ "$2" -eq 1 ] && [ "$(last)" != "check-brief: incomplete" ]; then st=1; fi
  report "$1" "$st"
}

HEADINGS=("Goal" "Context" "Inputs" "Constraints" "Output wanted" "Done when")

# A complete brief with every body filled in.
complete() {
  for h in "${HEADINGS[@]}"; do
    printf '## %s\nText for %s.\n\n' "$h" "$h"
  done
}

# ---- complete brief ----
complete > "$work/full.md"
run "$C" "$work/full.md"
expect "complete brief exits 0" 0 ""
st=0; [ "$(last)" = "check-brief: ok" ] || st=1; report "complete brief: last line is check-brief: ok" "$st"
st=0; [ -s "$work/err" ] && st=1; report "complete brief: nothing on stderr" "$st"

# ---- each heading missing ----
for h in "${HEADINGS[@]}"; do
  complete | awk -v h="## $h" '$0 == h {skip=1; next} skip && /^## / {skip=0} !skip' > "$work/miss.md"
  run "$C" "$work/miss.md"
  expect "missing heading '$h' exits 1 and names it" 1 "missing heading: $h"
done

# ---- empty body under each heading ----
for h in "${HEADINGS[@]}"; do
  complete | awk -v h="## $h" '
    $0 == h {print; print ""; skip=1; next}
    skip && /^## / {skip=0}
    !skip' > "$work/empty.md"
  run "$C" "$work/empty.md"
  expect "empty body '$h' exits 1 and names it" 1 "empty body: $h"
done

# A body that is only whitespace also counts as empty.
complete | sed 's/^Text for Done when\.$/   /' > "$work/blank.md"
run "$C" "$work/blank.md"
expect "whitespace-only body counts as empty" 1 "empty body: Done when"

# ---- oversized ----
{ complete; head -c 40000 /dev/zero | tr '\0' 'x'; echo; } > "$work/big.md"
run "$C" "$work/big.md"
expect "brief over 32 KiB exits 1" 1 "too large"

# ---- stdin input ----
run bash -c "\"$C\" < \"$work/full.md\""
expect "stdin redirect: complete brief exits 0" 0 ""
run bash -c "cat \"$work/miss.md\" | \"$C\" -"
expect "stdin pipe with '-': incomplete brief exits 1" 1 "missing heading"
run bash -c "cat \"$work/full.md\" | \"$C\""
expect "stdin pipe with no argument: complete brief exits 0" 0 ""

# ---- usage and read errors ----
run "$C" "$work/nope.md"
expect "unreadable file exits 2" 2 "cannot read"
run "$C" "$work"
expect "directory argument exits 2" 2 "cannot read"

# ---- template: passes once the guidance lines are replaced ----
sed -E 's/^_.*_$/filled in/' "$T" > "$work/tpl.md"
run "$C" "$work/tpl.md"
expect "template passes once guidance lines are replaced" 0 ""

# ---- raw unfilled template: every heading has only guidance lines, so every body is empty ----
run "$C" "$T"
expect "raw template exits 1" 1 ""
for h in "${HEADINGS[@]}"; do
  grep -qF -- "empty body: $h" "$work/err"; st=$?
  report "raw template: '$h' reported as empty body" "$st"
done
st=0; grep -q "missing heading" "$work/err" && st=1; report "raw template: no heading reported missing" "$st"

# Append CR to every line (portable: BSD sed does not expand \r or \n in replacements).
crlf() { awk '{ printf "%s\r\n", $0 }'; }

# A body that is exactly a template guidance line (outside a fence) is blank; a guidance-looking line in a fence is text.
tpl_guide="_One sentence: the outcome you need, stated so that it can be checked._"
complete | awk -v g="$tpl_guide" '/^Text for Goal\.$/ {print g; next} {print}' > "$work/guide.md"
run "$C" "$work/guide.md"
expect "template guidance line as body is empty" 1 "empty body: Goal"
complete | awk '/^Text for Goal\.$/ {print "```"; print "_code_"; print "```"; next} {print}' > "$work/fenceguide.md"
run "$C" "$work/fenceguide.md"
expect "guidance-looking line inside a fence counts as text" 0 ""

# An underscore-wrapped answer that is not a template guidance line is real text.
complete | awk '/^Text for Goal\.$/ {print "_see attached_"; next} {print}' > "$work/underscore.md"
run "$C" "$work/underscore.md"
expect "real underscore-wrapped answer counts as filled" 0 ""

# Without the template, any underscore-wrapped line outside a fence is blank (old rule).
mkdir -p "$work/notpl/scripts"; cp "$C" "$work/notpl/scripts/check-brief"
run "$work/notpl/scripts/check-brief" "$work/guide.md"
expect "missing template: underscore-wrapped body is empty" 1 "empty body: Goal"

# ---- CRLF line endings ----
complete | crlf > "$work/crlf.md"
run "$C" "$work/crlf.md"
expect "CRLF copy of a valid brief exits 0" 0 ""
st=0; [ "$(last)" = "check-brief: ok" ] || st=1; report "CRLF brief: last line is check-brief: ok" "$st"

crlf < "$T" > "$work/crlf-tpl.md"
run "$C" "$work/crlf-tpl.md"
expect "CRLF raw template exits 1 with empty body" 1 "empty body: Done when"

# A CRLF body with only blank lines is still empty (a lone \r is not text).
complete | awk '/^Text for Context\.$/ {print ""; next} {print}' | crlf > "$work/crlf-empty.md"
run "$C" "$work/crlf-empty.md"
expect "CRLF blank body is empty" 1 "empty body: Context"

# ---- "## " inside a fenced code block is not a heading ----
{
  printf '## Goal\nText for Goal.\n\n## Context\n```\n## Done when\nnot a heading\n```\n\n'
  printf '## Inputs\nText.\n\n## Constraints\nText.\n\n## Output wanted\nText.\n\n'
} > "$work/fence.md"
run "$C" "$work/fence.md"
expect "## inside a backtick fence does not create the Done when heading" 1 "missing heading: Done when"

# Tilde fences work the same way, and fence text still counts as body text.
{
  printf '## Goal\n~~~\n## Done when\n~~~\n\n## Context\nText.\n\n## Inputs\nText.\n\n'
  printf '## Constraints\nText.\n\n## Output wanted\nText.\n\n## Done when\nText.\n'
} > "$work/tilde.md"
run "$C" "$work/tilde.md"
expect "## inside a tilde fence is not a heading; fence body counts as text" 0 ""

# A ``` fence is closed only by ```, so a ~~~ line does not end it and the ## after it is not a heading.
{
  printf '## Goal\n```\ntext\n~~~\n## Done when\nnot a heading\n```\n\n'
  printf '## Context\nText.\n\n## Inputs\nText.\n\n## Constraints\nText.\n\n## Output wanted\nText.\n'
} > "$work/mismatch.md"
run "$C" "$work/mismatch.md"
expect "~~~ does not close a backtick fence: ## after it is not a heading" 1 "missing heading: Done when"

# A longer fence is closed only by a marker at least as long: ``` does not close ````.
{
  printf '## Goal\n````\n```\n## Done when\n````\n\n'
  printf '## Context\nText.\n\n## Inputs\nText.\n\n## Constraints\nText.\n\n## Output wanted\nText.\n'
} > "$work/longfence.md"
run "$C" "$work/longfence.md"
expect "a 3-backtick line does not close a 4-backtick fence: ## inside it is not a heading" 1 "missing heading: Done when"

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
