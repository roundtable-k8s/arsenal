---
name: handoff
description: Hand off a self-contained task to another knight at the same table - pick the right knight with find_knights (ready or live only), send a brief with Goal, Context, Inputs, Constraints, Output wanted and Done when, check it with check-brief, and verify the reply before using it. Use when the work belongs to another knight's domain or skill, or can run in parallel with your own.
compatibility: Needs bash, coreutils (wc, awk, sed, mktemp) and a knight with find_knights and nats_request. All ship in the knight image; no extra tools.
metadata:
  author: roundtable
  version: "1.0"
---

# handoff

A knight that receives a hand-off starts with none of your context. The brief is
the whole task, so it must carry the goal, the inputs, the limits and the test for
"done". This skill gives the steps and a checker that refuses an incomplete brief.

Scripts live at `S=/skills/project/handoff/scripts`.

## When to use

- The work is in another knight's domain or skill (security, operator, UI, ...).
- The work can run in parallel with yours and you need its result back.
- A chain step or a job names a knight to call. Use this skill for the brief.

Do not use it for work you can do in one step yourself, or for a chain step that
already has a fixed message format (see `chain-orchestration`).

## How to choose the knight

1. Call `find_knights` with `skill` (an exact skill id or tag) or `domain`.
   Use `query` only when neither fits.
2. Keep only knights whose status is `ready` or `live`. Skip `suspended`
   (it wakes late) and `not ready` (it will not answer).
3. Never keep a fixed roster. The table changes, so look the knight up each time.
4. If nothing usable is left, say so in your result. Do not hand the work to a
   knight outside its domain.

## The brief

Start from `/skills/project/handoff/assets/brief-template.md`. Fill in six
headings, in this order, each with real text:

| Heading | What goes in it |
|---|---|
| `## Goal` | One sentence: the outcome, stated so it can be checked. |
| `## Context` | Why the work exists and what you already tried or ruled out. |
| `## Inputs` | Paths, URLs, issue numbers, IDs, or the exact text to use, with where each lives. |
| `## Constraints` | Scope, files or tools to leave alone, time, and what must not be sent or published. |
| `## Output wanted` | The form of the reply and where any file or PR goes. |
| `## Done when` | The observable test that the task is finished. |

Write the brief as a file (for example `/data/scratch/brief-<slug>.md`) before you
send it, so it survives a retry.

## Check it before sending

```bash
S=/skills/project/handoff/scripts
"$S/check-brief" /data/scratch/brief-<slug>.md
```

- Exit 0 and last line `check-brief: ok`: send it.
- Exit 1 and last line `check-brief: incomplete`: stderr names what is missing
  (`missing heading: Done when`, `empty body: Goal`) or that it is too large
  (32 KiB limit). Fix the brief and run it again. Do not send an incomplete brief.
- Exit 2: the file could not be read.
- `check-brief -` or a pipe reads the brief from stdin.

## Send and read the reply

1. Send the brief with `nats_request` to the chosen knight, with
   `Do not delegate to other knights` in the task.
2. Verify the reply before you use it: check the artefacts it names exist
   (for example, the PR URL resolves, the file is there) and that `Done when`
   is met. Do not copy its claims into your result unchecked.
3. In your own result, say who did what: "rt-x wrote the PR; I checked CI is green."

## Tips and edge cases

- Put the brief in the message, not "see my earlier message". The receiver cannot see yours.
- A timeout is not a failure of the knight. Check whether its work landed before you resend.
- Keep the brief short. A large paste belongs in a file the receiver can read at `Inputs`.
- The checker tests shape, not quality. A brief that passes can still be vague.

## Dependencies

- `fleet-status` shows readiness and is the fallback when `find_knights` is unclear.
- `chain-orchestration` covers multi-step chains, where one knight's reply feeds the next.
