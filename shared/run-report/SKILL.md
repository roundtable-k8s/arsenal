---
name: run-report
description: >
  Summarise a finished or running chain run as a short markdown report, using only the run record the gateway returns. Use when a chain run has finished (or is still running) and you need its status, duration, step results, failed-step errors and final output in one readable note. Not for planning chains (use chain-orchestration) or for ledgers of scheduled jobs (use job-run).
compatibility: >
  Needs bash and jq. Both ship in the knight image; no extra tools, no network, no environment variables.
---

# run-report

Turn a chain run record into a markdown report. The script only reads the record;
it never calls the gateway. Script lives at `S=/skills/shared/run-report/scripts/render-run`.

## When to use

- A chain run you were asked about has finished and you must report how it went.
- A run is still running and you need a status snapshot.
- You need the failed-step errors of a run quoted exactly.

## Steps

1. Call the gateway's `get_run` MCP tool with `run` (the run name, required), `namespace`
   (optional, default namespace when omitted) and `waitSeconds` (optional, seconds to wait for
   an unfinished run before returning). A run that ended `Failed` comes back as a tool error
   that still carries the run record, so use the record from the error result too.
2. Save the JSON the tool returned to a file, for example `/data/scratch/run.json`.
3. Run `bash "$S" /data/scratch/run.json` (or pipe the JSON on stdin with `bash "$S"`).
4. Put the script's markdown in your answer, then add one sentence of your own conclusion.

## Output

The report has these parts, in order:

- Title with the chain and the run name, then Phase, Status (taken from the phase:
  `succeeded`, `failed`, `partially succeeded`, or `running`; a step error under a
  `Succeeded` phase is flagged as `partially succeeded`), Started, Finished and Duration. An unfinished run shows `still running`.
- A steps table (Step, Phase, Result `ok` or `failed`); `_No steps recorded._` when there are none.
- `## Errors` lists each failed step's error, only when a step failed (a multi-line error is
  indented under its item).
- `## Output` is the run's final output in a fence longer than any backtick run in it.
  Output over 2000 characters is cut and marked as truncated; so is output the gateway
  marked as truncated.

## Exit codes

- `0` report printed.
- `2` bad input: wrong arguments, an unreadable file, input that is not a JSON object, or a
  record with no `run` field. The reason is on stderr; fix the input and run again.

Do not paste the raw JSON into the report. Do not invent a cost figure: the run record has none.
