#!/usr/bin/env bash
# Tests for scripts/dispatch and scripts/alert using gh and curl stubs on PATH.
#   bash project/orchestrator/tests/dispatch.test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dispatch="$here/../scripts/dispatch"
alert="$here/../scripts/alert"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix" LOG="$work/log"

# gh stub: pr view <url> -> $FIX/pr-<num>.json; $FIX/fail-gh fails it.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
[ -e "$FIX/fail-gh" ] && { echo "HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr view") n="${3##*/}"; cat "$FIX/pr-$n.json" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
STUB
# curl stub: logs its arguments, the headers of any -H @file and the body.
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
prev=""
for a in "$@"; do
  if [ "$prev" = -H ] && [ "${a:0:1}" = @ ]; then sed 's/^/header /' "${a:1}" >> "$LOG"; fi
  prev="$a"
done
echo "body $(cat)" >> "$LOG"
[ -e "$FIX/fail-curl" ] && { echo "curl: (22) The requested URL returned error: 500" >&2; exit 22; }
exit 0
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
unset ORCHESTRATOR_STATE_DIR ORCHESTRATOR_CONFIG ORCHESTRATOR_NOW NTFY_URL NTFY_TOPIC NTFY_TOKEN NTFY_TITLE

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; echo "$out" | sed 's/^/#   /'; fails=$((fails+1)); fi; }
logged() { grep -qF -- "$1" "$LOG"; }
cfg="$work/config.json"
cat > "$cfg" <<'JSON'
{"repos": ["o/r", "o/s"], "leadKnight": "lead-knight",
 "knights": {"o/r": "coder-knight", "*": "other-knight"}}
JSON
LG="$work/state/dispatch.json"
U=https://github.com/o/r/pull
SHA=1234567890abcdef1234567890abcdef12345678
reset() { rm -rf "$FIX" "$LOG" "$work/state"; mkdir -p "$FIX" "$work/state"; : > "$LOG"; export ORCHESTRATOR_NOW=1767225600; }
pr() { jq -nc --arg s "${2:-OPEN}" --arg h "${3:-$SHA}" '{state: $s, headRefOid: $h}' > "$FIX/pr-$1.json"; }
run() { out="$("$dispatch" --config "$cfg" --ledger "$LG" "$@" 2>&1)"; rc=$?; }
field() { jq -r "$1" <<<"$out"; }

# ---- usage ----
reset; run; [ $rc -eq 2 ]; check "dispatch: no args exits 2" $?
reset; run nudge $U/1; [ $rc -eq 2 ]; check "dispatch: unknown kind exits 2" $?
reset; run review https://example.com/x; [ $rc -eq 2 ] && grep -q "expected a PR URL" <<<"$out"; check "dispatch: bad URL exits 2" $?
reset; out="$("$dispatch" --config "$cfg" --collect 2>&1)"; rc=$?
[ $rc -eq 2 ] && grep -q ORCHESTRATOR_STATE_DIR <<<"$out"; check "dispatch: no ledger or state dir is a usage error" $?
reset; pr 1; out="$(ORCHESTRATOR_STATE_DIR="$work/state" "$dispatch" --config "$cfg" review $U/1 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -s "$LG" ]; check "dispatch: ledger defaults to \$ORCHESTRATOR_STATE_DIR/dispatch.json" $?

# ---- review / re-review / fix ----
reset; pr 1; run review $U/1
[ $rc -eq 0 ] && [ "$(wc -l <<<"$out")" = 1 ]; check "review: one output line" $?
[ "$(field .knight)" = lead-knight ]; check "review: goes to leadKnight" $?
[ "$(field .taskId)" = "review-r-1-1234567-1767225600" ]; check "review: task id kind-repo-num-sha-time" $?
t="$(field .task)"
[[ "$t" == "Review $U/1 (head 1234567) with the pr-review skill:"* ]] && grep -q rt-review <<<"$t" && grep -q "Do not push" <<<"$t"; check "review: standard task text" $?
jq -e --arg u "$U/1" --arg s "$SHA" '.entries | length == 1 and .[0].kind == "review" and .[0].pr == $u
  and .[0].repo == "o/r" and .[0].number == 1 and .[0].sha == $s and .[0].knight == "lead-knight"
  and .[0].at == "2026-01-01T00:00:00Z" and .[0].result == null and .[0].taskId == "review-r-1-1234567-1767225600"' "$LG" >/dev/null
check "review: ledger entry has id, kind, PR, head SHA, knight, time" $?

reset; pr 1; run re-review $U/1
[ $rc -eq 0 ] && [ "$(field .knight)" = lead-knight ] && [[ "$(field .task)" == "Re-review $U/1 (head 1234567)"* ]] \
  && grep -q "previous review" <<<"$(field .task)"; check "re-review: lead knight, re-review text" $?

reset; pr 1; run fix $U/1
[ $rc -eq 0 ] && [ "$(field .knight)" = coder-knight ]; check "fix: goes to the repo's knight" $?
t="$(field .task)"
[[ "$t" == "Address the review on $U/1 (head 1234567)"* ]] && grep -q "Do not queue" <<<"$t" && grep -q push <<<"$t"; check "fix: standard task text" $?
reset; pr 3; run fix https://github.com/o/s/pull/3
[ $rc -eq 0 ] && [ "$(field .knight)" = other-knight ]; check "fix: falls back to the \"*\" knight" $?
reset; pr 1; jq '.knights = {}' "$cfg" > "$work/nok.json"
out="$("$dispatch" --config "$work/nok.json" --ledger "$LG" fix $U/1 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "no knight for o/r" <<<"$out" && [ ! -e "$LG" ]; check "fix: no knight configured is refused, nothing recorded" $?
reset; pr 1; jq 'del(.leadKnight)' "$cfg" > "$work/nolead.json"
out="$("$dispatch" --config "$work/nolead.json" --ledger "$LG" review $U/1 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "no leadKnight" <<<"$out"; check "review: no leadKnight is refused" $?

reset; pr 1; run fix $U/1 --note "keep the old flag name"
[ $rc -eq 0 ] && [[ "$(field .task)" == *"Note from the orchestrator: keep the old flag name" ]] \
  && jq -e '.entries[0].note == "keep the old flag name"' "$LG" >/dev/null; check "--note is appended and recorded" $?

reset; pr 1 MERGED; run review $U/1
[ $rc -eq 1 ] && grep -q "is MERGED, not open" <<<"$out" && [ ! -e "$LG" ]; check "closed or merged PR is refused" $?
reset; touch "$FIX/fail-gh"; run review $U/1
[ $rc -eq 1 ] && grep -q "could not read $U/1" <<<"$out"; check "gh failure is reported" $?

# ---- duplicate refusal ----
reset; pr 1; run review $U/1; first="$(field .taskId)"
run review $U/1
[ $rc -eq 1 ] && grep -q "already sent (task $first)" <<<"$out" && grep -q -- --force <<<"$out"; check "duplicate: same kind, same head is refused" $?
[ "$(jq '.entries | length' "$LG")" = 1 ]; check "duplicate: refusal records nothing" $?
run fix $U/1; [ $rc -eq 0 ]; check "duplicate: another kind on the same head is allowed" $?
pr 1 OPEN abcdef0000000000000000000000000000000000; run review $U/1
[ $rc -eq 0 ] && [ "$(field .taskId)" = "review-r-1-abcdef0-1767225600" ]; check "duplicate: same kind on a new head is allowed" $?
pr 1; run review $U/1 --force
[ $rc -eq 0 ] && [ "$(field .taskId)" = "$first-2" ] && [ "$(jq '.entries | length' "$LG")" = 4 ]; check "duplicate: --force sends again with a unique id" $?

# ---- record / collect ----
reset; run --collect; [ $rc -eq 0 ] && [ "$out" = "dispatch: no dispatches recorded" ]; check "collect: empty ledger says so" $?
pr 1; pr 2; run review $U/1; id1="$(field .taskId)"
ORCHESTRATOR_NOW=1767229200; run fix $U/2; id2="$(field .taskId)"
ORCHESTRATOR_NOW=1767236400
tok="gh""p_$(printf 'Q%.0s' $(seq 1 36))"  # fake token, assembled so no literal token is in the source
printf '\n  %s ship it\nbecause tests pass, token %s\n' "$U/1" "$tok" > "$work/reply.txt"
run --record "$id1" "$work/reply.txt"
[ $rc -eq 0 ] && [ "$out" = "dispatch: recorded result for $id1" ]; check "record: stores the reply" $?
jq -e --arg id "$id1" '.entries[] | select(.taskId == $id) | .resultAt == "2026-01-01T03:00:00Z" and (.result | contains("ship it"))' "$LG" >/dev/null
check "record: result and time in the ledger" $?
! grep -q "$tok" "$LG"; check "record: token-like strings are redacted" $?
run --record nope "$work/reply.txt"; [ $rc -eq 1 ] && grep -q "no ledger entry" <<<"$out"; check "record: unknown task id is refused" $?
run --record "$id2" "$work/missing.txt"; [ $rc -eq 1 ] && grep -q "not found" <<<"$out"; check "record: missing file is refused" $?
run --collect
[ $rc -eq 0 ] && [ "$(wc -l <<<"$out")" = 2 ]; check "collect: one line per entry" $?
[ "$(sed -n 1p <<<"$out")" = "review $U/1 3h $U/1 ship it" ]; check "collect: kind, PR, age, first line of the result" $?
[ "$(sed -n 2p <<<"$out")" = "fix $U/2 2h pending" ]; check "collect: pending when no result" $?
: > "$LOG"; run --collect; [ ! -s "$LOG" ]; check "collect: no GitHub calls" $?
echo '[]' > "$LG"; run --collect; [ $rc -eq 2 ] && grep -q "fix or remove it" <<<"$out"; check "corrupt ledger is a clear error" $?

# ---- alert ----
reset; out="$("$alert" "PR stuck" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "alert: NTFY_URL/NTFY_TOPIC not set, not sent" ] && [ ! -s "$LOG" ]; check "alert: skipped with one line when env is unset" $?
reset; out="$(NTFY_URL=https://ntfy.test "$alert" "PR stuck" 2>&1)"; rc=$?
[ $rc -eq 0 ] && grep -q "not set, not sent" <<<"$out" && [ ! -s "$LOG" ]; check "alert: skipped when only the topic is unset" $?
reset; out="$(NTFY_URL=https://ntfy.test/ NTFY_TOPIC=rt-owner "$alert" o/r#7 blocked: needs a token 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "alert: sent to topic rt-owner" ]; check "alert: sent, one line" $?
logged "-X POST" && logged "https://ntfy.test/rt-owner" && logged "body o/r#7 blocked: needs a token" && logged "header Title: "; check "alert: POSTs the message to \$NTFY_URL/\$NTFY_TOPIC" $?
! logged "Authorization"; check "alert: no auth header without a token" $?
reset; secret="tk_$(printf 'S%.0s' $(seq 1 24))"
out="$(NTFY_URL=https://ntfy.test NTFY_TOPIC=t NTFY_TOKEN="$secret" "$alert" hi 2>&1)"; rc=$?
[ $rc -eq 0 ] && logged "header Authorization: Bearer $secret"; check "alert: token sent as a Bearer header" $?
! grep -q "$secret" <<<"$out" && ! grep "^curl " "$LOG" | grep -q "$secret"; check "alert: token never printed nor on the command line" $?
reset; out="$(echo "from stdin" | NTFY_URL=https://ntfy.test NTFY_TOPIC=t "$alert" - 2>&1)"; rc=$?
[ $rc -eq 0 ] && logged "body from stdin"; check "alert: '-' reads the message from stdin" $?
reset; touch "$FIX/fail-curl"; out="$(NTFY_URL=https://ntfy.test NTFY_TOPIC=t NTFY_TOKEN="$secret" "$alert" hi 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "not sent to topic t (curl exit 22)" <<<"$out" && ! grep -q "$secret" <<<"$out"; check "alert: failed post exits 1 without the token" $?
reset; out="$("$alert" 2>&1)"; rc=$?; [ $rc -eq 2 ]; check "alert: no message exits 2" $?

echo "1..$n"
[ $fails -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
