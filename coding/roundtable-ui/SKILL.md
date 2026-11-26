---
name: roundtable-ui
description: Work within the roundtable-ui dashboard repo (React + Go API). Use when modifying the fleet dashboard, components, API endpoints, or WebSocket integration in roundtable-k8s/roundtable-ui.
---

# roundtable-ui Codebase Guide

_Last checked against roundtable-k8s/roundtable-ui @ `f423069`. Layout is by directory and pattern; run `ls api ui/src/*` for the current files._

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Frontend | React 18, Vite, TypeScript, Tailwind CSS |
| Backend | Go (see `api/go.mod`), gorilla/mux + gorilla/websocket |
| Tests | Vitest + Testing Library (UI), Go test (API) |
| Storybook | v8.6 for component development |
| CI | npm build + go vet + Docker multi-stage build |
| Image | `ghcr.io/roundtable-k8s/roundtable-ui:<sha>` |

## Project Layout

```
api/                  Go API (package main, flat): `main.go` wires routes; one file per
                      endpoint group (cards, chat, chains, dead_letters, schedules,
                      triggers, telemetry, isolation, gateway_dispatch, ...), each with a
                      `_test.go`; `testdata/` holds JSON fixtures; go.mod / go.sum
ui/
  src/
    App.tsx, main.tsx  Root component + routing, entry point
    pages/             One file per route (Dashboard, Fleet, Chains, Schedules, Triggers,
                       FailedTasks, Chat, Missions, Queues, Sessions, ...)
    components/        Reusable views/badges/graphs (@xyflow/react); `ui/index.tsx` holds
                       shared primitives; `.stories.tsx` and `.test.tsx` sit beside them
    hooks/             Data fetching (useCards, useTables, useRunning, usePolledFetch,
                       useTaskActivity, useWebSocket, ...)
    lib/               Pure logic and API client (api.ts, types.ts, formatters, parsers),
                       unit-tested beside the code
    test/              Vitest setup + fixtures
  .storybook/          Storybook config
  vite.config.ts       Builds to ../api/static
Dockerfile             Multi-stage: node→go→alpine
```

## Build & Test

```bash
# Frontend
cd ui
npm install
npm run build          # tsc -b && vite build
npm run dev            # Vite dev server
npm run test           # Vitest
npm run test:coverage  # Coverage report
npm run storybook      # Component development

# Backend
cd api
go vet ./...
go test ./...
```

The image is built by CI. A knight pod has no Docker daemon and no Docker Hub access, so never run `docker build` here.

## Finish inside the turn

- After the first commit that builds, push the branch (`git push -u origin <branch>`) and open the PR as a draft (`gh pr create --draft`). Keep pushing after each later commit. A task that runs out of time must leave its work on the remote.
- While iterating, run the narrowest test (one package, one file, `-run <name>`). Run the full suite once, at the end, and read its output instead of re-running it.
- Never end a turn while a command you started in the background is still running: wait for it to finish (or stop it), then push. A final message such as "tests are running in the background" loses the work.
- If the time limit in the task prompt (when there is one) is nearly used up, stop testing, push what builds, and say in the final message what is untested.

## If a test fails only in the pod

The pod sets variables that a developer machine and CI do not (`KNIGHT_NAME`, `NATS_*`, `ROUNDTABLE_TABLE`, `KNIGHT_MODEL`, `KNIGHT_DATA_DIR`, `MAX_CONCURRENT_TASKS`). Before changing any code:

1. Run the failing test again with a clean environment, keeping only what the toolchain needs:
   ```bash
   cd api && env -i PATH="$PATH" HOME="$HOME" go test ./...
   cd ui && env -i PATH="$PATH" HOME="$HOME" npm run test
   ```
2. If it now passes, the test depends on the pod's ambient variables. Compare `env | sort` with what the test and its source read (`grep -rn "os.Getenv\|process.env" <test and source files>`), then fix the test so it sets or clears the variables it reads itself. Never fix it by unsetting variables in product code.
3. If it still fails, it is a real failure: debug it as usual.
4. Name in the PR body the variables that made the difference.

`ui/package.json` scripts: `build`, `test`, `test:coverage`, `storybook` (also `dev`, `test:watch`, `build-storybook`).

## Architecture

- **Go API** serves static UI assets from `./static/` and proxies WebSocket connections to NATS
- **Vite** builds to `../api/static/` (configured in vite config)
- **WebSocket** connects UI to NATS for real-time fleet updates
- **@xyflow/react** powers the fleet topology graph

## Key Libraries

### Frontend
- `@xyflow/react` — Interactive node graph (fleet topology)
- `react-router-dom` v7 — Client-side routing
- `lucide-react` — Icons
- `tailwind-merge` + `clsx` — Conditional class merging
- `date-fns` — Date formatting
- `react-markdown` — Markdown rendering (briefings)

### Backend
- `gorilla/mux` — HTTP routing
- `gorilla/websocket` — WebSocket proxy to NATS
- `nats-io/nats.go` — NATS JetStream client

## Component Development

Use Storybook for isolated component work:
```bash
cd ui && npm run storybook
```

All visual components should have `.stories.tsx` files. Tests use `@testing-library/react` + `vitest`.

## Conventions

- Go API pattern: add a new endpoint group as its own file plus `_test.go`, register it in `main.go`
- **Always run `npx tsc --noEmit`** before committing — catches type errors Vite ignores
- Components in `components/`, page-level views in `pages/`, data fetching in `hooks/`
- Tailwind for all styling (no CSS modules)
- `CGO_ENABLED=0` for Go API builds
