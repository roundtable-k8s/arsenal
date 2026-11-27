# Groom procedure (one-off task)

A task that says to groom repositories is a one-off run, not the 30-minute check
in `SKILL.md`. Run this procedure instead. It writes issues in the shape from
[`issue-format.md`](issue-format.md), and it finishes with one fixed report.

Inputs from the task: the repositories to groom, and the cap per repository
(default 8 issues).

## 1. Fan out

- One subagent per repository, started in parallel, when the runtime has
  subagents. Otherwise do the repositories one after another.
- Each subagent gets its repository, the cap, and this file. It does not get the
  other repositories.

## 2. Read before drafting (each subagent)

- List open issues: `gh issue list --repo <r> --state open --limit 1000`. A
  smaller limit cuts the list off on a large repository, so a duplicate could be
  filed; if the list reaches 1000, say so in the report.
- Search closed issues by keyword before writing anything, so that a fixed or
  rejected idea is not filed again:
  `gh issue list --repo <r> --state all --search "<keywords>"`.
- Read the repository's tracker issues (epics, task lists) and the newest
  comment on each.
- Verify every row you plan to use against the default branch:
  `gh api repos/<r>/contents/<path>` (or `--jq` on the content). A file,
  function or type that is not there is not a gap. A tracker row that is
  already done goes under "tracker rows already fixed", not into an issue.

## 3. Draft the issues

- One pull request per issue. Testable. No decision needed from a human.
- Use the sections and rules of `issue-format.md`. Name real file paths, types
  and functions that you checked in step 2.
- No work that needs a decision: list it under "needs the owner".
- No new credentials, and no change that alters a live default.
- Stop at the cap for the repository.

## 4. File the issues

- Write each body to a file under `$ORCHESTRATOR_STATE_DIR/groom/<repo>/` first,
  so the text can be reviewed and re-filed after a failure.
- File with the `gh` commands in `project/github-pm/SKILL.md`. Add the
  `groomed` label and a milestone from the open list. Add `rt:ready` only when
  the task says so. Never add `rt:in-progress`; the factory sets it.

## 5. Report

Each subagent returns to the orchestrator:

| # | Title | One-line reason |
|---|-------|-----------------|

Then two more lines:

- `tracker rows already fixed:` the rows that step 2 showed are done, or `none`.
- `needs the owner:` the questions that need a decision, or `none`.

The orchestrator joins the per-repository results into one report, in the
repository order of the task, and puts the total issues filed first.
