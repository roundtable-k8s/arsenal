---
name: side-by-side
description: Compare an old job's dated output with its new scheduled-knight output over the last N days, one line per day, so the owner can decide on a cutover. Use during the side-by-side week of a migrated job, or when asked whether the new run wrote the same days as the old one.
allowed-tools: Bash(bash:*) Read
metadata:
  author: roundtable
  version: "1.0"
---

# Side by Side

Compares two directories of dated output files (`<dir>/YYYY-MM-DD.md`, optionally a JSON ledger) day by day. It reports which days each side wrote, file sizes, the size ratio, Markdown heading counts and a verdict per day. It only reads: it never writes into either directory.

## When to Use

- During the side-by-side week of a job migrated from kagent to a scheduled knight (the old job keeps writing to `Agents/<Job>/`, the new one to a sibling folder such as `Agents/<Job>-rt/`)
- When the owner asks whether the new run produced the same days of output as the old one
- When a scheduled run must fail if a day is missing or empty on the new side

Judging which output is better is not this skill's job. The report only shows missing or empty days and sizes; a human decides.

## Quick Reference

```bash
S=/skills/shared/side-by-side/scripts
bash $S/compare-outputs <old-dir> <new-dir>                 # last 7 days, *.md
bash $S/compare-outputs <old-dir> <new-dir> --days 14       # longer window
bash $S/compare-outputs <old-dir> <new-dir> --pattern '*.json'
bash $S/compare-outputs <old-dir> <new-dir> --diff 2026-11-26   # unified diff of one day
```

Options: `--days N` (default 7), `--pattern GLOB` (default `*.md`, matched against the file name), `--today YYYY-MM-DD` (default: the current date; the window is the N dates ending here, newest first), `--diff DATE`.

## Reading the Report

One line per day, newest first:

```
2026-11-26 old=200 new=100 ratio=0.50 old_headings=3 new_headings=2 verdict=both
2026-11-25 old=100 new=missing ratio=- old_headings=1 new_headings=- verdict=only-old
2026-11-20 old=0 new=60 ratio=n/a old_headings=0 new_headings=0 verdict=both
compare-outputs: 1 day(s) both, 1 only-old, 0 only-new, 0 new-empty
```

- `old=` / `new=`: size in bytes, or `missing`
- `ratio=`: new size divided by old size (`-` when a side is missing, `n/a` when the old file is empty)
- `*_headings=`: number of lines starting with `#`
- `verdict=`:
  - `both`: both sides wrote the day
  - `only-old`: the old job wrote it, the new one did not
  - `only-new`: the new one wrote it, the old one did not
  - `new-empty`: the new file exists but is under 50 bytes
  - `neither`: no file on either side

## Exit Codes

- `0`: report produced, and no day is `only-old` or `new-empty`
- `1`: at least one day is `only-old` or `new-empty` (a scheduled run can fail on this)
- `2`: bad arguments, an unreadable directory, or `--diff` with no file for that date on either side

## Dependencies

- Coreutils, `grep`, `awk` (`date -d`, `stat -c`). No `jq` needed.
- Stands alone: it needs no other skill. Use it with the migrated job's own output check if it has one.

## Tips

- `--diff` shows at most 200 lines and says so when it truncates. A missing side is diffed as empty, so an old-only day shows every line as removed.
- Dates are taken from file name prefixes only. Undated files such as `notes.md` are ignored.
- A day with only one side is a finding to report, not an error to fix; do not write into either directory to make the report look complete.
