---
name: night-watch-fix
description: Execute a Night Watch fix Mission - reproduce, fix, test, and open a PR for an incident dispatched by the watchman. Use when a mission briefing references a Night-Watch fingerprint.
---

# Night Watch Fix Procedure

You received a Mission briefing with a fingerprint, evidence, and a target repo.
The deliverable is a **PR**, or an explicit, well-argued "not a bug" verdict.
Follow coding-agent rules (branch, tests, PR); this skill adds the Night Watch
specifics.

Read your repo's codebase skill first: `coding/roundtable-operator`,
`coding/pi-knight-runtime`, `coding/roundtable-ui`, or `coding/roundtable-arsenal`.

## Per-repo procedure

| Repo | Full suite (run once, before marking ready) |
|---|---|
| roundtable-k8s/knights | from the repo root: `npm ci && npm run build && npm run typecheck && npm test && npm run lint` (one package: `npm test --workspace packages/pi-knight`) |
| roundtable-k8s/roundtable-ui | `cd api && go build ./... && go vet ./... && go test ./...`; UI changes: `cd ui && npm install && npm run build` |
| roundtable-k8s/roundtable | `go build ./... && go vet ./...`; run `make test` (envtest) — if the sandbox can't, say so in the PR body |
| roundtable-k8s/arsenal | skills are markdown: valid YAML frontmatter (`name`, `description`), check referenced paths/commands actually exist |
| the deployment's GitOps repo (named in the Mission briefing) | **Round Table app paths ONLY** (e.g. `kubernetes/apps/roundtable/**`) — never touch anything else. Update the matching `kustomization.yaml` for new files. |

## Finish inside the turn

- After the first commit that builds, push the branch (`git push -u origin <branch>`) and open the PR as a draft (`gh pr create --draft`). Keep pushing after each later commit. A task that runs out of time must leave its work on the remote.
- While iterating, run the narrowest test (one package, one file, `-run <name>`). Run the full suite once, at the end, and read its output instead of re-running it.
- Never end a turn while a command you started in the background is still running: wait for it to finish (or stop it), then push. A final message such as "tests are running in the background" loses the work.
- If the time limit in the task prompt (when there is one) is nearly used up, stop testing, push what builds, and say in the final message what is untested.

## If a test fails only in the pod

The pod sets variables that a developer machine and CI do not (`KNIGHT_NAME`, `NATS_*`, `ROUNDTABLE_TABLE`, `KNIGHT_MODEL`, `KNIGHT_DATA_DIR`, `MAX_CONCURRENT_TASKS`). Before changing any code, run the repo's test command from the table above again with a clean environment, keeping only what the toolchain needs, for example `env -i PATH="$PATH" HOME="$HOME" go test ./...` or `env -i PATH="$PATH" HOME="$HOME" npm test --workspace packages/<pkg>`.

1. If it now passes, the test depends on the pod's ambient variables. Compare `env | sort` with what the test and its source read (`grep -rn "os.Getenv\|process.env" <test and source files>`), then fix the test so it sets or clears the variables it reads itself. Never fix it by unsetting variables in product code.
2. If it still fails, it is a real failure: debug it as usual.
3. Name in the PR body the variables that made the difference.

## Rules

1. **Reproduce first when feasible.** A failing test that demonstrates the bug is
   worth more than the fix itself — it becomes the regression guard. If you
   cannot reproduce, say so in the PR body and explain your confidence anyway.
2. **Branch**: `night-watch/<fingerprint>`. Commits: conventional
   (`fix: <what> (night-watch <fp>)`). Never push to main. No Co-Authored-By lines.
3. **Smallest correct fix.** No drive-by refactors; the human reviewing at 7 AM
   must be able to grasp the diff in one read.
4. **PR body template** (the trailer line is machine-read — keep it exact):

   ```
   ## Night Watch fix

   **Incident:** <one-line summary>
   **Evidence:** <key log lines / metrics from the briefing>
   **Root cause:** <what was actually wrong>
   **Fix:** <what you changed and why this addresses the root cause>
   **Reproduced:** yes — <how> | no — <why not>
   **Tests:** <suites run + results>

   Night-Watch-Fingerprint: <fp>
   ```

## AUTOMERGE POLICY — current phase: 2 (human merges)

Do NOT run `gh pr merge` in any form. Open the PR and stop.
(Tier rules will be enabled here in Phase 3 — tier 1: arsenal + roundtable
manifests may auto-merge on green; tier 3: operator Go code, workflows, RBAC,
renovate config NEVER auto-merge.)

## Protected paths — never modify, any repo, any tier

- `.github/workflows/**`
- `kubernetes/apps/roundtable/infrastructure/app/*rbac*.yaml`, `*secret*.yaml`
- `.renovate/**`, `renovate.json*`

If the fix genuinely requires one of these, stop and say so in your result —
that escalation is a human decision.

## Afterwards

End your result with: PR URL, fingerprint, repos touched, test results.
The watchman reads Mission results to update the ledger — make them parseable
at a glance.
