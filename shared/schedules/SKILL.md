---
name: schedules
description: Inspect and operate the gateway's schedules (cron Triggers) with the schedule MCP tools, and turn the list into a short health report. Use when asked which schedules are failing, suspended or not firing, to pause, resume or run a schedule now, or to read what a scheduled run produced.
allowed-tools: Bash(bash:*) Read
metadata:
  author: roundtable
  version: "1.0"
---

# Schedules

A schedule is a cron Trigger that starts a chain or a knight task. The gateway's MCP tools list, read, suspend, resume and run them. The report script only reads files: it calls no gateway and needs no credentials.

## When to Use

- "Which schedules are failing?" or "is the morning job still firing?"
- Pausing, resuming or firing one schedule
- Reading what a scheduled run produced

Creating, replacing and deleting schedules are not MCP tools; do not look for them. Scheduled-job output checks are `job-run`.

## Tools

| Tool | Use |
|------|-----|
| `list_schedules` | All schedules; optional `table` and `namespace`. |
| `get_schedule` | One schedule by `name`, with recent firings. |
| `suspend_schedule` | Stop a schedule firing. |
| `resume_schedule` | Undo `suspend_schedule`. |
| `run_schedule` | Fire once now. |
| `schedule_next_runs` | Next fire times, in UTC and in the time zone, of an existing schedule (`name`, optional `namespace`) or of a cron expression that does not exist yet (`cron`, optional `timeZone`, default UTC); give one of the two, not both. `count` defaults to 5, max 50. Cron ticks only: skip rules are not applied. Read-only. |
| `list_schedule_runs` | A schedule's runs, newest first; `limit` caps them. |
| `get_schedule_run` | The result of one run (`name` and `run`). |

The run tools (`list_schedule_runs`, `get_schedule_run`) may be missing on a gateway; say so rather than guess.

Fields to read on a schedule: `suspended`, `suspendedBy` (`spec`, `annotation` or both), `nextRunAt`, `lastRunAt`, `lastResult.outcome` and `lastResult.skipReason`, `concurrency.policy`, `target.summary`, and `managedBy` (`git` or `api`). On a run: `outcome`, `reason`, `durationSeconds`, `costUSD`, `resultAvailable`.

## Steps: health report

1. `D=$(mktemp -d)`.
2. Call `list_schedules` and save the reply as `$D/schedules.json`.
3. Optional: call `list_schedule_runs` for the schedule you are looking at and save it as `$D/runs.json`.
4. Run the script:

```bash
bash /skills/shared/schedules/scripts/report --schedules $D/schedules.json --runs $D/runs.json
```

5. Add a conclusion in your own words: what is failing, what is not firing, what needs a person. Do not copy the output unchanged.

The report prints counts (active, suspended, Git-managed), schedules whose last result is `failed`, `lost` or `skipped`, active schedules with no `nextRunAt`, and the last five runs with outcome, duration and cost (`-` when unknown). Run `get_schedule` on each flagged schedule before drawing conclusions. A run list is for one schedule, so `--runs` describes only that one.

## Suspend and resume

- `suspend_schedule` works on Git-managed schedules too: it only sets an annotation, never the spec. Git still shows it unsuspended.
- `resume_schedule` removes that annotation only. A schedule suspended in its spec (`suspendedBy` contains `spec`) stays suspended and the result's `message` says so. Tell the owner the change belongs in Git; do not work around it.
- Check `suspended` and `suspendedBy` in the reply and report the real state.

## Run now

`run_schedule` fires once, even while suspended and for Git-managed schedules. Its state is one of:

- `started`: a run exists; fetch it with `get_schedule_run` using the run name in the reply.
- `pending`: requested but the operator has not started it; check `list_schedule_runs` shortly. Do not call `run_schedule` again, that fires twice.
- `skipped`: nothing started (for example the concurrency policy forbids it). The call returns a tool error with the reason; report it.

## Reading a run

`get_schedule_run` returns the output of the chain, knight task or mission. A run that failed is a tool error carrying the failure text: quote it, do not retry. A run still going says so; check again later. Run `outcome` values: `succeeded`, `failed`, `partiallySucceeded`, `lost`, `skipped`, `pending`, `running`, `unknown`.

## Rules

- Do not suspend a schedule you did not investigate. Read `get_schedule` and a recent run first, and say why in your answer. Undo your own suspension when you are done unless told otherwise.
- Never edit the Trigger YAML or the Trigger resource; schedule definitions live in Git.
- Run now has a real effect (a task, cost). Use it only when asked or to confirm a fix.
- Exit codes of the script: 0 report printed, 2 bad arguments, unreadable file or bad JSON. On 2, fix the input; do not guess numbers.
- Do not count schedules yourself when the script has printed the counts.

## Dependencies

- `jq` and coreutils. Both ship in the knight image.
