#!/usr/bin/env bash
# Tests for scripts/render-template.py.
#   bash shared/report-generator/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
render="$here/../scripts/render-template.py"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

# run <template-text> <data-json> : renders via --data; sets out, err, rc
run() {
  printf '%s' "$1" > "$work/t.md"
  printf '%s' "$2" > "$work/d.json"
  out=$(python3 "$render" --template "$work/t.md" --data "$work/d.json" 2>"$work/err"); rc=$?
  err=$(cat "$work/err")
}

run '{{count}} {{ok}} {{a.b}}' '{"count":3,"ok":true,"a":{"b":1}}'
check "top-level int, bool and dotted path render" $([ "$out" = "3 true 1" ]; echo $?)
check "successful render exits 0 with no warnings" $([ "$rc" -eq 0 ] && [ -z "$err" ]; echo $?)

run '{{x}}|{{f}}|{{n}}' '{"x":false,"f":1.5,"n":null}'
check "false, float and null render" $([ "$out" = "false|1.5|" ]; echo $?)

run '{{#each items}}{{this.n}}:{{this.ok}};{{/each}}' '{"items":[{"n":1,"ok":true},{"n":2.5,"ok":false}]}'
check "each renders numeric and boolean item fields" $([ "$out" = "1:true;2.5:false;" ]; echo $?)

run '{{#each items}}{{this}}-{{/each}}' '{"items":["a",7,true]}'
check "each renders scalar items via {{this}}" $([ "$out" = "a-7-true-" ]; echo $?)

run '{{#each items}}[{{this.name}}]{{/each}}' '{"items":[{"name":"ok"}]}'
check "each renders with no unresolved placeholder" $([ "$out" = "[ok]" ] && [ -z "$err" ]; echo $?)

run '{{title}} {{nope}}' '{"title":"T"}'
check "unknown placeholder exits 0 and stays in output" $([ "$rc" -eq 0 ] && [ "$out" = "T {{nope}}" ]; echo $?)
check "unknown placeholder warns on stderr" $([ "$err" = "warning: unresolved placeholder {{nope}}" ]; echo $?)

run '{{#each items}}{{this.missing}}{{/each}}' '{"items":[{"n":1}]}'
check "missing this.key inside each warns" $([ "$err" = "warning: unresolved placeholder {{this.missing}}" ]; echo $?)

run '{{a.missing}} {{items}} {{this}}' '{"a":{"b":1},"items":[1]}'
check "missing dotted path, object and this outside each all warn" $([ "$(echo "$err" | wc -l)" -eq 3 ] && [[ "$err" == *"{{a.missing}}"* && "$err" == *"{{items}}"* && "$err" == *"{{this}}"* ]]; echo $?)

run '{{#each gone}}x{{/each}}' '{"items":[]}'
check "missing each list warns and renders nothing" $([ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$err" = "warning: unresolved placeholder {{#each gone}}" ]; echo $?)

run '{{#each a}}{{#each b}}x{{/each}}{{/each}}' '{"a":[{"b":[1]}]}'
check "nested each is reported, not silently left" $([[ "$err" == *"unresolved placeholder"* ]]; echo $?)

printf '%s' '{{n}}' > "$work/t.md"; printf '%s' '{"n":1,"extra":2}' > "$work/d.json"
python3 "$render" --template "$work/t.md" --data "$work/d.json" --strict >/dev/null 2>&1; rc=$?
check "strict with all placeholders resolved exits 0" $([ "$rc" -eq 0 ]; echo $?)

printf '%s' '{{nope}}' > "$work/t.md"
out=$(python3 "$render" --template "$work/t.md" --data "$work/d.json" --strict 2>"$work/err"); rc=$?
check "strict with unresolved placeholder exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "strict writes no output and names the count" $([ -z "$out" ] && [[ "$(cat "$work/err")" == *"Error: 1 unresolved placeholder(s) with --strict; nothing written"* ]]; echo $?)

printf '%s' '{{nope}}' > "$work/t.md"
python3 "$render" --template "$work/t.md" --data "$work/d.json" --output "$work/o.md" --strict >/dev/null 2>&1
check "strict does not create the output file" $([ ! -e "$work/o.md" ]; echo $?)

run '{{x}}' '[1,2]'
check "array data exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "array data is one Error line without traceback" $([ "$err" = "Error: data in $work/d.json must be a JSON object, got list" ] && [ "$(echo "$err" | wc -l)" -eq 1 ]; echo $?)

run '{{x}}' '{"x":'
check "invalid JSON exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "invalid JSON is one Error line without traceback" $([[ "$err" == "Error: invalid JSON in $work/d.json: "* && "$(echo "$err" | wc -l)" -eq 1 && "$err" != *Traceback* ]]; echo $?)

python3 "$render" --template "$work/t.md" --data "$work/missing.json" >/dev/null 2>"$work/err"; rc=$?
check "missing data file exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "missing data file is one Error line without traceback" $([ "$(cat "$work/err")" = "Error: cannot read $work/missing.json: No such file or directory" ]; echo $?)

printf '[1]' | python3 "$render" --template "$work/t.md" --data-stdin >/dev/null 2>"$work/err"; rc=$?
check "array on stdin exits 1 with Error line" $([ "$rc" -eq 1 ] && [[ "$(cat "$work/err")" == "Error: data in stdin must be a JSON object, got list" ]]; echo $?)

python3 "$render" --template "$work/nope.md" --data "$work/d.json" >/dev/null 2>"$work/err"; rc=$?
check "missing template keeps its Error line" $([ "$rc" -eq 1 ] && [[ "$(cat "$work/err")" == "Error: Template not found: "* ]]; echo $?)

check "render-template.py stays executable" $([ -x "$render" ]; echo $?)

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
