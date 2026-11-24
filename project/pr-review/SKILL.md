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
- It posts as a comment review (the knights' bot account can't approve its own
  PRs) and checks the review actually landed, without posting duplicates.
- It returns as soon as the PR is queued. Don't wait for CI or the merge queue
  afterwards: your task is done.
- Its last output line (`rt-review: posted 'Verdict: ...' on <url>; queued: ...`)
  is what to report in your final message.
