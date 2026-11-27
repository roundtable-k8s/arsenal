#!/usr/bin/env bash
# Tests for workspace-snapshots/scripts/check: fresh, old, pending-only, empty,
# condition False, malformed and bad-argument cases. Temp dirs only, no network.
#   bash shared/workspace-snapshots/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }
run() { out="$("$@" 2>"$work/err")"; rc=$?; }
has() { grep -qF -- "$1" <<<"$out"; }

NOW=$(date -u -d '2026-11-27T12:00:00Z' +%s)

cat > "$work/fresh.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","lastSnapshotRequest":"1798372800000000000","snapshots":[
 {"name":"galahad-ws-1","createdAt":"2026-11-20T03:00:00Z","readyToUse":true},
 {"name":"galahad-ws-2","createdAt":"2026-11-27T11:30:00Z","readyToUse":true},
 {"name":"galahad-ws-3","createdAt":"2026-11-27T11:50:00Z","readyToUse":false}],
 "condition":{"status":"True","reason":"SnapshotsReady"}}
JSON
cat > "$work/old.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","snapshots":[
 {"name":"galahad-ws-1","createdAt":"2026-11-20T03:00:00Z","readyToUse":true}],
 "condition":{"status":"True","reason":"SnapshotsReady"}}
JSON
cat > "$work/pending.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","snapshots":[
 {"name":"galahad-ws-3","createdAt":"2026-11-27T11:59:00Z","readyToUse":false}]}
JSON
echo '{"knight":"galahad","namespace":"roundtable","snapshots":[]}' > "$work/empty.json"
cat > "$work/cond.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","snapshots":[
 {"name":"galahad-ws-2","createdAt":"2026-11-27T11:30:00Z","readyToUse":true}],
 "condition":{"status":"False","reason":"SnapshotFailed","message":"volumesnapshots: quota exceeded"}}
JSON
cat > "$work/frac.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","snapshots":[
 {"name":"galahad-ws-2","createdAt":"2026-11-27T11:30:00.123456789Z","readyToUse":true}]}
JSON
cat > "$work/two.json" <<'JSON'
{"knight":"galahad","namespace":"roundtable","snapshots":[
 {"name":"galahad-ws-2","createdAt":"2026-11-27T11:30:00Z","readyToUse":true},
 {"name":"galahad-ws-9","createdAt":"2026-11-27T11:45:00Z","readyToUse":true},
 {"name":"galahad-ws-5","createdAt":"2026-11-26T11:45:00Z","readyToUse":true}]}
JSON
echo '{"snapshots":[' > "$work/bad.json"
echo '{"snapshots":[{"name":"x","createdAt":"yesterday","readyToUse":true}]}' > "$work/baddate.json"
echo '[{"name":"x"}]' > "$work/wrong.json"
echo '{"snapshots":[{"name":"u","readyToUse":true},{"name":"d","createdAt":"2026-11-27T11:30:00Z","readyToUse":true}]}' > "$work/undated.json"

run bash "$S" --list "$work/undated.json" --max-age 3600 --now "$NOW"
has "1 ready but undated"; check "undated ready counted" $?
run bash "$S" --list "$work/fresh.json" --max-age 3600 --now "$NOW"
! has "undated"; check "no undated line when none" $?
check "fresh ready exits 0" "$rc"
has "Newest ready snapshot: galahad-ws-2  created 2026-11-27T11:30:00Z  age 1800s"; check "newest ready and age" $?
has "Fresh (ready and younger than 3600s): yes"; check "fresh yes" $?
has "Pending snapshots: 1"; check "pending counted" $?
has "  galahad-ws-3  created 2026-11-27T11:50:00Z"; check "pending listed" $?
has "Condition: True SnapshotsReady"; check "condition printed" $?

run bash "$S" --list "$work/old.json" --max-age 3600 --now "$NOW"
check "only old exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
has "Newest ready snapshot: galahad-ws-1"; check "old snapshot still named" $?
has "Fresh (ready and younger than 3600s): no"; check "old is not fresh" $?

run bash "$S" --list "$work/pending.json" --max-age 3600 --now "$NOW"
check "only pending exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
has "Newest ready snapshot: none"; check "no ready snapshot" $?
has "Pending snapshots: 1"; check "pending only" $?

run bash "$S" --list "$work/empty.json" --max-age 3600 --now "$NOW"
check "empty exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
has "Newest ready snapshot: none"; check "empty none" $?
has "Pending snapshots: 0"; check "empty pending 0" $?
has "Condition: none"; check "no condition" $?

run bash "$S" --list "$work/cond.json" --max-age 3600 --now "$NOW"
check "condition False with fresh snapshot exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
has "Condition: False SnapshotFailed: volumesnapshots: quota exceeded"; check "condition message" $?

run bash "$S" --list "$work/frac.json" --max-age 3600 --now "$NOW"
check "fractional seconds parsed exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
has "age 1800s"; check "fractional age" $?

run bash "$S" --list "$work/two.json" --max-age 3600 --now "$NOW"
has "Newest ready snapshot: galahad-ws-9"; check "newest by createdAt, not list order" $?

run bash "$S" --list "$work/fresh.json" --max-age 60 --now "$NOW"
check "younger than max-age only: 1800s is not under 60s" "$([ "$rc" -eq 1 ]; echo $?)"

run bash "$S" --list "$work/bad.json" --max-age 3600 --now "$NOW"
check "malformed JSON exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/wrong.json" --max-age 3600 --now "$NOW"
check "wrong shape exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/baddate.json" --max-age 3600 --now "$NOW"
check "unparsable createdAt exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/nope.json" --max-age 3600 --now "$NOW"
check "unreadable file exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --max-age 3600 --now "$NOW"
check "missing --list exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/fresh.json" --now "$NOW"
check "missing --max-age exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/fresh.json" --max-age soon --now "$NOW"
check "non-numeric max-age exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/fresh.json" --max-age 3600 --now later
check "non-numeric now exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
run bash "$S" --list "$work/fresh.json" --max-age 3600 --bogus
check "unknown option exits 2" "$([ "$rc" -eq 2 ]; echo $?)"

echo "$((n-fails))/$n passed"
[ "$fails" -eq 0 ]
