---
name: roundtable-arsenal
description: Work within the Round Table platform arsenal repo (roundtable-k8s/arsenal). Use when creating, editing, or organizing knight skills in roundtable-k8s/arsenal, or reasoning about how arsenals are delivered to knights (spec.arsenal / spec.arsenals).
---

# Arsenal (roundtable-k8s/arsenal) Codebase Guide

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Repo | `roundtable-k8s/arsenal` — the platform arsenal (`spec.arsenal: {}` resolves here) |
| Format | AgentSkills (SKILL.md + scripts/references/assets) |
| CI | `.github/workflows/validate-skills.yaml` |
| Git-synced | Operator syncs it to knight pods via `spec.arsenal`; extra arsenals via `spec.arsenals`, merged per skill |

## Repository Layout

Skills are organized by tier folder, each containing one or more skills:

```
shared/      Cross-cutting skills (daily-reports, web-search, evidence-verification, …)
project/     Round Table project work (briefing-synthesis, chain-orchestration, fleet-status, github-pm)
watch/       Night Watch (night-watch-triage, telemetry-queries)
coding/      Working on the Round Table itself (roundtable-operator, roundtable-ui,
             pi-knight-runtime, roundtable-arsenal, night-watch-fix) + coding-agent.md
operator/    Prompts used by the operator (planner.md)
```

Domain packs (security, finance, intel, …) are NOT in this repo — they live in
separate arsenals layered on via `spec.arsenals` (e.g. `dapperdivers/roundtable-arsenal`).

## Skill Structure

Every skill MUST have a `SKILL.md` with YAML frontmatter:

```
skill-name/
├── SKILL.md              # Required: frontmatter (name, description) + instructions
├── scripts/              # Optional: executable code (bash, python)
├── references/           # Optional: docs loaded into context as needed
├── templates/            # Optional: output templates (markdown, etc.)
└── assets/               # Optional: static files (icons, fonts)
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
5. **Templates for consistent output** — daily reports, briefings, etc.

## Conventions

- Domain folders are lowercase, hyphenated
- Skill folders are lowercase, hyphenated
- Scripts should be executable (`chmod +x`) with shebangs
- Config shared across skills goes in `<domain>/config/`
- `shared/` skills are mounted by ALL knights — keep them lean

## CI Validation

The `validate-skills.yaml` workflow checks:
- Every skill directory has a `SKILL.md`
- Frontmatter has `name` and `description`
- No broken references

## Git Sync

The operator delivers skills from one or more arsenals, configured on the Knight CR:

- `spec.arsenal` (`repo`/`ref`/`period`/`image`) — primary arsenal; its fields default
  to `https://github.com/roundtable-k8s/arsenal` @ `main`, every `300s`, so
  `arsenal: {}` means this repo. If `spec.arsenal` is omitted, only `spec.arsenals` sync.
- `spec.arsenals` — optional list of extra arsenals (same fields plus `name`),
  merged after `spec.arsenal` in order. Each gets its own `git-sync-<name>` sidecar
  syncing to `/arsenal/<name>` (`name` defaults to the repo basename).
- The skill-filter sidecar links `/skills/<category>/<skill>` for each category in
  `spec.skills`, merging **per skill**: the last arsenal that provides
  `<category>/<skill>` wins. Links refresh every 60s; removed skills are pruned.
- Knights only see categories listed in `spec.skills` (list `shared` explicitly).

```yaml
spec:
  skills: [shared, project, security]
  arsenal: {}            # this repo
  arsenals:
    - name: personal
      repo: https://github.com/<you>/<your-skills>
```

Skills are read-only at `/skills/<category>/<skill>/` in the knight; changes merged
here reach running knights within one sync period plus the 60s link refresh.
