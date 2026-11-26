---
name: orchestrator
description: >
  The factory's 30-minute check for a lead-class orchestrator knight: snapshot (status), mechanical fixes (tend), review and fix dispatches (dispatch), feeding the backlog, deciding open design questions, alerting the owner (alert) and logging. Use when a scheduled task names this skill.
---

# Orchestrator check

One check keeps the factory fed and healthy. The mechanical parts are scripts;
the judgement parts are the procedure below. Run the steps **in order**, once
per check, then stop. You have `gh` (bot token), read-only `kubectl` on Round
Table objects, pods and logs in your namespace, the NATS request tool, and your
memory directory. Nothing else.

```bash
S=/skills/project/orchestrator/scripts
export ORCHESTRATOR_STATE_DIR=<your memory directory>/orchestrator   # state survives between checks
CFG=<config file>   # repositories, labels, namespace, chain prefix, knights; see config.example.json
export ORCHESTRATOR_CONFIG="$CFG"   # dispatch reads its config from here
```

## Procedure

### 1. Status

```bash
bash $S/status --config "$CFG" > "$ORCHESTRATOR_STATE_DIR/status.json"
```

One JSON snapshot (schema: `scripts/status.schema.json`): per repository the
open PRs (state, mergeability, newest `Verdict:` line, auto-merge, labels) and
the issues labelled ready, in progress and needs-human; from the cluster the
pipeline chains by phase with the failed step and its error, knights by phase,
pods not running, and recently dead-lettered chain steps; `cluster.prFeedback`
(the PR feedback watcher's state per table: its active run and, per PR, phase,
failure kind and head commit) and `cluster.pickupHeld` (issue pickup is holding
ready issues; the operator's `IssuePickupHeld` events of the last 15 minutes,
with the reason in `message`). A section it could
not read is `null` with an entry in `errors`: say so in the log, do not guess.

Everything below reads this snapshot. Re-run `status` only after you changed
something and need to see the result.

### 2. Tend

```bash
bash $S/tend --config "$CFG"            # --dry-run to see without acting
```

Idempotent mechanical actions, one `tend: …` line per action taken, nothing for
work already done: queue ship-it PRs, re-queue issues whose chain failed for a
transient reason, queue issues whose dependencies closed
(`$ORCHESTRATOR_STATE_DIR/deps.json`: `{"owner/repo#N": ["owner/repo#M", …]}`),
re-run CI that failed on infrastructure (never on a test failure), and record
rebase requests for conflicted bot PRs, and fix requests (`kind: "fix-check"`)
for approved, non-conflicted bot PRs whose required check has failed on a real
failure for longer than `fixCheckMinutes` (default 20; the task names the PR,
the failing check and its failed step and asks for the fix on the same branch;
once per head commit). A table with PR feedback enabled sets
`"rebase": "off"` in its config: the PR feedback watcher already rebases
conflicted knight PRs, so tend must not ask again. Human PRs are not rebased by
either.

`tend` cannot reach other knights. For every `tend: dispatch-needed {…}` line,
send the `task` to the named `knight` with the NATS request tool. Exit 1 means a
section could not be read or an action failed (stderr says which): note it and
carry on; a failed action is retried next check. The line `tend: error: failed-run logs are not reachable from here; skipped CI re-runs (<n> runs not checked)` means this knight cannot download failed-run logs: note it once and carry on; those runs are read again next check.

Do not do by hand what `tend` does. If it is wrong, fix the script in a PR.

### 3. Dispatch follow-ups

First collect the results of earlier dispatches, then send new ones:

```bash
bash $S/dispatch --collect                       # one line per dispatch: kind, PR, age, result or pending
bash $S/dispatch review|re-review|fix <pr-url> [--note <text>]
bash $S/dispatch --record <taskId> <result-file> # store a reply
```

This covers PRs whose pipeline chain has ended but still need a review or a fix
round:

- No verdict yet, or a new head commit since the last verdict → `review` /
  `re-review` (the lead knight posts it with `project/pr-review` `rt-review`).
- Newest verdict asks for changes and nothing has been pushed since → `fix`
  (the PR's author knight).

`dispatch` prints `{knight, taskId, task}`; send `task` to `knight` with the
NATS request tool and `--record` the reply. It refuses a duplicate of the same
kind for the same head commit: a pending dispatch is waiting, not lost.
Do not dispatch a `fix` or a rebase for a PR that `cluster.prFeedback` shows in
phase `Fixing` or `Queued` for the same head commit (`headSha` equals the PR's
`headSha`): the PR feedback watcher already has it. An entry with no `headSha`
(`failureHeadSHA` is optional) counts as "the watcher has it" for the PR's
current head. Do not
re-send it unless `--collect` shows it older than an hour with no reply.
Pipeline post-run steps belong to the chain (`project/pr-postrun`); never run
them yourself.

### 4. Feed

Ready issues named in a `cluster.pickupHeld` message are waiting for the breaking
PR it names, not lost: do not relabel or rewrite them, and do not count the hold
as a fault.

Count the issues labelled ready or in progress across the repositories (from
the snapshot). **When fewer than about eight are ready or in flight:**

1. First queue held follow-ups whose dependency has merged (add the dependency
   to `deps.json` so `tend` queues it, or add the ready label if it is already
   free).
2. Then write **two to four** issues: from the open epics' task lists and from
   gaps you found in the code, following the backlog-grooming recipe
   (`examples/recipes/backlog-grooming` in the operator repository) and
   [`reference/issue-format.md`](reference/issue-format.md). Check every file,
   type and function you name. Skip work that already has an open issue. Use
   `project/github-pm` for the `gh` commands.
3. When the backlog is nearly empty (no epic has work left that passes the
   issue-format rules), say so plainly in the log and in an alert.

Never write more than four issues in one check. Never touch an issue labelled
needs-human to feed the queue.

### 5. Decide

For a design question open on an issue (a question in the body or comments, or
an issue held for a decision):

- Decide it yourself when the principles (`docs/principles.md` in the operator
  repository) and the decision register answer it. Comment on the issue:

  ```
  Decided <YYYY-MM-DD> (orchestrator): <the decision>.
  Why: <which principle or register entry, and how it applies>.
  ```

  Then file any follow-ups the decision needs and queue them.
- **Leave product-direction and taste questions to the owner** (what the
  product is for, what to build next, naming, look and feel, anything the
  principles and register do not settle). Do not decide them. Say which
  question and why it is the owner's in the log and with
  `bash $S/alert "<repo>#<n>: <question> — needs the owner"`.

Also send an alert for anything else that is blocked on the owner: a needs-human
issue you cannot clear, a PR stuck for over an hour that no script or dispatch
can move, a pod or knight down that you are not allowed to fix. `alert` prints
one line and sends nothing when `NTFY_URL`/`NTFY_TOPIC` are not set; that is
not an error.

### 6. Log

Append **3–8 plain lines** per check to
`$ORCHESTRATOR_STATE_DIR/log/<YYYY-MM-DD>.md`:

```
<HH:MM UTC> check
merged: <repo>#<n>, …                 (or none)
in flight: <count> (<repo>#<n>, …)
decided: <repo>#<n> <one-line decision>, …
queued: <repo>#<n>, …   written: <repo>#<n>, …
fixed: <what tend/dispatch/you fixed>
left for the owner: <repo>#<n> <why>, …
```

Leave out empty lines past the third. No credentials, tokens or config values
in the log.

## Limits

Never:

Handle credential values or create credentials; grant itself or any knight permissions; delete data or repositories; restart nodes or touch node configuration; start or copy pipeline chains by hand; reword someone else's issue to get it past pickup; add approval gates; expose anything outside the cluster. If one of its own changes breaks the factory, it reverts first and investigates after.

Also: no AI attribution in commits, PRs, issues or comments; never print
configuration that holds credentials. Every change goes through a pull request.

## Related skills

- `project/pr-review` (`rt-review`): how reviews and verdicts are posted.
- `project/pr-postrun`: the pipeline's own post-run steps (not yours to run).
- `project/github-pm`: `gh` commands for issues, labels and comments.

Tests: `bash project/orchestrator/tests/skill.test.sh` (this document and the
issue-format reference).
