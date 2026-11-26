---
name: pi-knight-runtime
description: Work within the knights monorepo (TypeScript/Node) that holds the pi-knight and claude-knight runtimes and their shared core. Use when modifying knight runtime, NATS messaging, tools, or the task contract in roundtable-k8s/knights. (Skill name kept as pi-knight-runtime so arsenal links keep working.)
---

# knights Monorepo Codebase Guide (pi-knight, claude-knight, core)

_Last checked against roundtable-k8s/knights @ `491a5e8`. The old standalone `roundtable-k8s/pi-knight` repo is no longer the code home; the container image is still `ghcr.io/roundtable-k8s/pi-knight`._

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Language | TypeScript (ES modules), npm workspaces |
| Packages | `packages/core` (`@roundtable/knight-core`), `packages/pi-knight`, `packages/claude-knight` |
| pi SDKs | `@earendil-works/pi-agent-core`, `pi-ai`, `pi-coding-agent` (pi-knight) |
| NATS | `@nats-io/*` v3 (jetstream, kv, services, transport-node), in core |
| Tests | `tsx --test` per package (`tests/` dir) |
| Image | `ghcr.io/roundtable-k8s/pi-knight:<sha>` (Dockerfile in `packages/pi-knight/`) |

## Project Layout

```
packages/core/src/          Shared code: config, NATS (`nats/`), health, metrics, telemetry,
                            memory, roster, slots, drain, guardrails, introspect, logger,
                            and the task/result contract (`contract/`)
packages/pi-knight/src/     pi runtime: index.ts, knight.ts (task handling), config, model,
                            memory, sessions, spans, result-extraction, task-payload, hooks
  tools/                    Knight tools (nats.ts, find-knights.ts, browser.ts, subagent.ts)
packages/claude-knight/src/ Claude Code runtime: cli-runner, hooks, guardrails, mcp-*, sessions, stream
packages/*/tests/           Tests per package
scripts/dev                 Dev script
```

Shared code goes in `packages/core`; work in one package unless the task says otherwise.

## Build & Test (from the repo root, per the repo's AGENTS.md)

```bash
npm ci
npm run build
npm run typecheck
npm test
npm run lint
npm test --workspace packages/pi-knight   # one package
```

Run typecheck, test and lint before pushing.

## If a test fails only in the pod

The pod sets variables that a developer machine and CI do not (`KNIGHT_NAME`, `NATS_*`, `ROUNDTABLE_TABLE`, `KNIGHT_MODEL`, `KNIGHT_DATA_DIR`, `MAX_CONCURRENT_TASKS`). Before changing any code:

1. Run the failing test again with a clean environment, keeping only what the toolchain needs:
   ```bash
   env -i PATH="$PATH" HOME="$HOME" npm test --workspace packages/<pkg>
   ```
2. If it now passes, the test depends on the pod's ambient variables. Compare `env | sort` with what the test and its source read (`grep -rn "process.env" <test and source files>`), then fix the test so it sets or clears the variables it reads itself. Never fix it by unsetting variables in product code.
3. If it still fails, it is a real failure: debug it as usual.
4. Name in the PR body the variables that made the difference.

## NATS and the task contract

- Knights consume tasks from JetStream WorkQueue streams; stream names and prefix come from env (`NATS_TASKS_STREAM`, `NATS_RESULTS_STREAM`, `NATS_RESULTS_PREFIX`).
- Payload schemas live in `packages/core/src/contract/`; the operator vendors them via `make contract-sync` (roundtable repo), so a schema change here needs a matching operator sync. See `docs/knight-task-contract.md` in roundtable-k8s/roundtable.

## Environment Variables

Core vars: `KNIGHT_NAME`, `NATS_*` (URL and stream vars above), `ROUNDTABLE_TABLE`, `KNIGHT_MODEL`, `KNIGHT_DATA_DIR`, `KNIGHT_WORK_ROOT`, `KNIGHT_SESSIONS_ROOT`, `KNIGHT_MEMORY_*`, `MAX_CONCURRENT_TASKS`; claude-knight also reads `KNIGHT_SKILLS_DIR`. The authoritative list is the `config.ts` files under `packages/`; check them rather than trusting this line.

## Knight Communication

Knight-to-knight tools are built in (`packages/pi-knight/src/tools/nats.ts`, `find-knights.ts`), not arsenal skills. The NATS prefix derives from `NATS_RESULTS_PREFIX`, set per table by the operator.

## Known Gotchas

- Knights can self-install tools: `nix profile install nixpkgs#<package>` (persists on PVC)
- Stale PVCs with broken `~/.nix-profile` symlinks cause silent tool failure (delete PVC to fix)
- Knights describe work instead of outputting artifacts — verify output IS the deliverable
- Frontend tasks need an explicit `npx tsc --noEmit` mandate — knights skip it otherwise
