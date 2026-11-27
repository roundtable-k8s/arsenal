---
name: job-run
description: >
  Ledger and output checks for scheduled jobs. Use from a scheduled job's script, after the knight's answer is written, to append a run to a per-job ledger (ledger append), read the last run (ledger last), and verify the expected output file exists, is not empty and is fresh (verify-output). Not for chain or PR steps; use pr-postrun there.
compatibility: >
  Needs bash, jq, and coreutils (stat, mktemp, date). All ship in the knight image; no extra tools.
---

# job-run

Two small bash tools for scheduled-job scripts, so a job cannot report success
without its output. Scripts live at `S=/skills/shared/job-run/scripts`.

## When to use

Call them from the script that runs after a scheduled knight task finishes.
Use them only when the job script (or the job's instructions) names them.

## verify-output: did the job produce its file?

```bash
S=/skills/shared/job-run/scripts
"$S/verify-output" /path/to/note.md --min-bytes 1 --newer-than-minutes 120
```

- Each path must be a regular file of at least `--min-bytes` (default 1) and, if
  `--newer-than-minutes` is given, modified within that many minutes.
- Success: exit 0, last line `verify-output: ok N file(s)`.
- Failure: exit 1, problems on stderr, and the last stdout line is
  `Outcome: failed output missing or empty: <first problem>`, or
  `Outcome: failed output not usable: <first problem>` when the only problem is
  staleness (`--newer-than-minutes`).
- Exit 2 means bad arguments.

**If `verify-output` prints `Outcome: failed`, make that your final line.** Do not
add anything after it. The runtime then records the task as failed.

## ledger: what did each run do?

```bash
S=/skills/shared/job-run/scripts
"$S/ledger" append /path/to/job-ledger.json nightwatch done --items 3 --note "filed 3 notes"
"$S/ledger" append /path/to/job-ledger.json nightwatch failed --note "no output"
"$S/ledger" last /path/to/job-ledger.json nightwatch
```

- `append <ledger.json> <job> <status> [--items N] [--note TEXT] [--date YYYY-MM-DD]`
  adds `{"job","date","status","items","note"}` to a JSON array. The file is
  created if missing, `date` is today in UTC unless `--date` is given, and only the
  newest 200 entries are kept.
- The last line of `append` is `ledger: ok ...`.
- `last <ledger.json> [job]` prints the newest entry (optionally for one job) as JSON.
  Exit 1 when there is no matching entry.
- A ledger that is not a JSON array is never overwritten: exit 1, file untouched.
- `append` also creates a `<ledger>.lock` file next to the ledger to serialise
  concurrent appends. It is left in place on purpose and is safe to ignore or
  delete between runs; do not delete it while a job may be running.
- Writes go through a temp file and `mv`, so an interrupted run cannot leave a
  half-written ledger.

## Rules

- Use only the paths the job gives you. Do not write anywhere else.
- Do not reimplement these checks with ad-hoc `test`, `jq` or `cat` commands.
- Exit codes: 0 ok, 1 failure reported above, 2 bad arguments.
