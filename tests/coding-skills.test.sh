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
# Each dev-knight skill must say, once, how to finish inside the turn: push early,
# run the full suite once, and never end a turn with background work.
for f in coding/coding-agent.md coding/night-watch-fix/SKILL.md \
         coding/roundtable-operator/SKILL.md coding/roundtable-ui/SKILL.md \
         coding/pi-knight-runtime/SKILL.md coding/roundtable-arsenal/SKILL.md; do
  if [ ! -f "$f" ]; then
    echo "FAIL: $f missing"; fail=1; continue
  fi
  n=$(grep -c '^## Finish inside the turn$' "$f")
  [ "$n" -eq 1 ] || { echo "FAIL: $f has $n \"Finish inside the turn\" headings, want 1"; fail=1; }
  grep -q 'Never end a turn while a command you started in the background' "$f" \
    || { echo "FAIL: $f lacks the background-command rule"; fail=1; }
done
[ $fail -eq 0 ] && echo "ok: coding skills"
exit $fail
