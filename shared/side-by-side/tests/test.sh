#!/usr/bin/env bash
# Tests for side-by-side/scripts/compare-outputs: builds throwaway old/new output
# directories with known sizes and headings, then checks the report, the diff mode,
# the month boundary, the pattern filter, read-only behaviour and bad arguments.
#   bash shared/side-by-side/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cmp="$here/../scripts/compare-outputs"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
old="$tmp/old"; new="$tmp/new"
mkdir -p "$old" "$new"

# mkf <file> <bytes> <heading-lines>: exact size, with N lines starting with "# "
mkf() {
    local f=$1 size=$2 h=$3 i cur
    : > "$f"
    for ((i = 0; i < h; i++)); do printf '# h\n' >> "$f"; done
    cur=$(stat -c %s "$f")
    head -c $((size - cur)) /dev/zero | tr '\0' 'x' >> "$f"
}

# Window 2026-11-20..2026-11-26 (7 days, today 2026-11-26)
mkf "$old/2026-11-26.md" 200 3;  mkf "$new/2026-11-26.md" 100 2   # both, 0.50
mkf "$old/2026-11-25.md" 100 1                                    # only-old
mkf "$new/2026-11-24.md" 300 4                                    # only-new
mkf "$old/2026-11-22.md" 80 2;   mkf "$new/2026-11-22.md" 31 1    # new-empty, 0.39
mkf "$old/2026-11-21.md" 60 0                                     # only-old
: > "$old/2026-11-20.md"; mkf "$new/2026-11-20.md" 60 0          # old 0 bytes -> n/a, both
mkf "$old/2026-11-19.md" 10 0; mkf "$new/2026-11-19.md" 10 0    # outside the window
mkf "$old/2026-11-26.json" 999 0                                  # ignored by default pattern
mkf "$old/notes.md" 70 1                                          # undated, ignored

snapshot() { find "$old" "$new" -printf '%p %s %T@\n' | sort; }

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

expected_report='2026-11-26 old=200 new=100 ratio=0.50 old_headings=3 new_headings=2 verdict=both
2026-11-25 old=100 new=missing ratio=- old_headings=1 new_headings=- verdict=only-old
2026-11-24 old=missing new=300 ratio=- old_headings=- new_headings=4 verdict=only-new
2026-11-23 old=missing new=missing ratio=- old_headings=- new_headings=- verdict=neither
2026-11-22 old=80 new=31 ratio=0.39 old_headings=2 new_headings=1 verdict=new-empty
2026-11-21 old=60 new=missing ratio=- old_headings=0 new_headings=- verdict=only-old
2026-11-20 old=0 new=60 ratio=n/a old_headings=0 new_headings=0 verdict=both
compare-outputs: 2 day(s) both, 2 only-old, 1 only-new, 1 new-empty'

out=$(bash "$cmp" "$old" "$new" --today 2026-11-26 --days 7); rc=$?
[ "$out" = "$expected_report" ]; check "7-day mixed fixture matches expected report" $?
check "exit 1 when a day is only-old or new-empty" $([ "$rc" -eq 1 ]; echo $?)

# Default window is 7 days; --days 1 reports only today
out=$(bash "$cmp" "$old" "$new" --today 2026-11-26 --days 1)
[ "$out" = "2026-11-26 old=200 new=100 ratio=0.50 old_headings=3 new_headings=2 verdict=both
compare-outputs: 1 day(s) both, 0 only-old, 0 only-new, 0 new-empty" ]; check "--days 1 reports one day, exit 0 path when no only-old/new-empty" $?
bash "$cmp" "$old" "$new" --today 2026-11-26 --days 1 >/dev/null; check "exit 0 when every day is both or neither" $?
out=$(bash "$cmp" "$old" "$new" --today 2026-11-26 --days 7 | cut -d' ' -f1 | head -n 7 | tr '\n' ' ')
[ "$out" = "2026-11-26 2026-11-25 2026-11-24 2026-11-23 2026-11-22 2026-11-21 2026-11-20 " ]; check "days listed newest first" $?

# Month boundary: today 2026-03-02, 4 days back crosses February (no leap-day error)
mkf "$old/2026-03-01.md" 60 1; mkf "$new/2026-02-28.md" 60 1; mkf "$old/2026-02-27.md" 60 0; mkf "$new/2026-02-27.md" 60 0
out=$(bash "$cmp" "$old" "$new" --today 2026-03-02 --days 4)
[ "$(echo "$out" | cut -d' ' -f1 | head -n 4 | tr '\n' ' ')" = "2026-03-02 2026-03-01 2026-02-28 2026-02-27 " ]; check "window crosses month boundary" $?
echo "$out" | grep -q '^2026-02-28 old=missing new=60 .* verdict=only-new$'; check "only-new across February boundary" $?
rm -f "$old/2026-03-01.md" "$new/2026-02-28.md" "$old/2026-02-27.md" "$new/2026-02-27.md"

# --pattern selects the JSON ledger instead of Markdown
out=$(bash "$cmp" "$old" "$new" --today 2026-11-26 --days 1 --pattern '*.json')
[ "$out" = "2026-11-26 old=999 new=missing ratio=- old_headings=0 new_headings=- verdict=only-old
compare-outputs: 0 day(s) both, 1 only-old, 0 only-new, 0 new-empty" ]; check "--pattern selects JSON files" $?
bash "$cmp" "$old" "$new" --today 2026-11-26 --days 1 --pattern '*.json' >/dev/null; [ $? -eq 1 ]; check "only-old via --pattern exits 1" $?

# --diff: both sides, old-only (missing side is empty), truncation at 200 lines
bash "$cmp" "$old" "$new" --diff 2026-11-26 > "$tmp/d1"; rc=$?
grep -q '^-# h$' "$tmp/d1" && grep -q '^+x' "$tmp/d1" && [ "$rc" -eq 0 ]; check "--diff shows both sides, exit 0" $?
bash "$cmp" "$old" "$new" --diff 2026-11-25 | grep -q '^-# h$'; check "--diff with missing new side diffs against empty" $?
for ((i = 1; i <= 300; i++)); do echo "line $i"; done > "$old/2026-11-17.md"
for ((i = 1; i <= 300; i++)); do echo "changed $i"; done > "$new/2026-11-17.md"
bash "$cmp" "$old" "$new" --diff 2026-11-17 > "$tmp/d2"
[ "$(wc -l < "$tmp/d2")" -eq 201 ] && tail -n 1 "$tmp/d2" | grep -q '^compare-outputs: diff truncated at 200 lines'; check "--diff truncated to 200 lines" $?
rm -f "$old/2026-11-17.md" "$new/2026-11-17.md"

# Read-only: directory contents, sizes and mtimes unchanged by the script's runs
chmod -R a-w "$old" "$new"
before=$(snapshot)
bash "$cmp" "$old" "$new" --today 2026-11-26 --days 7 >/dev/null 2>&1
bash "$cmp" "$old" "$new" --today 2026-11-26 --days 7 --pattern '*.json' >/dev/null 2>&1
bash "$cmp" "$old" "$new" --diff 2026-11-26 >/dev/null 2>&1
after=$(snapshot)
chmod -R u+w "$old" "$new"
[ "$before" = "$after" ]; check "script never writes into either directory" $?

# Bad arguments and unreadable directories exit 2
bash "$cmp" >/dev/null 2>&1; [ $? -eq 2 ]; check "no arguments exits 2" $?
bash "$cmp" "$old" >/dev/null 2>&1; [ $? -eq 2 ]; check "one directory exits 2" $?
bash "$cmp" "$old" "$new" --days 0 >/dev/null 2>&1; [ $? -eq 2 ]; check "--days 0 exits 2" $?
bash "$cmp" "$old" "$new" --days abc >/dev/null 2>&1; [ $? -eq 2 ]; check "--days non-numeric exits 2" $?
bash "$cmp" "$old" "$new" --today 2026-02-30 >/dev/null 2>&1; [ $? -eq 2 ]; check "impossible --today exits 2" $?
bash "$cmp" "$old" "$tmp/missing" >/dev/null 2>&1; [ $? -eq 2 ]; check "unreadable new directory exits 2" $?
bash "$cmp" "$tmp/missing" "$new" >/dev/null 2>&1; [ $? -eq 2 ]; check "unreadable old directory exits 2" $?
mkdir "$tmp/noexec"; chmod a-x "$tmp/noexec"
bash "$cmp" "$old" "$tmp/noexec" >/dev/null 2>&1; [ $? -eq 2 ]; check "dir without x exits 2 (new)" $?
bash "$cmp" "$tmp/noexec" "$new" >/dev/null 2>&1; [ $? -eq 2 ]; check "dir without x exits 2 (old)" $?
chmod u+x "$tmp/noexec"
bash "$cmp" "$old" "$new" --bogus >/dev/null 2>&1; [ $? -eq 2 ]; check "unknown option exits 2" $?
bash "$cmp" "$old" "$new" --diff 2026-01-01 >/dev/null 2>&1; [ $? -eq 2 ]; check "--diff with no file on either side exits 2" $?
bash "$cmp" "$old" "$new" --diff notadate >/dev/null 2>&1; [ $? -eq 2 ]; check "--diff with a bad date exits 2" $?

echo "# $((n - fails))/$n passed"
[ "$fails" -eq 0 ]
