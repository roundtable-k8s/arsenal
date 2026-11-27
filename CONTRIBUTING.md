# Contributing Skills to the Arsenal

This guide covers how to create, structure, and contribute skills following the open [Agent Skills](https://agentskills.io) standard.

## Quick Start

1. Pick a category: `shared/`, `project/`, `watch/`, `coding/` or `operator/` (`operator/` holds plain prompt `.md` files, not skills)
2. Create a directory: `<category>/<skill-name>/`
3. Write a `SKILL.md` with YAML frontmatter
4. Add `scripts/`, `references/`, and `assets/` as needed
5. Open a PR

## Skill Categories

| Category | Directory | Purpose |
|----------|-----------|---------|
| **shared** | `shared/` | Base capabilities for all knights — search, reporting, verification |
| **project** | `project/` | Chains and fleet coordination — orchestrator, PR review, briefings |
| **watch** | `watch/` | Night Watch — platform self-healing |
| **coding** | `coding/` | Working on the Round Table itself — operator, UI, arsenal, runtime |
| **operator** | `operator/` | Prompts used by the operator (plain `.md` files, not skills) |

**Rule of thumb:** If every knight needs it → `shared/`. Otherwise pick the closest
category above. **Domain packs (security, finance, intel, …) live in your own
arsenal**, added as a `spec.arsenals` entry (see [Git-Sync Delivery](#git-sync-delivery)),
not in this repo.

## Directory Structure (agentskills.io spec)

```
skill-name/
├── SKILL.md              # REQUIRED — Frontmatter + instructions
├── scripts/              # Optional — Executable code (bash, python, JS)
├── references/           # Optional — On-demand documentation
└── assets/               # Optional — Templates, schemas, static data
```

### SKILL.md — The Core File

Every skill MUST have a `SKILL.md` with YAML frontmatter:

```yaml
---
name: my-skill
description: What this skill does and when to use it. Be specific — this is how agents discover your skill.
allowed-tools: Bash(curl:*) Read Write
metadata:
  author: roundtable
  version: "1.0"
---

# My Skill

Instructions for the agent go here as markdown.
```

#### Frontmatter Fields

| Field | Required | Rules |
|-------|----------|-------|
| `name` | ✅ | 1-64 chars, lowercase alphanumeric + hyphens, must match directory name |
| `description` | ✅ | 1-1024 chars, describe what AND when to use |
| `allowed-tools` | No | Space-delimited list of pre-approved tools |
| `license` | No | License name or reference to LICENSE file |
| `compatibility` | No | Environment requirements (max 500 chars) |
| `metadata` | No | Optional key-value pairs: author, version, etc. (no skill here requires it) |

#### Name Rules
- ✅ `cve-deep-dive`, `web-search`, `opencti-intel`
- ❌ `CVE-Deep-Dive` (no uppercase)
- ❌ `-web-search` (no leading hyphen)
- ❌ `web--search` (no consecutive hyphens)
- ❌ Name must match the parent directory exactly

#### Writing Good Descriptions

The description is the **primary signal** agents use to decide when to activate your skill. Be specific:

```yaml
# ❌ Bad — too vague
description: Helps with security stuff.

# ✅ Good — specific triggers and capabilities
description: Query the OpenCTI threat intelligence platform for STIX 2.1 data including indicators, vulnerabilities, malware, reports, and attack patterns. Use for threat briefings, CVE lookups, IOC searches, and platform statistics.
```

### scripts/ — Executable Code

Put runnable scripts here. They should be:
- **Self-contained** — minimal external dependencies
- **Image tools** — `jq`, `curl`, `git` and `gh` are in the knight image. Anything else (`sqlite3`, `yq`, …) must be named in the skill's `compatibility` field and comes from `spec.tools.nix`
- **Executable** — `chmod +x` all scripts
- **Documented** — include usage comments at the top

```bash
#!/usr/bin/env bash
# Query NVD API for CVE details
# Usage: query-nvd.sh CVE-2026-XXXXX
set -euo pipefail

CVE_ID="${1:?Usage: query-nvd.sh CVE-ID}"
# ... implementation
```

Supported languages: **Bash** (preferred for portability), **Python 3**, **JavaScript/Node**.

### references/ — On-Demand Documentation

Reference material the agent loads only when needed. Keep files focused — each one should cover ONE topic.

Good examples:
- `QUERIES.md` — GraphQL query reference for an API skill
- `nvd-api.md` — NVD API endpoint documentation
- `feeds.md` — List of configured RSS feeds with URLs

**Keep individual files under 500 lines.** If it's longer, split it.

### assets/ — Static Resources

Templates, schemas, and data files:
- `daily-briefing.md` — Handlebars-style report template
- `cve-analysis.md` — Structured analysis output template
- `config.yaml` — Default configuration

Templates use `{{variable}}` syntax and `{{#each list}}...{{/each}}` for iteration.

## Progressive Disclosure

This is the key design principle. Don't front-load everything into context:

1. **Startup (~100 tokens/skill)** — Only `name` + `description` from frontmatter
2. **Activation (~500-2000 tokens)** — Full SKILL.md body loaded when agent picks the skill
3. **Execution (on-demand)** — `references/` and `assets/` loaded only when the agent reads them

**Why this matters:** A knight with 10 skills loads ~1000 tokens at startup instead of ~20,000. The agent only pays the context cost for skills it actually uses.

## Writing SKILL.md Instructions

The markdown body after frontmatter is your agent's playbook. Structure it for efficiency:

### Recommended Sections

```markdown
# Skill Name

Brief overview (1-2 sentences).

## When to Use
Specific triggers and scenarios.

## Quick Reference
Most common commands/patterns — the 80% case.

## Scripts
Document each script with usage examples.

## Configuration
Environment variables, endpoints, auth.

## Tips / Edge Cases
Things the agent should watch out for.

## Dependencies
Other skills this works best with.
```

### Keep SKILL.md Under 500 Lines

If your instructions are longer, move detailed content to `references/`:

```markdown
## Common Queries
See [references/QUERIES.md](references/QUERIES.md) for the full query reference.
```

## Example: Creating a New Skill

Let's say you want a skill for checking Prometheus alerts, in the `watch/` category:

```
watch/prometheus-alerts/
├── SKILL.md
├── scripts/
│   └── alerts.sh            # Fetch firing alerts
├── tests/
│   └── test.sh              # Script tests (stubs on PATH)
├── references/
│   └── api-endpoints.md     # Prometheus API reference
└── assets/
    └── alert-report.md      # Report template
```

```yaml
---
name: prometheus-alerts
description: Query Prometheus for firing alerts and summarise them. Use for incident triage and platform health checks.
allowed-tools: Bash(curl:*) Read Write
compatibility: Requires PROMETHEUS_URL environment variable
---
```

## Git-Sync Delivery

Knights are configured through their **Knight CR**, not per-knight Helm values.
The operator adds one git-sync sidecar per arsenal (syncing to `/arsenal/<name>`)
and a skill-filter sidecar that links the categories in `spec.skills` into
`/skills/<category>/<skill>`. This repo is what an empty `spec.arsenals` entry
(`{name: platform}`) resolves to by default; extra arsenals follow it in the list
and are merged per skill (the last arsenal providing `<category>/<skill>` wins).

```yaml
# Galahad (security) — shared + project from this repo, security from a personal repo
spec:
  skills: [shared, project, security]
  arsenals:
    - name: platform             # defaults: this repo @ main
    - name: my-skills            # synced to /arsenal/my-skills
      repo: https://github.com/<you>/<your-skills>
      ref: main
      periodSeconds: 300         # integer seconds
    # an entry may use `oci` instead of `repo` for an OCI-packaged arsenal

# Gawain (framework) — platform categories only
spec:
  skills: [shared, coding, operator]
  arsenals:
    - name: platform
```

Skills appear read-only under `/skills/<category>/<skill>/`, where the pi-knight
runtime discovers them (links refresh every 60s). Reference bundled scripts by
that path, e.g. `bash /skills/shared/web-search/scripts/search.sh`. Write output
to the knight's workspace (`/data`), never into `/skills` or `/arsenal`.

## Validation

Before submitting a PR:

```bash
# Check frontmatter is valid
python3 -c "
import yaml, sys
with open('SKILL.md') as f:
    content = f.read()
parts = content.split('---', 2)
meta = yaml.safe_load(parts[1])
assert meta.get('name'), 'Missing name'
assert meta.get('description'), 'Missing description'
print(f'✓ {meta[\"name\"]}: {meta[\"description\"][:60]}...')
"

# Check scripts are executable
find scripts/ -type f \( -name "*.sh" -o -name "*.py" \) ! -executable

# Check shell scripts parse
find scripts/ -name "*.sh" -exec bash -n {} \;
```

The CI `validate-skills` job checks frontmatter, that `name` equals the
directory, and script executable bits. It does not run script tests or check
references; run those yourself.

### Tests

Skills with scripts get `tests/test.sh`, using stubs on `PATH` instead of real
network calls; `project/pr-review/tests/test.sh` is the model. Run them all with:

```bash
for t in */*/tests/*.sh; do bash "$t"; done
bash tests/layout.test.sh   # README tree and SKILL.md path references
```

## Checklist

Before submitting:

- [ ] `SKILL.md` has valid YAML frontmatter with `name` and `description`
- [ ] `name` matches the directory name exactly
- [ ] `description` is specific enough for agents to discover
- [ ] Scripts are executable (`chmod +x`)
- [ ] Scripts only need `jq`, `curl`, `git`, `gh` — anything else is in `compatibility`
- [ ] Script tests in `tests/test.sh` pass
- [ ] No hardcoded secrets (use environment variables)
- [ ] SKILL.md body is under 500 lines
- [ ] Placed in the correct category directory and listed in the README tree
