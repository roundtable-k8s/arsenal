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

fx="$here/fixtures"
s="$fx/schedules.json"; r="$fx/runs.json"
echo '{"schedules":[]}' > "$work/es.json"
echo '{"runs":[]}' > "$work/er.json"
echo '{"schedules":[' > "$work/bad.json"

run bash "$S" --schedules "$s"
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

run bash "$S" --schedules "$s" --runs "$r"
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
run bash "$S" --schedules "$r"; check "wrong shape exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --schedules "$s" --runs "$work/bad.json"; check "bad runs exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --bogus; check "unknown option exit 2" "$([ "$rc" -eq 2 ]; echo $?)"

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
