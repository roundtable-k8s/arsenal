#!/usr/bin/env bash
# Tests for the job-run scripts (ledger, verify-output). Temp dirs only, no network.
#   bash shared/job-run/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/../scripts"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
L="$scripts/ledger"; V="$scripts/verify-output"

fails=0; n=0
check() { # name, condition-exit
  n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi
}
run() { out="$("$@" 2>"$work/err")"; rc=$?; }   # stdout in $out, stderr in $work/err, status in $rc
last() { tail -n 1 <<<"$out"; }
nentries() { jq 'length' "$1"; }

# ---- ledger: usage ----
run "$L"; [ $rc -eq 2 ]; check "ledger: no args exits 2" $?
run "$L" append "$work/x.json" job; [ $rc -eq 2 ]; check "ledger: append without status exits 2" $?
run "$L" append "$work/x.json" job ok --items x; [ $rc -eq 2 ]; check "ledger: non-numeric --items exits 2" $?
run "$L" append "$work/x.json" job ok --bogus; [ $rc -eq 2 ]; check "ledger: unknown option exits 2" $?
run "$L" append "$work/x.json" job ok --date 2026-1-1; [ $rc -eq 2 ]; check "ledger: bad --date exits 2" $?
run "$L" last; [ $rc -eq 2 ]; check "ledger: last without file exits 2" $?

# ---- ledger: append creates, appends, fills fields ----
f="$work/ledger.json"
run "$L" append "$f" nightwatch done --items 3 --note "two notes" --date 2026-11-26
[ $rc -eq 0 ] && [ "$(last)" = "ledger: ok $f nightwatch done 2026-11-26" ]; check "ledger: append creates file, last line ok" $?
[ "$(nentries "$f")" = 1 ]; check "ledger: first append writes one entry" $?
jq -e '.[0] == {job:"nightwatch",date:"2026-11-26",status:"done",items:3,note:"two notes"}' "$f" >/dev/null; check "ledger: entry has the documented fields" $?

run "$L" append "$f" nightwatch failed --date 2026-11-27; [ $rc -eq 0 ]; check "ledger: second append succeeds" $?
jq -e '.[1].items == null and .[1].note == "" and .[1].status == "failed"' "$f" >/dev/null; check "ledger: items null and note empty when not given" $?
[ "$(nentries "$f")" = 2 ]; check "ledger: append adds to the end" $?

run "$L" append "$f" other done
jq -e '.[2].date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' "$f" >/dev/null; check "ledger: default date is YYYY-MM-DD" $?

# ---- ledger: trim to newest 200 ----
g="$work/trim.json"
jq -n '[range(1; 206) | {job: "job-\(.)", date: "2026-01-01", status: "done", items: null, note: ""}]' > "$g"
run "$L" append "$g" job-206 done --date 2026-01-02; [ $rc -eq 0 ]; check "ledger: append to a 205-entry ledger succeeds" $?
[ "$(nentries "$g")" = 200 ]; check "ledger: keeps the newest 200 entries" $?
jq -e '.[0].job == "job-7" and .[-1].job == "job-206"' "$g" >/dev/null; check "ledger: trimming drops the oldest first" $?

# ---- ledger: concurrent appends keep valid JSON ----
c="$work/conc.json"
"$L" append "$c" a done --date 2026-01-01 >/dev/null &
"$L" append "$c" b done --date 2026-01-01 >/dev/null &
wait
jq -e 'type == "array"' "$c" >/dev/null; check "ledger: two concurrent appends leave valid JSON" $?

# ---- ledger: stray temp file from an interrupted write is ignored ----
s="$work/stray.json"
run "$L" append "$s" job done --date 2026-01-01
printf 'garbage{' > "$s.tmp.AAAAAA"
run "$L" append "$s" job done --date 2026-01-02
jq -e 'length == 2' "$s" >/dev/null; check "ledger: stray temp file does not corrupt the ledger" $?
rm -f "$s.tmp.AAAAAA"

# ---- ledger: corrupt ledger is left untouched ----
bad="$work/bad.json"; printf '{"not":"an array"' > "$bad"; cp "$bad" "$work/bad.orig"
run "$L" append "$bad" job done; [ $rc -eq 1 ]; check "ledger: corrupt ledger exits 1 on append" $?
cmp -s "$bad" "$work/bad.orig"; check "ledger: corrupt ledger is untouched after append" $?
run "$L" last "$bad"; [ $rc -eq 1 ]; check "ledger: corrupt ledger exits 1 on last" $?
printf '{"a":1}' > "$bad"; cp "$bad" "$work/bad.orig"
run "$L" append "$bad" job done; [ $rc -eq 1 ]; check "ledger: JSON object (not array) is rejected" $?
cmp -s "$bad" "$work/bad.orig"; check "ledger: JSON object is untouched" $?

# ---- ledger: last ----
run "$L" last "$f"; [ $rc -eq 0 ] && jq -e '.job == "other"' <<<"$out" >/dev/null; check "ledger: last without job returns newest entry" $?
run "$L" last "$f" nightwatch; [ $rc -eq 0 ] && jq -e '.status == "failed" and .date == "2026-11-27"' <<<"$out" >/dev/null; check "ledger: last filters by job" $?
run "$L" last "$f" missing-job; [ $rc -eq 1 ]; check "ledger: last with no match exits 1" $?
run "$L" last "$work/none.json"; [ $rc -eq 1 ]; check "ledger: last on missing file exits 1" $?

# ---- verify-output ----
mkdir -p "$work/out"
printf 'hello world\n' > "$work/out/a.md"; printf 'x%.0s' $(seq 1 50) > "$work/out/b.md"
: > "$work/out/empty.md"
printf 'old\n' > "$work/out/stale.md"; touch -d '3 hours ago' "$work/out/stale.md"

run "$V" "$work/out/a.md" "$work/out/b.md"; [ $rc -eq 0 ] && [ "$(last)" = "verify-output: ok 2 file(s)" ]; check "verify-output: good files are ok" $?
run "$V" "$work/out/b.md" --min-bytes 50; [ $rc -eq 0 ]; check "verify-output: --min-bytes accepts files at the minimum" $?
run "$V" "$work/out/a.md" --min-bytes 1000; [ $rc -eq 1 ]; check "verify-output: file under --min-bytes fails" $?
[[ "$(last)" == "Outcome: failed "* ]]; check "verify-output: failure last stdout line starts 'Outcome: failed '" $?
grep -q 'too small' "$work/err"; check "verify-output: too-small problem is listed on stderr" $?

run "$V" "$work/out/missing.md" "$work/out/a.md"; [ $rc -eq 1 ]; check "verify-output: missing file exits 1" $?
[[ "$(last)" == "Outcome: failed "* ]]; check "verify-output: missing file prints Outcome line last" $?
grep -q 'missing' "$work/err"; check "verify-output: missing problem on stderr" $?

run "$V" "$work/out/empty.md"; [ $rc -eq 1 ]; check "verify-output: empty file exits 1" $?
[[ "$(last)" == "Outcome: failed output missing or empty: empty "* ]]; check "verify-output: empty file reported as Outcome failure" $?

run "$V" "$work/out/a.md" "$work/out/stale.md" --newer-than-minutes 60; [ $rc -eq 1 ]; check "verify-output: stale file fails --newer-than-minutes" $?
[[ "$(last)" == "Outcome: failed "* ]]; check "verify-output: stale file prints Outcome line last" $?
run "$V" "$work/out/a.md" --newer-than-minutes 60; [ $rc -eq 0 ]; check "verify-output: fresh file passes --newer-than-minutes" $?

# ---- verify-output: bad arguments ----
run "$V"; [ $rc -eq 2 ]; check "verify-output: no paths exits 2" $?
run "$V" "$work/out/a.md" --min-bytes x; [ $rc -eq 2 ]; check "verify-output: non-numeric --min-bytes exits 2" $?
run "$V" "$work/out/a.md" --newer-than-minutes; [ $rc -eq 2 ]; check "verify-output: option without value exits 2" $?
run "$V" "$work/out/a.md" --bogus; [ $rc -eq 2 ]; check "verify-output: unknown option exits 2" $?

echo "# $n tests, $fails failed"
[ "$fails" -eq 0 ]
