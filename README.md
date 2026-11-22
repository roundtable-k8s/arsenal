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
│   └── fleet-status/          # Fleet health summary
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
point a Knight's arsenal at your own skills repository for those.

## Architecture

Knights run on the **pi-knight** runtime (Pi SDK). Skills are delivered via git-sync sidecar with per-knight filtering:

```
git-sync → /arsenal (full repo)
skill-filter sidecar → symlinks SKILL_CATEGORIES → /skills
pi-knight → discovers skills from /skills via Pi SDK
```

Each knight only sees `shared/` plus its domain categories. Configured via `SKILL_CATEGORIES` env var on the skill-filter sidecar.

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

## License

MIT
