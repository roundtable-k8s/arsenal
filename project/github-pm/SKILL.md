---
name: github-pm
description: >
  Manage Round Table GitHub project — create/update issues, track milestones, review PRs, and maintain the roadmap. Uses gh CLI.
---

# GitHub Project Management

You manage the issues, PRs and roadmap of the Round Table repositories using the `gh` CLI.

## Repositories

Always pass `--repo owner/name` explicitly; do not rely on the working directory.

- `roundtable-k8s/roundtable` — operator, CRDs, Helm chart, roadmap epics
- `roundtable-k8s/roundtable-ui` — dashboard (React + Go API)
- `roundtable-k8s/knights` — knight definitions
- `roundtable-k8s/arsenal` — knight skills (this repo)

## Milestones

Milestones are per repository and change over time, so do not hard-code them.
List the open ones before you set one:

```bash
gh api repos/roundtable-k8s/roundtable/milestones --paginate \
  --jq '.[] | select(.state=="open") | .title'
```

Use the exact title returned in `--milestone "<title>"`. Closed milestones are
not valid targets for new work.

## Labels

Check the live set with `gh label list --repo <owner/name>`. The labels this
skill uses, in `roundtable-k8s/roundtable`:

Topic labels (what the issue is about):
- `crd` — Custom Resource Definition work
- `operator` — operator controller changes
- `ui` — dashboard and visualization
- `chain` — multi-knight orchestration
- `knight` — individual knight configuration
- `infra` — infrastructure and deployment
- `epic` — large feature spanning multiple issues
- `observability` — traces, metrics, logs
- `runtime` — knight runtime backends and sandboxing
- `security` — security hardening
- `refactor` — code quality and architecture improvements

Factory labels (they drive the automation; see below):
- `rt:ready` — ready to be picked up: a knight builds the issue when it is queued
- `rt:in-progress` — a chain is working on the issue (set by the factory)
- `groomed` — rewritten to the loop-ready shape: goal, tasks, acceptance criteria
- `needs-human` — knights stop here; a human decides
- `hold` — do not merge: needs a human to sequence it
- `breaking` — breaking change (CRD field or API removal)
- `product-direction` — needs the owner to set product direction
- `parked` — idea kept for later; not on the roadmap

When you create an issue, write it in the format from
`project/orchestrator/reference/issue-format.md`, set a milestone from the open
list, and add `groomed`. Add `rt:ready` only when the task says so. Do not add
`rt:in-progress`; the factory sets it.

## Common Commands

```bash
# List open issues
gh issue list --repo roundtable-k8s/roundtable

# View issue details
gh issue view 8 --repo roundtable-k8s/roundtable

# Create issue (<milestone> from the open list above; <label> from the label list)
gh issue create --repo roundtable-k8s/roundtable --title "Title" --body "Description" --label <label> --milestone "<milestone>"

# Comment on issue
gh issue comment 8 --repo roundtable-k8s/roundtable --body "Update: ..."

# Close issue
gh issue close 8 --repo roundtable-k8s/roundtable

# List PRs
gh pr list --repo roundtable-k8s/roundtable
```

## Workflow

When completing work related to an issue:
1. Comment on the issue with what was done
2. If fully complete, close it
3. If partially done, update with remaining tasks
4. Create new issues for discovered sub-work

## Constraints

- **Read + Write access** to issues, PRs, contents, projects
- **Administration: Read only** — can create repos, CANNOT delete them
