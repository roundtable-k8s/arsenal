#!/usr/bin/env bash
# Tests for the vault-indexer scripts: builds a throwaway vault, indexes it, then
# checks query-vault.sh and recent-notes.sh. Skips (exit 0) without sqlite3 or yq.
#   bash shared/vault-indexer/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/../scripts"

for tool in sqlite3 yq python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: $tool not found (vault-indexer needs sqlite3 and yq, e.g. via spec.tools.nix)"
        exit 0
    fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
vault="$tmp/vault"; db="$tmp/t.db"
mkdir -p "$vault/Briefings/Daily" "$vault/Notes/o'brien"

cat > "$vault/Briefings/Daily/2026-03-01.md" <<'N'
---
title: March first
type: briefing
tags: [security, kubernetes]
created: 2026-03-01
---
# Daily briefing one
N
cat > "$vault/Briefings/Daily/2026-04-01.md" <<'N'
---
title: April first
type: briefing
tags: [security]
created: 2026-04-01
---
# Daily briefing two
N
cat > "$vault/Notes/o'brien/person.md" <<'N'
---
title: Person note
type: note
tags: ["o'brien"]
created: 2026-03-15
---
# Person
N
printf '# no frontmatter\n' > "$vault/Notes/plain.md"
# --since/--until match created OR modified, so pin mtimes to the created dates
touch -d 2026-03-01 "$vault/Briefings/Daily/2026-03-01.md"
touch -d 2026-04-01 "$vault/Briefings/Daily/2026-04-01.md"
touch -d 2026-03-15 "$vault/Notes/o'brien/person.md"

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

idx_out=$(VAULT_INDEX_DB="$db" bash "$scripts/index-vault.sh" --vault "$vault" --db "$db" 2>&1); rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$db" ]; then
    echo "not ok - index-vault.sh failed (rc=$rc): $idx_out"; exit 1
fi

q() { bash "$scripts/query-vault.sh" --db "$db" "$@"; }
r() { bash "$scripts/recent-notes.sh" --db "$db" "$@"; }

out=$(q --tag security --format paths 2>&1); rc=$?
check "query tag returns both security notes" $([[ $rc -eq 0 && $(echo "$out" | wc -l) -eq 2 ]]; echo $?)

out=$(q --tag "o'brien" --format paths 2>&1); rc=$?
check "query apostrophe tag finds the note" $([[ $rc -eq 0 && "$out" == *person.md* ]]; echo $?)

out=$(q --path "o'brien" --format paths 2>&1); rc=$?
check "query apostrophe path finds the note" $([[ $rc -eq 0 && "$out" == *person.md* ]]; echo $?)

out=$(q --path "Briefings/Daily" --format paths 2>&1); rc=$?
check "query path matches two briefings" $([[ $rc -eq 0 && $(echo "$out" | wc -l) -eq 2 ]]; echo $?)

out=$(q --tag "x' OR '1'='1" --format paths 2>&1); rc=$?
check "injection attempt matches nothing, exit 0" $([[ $rc -eq 0 && "$out" == *"No results found"* ]]; echo $?)

out=$(q --tag nonexistent --format paths 2>&1); rc=$?
check "empty result says No results found, exit 0" $([[ $rc -eq 0 && "$out" == *"No results found"* ]]; echo $?)

out=$(q --since 2026-04-01 --format paths 2>&1)
check "query --since keeps only April" $([[ "$out" == *2026-04-01.md* && "$out" != *2026-03-01.md* ]]; echo $?)

out=$(q --until 2026-03-02 --path Daily --format paths 2>&1)
check "query --until keeps only March" $([[ "$out" == *2026-03-01.md* && "$out" != *2026-04-01.md* ]]; echo $?)

out=$(q --tag security --path Daily --since 2026-03-01 --format paths 2>&1); rc=$?
check "combined filters are ANDed (valid SQL)" $([[ $rc -eq 0 && $(echo "$out" | wc -l) -eq 2 ]]; echo $?)

out=$(q --sort size --order asc --limit 1 --format paths 2>&1); rc=$?
check "valid sort/order/limit accepted" $([[ $rc -eq 0 ]]; echo $?)

out=$(q --sort bogus 2>&1); rc=$?
check "bad --sort exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

out=$(q --order sideways 2>&1); rc=$?
check "bad --order exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

out=$(q --limit abc 2>&1); rc=$?
check "bad --limit exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

out=$(q --days abc 2>&1); rc=$?
check "bad --days exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

out=$(bash "$scripts/query-vault.sh" --db "$tmp/missing.db" 2>&1); rc=$?
check "query missing db exits 1" $([[ $rc -eq 1 && "$out" == *"Database not found"* ]]; echo $?)

out=$(r --tag "o'brien" --format paths 2>&1); rc=$?
check "recent apostrophe tag finds the note" $([[ $rc -eq 0 && "$out" == *person.md* ]]; echo $?)

out=$(r --path "o'brien" --format paths 2>&1); rc=$?
check "recent apostrophe path finds the note" $([[ $rc -eq 0 && "$out" == *person.md* ]]; echo $?)

out=$(r --tag security --limit 1 --format paths 2>&1)
check "recent --limit 1 returns one note" $([[ $(echo "$out" | wc -l) -eq 1 ]]; echo $?)

out=$(r --since 2999-01-01 --format paths 2>&1); rc=$?
check "recent --since future: No results found, exit 0" $([[ $rc -eq 0 && "$out" == *"No results found"* ]]; echo $?)

out=$(r --limit abc 2>&1); rc=$?
check "recent bad --limit exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

out=$(bash "$scripts/recent-notes.sh" --db "$tmp/missing.db" 2>&1); rc=$?
check "recent missing db exits 1" $([[ $rc -eq 1 && "$out" == *"Database not found"* ]]; echo $?)

# corrupt and wrong-schema databases must fail, not say "No results found"
echo "this is not a database" > "$tmp/corrupt.db"
sqlite3 "$tmp/wrong.db" "CREATE TABLE other(x INTEGER);" >/dev/null 2>&1
for bad in corrupt wrong; do
    out=$(bash "$scripts/query-vault.sh" --db "$tmp/$bad.db" 2>&1); rc=$?
    check "query $bad db exits 1, no 'No results'" $([[ $rc -eq 1 && "$out" == *"Error:"* && "$out" != *"No results"* ]]; echo $?)
    out=$(bash "$scripts/recent-notes.sh" --db "$tmp/$bad.db" 2>&1); rc=$?
    check "recent $bad db exits 1, no 'No results'" $([[ $rc -eq 1 && "$out" == *"Error:"* && "$out" != *"No results"* ]]; echo $?)
done

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
