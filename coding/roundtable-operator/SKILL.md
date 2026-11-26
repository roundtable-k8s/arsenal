---
name: roundtable-operator
description: Work within the roundtable operator repo (Go, Kubebuilder). Use when modifying CRDs, controllers, Helm charts, or NATS integration in roundtable-k8s/roundtable.
---

# roundtable-operator Codebase Guide

_Last checked against roundtable-k8s/roundtable @ `09b66fb`. Layout below is by directory; run `ls internal/` to see what changed since._

## Quick Reference

| Aspect | Detail |
|--------|--------|
| Language | Go (version in `go.mod`; set `GOTOOLCHAIN` to the toolchain named in `go.mod` for `make test` / `make lint`) |
| Framework | Kubebuilder (controller-runtime) |
| Tests | Ginkgo + Gomega (BDD), envtest |
| CRD Group | `ai.roundtable.io/v1alpha1` |
| Kinds | Knight, Chain, Mission, RoundTable, Trigger (plus IssuePickup/PRFeedback types in `api/v1alpha1`) |
| NATS | `github.com/nats-io/nats.go` (version in `go.mod`) |
| CI | `.github/workflows/ci.yml` (vet, lint, test, helm-check), Docker build+push to GHCR |
| Image | `ghcr.io/roundtable-k8s/roundtable:<sha>` |

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
internal/github/                    GitHub client/auth (pickup, PR feedback)
pkg/nats/                           JetStream client, config, consumers, payload types
pkg/nats/contract/                  Knight task contract: vendored schemas + generated Go types
pkg/runtime/                        RuntimeBackend interface + Deployment/sandbox backends
pkg/metrics/                        Prometheus metrics
charts/roundtable-operator/         Helm chart (CRDs in crds/, templates in templates/)
config/crd/bases/                   Generated CRDs — never edit directly
docs/                               Design docs (ARCHITECTURE.md, knight-task-contract.md, ...)
hack/                               Dev scripts
```

Tests live beside the code as `*_test.go`; check `Makefile` (`make help`) for targets
(`make test`, `make lint`, `make helm-check`, `make contract-sync`).

## Critical Rules

1. **Never edit auto-generated files**: `config/crd/bases/*.yaml`, `config/rbac/role.yaml`, `**/zz_generated.*.go`
2. **Never remove scaffold markers**: `// +kubebuilder:scaffold:*` comments
3. **After editing `*_types.go`**: Run `make manifests generate`
4. **After editing `*.go`**: Run `make test`
5. **Always `CGO_ENABLED=0`** for builds (no gcc in runtime image)
6. **Kubebuilder CRD defaults are applied at API server admission** — controller-side env vars can't override them

## Build & Test

```bash
make manifests generate   # Regen CRDs + DeepCopy after type changes
GOTOOLCHAIN=<go.mod toolchain> make test   # fmt, vet, envtest (real API server + etcd)
GOTOOLCHAIN=<go.mod toolchain> make lint   # golangci-lint
make helm-check           # Lint the Helm chart
make build                # manager + gateway binaries
```

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
