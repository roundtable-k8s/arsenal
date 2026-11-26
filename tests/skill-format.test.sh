#!/usr/bin/env bash
# Skill format check: every SKILL.md under shared, project, watch and coding has
# frontmatter whose name equals its directory and whose description says when to
# use the skill. The four skills whose descriptions once lacked a trigger must
# also have a "When to use" (or "use when") wording in the body.
# Usage: bash tests/skill-format.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
problem() { echo "FAIL: $1"; fail=1; }

# Skills that must say when to use them in the body, not only in the description.
body_required=" project/briefing-synthesis project/github-pm shared/evidence-verification shared/open-items-ledger "

while IFS= read -r f; do
  dir=$(dirname "$f")
  dir_name=${dir##*/}

  if [ "$(head -n 1 "$f")" != "---" ] || ! awk 'NR>1 && /^---$/ {found=1; exit} END {exit !found}' "$f"; then
    problem "$f: no YAML frontmatter"
    continue
  fi

  name=$(awk 'NR==1 {next} /^---$/ {exit} /^name:/ {sub(/^name: */, ""); print; exit}' "$f")
  if [ "$name" != "$dir_name" ]; then
    problem "$f: name '$name' does not match directory '$dir_name'"
  fi

  # The description may be a folded block (description: >) spanning indented lines.
  desc=$(awk '
    NR==1 {next}
    /^---$/ {exit}
    /^description:/ {sub(/^description: */, ""); if ($0 != ">") printf "%s ", $0; indesc=1; next}
    /^[^ ]/ {indesc=0}
    indesc {sub(/^ +/, ""); printf "%s ", $0}
  ' "$f")
  if [ -z "${desc//[[:space:]]/}" ]; then
    problem "$f: description is empty"
  elif ! grep -qiwE 'use|when' <<<"$desc"; then
    problem "$f: description does not say when to use it (no 'Use' or 'when')"
  fi

  if [[ "$body_required" == *" $dir "* ]]; then
    body=$(awk 'c>=2 {print} /^---$/ {c++}' "$f")
    if ! grep -qiE 'when to use|use when' <<<"$body"; then
      problem "$f: body has no 'When to use' section"
    fi
  fi
done < <(find shared project watch coding -mindepth 2 -maxdepth 2 -name SKILL.md | sort)

[ $fail -eq 0 ] && echo "ok: skill format"
exit $fail
