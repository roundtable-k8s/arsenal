#!/usr/bin/env bash
# Tests for ledger-check. Temp dirs only, no network.
#   bash shared/open-items-ledger/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/ledger-check"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
T=2026-11-26

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }
run() { out="$("$@" 2>"$work/err")"; rc=$?; }
line() { grep "^$1 " <<<"$out"; }

# item <id> <severity> <first_seen> <last_verified> <verification-json> <notes>
item() {
  jq -n --arg id "$1" --arg sev "$2" --arg fs "$3" --arg lv "$4" --argjson v "$5" --arg notes "$6" \
    '{id:$id,claim:"c",severity:$sev,first_seen:(if $fs=="null" then null else $fs end),last_verified:$lv,verification:$v,status:"open",resolved_on:null,notes:$notes}'
}
mk() { jq -s '{domain:"t",knight:"k",meta:{},items:.}' > "$1"; }
V='{"command":"true","expect":"x"}'

f="$work/l.json"
{
  item day25 medium 2026-11-01 2026-11-26 "$V" ""
  item nofirst medium null 2026-11-26 "$V" ""
  item fresh high 2026-11-20 2026-11-26 "$V" ""
  item reverify high 2026-11-20 2026-11-22 "$V" ""
  item dwn high 2026-11-20 2026-11-18 null ""
  item dwnmed medium 2026-11-20 2026-11-18 null ""
  item low7 low 2026-11-20 2026-11-18 null ""
  item verified8 high 2026-11-20 2026-11-18 "$V" ""
  item d14 high 2026-11-12 2026-11-26 "$V" ""
  item d30 high 2026-10-20 2026-11-26 "$V" ""
  item cve-2026-1 low 2026-09-01 2026-10-01 null ""
  item pinned medium 2026-09-01 2026-10-01 null "tax, decay: false"
} | mk "$f"
cp "$f" "$work/orig.json"

run "$C"; [ $rc -eq 2 ]; check "no args exits 2" $?
run "$C" "$f" --bogus; [ $rc -eq 2 ]; check "unknown option exits 2" $?
run "$C" "$f" --today 2026-13-45; [ $rc -eq 2 ]; check "bad --today exits 2" $?

run "$C" "$f" --today $T; [ $rc -eq 0 ]; check "valid ledger exits 0" $?
[ "$(line day25)" = "day25 day=25 last_verified_age=0 action=resolve-14d" ]; check "Day-N is 25" $?
line nofirst | grep -q 'day=none .*action=keep'; check "null first_seen prints day=none" $?
line fresh | grep -q 'action=keep'; check "fresh item keeps" $?
line reverify | grep -q 'last_verified_age=4 action=reverify'; check "4-day-old verified item is reverify" $?
line dwn | grep -q 'last_verified_age=8 action=downgrade'; check "8 days, no command: downgrade" $?
line low7 | grep -q 'action=resolve-7d'; check "low severity 8 days: resolve-7d" $?
line verified8 | grep -q 'action=reverify'; check "8 days with command: reverify, no 7d decay" $?
line d14 | grep -q 'day=14 .*action=resolve-14d'; check "14 days: resolve-14d" $?
line d30 | grep -q 'day=37 .*action=resolve-30d'; check "37 days: resolve-30d" $?
line cve-2026-1 | grep -q 'action=keep'; check "cve- item immune" $?
line pinned | grep -q 'action=keep'; check "decay: false item immune" $?
cmp -s "$f" "$work/orig.json"; check "no --apply leaves file untouched" $?

# ---- invalid files ----
bad() { # name, jq filter applied to the ledger
  jq "$2" "$f" > "$work/bad.json"; run "$C" "$work/bad.json" --today $T
  [ $rc -eq 1 ] && [ -s "$work/err" ]; check "invalid: $1" $?
}
bad "duplicate id" '.items[1].id = .items[0].id'
bad "bad severity" '.items[0].severity = "urgent"'
bad "bad status" '.items[0].status = "closed"'
bad "bad first_seen" '.items[0].first_seen = "2026-11-1"'
bad "impossible date" '.items[0].last_verified = "2026-02-30"'
bad "null last_verified" '.items[0].last_verified = null'
bad "missing claim" 'del(.items[0].claim)'
bad "resolved without resolved_on" '.items[0].status = "resolved"'
bad "open with resolved_on" '.items[0].resolved_on = "2026-11-01"'
echo '[1]' > "$work/arr.json"; run "$C" "$work/arr.json"; [ $rc -eq 1 ]; check "invalid: not an object" $?
echo '{bad' > "$work/junk.json"; run "$C" "$work/junk.json"; [ $rc -eq 1 ]; check "invalid: not JSON" $?
run "$C" "$work/missing.json"; [ $rc -eq 1 ]; check "invalid: missing file" $?

# ---- apply ----
run "$C" "$f" --today $T --apply
[ $rc -eq 0 ] && [ "$(tail -n 1 <<<"$out")" = "ledger-check: applied 6 change(s)" ]; check "apply reports 6 changes" $?
r() { jq -r --arg id "$1" ".items[] | select(.id==\$id) | $2" "$f"; }
[ "$(r dwn .severity)" = medium ] && [ "$(r dwn .status)" = open ]; check "downgrade high->medium" $?
[ "$(r dwnmed .severity)" = low ]; check "downgrade medium->low" $?
[ "$(r low7 .status)" = resolved ] && [ "$(r low7 .resolved_on)" = $T ] && [ "$(r low7 .notes)" = "auto-resolved: low-severity item unverified for 7+ days" ]; check "low item resolved with skill notes" $?
[ "$(r d14 .notes)" = "auto-resolved: 14-day staleness threshold (last_verified 2026-11-26)" ]; check "14d notes text" $?
[ "$(r d30 .status)" = resolved ]; check "30d resolved" $?
[ "$(r cve-2026-1 .status)" = open ] && [ "$(r pinned .status)" = open ]; check "immune items untouched" $?
[ "$(r verified8 .severity)" = high ]; check "verified item not downgraded" $?
jq -e . "$f" >/dev/null; check "applied file is valid JSON" $?
ls "$work" | grep -q '^\.ledger-check' ; [ $? -ne 0 ]; check "no temp file left behind" $?
cp "$f" "$work/after1.json"
run "$C" "$f" --today $T --apply
[ "$(tail -n 1 <<<"$out")" = "ledger-check: applied 0 change(s)" ]; check "second apply reports 0 changes" $?
cmp -s "$f" "$work/after1.json"; check "second apply is byte-identical" $?
run "$C" "$f" --today $T; ! grep -q 'action=\(downgrade\|resolve\)' <<<"$out"; check "no decay actions pending after apply" $?
line dwn | grep -q 'action=reverify'; check "downgraded item re-run reports reverify, not keep" $?
[ "$(r day25 .status)" = resolved ] && [ "$(r fresh .status)" = open ]; check "decayed item resolved, fresh item stays open" $?

echo "1..$n"; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
