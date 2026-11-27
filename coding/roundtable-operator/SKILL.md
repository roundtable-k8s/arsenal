---
name: roundtable-operator
description: Work within the roundtable operator repo (Go, Kubebuilder). Use when modifying CRDs, controllers, Helm charts, or NATS integration in roundtable-k8s/roundtable.
---

# roundtable-operator Codebase Guide

_Last checked against roundtable-k8s/roundtable @ `74e10d2`. Layout below is by directory; run `ls internal/` to see what changed since._

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Language | Go (version and `toolchain` pinned in `go.mod`) |
| Framework | Kubebuilder (controller-runtime) |
| Tests | Ginkgo + Gomega (BDD), envtest |
| CRD Group | `ai.roundtable.io/v1alpha1` |
| Kinds | Knight, Chain, Mission, RoundTable, Trigger (plus IssuePickup/PRFeedback types in `api/v1alpha1`) |
| NATS | `github.com/nats-io/nats.go` (version in `go.mod`) |
| CI | `.github/workflows/ci.yml` (vet, lint, test, helm-check; on main also publishes the chart), `e2e.yml` (kind harness), `release.yml` (on `vX.Y.Z` tags), `tools-builder.yml` (tools image), `merge-guard.yml`, `tilt.yml`, `trigger-autodeploy.yml` |
| Image | `ghcr.io/roundtable-k8s/roundtable:<sha>` (also `:latest`) from `ci.yml` on main; `:vX.Y.Z` on release (`release.yml`) |
| Chart | `oci://ghcr.io/roundtable-k8s/charts`: main pushes `<Chart.yaml version>-dev.<short sha>` (`appVersion` = full SHA); release tags `vX.Y.Z` publish `X.Y.Z` |

## Project Layout

```
cmd/main.go                         Manager entry (registers controllers)
cmd/gateway/                        Gateway binary (HTTP API in front of NATS/CRs)
cmd/toolsflake/                     Tools-flake helper
api/v1alpha1/*_types.go             CRD schemas (kubebuilder markers)
api/v1alpha1/zz_generated.*         AUTO-GENERATED — never edit
internal/controller/                Reconcilers, one file group per concern
                                    (knight_*, chain_*, mission_*, trigger_*,
                                    roundtable_*, issuepickup_*, prfeedback_*)
internal/knight/                    Pod/Deployment building, isolation, MCP, scaling, tools image
internal/mission/                   Mission planner, assembler, chains, cost, netpol, cleanup
internal/chainrun/                  Chain run helpers shared with the gateway
internal/firetrigger/               Trigger firing logic
internal/gateway/                   Gateway HTTP handlers (fire, runs, schedules, dead letters, MCP, openapi)
internal/deadletter/                Dead-letter handling
internal/notify/                    Notifications
internal/status/                    Status builder
internal/telemetry/                 Trace/telemetry ids
internal/util/                      Shared helpers
internal/github/                    GitHub client/auth (pickup, PR feedback)
pkg/nats/                           JetStream client, config, consumers, payload types
pkg/nats/contract/                  Knight task contract: vendored schemas + generated Go types
pkg/runtime/                        RuntimeBackend interface + Deployment/sandbox backends
pkg/metrics/                        Prometheus metrics
charts/roundtable-operator/         Helm chart (CRDs in crds/, templates in templates/)
config/crd/bases/                   Generated CRDs — never edit directly
docs/                               Design docs (ARCHITECTURE.md, knight-task-contract.md, ...)
hack/                               Dev scripts
test/                               e2e (needs a kind cluster), CRD tests, test utils
```

The repository's `AGENTS.md` is the authority for commands and generated files; read it first and follow it over this guide.

Tests live beside the code as `*_test.go`; check `Makefile` (`make help`) for targets
(`make test`, `make lint`, `make helm-check`, `make contract-sync`).

## Critical Rules

1. **Never edit auto-generated files**: `config/crd/bases/*.yaml`, `config/rbac/role.yaml`, `**/zz_generated.*.go`
2. **Never remove scaffold markers**: `// +kubebuilder:scaffold:*` comments
3. **After editing `*_types.go`**: Run `make manifests generate`
4. **After editing `*.go`**: Run the narrowest test for what you touched (`go test ./path/... -run <name>`); `make test` runs once, at the end
5. **Always `CGO_ENABLED=0`** for builds (no gcc in runtime image)
6. **Kubebuilder CRD defaults are applied at API server admission** — controller-side env vars can't override them

## Build & Test

```bash
make manifests generate   # Regen CRDs + DeepCopy after type changes
make test                 # fmt, vet, envtest (real API server + etcd)
make lint                 # golangci-lint
make helm-check           # Lint the Helm chart
make build                # manager + gateway binaries
```

`go.mod` pins `toolchain`, so do not set `GOTOOLCHAIN` by hand. Do not run `make docker-*`, `tilt-up` or the e2e targets in a knight pod (no Docker daemon, no kind cluster); leave them to CI.

## Finish inside the turn

- After the first commit that builds, push the branch (`git push -u origin <branch>`) and open the PR as a draft (`gh pr create --draft`). Keep pushing after each later commit. A task that runs out of time must leave its work on the remote.
- While iterating, run the narrowest test (one package, one file, `-run <name>`). Run the full suite once, at the end, and read its output instead of re-running it.
- Never end a turn while a command you started in the background is still running: wait for it to finish (or stop it), then push. A final message such as "tests are running in the background" loses the work.
- If the time limit in the task prompt (when there is one) is nearly used up, stop testing, push what builds, and say in the final message what is untested.

## If a test fails only in the pod

The pod sets variables that a developer machine and CI do not (`KNIGHT_NAME`, `NATS_*`, `ROUNDTABLE_TABLE`, `KNIGHT_MODEL`, `KNIGHT_DATA_DIR`, `MAX_CONCURRENT_TASKS`). Before changing any code:

1. Run the failing test again with a clean environment, keeping only what the toolchain needs:
   ```bash
   env -i PATH="$PATH" HOME="$HOME" go test ./...
   ```
2. If it now passes, the test depends on the pod's ambient variables. Compare `env | sort` with what the test and its source read (`grep -rn "os.Getenv" <test and source files>`), then fix the test so it sets or clears the variables it reads itself. Never fix it by unsetting variables in product code.
3. If it still fails, it is a real failure: debug it as usual.
4. Name in the PR body the variables that made the difference.

## CRD Types — Source of Truth

**Always validate Knight CRs against `api/v1alpha1/knight_types.go`.**

Key fields:
- `spec.nats.subjects` (NOT `topics`)
- `spec.workspace.size` (NOT `storageSize`)
- `spec.arsenals` is the single ordered list of arsenals (`name/repo/ref/periodSeconds/image`, or `oci`); `periodSeconds` is an integer. An empty entry defaults to the platform arsenal. Merged per skill in list order (last provider of `<category>/<skill>` wins); one `git-sync-<name>` sidecar each → `/arsenal/<name>`. The old singular `arsenal` field was removed
- `spec.skills` is top-level (not under arsenal)

## NATS Integration

- Streams are configurable via env: `NATS_TASKS_STREAM`, `NATS_RESULTS_STREAM`, `NATS_RESULTS_PREFIX`
- Chain task subjects: `chain-name-step.timestamp` (dots, not dashes, before timestamp)
- WorkQueue retention for dynamic/ephemeral tables
- `OrderedConsumer` incompatible with WorkQueue retention streams

## Helm Chart

Located at `charts/roundtable-operator/`. CRDs go in `crds/` (plain YAML, no templating).

Versions: CI overwrites `Chart.yaml` on main with `<version>-dev.<short sha>` (the committed `version` is the base). The main chart step fails when the tag `v<version>` already exists, so when you bump `version` in `Chart.yaml`, never reuse a released chart version.

**Trap**: `cp *.yaml` into `crds/` dir can grab kustomization.yaml → breaks chart upgrade. Be explicit with filenames.

## Controller Patterns

- Idempotent reconciliation (safe to run multiple times)
- Re-fetch before updates to avoid conflicts
- Owner references for garbage collection
- Structured logging (capital first letter, no trailing period, past tense)
- `metav1.Condition` for status (not custom strings)

## Known Gotchas

- `spec.timeout` on Chain CRD defaults to 600s — set explicitly for multi-step chains (3600+)
- Step names in chains: **underscores, not hyphens** (Go templates interpret `-` as subtraction)
- Never hardcode a table/namespace name; derive it from the RoundTable/CR
- `Flux targetNamespace` rewrites ALL namespace fields including cross-namespace SA refs
