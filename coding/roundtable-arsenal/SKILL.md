---
name: roundtable-arsenal
description: Work within the Round Table platform arsenal repo (roundtable-k8s/arsenal). Use when creating, editing, or organizing knight skills in roundtable-k8s/arsenal, or reasoning about how arsenals are delivered to knights (spec.arsenals).
---

# Arsenal (roundtable-k8s/arsenal) Codebase Guide

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Repo | `roundtable-k8s/arsenal` — the platform arsenal (an empty `spec.arsenals` entry resolves here) |
| Format | AgentSkills (SKILL.md + `scripts/`, `references/`, `assets/`) |
| CI | `.github/workflows/validate-skills.yaml` |
| Git-synced | Operator syncs it to knight pods via `spec.arsenals` (ordered list), merged per skill |

## Repository Layout

Skills are organized by category folder, each containing one or more skills:

```
shared/      Cross-cutting skills (daily-reports, web-search, evidence-verification, …)
project/     Round Table project work (briefing-synthesis, chain-orchestration, fleet-status, github-pm,
             orchestrator, pr-postrun, pr-review)
watch/       Night Watch (night-watch-triage, telemetry-queries)
coding/      Working on the Round Table itself (roundtable-operator, roundtable-ui,
             pi-knight-runtime [= the knights monorepo], roundtable-arsenal, night-watch-fix) + coding-agent.md
operator/    Prompts used by the operator (planner.md)
```

Domain packs (security, finance, intel, …) are NOT in this repo — they live in
separate arsenals layered on via `spec.arsenals` (e.g. `<you>/<your-skills>`).

## Skill Structure

Every skill MUST have a `SKILL.md` with YAML frontmatter:

```
skill-name/
├── SKILL.md              # Required: frontmatter (name, description) + instructions
├── scripts/              # Optional: executable code (bash, python)
├── references/           # Optional: docs loaded into context as needed
├── assets/               # Optional: templates, schemas, static data
└── tests/test.sh         # Script tests (stubs on PATH); model: project/pr-review/tests/test.sh
```

### SKILL.md Format

```markdown
---
name: my-skill
description: Clear description of what this skill does and when to use it.
---

# Skill Title

Instructions, workflows, and guidance here.
```

## Creating Skills — Key Principles

1. **Concise is key** — context window is shared. Only add what the model doesn't already know.
2. **Match freedom to fragility** — fragile operations need specific scripts; flexible tasks need guidance.
3. **Prefer examples over explanations** — show, don't tell.
4. **Scripts for repeatability** — if you'd rewrite the same code twice, make it a script.
5. **Assets for consistent output** — report and briefing templates in `assets/`.

## Conventions

- Domain folders are lowercase, hyphenated
- Skill folders are lowercase, hyphenated
- Scripts should be executable (`chmod +x`) with shebangs
- Knight images ship `jq`, `curl`, `git`, `gh`; anything else goes in `compatibility` and `spec.tools.nix`
- Run `bash tests/layout.test.sh` (README tree and SKILL.md path references) and the script tests
- `shared/` skills are mounted by ALL knights — keep them lean

## Finish inside the turn

- After the first commit that builds, push the branch (`git push -u origin <branch>`) and open the PR as a draft (`gh pr create --draft`). Keep pushing after each later commit. A task that runs out of time must leave its work on the remote.
- While iterating, run the narrowest test (one package, one file, `-run <name>`). Run the full suite once, at the end, and read its output instead of re-running it.
- Never end a turn while a command you started in the background is still running: wait for it to finish (or stop it), then push. A final message such as "tests are running in the background" loses the work.
- If the time limit in the task prompt (when there is one) is nearly used up, stop testing, push what builds, and say in the final message what is untested.

## CI Validation

The `validate-skills.yaml` workflow checks:
- Frontmatter has `name` and `description`
- `name` equals the directory name
- Script files are executable

It does not check references or run script tests (see `tests/layout.test.sh`).

## Git Sync

The operator delivers skills from one or more arsenals, configured on the Knight CR:

- `spec.arsenals` — the single ordered list of arsenals (`name`, `repo`, `ref`,
  `periodSeconds` as an integer, `image`; or an `oci` source). An empty entry
  (`{name: platform}`) defaults to `https://github.com/roundtable-k8s/arsenal` @ `main`,
  so it means this repo. Extra arsenals follow it. Each entry gets its own
  `git-sync-<name>` sidecar syncing to `/arsenal/<name>` (`name` defaults to the repo basename).
- The skill-filter sidecar links `/skills/<category>/<skill>` for each category in
  `spec.skills`, merging **per skill**: the last arsenal that provides
  `<category>/<skill>` wins. Links refresh every 60s; removed skills are pruned.
- Knights only see categories listed in `spec.skills` (list `shared` explicitly).

```yaml
spec:
  skills: [shared, project, security]
  arsenals:
    - name: platform     # this repo
    - name: personal
      repo: https://github.com/<you>/<your-skills>
```

Skills are read-only at `/skills/<category>/<skill>/` in the knight; changes merged
here reach running knights within one sync period plus the 60s link refresh.
