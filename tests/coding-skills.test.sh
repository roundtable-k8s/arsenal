#!/usr/bin/env bash
# Coding skills check: each dev-knight skill that runs the repo's tests in a
# knight pod must say how to tell a pod-only (ambient environment) failure apart
# from a real one: the heading and a clean-environment `env -i` command.
# Usage: bash tests/coding-skills.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
for f in coding/roundtable-operator/SKILL.md coding/pi-knight-runtime/SKILL.md \
         coding/roundtable-ui/SKILL.md coding/night-watch-fix/SKILL.md; do
  if [ ! -f "$f" ]; then
    echo "FAIL: $f missing"; fail=1; continue
  fi
  grep -q '^## If a test fails only in the pod$' "$f" \
    || { echo "FAIL: $f lacks the heading \"If a test fails only in the pod\""; fail=1; }
  grep -q 'env -i' "$f" \
    || { echo "FAIL: $f lacks the clean-environment command (env -i)"; fail=1; }
done
[ $fail -eq 0 ] && echo "ok: coding skills"
exit $fail
