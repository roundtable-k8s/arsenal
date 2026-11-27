---
name: runs
description: Read the gateway's chain and pickup runs with the list_runs and get_run tools, and turn the run list into a short "what are the pipelines doing" report. Use when asked what runs are active, which runs are stuck or long-running, which runs belong to an issue, or what one run did.
allowed-tools: Bash(bash:*) Read
metadata:
  author: roundtable
  version: "1.0"
---

# Runs

A run is one execution of a chain, a gateway task or a pickup (a knight working an issue). The gateway's MCP tools list runs and read one. The report script only reads files: it calls no gateway and needs no credentials.

These tools are only listed when the gateway has `gateway.runs.enabled`. If they are missing, say so rather than guess.

## When to Use

- "What is running right now?" or "which pipelines are stuck?"
- Which runs are working on a given issue
- Reading what one run did (use `run-report` to write it up once you have the record)

Cancelling and rerunning runs are not available here. Summarising a single finished chain run is `run-report`; scheduled-job output checks are `job-run`.

## Tools

| Tool | Use |
|------|-----|
| `list_runs` | Runs, newest first. Filters: `namespace`, `chain`, `phase`, `source` (`gateway`, `trigger`, `pickup` or `all`; defaults to `gateway`), `active` (true for runs still going), `issue` (`owner/repo#n`), `limit`. |
| `get_run` | One run by its id (`run` field), with its step results. |

A run record has `run`, `chain`, `phase`, `source`, `ageSeconds`, `runningSeconds` (only while active), `traceId` and, for pickup runs, `issue: {repo, number}`.

## Steps: run report

1. `D=$(mktemp -d)`.
2. Call `list_runs` with `source: all`; without it only gateway runs come back and the pickup and trigger runs are missing. Add `active: true` to see only runs still going. Save the reply as `$D/runs.json`.
3. Run the script:

```bash
bash /skills/shared/runs/scripts/report --runs $D/runs.json [--stuck-after 7200]
```

4. For each flagged run, call `get_run` (pass its `namespace` if it is not the default one; the report does not print it) before drawing conclusions. Do not infer a failure from age alone.
5. Add a conclusion in your own words: what is running, what is stuck, which issues are being worked. Do not copy the output unchanged.

The report prints counts by source and by phase, the active runs with their `runningSeconds`, the runs over the `--stuck-after` threshold (default 7200 seconds), and the pickup runs grouped by issue.

## Rules

- A list is a snapshot. Runs that finish while you read them may still show as active; check `phase` on `get_run` before saying one is stuck.
- Never print a trace id or run id as a credential or link to anything outside the gateway.
- Exit codes of the script: 0 report printed, 2 bad arguments, unreadable file or bad JSON. On 2, fix the input; do not guess numbers.
- Do not count runs yourself when the script has printed the counts.

## Dependencies

- `jq` and coreutils. Both ship in the knight image.
