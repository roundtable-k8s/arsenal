# Round Table Arsenal

Skills and resources for Knights of the Round Table — AI agents running on the [pi-knight](https://github.com/roundtable-k8s/pi-knight) runtime.

All skills follow the open [Agent Skills](https://agentskills.io) standard.

## Structure

```
arsenal/
├── shared/                    # Base capabilities (ALL knights)
│   ├── daily-reports/         # Daily briefing templates
│   ├── evidence-verification/ # Source/evidence checking
│   ├── open-items-ledger/     # Carry-forward ledger protocol
│   ├── report-generator/      # Template-based report rendering
│   ├── vault-indexer/         # Vault indexing helpers
│   ├── web-browser/           # Headless browsing
│   ├── web-search/            # SearXNG metasearch
│   └── web-fetch/             # URL content extraction
│
├── project/                   # Chains & fleet coordination
│   ├── chain-orchestration/   # Multi-knight chain execution
│   ├── briefing-synthesis/    # Merge knight outputs into one briefing
│   ├── fleet-status/          # Fleet health summary
│   └── github-pm/             # Roadmap/issue management for the operator repo
│
├── watch/                     # Night Watch — platform self-healing
│   ├── telemetry-queries/     # Prometheus / Victoria Logs queries
│   └── night-watch-triage/    # Fingerprint incidents, dispatch fix Missions
│
├── coding/                    # Working on the Round Table itself
│   ├── roundtable-operator/   # Go / Kubebuilder operator
│   ├── roundtable-ui/         # React + Go dashboard
│   ├── roundtable-arsenal/    # This repo
│   ├── pi-knight-runtime/     # TypeScript knight runtime
│   └── night-watch-fix/       # Execute a Night Watch fix Mission
│
└── operator/                  # Prompts used by the operator (planner)
```

Domain skill packs (security, finance, research, …) are not part of this repo;
add your own skills repository as a Knight `spec.arsenals` entry for those (see
[Architecture](#architecture)).

## Architecture

Knights run on the **pi-knight** runtime (Pi SDK). The operator delivers skills
from one or more **arsenals** (git repos of skills) and filters them per knight:

```
git-sync / git-sync-<name> (one sidecar per arsenal) → /arsenal/<name>   (full repo, read-only)
skill-filter sidecar → /skills/<category>/<skill> symlinks    (only categories in spec.skills)
pi-knight → discovers skills from /skills via Pi SDK
```

- **`spec.arsenal`** — the primary arsenal. Its fields default to
  `https://github.com/roundtable-k8s/arsenal` (`ref: main`, `period: 300s`), so
  `arsenal: {}` gives the platform arsenal. Leave `spec.arsenal` out entirely and
  only the `spec.arsenals` entries are synced.
- **`spec.arsenals`** — optional extra arsenals (`name`, `repo`, `ref`, `period`,
  `image`), merged after `spec.arsenal` in list order. `name` sets the sync path
  `/arsenal/<name>` and sidecar `git-sync-<name>`; it defaults to the repo basename.
- **Per-skill merge** — for every category in `spec.skills`, `/skills/<category>/<skill>`
  links to the **last** arsenal that provides `<category>/<skill>`, so later
  arsenals override individual skills without hiding the rest of the category.
  The links are refreshed every 60s; skills no arsenal provides any more are pruned.
- **Categories** — a knight only sees the categories listed in `spec.skills`
  (list `shared` explicitly).

Domain packs (security, finance, …) live in your own repo, added as an `arsenals` entry after this one:

```yaml
apiVersion: ai.roundtable.io/v1alpha1
kind: Knight
metadata:
  name: galahad
spec:
  # …other Knight fields omitted
  skills: [shared, security]
  arsenal: {}                  # roundtable-k8s/arsenal @ main (defaults)
  arsenals:
    - name: my-skills
      repo: https://github.com/<you>/<your-skills>
      ref: main
```

### Native Tools

Knights have three custom tools registered natively (not bash scripts):

- **`nats_publish`** — Fire-and-forget NATS messaging
- **`nats_request`** — Cross-knight collaboration (send task, wait for response)
- **`spawn_subagent`** — In-process sub-agent for focused subtasks

The `knight-comms` and `nats-comms` skills document when and how to use these tools.

## Skill Format (agentskills.io)

Each skill is a directory with:

```
skill-name/
├── SKILL.md              # Required — frontmatter + instructions
├── scripts/              # Executable helpers (bash, python)
├── references/           # On-demand documentation
└── assets/               # Templates, schemas, static data
```

### Progressive Disclosure

1. **Startup** — Only `name` + `description` loaded (~100 tokens per skill)
2. **Activation** — Full SKILL.md instructions loaded when task matches
3. **Execution** — `references/` and `assets/` loaded on-demand

## Vault layout

Skills that read or write vault files take their roots from these environment
variables, falling back to the defaults (the `Knight.spec.vault.writablePaths`
layout of the reference deployment):

| Variable | Default | Used for |
|---|---|---|
| `RT_BRIEFINGS_DIR` | `/vault/Agents/Briefings` | Daily briefings and the open-items ledger |
| `RT_REPORTS_DIR` | `/vault/Agents/Roundtable` | Knight reports |
| `RT_NIGHTWATCH_DIR` | `/vault/Agents/NightWatch` | Night Watch ledger |

## License

MIT
