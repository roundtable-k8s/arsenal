---
name: pr-review
description: >
  Post a pull request review with a verdict and queue the PR for merge. Use for every PR review on the roundtable-k8s repos instead of gh pr review / gh pr merge, so the verdict line is always in the exact form the merge-guard check accepts.
---

# PR review (rt-review)

Every review is posted with `rt-review`. Never post a review with `gh pr review`
or queue with `gh pr merge` yourself: the `merge-guard` required check only lets
a knight PR merge when the newest verdict reads `Verdict: ship it`, and
`rt-review` is what guarantees that line.

## Usage

```bash
# 1. Write the review (Markdown) to a file. No verdict line: rt-review adds it.
cat > /tmp/review-123.md <<'EOF'
Solves #120: ...
Tests: ...
Non-blocking: ...
EOF

# 2. Post it with exactly one of the two verdicts.
bash /skills/project/pr-review/scripts/rt-review https://github.com/roundtable-k8s/roundtable/pull/123 ship_it /tmp/review-123.md
bash /skills/project/pr-review/scripts/rt-review https://github.com/roundtable-k8s/roundtable/pull/123 needs_changes /tmp/review-123.md

# Approve but leave the merge to a human (deletes data, touches secrets/auth):
bash /skills/project/pr-review/scripts/rt-review --no-queue https://github.com/roundtable-k8s/roundtable/pull/123 ship_it /tmp/review-123.md
```

- The verdict is an argument: `ship_it` or `needs_changes`. Nothing else is accepted.
- `ship_it` queues the PR (`gh pr merge --auto`) unless it is a draft, has the
  `hold` label, or you pass `--no-queue`. `needs_changes` never queues.
- `ship_it --no-queue` adds the `hold` label before posting the review, so the
  orchestrator's `tend` won't queue a PR you deliberately left for a human, and
  merge-guard blocks the merge until a human removes `hold`. If the label can't
  be added, nothing is posted and the script exits 1. `needs_changes` never adds
  `hold`.
- It posts as a comment review (the knights' bot account can't approve its own
  PRs) and checks the review actually landed, without posting duplicates.
- It returns as soon as the PR is queued. Don't wait for CI or the merge queue
  afterwards: your task is done.
- Its last output line (`rt-review: posted 'Verdict: ...' on <url>; queued: ...`)
  is what to report in your final message.

## Reviewing

Run `rt-checks` first. It reads the PR's required CI checks in one command:

```bash
bash /skills/project/pr-review/scripts/rt-checks https://github.com/roundtable-k8s/roundtable/pull/123
```

It prints one line per required check (`pass|fail|pending|skipping`, name, link);
for a failed check it adds the failed step and the last 20 log lines (tokens
redacted, or `log unavailable`). The last line decides what to do:

- `rt-checks: pass`: do not re-run the repo's build or test suites. Cite the
  check names in the review and spend the effort on the diff against the issue
  and on whether the tests cover the change.
- `rt-checks: fail`: the verdict is `needs_changes`; quote the failed step in
  the review.
- `rt-checks: pending`: review the diff, say CI is still running, and do not
  wait (the rule not to wait for CI stays).
- `rt-checks: none`: no required checks; run the repo's own commands from its
  AGENTS.md.

Exit codes: 0 for the four results, 2 for bad arguments, 1 when GitHub cannot
be reached. `RT_CHECKS_LOG_TIMEOUT` (default 60 s) bounds each log read.

Tests: `bash project/pr-review/tests/test.sh` (rt-review) and
`bash project/pr-review/tests/rt-checks.test.sh` (rt-checks), both with a `gh` stub.
