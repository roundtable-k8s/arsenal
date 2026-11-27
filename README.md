# Round Table Arsenal

Skills and resources for Knights of the Round Table — AI agents running on the [pi-knight](https://github.com/roundtable-k8s/pi-knight) runtime.

All skills follow the open [Agent Skills](https://agentskills.io) standard.

## Structure

```
arsenal/
├── shared/                    # Base capabilities (ALL knights)
│   ├── daily-reports/         # Daily briefing templates
│   ├── dead-letter-triage/    # Dead letters sorted into retry, rerun, skip or inspect
│   ├── evidence-verification/ # Source/evidence checking
│   ├── fleet-summary/         # Recent tasks and dead letters as a plain summary
│   ├── job-run/               # Scheduled-job run ledger and output checks
│   ├── open-items-ledger/     # Carry-forward ledger protocol
│   ├── report-generator/      # Template-based report rendering
│   ├── run-report/            # Summarise a chain run record as markdown
│   ├── schedules/             # Inspect and operate schedules, with a health report
│   ├── side-by-side/          # Compare an old job's dated output with the new one
│   ├── vault-indexer/         # Vault indexing helpers
│   ├── workspace-snapshots/   # Check and take workspace snapshots before risky work
│   ├── web-browser/           # Headless browsing
│   ├── web-search/            # SearXNG metasearch
│   └── web-fetch/             # URL content extraction
│
├── project/                   # Chains & fleet coordination
│   ├── chain-orchestration/   # Multi-knight chain execution
│   ├── briefing-synthesis/    # Merge knight outputs into one briefing
│   ├── fleet-status/          # Fleet health summary
│   ├── github-pm/             # Roadmap/issue management for the operator repo
│   ├── handoff/               # Pass work to another knight with a brief checked before sending
│   ├── orchestrator/          # Plan, dispatch and tend issue work
│   ├── pr-postrun/            # Post-run PR housekeeping
│   └── pr-review/             # PR review helpers
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

Knights run on the **pi-knight** (Pi SDK) or **claude-knight** (Claude Code) runtime. The operator delivers skills
from one or more **arsenals** (git repos of skills) and filters them per knight:

```
git-sync / git-sync-<name> (one sidecar per arsenal) → /arsenal/<name>   (full repo, read-only)
skill-filter sidecar → /skills/<category>/<skill> symlinks    (only categories in spec.skills)
runtime (pi-knight / claude-knight) → discovers skills from /skills
```

- **`spec.arsenals`** — the single ordered list of arsenals. Each entry has `name`,
  `repo`, `ref`, `periodSeconds` (integer seconds, not `300s`) and `image`, or an
  `oci` source instead of a git repo. An empty entry (`{name: platform}`) uses the
  defaults: `https://github.com/roundtable-k8s/arsenal`, `ref: main`. `name` sets
  the sync path `/arsenal/<name>` and sidecar `git-sync-<name>`; it defaults to the
  repo basename. Extra arsenals go after the platform entry; the list order is the
  merge order.
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
  arsenals:
    - name: platform           # empty entry = roundtable-k8s/arsenal @ main (defaults)
    - name: my-skills
      repo: https://github.com/<you>/<your-skills>
      ref: main
```

### Native Tools

Knights have four custom tools registered natively (not bash scripts):

- **`nats_publish`** — Fire-and-forget NATS messaging
- **`nats_request`** — Cross-knight collaboration (send task, wait for response)
- **`find_knights`** — Lists the knights at your table from their agent cards and status
- **`spawn_subagent`** — In-process sub-agent for focused subtasks

Use `find_knights` to see who is at your table before calling one with `nats_request`. The `chain-orchestration` project skill documents when and how to use these tools.

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

## Use this arsenal as an OCI image

Every push to `main` publishes the skills as an image to `ghcr.io/roundtable-k8s/arsenal`, tagged `sha-<commit>` and `main`. The digest is in the run summary of the "Publish Arsenal Image" workflow. Mount it by digest (the reference must be digest-pinned; needs Kubernetes image volumes):

```yaml
spec:
  arsenals:
    - name: platform
      oci:
        reference: ghcr.io/roundtable-k8s/arsenal@sha256:<digest>
        pullPolicy: IfNotPresent
```

The image root is the arsenal root (`coding`, `operator`, `project`, `shared`, `watch`); it mounts at `/arsenal-oci/<name>`.

## License

MIT
