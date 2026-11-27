#!/usr/bin/env bash
# Tests for the dead-letter-triage classify script. Temp dirs only, no network.
#   bash shared/dead-letter-triage/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/classify"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc
action_of() { jq -r --arg t "$1" 'select(.taskId == $t) | .action' <<<"$out"; }

# One fixture entry per class, plus the edge cases.
cat > "$work/fixture.json" <<'JSON'
[
  {"taskId":"t-retry-lost","knight":"galahad","table":"main","state":"open","reason":"lost","error":"","attempt":1,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-retry-timeout","knight":"galahad","table":"main","state":"open","reason":"timeout","error":"","attempt":2,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-retry-failed","knight":"lancelot","table":"main","state":"open","reason":"failed","error":"exit 1","attempt":1,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-chain","knight":"galahad","table":"main","state":"open","reason":"failed","error":"","attempt":1,"retryOf":null,"chainName":"nightwatch","stepName":"file-report"},
  {"taskId":"t-usage","knight":"lancelot","table":"main","state":"open","reason":"usage_limited","error":"","attempt":1,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-refused","knight":"lancelot","table":"main","state":"open","reason":"refused","error":"","attempt":1,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-attempt3","knight":"galahad","table":"main","state":"open","reason":"lost","error":"","attempt":3,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-retried","knight":"galahad","table":"main","state":"retried","reason":"lost","error":"","attempt":1,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-dismissed-chain","knight":"galahad","table":"main","state":"dismissed","reason":"timeout","error":"","attempt":1,"retryOf":null,"chainName":"nightwatch","stepName":"x"},
  {"taskId":"t-no-attempt","knight":"galahad","table":"main","state":"open","reason":"lost","error":"","attempt":null,"retryOf":null,"chainName":null,"stepName":null},
  {"taskId":"t-unknown-reason","knight":"galahad","table":"main","state":"open","reason":"weird","error":"","attempt":1,"retryOf":null,"chainName":null,"stepName":null}
]
JSON

# ---- usage ----
run "$C" --bogus; [ $rc -eq 2 ]; check "classify: unknown option exits 2" $?
run "$C" "$work/fixture.json" "$work/other.json"; [ $rc -eq 2 ]; check "classify: two files exit 2" $?
run "$C" "$work/missing.json"; [ $rc -eq 2 ]; check "classify: missing file exits 2" $?
run "$C" --help; [ $rc -eq 2 ]; check "classify: --help exits 2" $?

# ---- each fixture entry lands in its documented class ----
run "$C" "$work/fixture.json"; [ $rc -eq 0 ]; check "classify: fixture exits 0" $?
[ "$(wc -l <<<"$out")" = 11 ]; check "classify: one line per entry" $?
[ "$(action_of t-retry-lost)" = retry ]; check "classify: lost with attempt 1 is retry" $?
[ "$(action_of t-retry-timeout)" = retry ]; check "classify: timeout with attempt 2 is retry" $?
[ "$(action_of t-retry-failed)" = retry ]; check "classify: failed with attempt 1 is retry" $?
[ "$(action_of t-chain)" = rerun-chain ]; check "classify: chain-owned entry is rerun-chain" $?
jq -e 'select(.taskId == "t-chain") | .why | contains("nightwatch") and contains("file-report")' <<<"$out" >/dev/null
check "classify: rerun-chain why names the chain and step" $?
[ "$(action_of t-usage)" = skip-usage ]; check "classify: usage_limited is skip-usage" $?
[ "$(action_of t-refused)" = inspect ]; check "classify: refused is inspect" $?
[ "$(action_of t-attempt3)" = inspect ]; check "classify: attempt 3 is inspect, not retried again" $?
[ "$(action_of t-no-attempt)" = inspect ]; check "classify: missing attempt is inspect" $?
[ "$(action_of t-unknown-reason)" = inspect ]; check "classify: unknown reason is inspect" $?

# ---- non-open entries are never retry ----
jq -e -s '[.[] | select(.taskId == "t-retried" or .taskId == "t-dismissed-chain") | .action] | length == 2 and all(.[]; . != "retry")' <<<"$out" >/dev/null
check "classify: retried and dismissed entries are never retry" $?

# ---- summary ----
run "$C" --summary "$work/fixture.json"; [ $rc -eq 0 ]; check "classify: --summary exits 0" $?
[ "$out" = '{"retry":3,"rerun-chain":1,"skip-usage":1,"inspect":6}' ]; check "classify: --summary counts per action" $?
run "$C" "$work/fixture.json" --summary; [ $rc -eq 0 ] && [ "$out" = '{"retry":3,"rerun-chain":1,"skip-usage":1,"inspect":6}' ]
check "classify: --summary works after the file argument" $?

# ---- stdin, empty list and the wrapped form ----
run bash -c "cat '$work/fixture.json' | '$C' --summary"; [ $rc -eq 0 ] && [ "$out" = '{"retry":3,"rerun-chain":1,"skip-usage":1,"inspect":6}' ]
check "classify: reads stdin" $?
echo '[]' > "$work/empty.json"
run "$C" "$work/empty.json"; [ $rc -eq 0 ] && [ -z "$out" ]; check "classify: empty list prints nothing and exits 0" $?
run "$C" --summary "$work/empty.json"; [ $rc -eq 0 ] && [ "$out" = '{"retry":0,"rerun-chain":0,"skip-usage":0,"inspect":0}' ]
check "classify: empty list summary is all zeros" $?
printf '{"deadLetters":[{"taskId":"w","knight":"k","state":"open","reason":"lost","attempt":1}]}' > "$work/wrapped.json"
run "$C" "$work/wrapped.json"; [ $rc -eq 0 ] && [ "$(action_of w)" = retry ]; check "classify: accepts the deadLetters wrapper" $?

# ---- bad input exits 2 ----
printf '[{"taskId":' > "$work/malformed.json"
run "$C" "$work/malformed.json"; [ $rc -eq 2 ]; check "classify: malformed JSON exits 2" $?
printf '[{"knight":"k","state":"open","reason":"lost","attempt":1}]' > "$work/notask.json"
run "$C" "$work/notask.json"; [ $rc -eq 2 ]; check "classify: entry without taskId exits 2" $?
printf '[{"taskId":"x","knight":"k","reason":"lost","attempt":1}]' > "$work/nostate.json"
run "$C" "$work/nostate.json"; [ $rc -eq 2 ]; check "classify: entry without state exits 2" $?
printf '{"not":"a list"}' > "$work/object.json"
run "$C" "$work/object.json"; [ $rc -eq 2 ]; check "classify: object without deadLetters exits 2" $?
printf '"text"' > "$work/string.json"
run "$C" "$work/string.json"; [ $rc -eq 2 ]; check "classify: JSON string exits 2" $?

echo "$n checks, $fails failed"
[ $fails -eq 0 ]
