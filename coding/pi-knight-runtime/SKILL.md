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
scripts/                    Dev scripts
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

## NATS and the task contract

- Knights consume tasks from JetStream WorkQueue streams; stream names and prefix come from env (`NATS_TASKS_STREAM`, `NATS_RESULTS_STREAM`, `NATS_RESULTS_PREFIX`).
- Payload schemas live in `packages/core/src/contract/`; the operator vendors them via `make contract-sync` (roundtable repo), so a schema change here needs a matching operator sync. See `docs/knight-task-contract.md` in roundtable-k8s/roundtable.

## Environment Variables

Set by the operator: `KNIGHT_NAME`, `NATS_URL`, the `NATS_*` stream vars above, `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`, `SKILLS_DIR`, `WORKSPACE_DIR`, `SHARED_DIR`. The authoritative list is `packages/core/src/config.ts` and `packages/pi-knight/src/config.ts`.

## Knight Communication

Knight-to-knight tools are built in (`packages/pi-knight/src/tools/nats.ts`, `find-knights.ts`), not arsenal skills. The NATS prefix derives from `NATS_RESULTS_PREFIX`, set per table by the operator.

## Known Gotchas

- Knights can self-install tools: `nix profile install nixpkgs#<package>` (persists on PVC)
- Stale PVCs with broken `~/.nix-profile` symlinks cause silent tool failure (delete PVC to fix)
- Knights describe work instead of outputting artifacts — verify output IS the deliverable
- Frontend tasks need an explicit `npx tsc --noEmit` mandate — knights skip it otherwise
