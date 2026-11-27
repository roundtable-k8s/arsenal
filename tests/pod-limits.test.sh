#!/usr/bin/env bash
# Pod-limits check: skills that touch the network or the vault say what the pod can and cannot do.
# Usage: bash tests/pod-limits.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
H="What this knight can and cannot do"
check() { # file needle
  grep -q -- "$2" "$1/SKILL.md" || { echo "FAIL: $1/SKILL.md missing: $2"; fail=1; }
}
for d in shared/web-browser watch/telemetry-queries project/github-pm \
         project/briefing-synthesis shared/daily-reports shared/open-items-ledger \
         watch/night-watch-triage shared/vault-indexer; do
  check "$d" "^## $H"
done
for d in project/briefing-synthesis shared/daily-reports shared/open-items-ledger \
         watch/night-watch-triage shared/vault-indexer; do
  check "$d" "writablePaths"
done
# the vault-write sentence must be identical in the five vault skills
VW='The vault is mounted read-only unless the Knight lists the sub-path in `spec.vault.writablePaths` (no default: an absent or empty list means no writable paths); entries are relative to the vault root, and the trailing slash is the convention, not required (e.g. `Agents/Briefings/`, mounted at `/vault/Agents/Briefings`), never absolute `/vault/...` paths, and a write anywhere else fails with `Read-only file system`.'
for d in project/briefing-synthesis shared/daily-reports shared/open-items-ledger \
         watch/night-watch-triage shared/vault-indexer; do
  grep -qF -- "$VW" "$d/SKILL.md" || { echo "FAIL: $d/SKILL.md vault-write sentence differs"; fail=1; }
done
check shared/web-browser allowedHosts
check watch/telemetry-queries allowedServices
check project/github-pm allowedHosts
[ $fail -eq 0 ] && echo "ok: pod limits"
exit $fail
