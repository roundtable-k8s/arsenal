#!/usr/bin/env bash
# Tests for fleet-summary/scripts/summarise: fixtures with known counts, sums and
# timestamps, empty inputs, the --since boundary, absent costs, odd characters in
# error text, and bad arguments. Temp dirs only, no network.
#   bash shared/fleet-summary/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/summarise"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { # name, condition-exit
    n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc

cat > "$work/t.json" <<'JSON'
{"tasks":[
 {"taskId":"t1","knight":"galahad","status":"completed","cost":0.25,"durationMs":1200,"createdAt":"2026-11-26T08:00:00Z"},
 {"taskId":"t2","knight":"galahad","status":"completed","cost":0.5,"durationMs":5000,"createdAt":"2026-11-26T09:00:00Z"},
 {"taskId":"t3","knight":"lancelot","status":"failed","cost":0.1,"durationMs":9000,"createdAt":"2026-11-26T10:00:00Z"},
 {"taskId":"t4","knight":"lancelot","status":"running","durationMs":0,"createdAt":"2026-11-26T11:00:00Z"},
 {"taskId":"t5","knight":"galahad","status":"completed","cost":0.0,"durationMs":300,"createdAt":"2026-11-25T23:59:59Z"}
]}
JSON
cat > "$work/d.json" <<'JSON'
{"deadLetters":[
 {"taskId":"d1","knight":"galahad","state":"open","reason":"failed","error":"exit 1: boom\nstack trace line","deadLetteredAt":"2026-11-26T08:30:00Z"},
 {"taskId":"d2","knight":"lancelot","state":"open","reason":"lost","error":"","deadLetteredAt":"2026-11-25T12:00:00.123456789Z"},
 {"taskId":"d3","knight":"galahad","state":"resolved","reason":"failed","error":"old","deadLetteredAt":"2026-11-20T00:00:00Z"},
 {"taskId":"d4","knight":"bedivere","state":"open","reason":"failed","error":"quote \" and tab\tand 50% \\ slash","deadLetteredAt":"2026-11-26T09:00:00Z"}
]}
JSON
cat > "$work/k.json" <<'JSON'
{"knights":[{"name":"galahad","ready":true},{"name":"lancelot","ready":true},{"name":"bedivere","ready":false,"suspended":true},{"name":"percival","ready":false}]}
JSON
echo '{"tasks":[]}' > "$work/empty-t.json"
echo '{"deadLetters":[]}' > "$work/empty-d.json"
echo '{"tasks":[{"taskId":"x","knight":"k","status":"completed","durationMs":5,"createdAt":"2026-11-26T08:00:00Z"}]}' > "$work/nocost.json"
echo '{"tasks":[' > "$work/bad.json"
echo '{"deadLetters":"nope"}' > "$work/wrongshape.json"

# ---- full summary on the mixed fixture ----
expected='Fleet summary, all time
Tasks: 5
  by status: completed=3 failed=1 running=1
  by knight: galahad=3 lancelot=2
  total cost: $0.8500
  slowest:
    9000 ms  lancelot  failed  t3
    5000 ms  galahad  completed  t2
    1200 ms  galahad  completed  t1
    300 ms  galahad  completed  t5
    0 ms  lancelot  running  t4
Open dead letters: 3
  failed: 2
    galahad  d1  2026-11-26T08:30:00Z  exit 1: boom
    bedivere  d4  2026-11-26T09:00:00Z  quote " and tab	and 50% \ slash
  lost: 1
    lancelot  d2  2026-11-25T12:00:00.123456789Z  (no error text)
Knights not ready: bedivere, percival'
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --knights "$work/k.json"
[ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; check "mixed fixture: exact summary, exit 0" $?

# ---- --since: boundary is inclusive, both timestamp kinds filtered ----
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --since 2026-11-26T09:00:00Z
expected_since='Fleet summary since 2026-11-26T09:00:00Z
Tasks: 3
  by status: completed=1 failed=1 running=1
  by knight: lancelot=2 galahad=1
  total cost: $0.6000
  slowest:
    9000 ms  lancelot  failed  t3
    5000 ms  galahad  completed  t2
    0 ms  lancelot  running  t4
Open dead letters: 1
  failed: 1
    bedivere  d4  2026-11-26T09:00:00Z  quote " and tab	and 50% \ slash'
[ "$rc" -eq 0 ] && [ "$out" = "$expected_since" ]; check "--since 09:00:00Z includes the exact boundary, drops earlier tasks and dead letters" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --since 2026-11-26T09:00:00.5Z
[ "$rc" -eq 0 ] && grep -qx 'Tasks: 2' <<<"$out" && grep -qx 'No open dead letters' <<<"$out"; check "--since with fractional seconds is honoured (09:00:00 is before 09:00:00.5)" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --since 2026-11-27T00:00:00Z
[ "$(sed -n 2p <<<"$out")" = "No tasks" ] && [ "$(sed -n 3p <<<"$out")" = "No open dead letters" ]; check "--since after all data prints No tasks and No open dead letters" $?

# ---- empty inputs ----
run "$S" --tasks "$work/empty-t.json" --dead-letters "$work/empty-d.json"
[ "$rc" -eq 0 ] && [ "$out" = "Fleet summary, all time
No tasks
No open dead letters" ]; check "empty inputs print No tasks and No open dead letters" $?

# ---- absent costs and no knights file ----
run "$S" --tasks "$work/nocost.json" --dead-letters "$work/empty-d.json"
echo "$out" | grep -qx '  total cost: \$0.0000'; check "tasks without cost print total cost \$0.0000" $?
! grep -q '^Knights' <<<"$out"; check "no Knights line without --knights" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --knights "$work/k.json" --since 2026-11-26T00:00:00Z
echo "$out" | grep -qx 'Knights not ready: bedivere, percival'; check "knights not ready listed with --since too" $?
run "$S" --tasks "$work/nocost.json" --dead-letters "$work/empty-d.json" --knights "$work/k.json"
echo "$out" | grep -qx 'Knights not ready: bedivere, percival'; check "knights not ready listed" $?
echo '{"knights":[{"name":"a","ready":true}]}' > "$work/allready.json"
run "$S" --tasks "$work/empty-t.json" --dead-letters "$work/empty-d.json" --knights "$work/allready.json"
echo "$out" | grep -qx 'Knights not ready: none'; check "all ready prints Knights not ready: none" $?

# ---- bad arguments and bad input exit 2 ----
run "$S" --dead-letters "$work/d.json"; [ $rc -eq 2 ]; check "missing --tasks exits 2" $?
run "$S" --tasks "$work/t.json"; [ $rc -eq 2 ]; check "missing --dead-letters exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --bogus; [ $rc -eq 2 ]; check "unknown option exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --since 2026-11-26; [ $rc -eq 2 ]; check "date-only --since exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --since "yesterday"; [ $rc -eq 2 ]; check "non-ISO --since exits 2" $?
run "$S" --tasks "$work/missing.json" --dead-letters "$work/d.json"; [ $rc -eq 2 ]; check "missing tasks file exits 2" $?
run "$S" --tasks "$work/bad.json" --dead-letters "$work/d.json"; [ $rc -eq 2 ]; check "malformed tasks JSON exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/wrongshape.json"; [ $rc -eq 2 ]; check "dead letters without a deadLetters array exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --knights "$work/bad.json"; [ $rc -eq 2 ]; check "malformed knights JSON exits 2" $?
run "$S" --tasks "$work/t.json" --dead-letters "$work/d.json" --knights "$work/k.json" --tasks; [ $rc -eq 2 ]; check "--tasks without a value exits 2" $?

echo "# $((n - fails))/$n passed"
[ "$fails" -eq 0 ]
