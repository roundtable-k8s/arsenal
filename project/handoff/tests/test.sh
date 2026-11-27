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

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
