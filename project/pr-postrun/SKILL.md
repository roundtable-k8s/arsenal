---
name: pr-postrun
description: >
  Post-run GitHub steps of the chain-mode PR pipeline (spec.issuePickup.postRun: chain): verify PRs are merged or queued, close a split parent, hand a failed run back to a human. Use only from the PR pipeline steps that name these scripts; never in ad-hoc work.
---

# PR pipeline post-run (rt-verify, rt-close-parent, rt-handback)

These scripts do the GitHub work the operator otherwise does after a PR pipeline
run. **Use them only when a pipeline step tells you to**, with the exact
arguments the step gives. Do not reimplement them with `gh` commands, and do not
run them on your own initiative: they add `needs-human` and remove the
in-progress label.

All three: bash, `gh` and `jq`, token from `GH_TOKEN`. Options
`--in-progress-label` (default `rt:in-progress`) and `--needs-human-label`
(default `needs-human`). Bad arguments exit 2 with a usage line. The **last
output line** is the result; the chain checks it for `<script>: ok`. Re-running
after a partial failure is safe: no duplicate comments, in-progress removed last.

```bash
S=/skills/project/pr-postrun/scripts

# Verify each PR is merged, or approve and queue it (uses project/pr-review rt-review).
bash $S/rt-verify <repo> <issue> <ship_it|needs_changes> <review-file> <pr-url>...
#   ok:       rt-verify: ok <url> merged|queued ...        (exit 0)
#   problems: rt-verify: needs-human <summary>             (exit 1; issue handed back)

# Split parent: wait for sub-issues, then close the parent or hand it back.
bash $S/rt-close-parent <repo> <parent> <sub-issue>... [--wait-minutes N]
#   rt-close-parent: ok closed|handed-back|left-alone ...

# Failed run: hand the issue back with the summary as a comment.
bash $S/rt-handback <repo> <issue> <summary-file>
#   rt-handback: ok labelled|left-alone <repo>#<issue>
```

If the last line is not `<script>: ok ...`, report it verbatim; the step fails.

Tests: `bash project/pr-postrun/tests/test.sh` (uses a `gh` stub).
