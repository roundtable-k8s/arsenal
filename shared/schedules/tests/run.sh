#!/usr/bin/env bash
# Tests for schedules/scripts/report: fixtures with known counts, empty inputs,
# the last-five-runs cut, and bad arguments. Temp dirs only, no network.
#   bash shared/schedules/tests/run.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/report"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }
run() { out="$("$@" 2>"$work/err")"; rc=$?; }
has() { grep -qF -- "$1" <<<"$out"; }

cat > "$work/s.json" <<'JSON'
{"schedules":[
 {"name":"morning","cron":"0 7 * * *","suspended":false,"managedBy":"git","nextRunAt":"2026-11-28T07:00:00Z","lastResult":{"time":"2026-11-27T07:00:00Z","outcome":"succeeded"}},
 {"name":"nightly","cron":"0 2 * * *","suspended":false,"managedBy":"git","nextRunAt":"2026-11-28T02:00:00Z","lastResult":{"time":"2026-11-27T02:00:00Z","outcome":"failed"}},
 {"name":"hourly","cron":"0 * * * *","suspended":false,"managedBy":"api","nextRunAt":"2026-11-27T11:00:00Z","lastResult":{"time":"2026-11-27T10:00:00Z","outcome":"skipped","skipReason":"concurrency forbids"}},
 {"name":"weekly","cron":"0 9 * * 1","suspended":true,"suspendedBy":"annotation","managedBy":"git","lastResult":{"time":"2026-11-23T09:00:00Z","outcome":"lost"}},
 {"name":"stuck","cron":"5 5 * * *","suspended":false,"managedBy":"api"}
]}
JSON
cat > "$work/r.json" <<'JSON'
{"runs":[
 {"run":"r7","time":"2026-11-27T07:00:00Z","outcome":"succeeded","durationSeconds":12.4,"costUSD":"0.0123"},
 {"run":"r6","time":"2026-11-26T07:00:00Z","outcome":"failed","durationSeconds":3,"costUSD":"0.0100"},
 {"run":"r5","time":"2026-11-25T07:00:00Z","outcome":"succeeded","durationSeconds":10},
 {"run":"r4","time":"2026-11-24T07:00:00Z","outcome":"skipped"},
 {"run":"r3","time":"2026-11-23T07:00:00Z","outcome":"lost","durationSeconds":60,"costUSD":"0.5"},
 {"run":"r2","time":"2026-11-22T07:00:00Z","outcome":"succeeded","durationSeconds":1,"costUSD":"0.1"}
]}
JSON
echo '{"schedules":[]}' > "$work/es.json"
echo '{"runs":[]}' > "$work/er.json"
echo '{"schedules":[' > "$work/bad.json"

run bash "$S" --schedules "$work/s.json"
check "exit 0" "$rc"
has "Schedules: 5"; check "total" $?
has "active: 4  suspended: 1  git-managed: 3"; check "counts" $?
has "Last result failed, lost or skipped: 3"; check "bad results counted" $?
has "  nightly  failed  2026-11-27T02:00:00Z"; check "failed listed" $?
has "  hourly  skipped  2026-11-27T10:00:00Z  (concurrency forbids)"; check "skip reason" $?
has "  weekly  lost"; check "lost listed" $?
! has "morning  succeeded"; check "succeeded not listed" $?
has "Active but no next run: 1"; check "no next run count" $?
has "  stuck  cron 5 5 * * *"; check "stuck listed" $?
! grep -q "weekly  cron" <<<"$out"; check "suspended not in no-next-run" $?
! has "runs"; check "no runs section without --runs" $?

run bash "$S" --schedules "$work/s.json" --runs "$work/r.json"
check "with runs exit 0" "$rc"
has "Last 5 runs:"; check "five runs" $?
has "  2026-11-27T07:00:00Z  succeeded  12s  \$0.0123  r7"; check "run line" $?
has "  2026-11-24T07:00:00Z  skipped  -  -  r4"; check "unknown duration and cost" $?
! has " r2"; check "sixth run cut" $?

run bash "$S" --schedules "$work/es.json" --runs "$work/er.json"
check "empty exit 0" "$rc"
has "Schedules: 0"; check "empty count" $?
has "active: 0  suspended: 0  git-managed: 0"; check "empty counts" $?
has "No schedules with a failed, lost or skipped last result"; check "empty none failed" $?
has "No active schedules without a next run"; check "empty none stuck" $?
has "No runs"; check "empty runs" $?

run bash "$S"; check "no args exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules; check "missing value exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules "$work/nope.json"; check "unreadable exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules "$work/bad.json"; check "bad JSON exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules "$work/r.json"; check "wrong shape exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules "$work/s.json" --runs "$work/bad.json"; check "bad runs exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --bogus; check "unknown option exit 2" "$([ "$rc" -eq 2 ]; echo $?)"

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
