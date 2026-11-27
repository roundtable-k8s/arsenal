---
name: fleet-summary
description: Summarise what the fleet did recently, from the gateway's tasks and dead letters, as a plain summary a person can read in a minute. Use for a morning or end-of-day summary, or when asked "what did the fleet do", and the fleet-status skill (who is online) is not enough.
allowed-tools: Bash(bash:*) Read
metadata:
  author: roundtable
  version: "1.0"
---

# Fleet Summary

Turns the gateway's recent tasks, open dead letters and knight readiness into one short text summary. The script only reads files: it calls no gateway and needs no credentials. Get the data with the MCP tools, save it, then run the script.

## When to Use

- A morning or end-of-day summary of fleet activity
- "What did the fleet do since yesterday?" or a similar question about recent work
- Before deciding whether dead letters need triage

`fleet-status` answers who is online right now. Use this skill for what happened.

## Steps

1. Work in a scratch directory: `D=$(mktemp -d)`.
2. Call `list_tasks` with `limit: 100` and save the reply as `$D/tasks.json`.
3. Call `list_dead_letters` with `limit: 100` and save the reply as `$D/deadletters.json`.
4. Optional: call `list_knights` and save the reply as `$D/knights.json`.
5. Run the script:

```bash
S=/skills/shared/fleet-summary/scripts
bash $S/summarise --tasks $D/tasks.json --dead-letters $D/deadletters.json --knights $D/knights.json --since 2026-11-26T00:00:00Z
```

If you skipped step 4, drop `--knights $D/knights.json`:

```bash
bash $S/summarise --tasks $D/tasks.json --dead-letters $D/deadletters.json --since 2026-11-26T00:00:00Z
```

6. Add a conclusion in your own words under the script output: what went well, what failed, and what needs a person. Do not copy the output unchanged.

## Options

- `--tasks FILE` and `--dead-letters FILE`: required.
- `--knights FILE`: adds a "Knights not ready" line.
- `--since ISO8601`: UTC, such as `2026-11-26T00:00:00Z`. Keeps tasks by `createdAt` and dead letters by `deadLetteredAt`, at or after that time. Entries without the timestamp are left out.

## Reading the Output

- `Tasks:` with counts by status and by knight, `total cost` (`$0.0000` when no task has a cost) and the five slowest tasks.
- `Open dead letters:` only entries with state `open`, grouped by reason, each with knight, task ID, time and the first line of its error.
- `No tasks` and `No open dead letters` mean the inputs were empty or outside `--since`.

## Rules

- Use only the files you saved for this run. Do not retry dead letters or change anything in the gateway from this skill.
- Exit codes: 0 summary printed, 2 bad arguments, unreadable file, bad JSON or bad `--since`. On 2, fix the input and run again; do not guess the numbers.
- Do not compute counts yourself when the script has printed them.

## Dependencies

- `jq` and coreutils. Both ship in the knight image.
