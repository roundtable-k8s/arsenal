#!/usr/bin/env bash
# Layout check: every skill dir is in README's tree, and every path-like
# reference (scripts/, references/, assets/) in a SKILL.md exists in that skill.
# Usage: bash tests/layout.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
for f in shared/*/SKILL.md project/*/SKILL.md watch/*/SKILL.md coding/*/SKILL.md; do
  dir=$(dirname "$f"); cat=${dir%%/*}; name=${dir#*/}
  # tree lines look like "│   ├── name/ ..." under the category block
  if ! awk -v c="$cat/" -v n="$name/" '
      $0 ~ "^(├|└)── " c {inc=1; next}
      /^(├|└)── / {inc=0}
      inc && index($0, "── " n) {found=1}
      END {exit !found}' README.md; then
    echo "FAIL: $dir not listed in README.md tree"; fail=1
  fi
  while read -r ref; do
    ref=${ref%%[\`\)\]\"\',.:;]}
    [ -e "$dir/$ref" ] || { echo "FAIL: $f references missing $ref"; fail=1; }
  done < <(awk '/^```/{c=!c; next} !c' "$f" | grep -oE '(^|[^A-Za-z0-9_./<-])(scripts|references|assets)/[A-Za-z0-9_./-]+' | sed -E 's/^[^sra]*//' | sort -u)
done
[ $fail -eq 0 ] && echo "ok: layout" 
exit $fail
