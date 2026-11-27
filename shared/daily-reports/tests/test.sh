#!/usr/bin/env bash
# Tests for shared/daily-reports/scripts/validate-report. Temp dirs only, no network.
#   bash shared/daily-reports/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
V="$here/../scripts/validate-report"
schema="$here/../assets/contract.schema.json"
skill="$here/../SKILL.md"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc
last() { tail -n 1 <<<"$out"; }

# Fixture: the first json block of SKILL.md (the contract example).
good="$work/good.json"
awk '/^```json/{c++; if(c==1){p=1;next}} /^```/{p=0} p' "$skill" > "$good"
jq -e . "$good" >/dev/null; check "fixture: SKILL.md example extracted as JSON" $?

# expect_fail <name> <jq filter applied to the good report> <stderr substring>
expect_fail() {
  jq "$2" "$good" > "$work/bad.json"
  run "$V" "$work/bad.json"
  [ $rc -eq 1 ]; check "$1: exits 1" $?
  grep -qF -- "$3" "$work/err"; check "$1: stderr names '$3'" $?
  [[ "$(last)" == "Outcome: failed report invalid: "* ]]; check "$1: last stdout line is Outcome: failed" $?
}

# ---- valid ----
run "$V" "$good"; [ $rc -eq 0 ] && [ "$(last)" = "validate-report: ok" ]; check "SKILL.md example passes" $?
[ ! -s "$work/err" ]; check "valid report prints nothing on stderr" $?
run "$V" - < "$good"; [ $rc -eq 0 ] && [ "$(last)" = "validate-report: ok" ]; check "stdin works" $?
for pair in null:null false:boolean; do
  lit=${pair%%:*}; tn=${pair##*:}
  printf "%s" "$lit" > "$work/lit.json"; run "$V" "$work/lit.json"
  [ $rc -eq 1 ] && grep -q "top level is $tn, not an object" "$work/err" && ! grep -q "not valid JSON" "$work/err"; check "bare $lit is valid JSON but not an object" $?
done
for case in empty whitespace; do
  case $case in empty) printf '' ;; whitespace) printf ' \n\t\n' ;; esac > "$work/odd.json"
  run "$V" "$work/odd.json"
  [ $rc -eq 1 ] && grep -qF "not valid JSON" "$work/err" && [ "$(grep -c "not valid JSON" "$work/err")" -eq 1 ]; check "$case input fails as not valid JSON" $?
done
printf '{} {}' > "$work/multi.json"
run "$V" "$work/multi.json"
[ $rc -eq 1 ] && grep -qF '$: expected exactly one JSON document' "$work/err" && ! grep -q "not valid JSON" "$work/err"; check "multi-document input says exactly one JSON document expected" $?

# ---- one failing case per rule ----
for k in $(jq -r '.required[]' "$schema"); do
  expect_fail "missing $k" "del(.$k)" "$k: required key is missing"
done
for k in $(jq -r '.properties.sections.items.required[]' "$schema"); do
  expect_fail "missing sections[0].$k" "del(.sections[0].$k)" "sections[0].$k: required key is missing"
done
expect_fail "bad run_id" '.run_id="daily-2026-2-15"' 'run_id: "daily-2026-2-15"'
expect_fail "run_id with trailing text" '.run_id="daily-2026-02-15x"' 'run_id:'
expect_fail "bad report_type" '.report_type="weekly"' 'report_type: "weekly"'
expect_fail "bad timestamp" '.timestamp="yesterday"' 'timestamp: "yesterday"'
expect_fail "non-string summary" '.summary=3' 'summary: 3 is not a string'
expect_fail "empty sections" '.sections=[]' 'sections: must contain at least one'
expect_fail "unknown priority" '.sections += [.sections[0]] | .sections[1].priority="urgent"' 'sections[1].priority: "urgent" is not one of high|medium|low'
expect_fail "unknown confidence" '.sections[0].confidence="certain"' 'sections[0].confidence: "certain" is not one of high|medium|low'
expect_fail "non-string data source" '.sections[0].data_sources=["a",2]' 'sections[0].data_sources[1]: 2 is not a string'
expect_fail "six highlights" '.highlights=["a","b","c","d","e","f"]' 'highlights: 6 items, at most 5'
expect_fail "empty highlights" '.highlights=[]' 'highlights: must contain at least 1'
expect_fail "non-string highlight" '.highlights[0]=1' 'highlights[0]: 1 is not a string'
expect_fail "follow_up_needed not boolean" '.follow_up_needed="no"' 'follow_up_needed: "no" is not a boolean'
expect_fail "follow_up_questions not array" '.follow_up_questions="x"' 'follow_up_questions: "x" is not an array'

# all problems are collected, not just the first
jq '.run_id="x" | .sections[0].priority="urgent" | del(.knight)' "$good" > "$work/multi.json"
run "$V" "$work/multi.json"
[ "$(wc -l < "$work/err")" -eq 3 ]; check "collects every problem (3 lines on stderr)" $?
[[ "$(last)" == "Outcome: failed report invalid: knight: required key is missing" ]]; check "Outcome names the first problem" $?

# ---- bad input ----
echo 'not json' > "$work/text.json"
run "$V" "$work/text.json"; [ $rc -eq 1 ] && [[ "$(last)" == "Outcome: failed "* ]]; check "non-JSON input exits 1" $?
echo '[]' > "$work/array.json"
run "$V" "$work/array.json"; [ $rc -eq 1 ] && grep -q 'not an object' "$work/err"; check "JSON array exits 1" $?
run "$V" "$work/missing.json"; [ $rc -eq 2 ]; check "missing file exits 2" $?
run "$V"; [ $rc -eq 2 ]; check "no arguments exits 2" $?
run "$V" a b; [ $rc -eq 2 ]; check "two arguments exits 2" $?

# ---- script stays in step with the schema ----
# A report generated from the schema's own required lists passes.
jq -n --slurpfile s "$schema" '
  ($s[0]) as $s
  | ($s.required | map({key: ., value: null}) | from_entries)
  | .knight="k" | .run_id="daily-2026-01-01" | .report_type=$s.properties.report_type.enum[0]
  | .timestamp="2026-01-01T00:00:00Z" | .summary="s" | .follow_up_needed=false | .follow_up_questions=[]
  | .highlights=[range(0; $s.properties.highlights.maxItems) | "h"]
  | .sections=[($s.properties.sections.items.required | map({key: ., value: "x"}) | from_entries)
      | .priority=$s.properties.sections.items.properties.priority.enum[0]
      | .confidence=$s.properties.sections.items.properties.confidence.enum[0]
      | .data_sources=[]]' > "$work/gen.json"
run "$V" "$work/gen.json"; [ $rc -eq 0 ]; check "report generated from the schema passes" $?
jq '.highlights += ["one more"]' "$work/gen.json" > "$work/gen6.json"
run "$V" "$work/gen6.json"; [ $rc -eq 1 ]; check "schema maxItems + 1 highlights fails" $?

# The script's rules reference the same values as the schema.
for k in $(jq -r '.required[], .properties.sections.items.required[]' "$schema"); do
  grep -q "\"$k\"" "$V"; check "script lists required key $k" $?
done
for path in '.properties.sections.items.properties.priority.enum' '.properties.sections.items.properties.confidence.enum'; do
  want="$(jq -c "$path" "$schema")"
  grep -qF "$want" "$V"; check "script has enum $want from schema $path" $?
done
want="$(jq -r '.properties.report_type.enum[0]' "$schema")"
grep -qF "\"$want\"" "$V"; check "script has report_type $want" $?
want="$(jq -r '.properties.run_id.pattern' "$schema")"
[ "$want" = '^daily-\d{4}-\d{2}-\d{2}$' ]; check "schema run_id pattern unchanged (script uses [0-9] form)" $?
max="$(jq -r '.properties.highlights.maxItems' "$schema")"
grep -qE "^ +\| $max as \\\$maxhl" "$V"; check "script has highlights maxItems $max" $?

echo "# $n tests, $fails failed"
[ "$fails" -eq 0 ]
