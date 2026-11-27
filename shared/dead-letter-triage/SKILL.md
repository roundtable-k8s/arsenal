---
name: dead-letter-triage
description: >
  Sorts open dead letters into retry, rerun-chain, skip-usage and inspect, following the gateway's own retry rules, so a knight can clear a backlog safely. Use when a dead-letter backlog needs clearing or when asked which dead letters can be retried.
compatibility: >
  Needs bash and jq (both ship in the knight image). Uses the MCP tools list_dead_letters, get_dead_letter, retry_task and get_task (get_dead_letter is optional: skip it on an older gateway).
---

# dead-letter-triage

Classifies the open dead letters from `list_dead_letters` with the same rules the
gateway applies to `POST /v1/dead-letters/{taskId}/retry`, then retries only the
entries that are safe to retry. The script is at `S=/skills/shared/dead-letter-triage/scripts`.

## When to use

Use it when a backlog of dead letters must be cleared, or when asked which dead
letters can be retried. Do not use it to dismiss entries: there is no endpoint for that.

## Steps

1. Call `list_dead_letters` and save the JSON result to a file in your task directory,
   e.g. `triage/list.json`.
2. Summarise: `"$S/classify" triage/list.json --summary`
3. Classify: `"$S/classify" triage/list.json > triage/classes.jsonl`
   (one line per entry: `{taskId, knight, action, why}`, plus `traceId` and `chainName` when set).
4. Read the payload of the entries a person will look at. Call `get_dead_letter` with the
   `taskId` (and `table` when the entry has one) for every `inspect` entry, and for the
   first `retry` entry of each knight. From the response take the first line of `task.task`,
   cut it to 200 characters, and keep it as quoted text; take the `traceId` from the entry
   in the classify output. If `get_dead_letter` is missing (an older gateway) or fails, skip
   this step for that entry and say so in the report. This step only reads: it never retries.
5. Retry the `retry` group one entry at a time. For each line with `"action":"retry"`,
   call `retry_task` with that `taskId`, and `table` when the entry has one. Never pass `force`.
6. Follow each retry: the response gives the new task's `taskId`; call `get_task` on it
   and note its state. Do not retry the same entry twice in one run.
7. Report: the summary counts, each retried entry with its new `taskId` and state, the
   `rerun-chain` entries with their chain names, the `skip-usage` entries, and every
   `inspect` entry with its `why`, its `traceId` and the quoted payload line from step 4.

## The rules

- **retry**: the entry is `open`, not chain-owned (no `chainName`), and its reason is
  `lost`, `timeout` or `failed` with an `attempt` below 3. The gateway accepts these.
- **rerun-chain**: the entry belongs to a chain (`chainName` set). The gateway answers
  409 for these unless `force` is given, and the right action is to rerun the chain or let its
  `retryPolicy` handle it. Do not retry the entry.
- **skip-usage**: reason `usage_limited`. Wait for the plan window; retrying now only fails again.
- **inspect**: everything else. That covers entries that are not `open`, `refused`
  entries, entries with an unknown reason, and entries whose `attempt` is 3 or more: those
  have already failed three times and are not retried again. Entries without an `attempt`
  count are also inspected.
- If `retry_task` answers 409 or 422 for an entry, record the answer in the report and
  move on. 422 means the entry has no task payload to retry.

## Exit codes

`classify` exits 0 on success and 2 on bad arguments or input that is not a list of
dead-letter entries. With exit 2, stop and report the error; do not retry anything.
