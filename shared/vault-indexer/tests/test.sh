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
# a title containing the pipe character, and a scalar (non-list) tags value
cat > "$vault/Notes/pipe-title.md" <<'N'
---
type: note
tags: [piped-tag]
created: 2026-03-22
---
# a | b
N
cat > "$vault/Notes/scalar-tag.md" <<'N'
---
title: Scalar tag note
type: note
tags: scalar-tag
created: 2026-03-23
---
# Scalar
N
# a body after the frontmatter, including a line that is not valid YAML
cat > "$vault/Notes/body-note.md" <<'N'
---
title: Body note
type: note
tags: [indexer-body, kube-body, indexer-body]
created: 2026-03-20
---
# Body
see: this: is not yaml
N
# names that differ only in the characters LIKE treats as wildcards
printf '# underscore\n' > "$vault/Notes/a_b.md"
printf '# letter\n' > "$vault/Notes/aXb.md"
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

# frontmatter tags survive a body that is not valid YAML, duplicates included
out=$(q --tag indexer-body --format paths 2>&1); rc=$?
check "tags from a note with a body are indexed" $([[ $rc -eq 0 && "$out" == *body-note.md* ]]; echo $?)

out=$(q --tag kube-body --format json 2>&1); rc=$?
check "json output carries the body note's tags" $([[ $rc -eq 0 && "$out" == *'"indexer-body"'* && "$out" == *'"kube-body"'* ]]; echo $?)

out=$(q --tag kube-body 2>&1); rc=$?
check "table output shows the body note with its tags" $([[ $rc -eq 0 && "$out" == *body-note.md* && "$out" == *indexer-body* && "$out" == *kube-body* ]]; echo $?)

out=$(q --tag kube-body --format csv 2>&1); rc=$?
check "csv output carries the body note's tags" $([[ $rc -eq 0 && "$out" == *'body-note.md'* && "$out" == *indexer-body* && "$out" == *kube-body* ]]; echo $?)

out=$(q --tag scalar-tag --format paths 2>&1); rc=$?
check "scalar tags value is indexed as one tag" $([[ $rc -eq 0 && "$out" == *scalar-tag.md* ]]; echo $?)

out=$(q --tag piped-tag --format table 2>&1); rc=$?
check "table output keeps a title with a pipe in its column" $([[ $rc -eq 0 && "$out" == *pipe-title.md* && "$out" == *piped-tag* ]]; echo $?)

out=$(q --tag piped-tag --format json 2>&1); rc=$?
check "json output keeps a title with a pipe" $([[ $rc -eq 0 && "$out" == *'"title": "a | b"'* && "$out" == *'"piped-tag"'* ]]; echo $?)

out=$(q --tag piped-tag --format csv 2>&1); rc=$?
check "csv output keeps a title with a pipe" $([[ $rc -eq 0 && "$out" == *'"a | b"'* && "$out" == *piped-tag* ]]; echo $?)

out=$(q --tag piped-tag --format paths 2>&1); rc=$?
check "paths output prints the path of a pipe-title note" $([[ $rc -eq 0 && "$out" == *pipe-title.md* ]]; echo $?)

out=$(r --tag piped-tag --format table 2>&1); rc=$?
check "recent table keeps a title with a pipe" $([[ $rc -eq 0 && "$out" == *"a | b"* ]]; echo $?)

out=$(r --tag piped-tag --format json 2>&1); rc=$?
check "recent json keeps a title with a pipe" $([[ $rc -eq 0 && "$out" == *'"a | b"'* ]]; echo $?)

out=$(q --path "a_b" --format paths 2>&1); rc=$?
check "--path '_' matches only a literal underscore" $([[ $rc -eq 0 && "$out" == *"a_b.md"* && "$out" != *"aXb.md"* ]]; echo $?)

out=$(q --path "%" --format paths 2>&1); rc=$?
check "--path '%' matches only a literal percent sign" $([[ $rc -eq 0 && "$out" == *"No results found"* ]]; echo $?)

# a failing tag lookup must exit 1 with Error:, never show an empty tag column
cp "$db" "$tmp/notags.db"
sqlite3 "$tmp/notags.db" "DROP TABLE tags;" >/dev/null 2>&1
for fmt in table json csv; do
    out=$(bash "$scripts/query-vault.sh" --db "$tmp/notags.db" --format $fmt 2>&1); rc=$?
    check "query $fmt: failed tag lookup exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)
done
out=$(bash "$scripts/recent-notes.sh" --db "$tmp/notags.db" --format json 2>&1); rc=$?
check "recent json: failed tag lookup exits 1 with Error:" $([[ $rc -eq 1 && "$out" == *"Error:"* ]]; echo $?)

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
