#!/usr/bin/env bash
# Tests for rt-checks using a gh stub on PATH.
#   bash project/pr-review/tests/rt-checks.test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/rt-checks"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FIX="$work/fix"

# gh stub: pr checks -> $FIX/checks.json (exit 1/8 like gh, or stderr from $FIX/checks.err
# with exit 1); run view -> $FIX/log, or hangs when $FIX/hang exists, or fails with $FIX/nolog.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr checks")
    if [ -e "$FIX/checks.err" ]; then cat "$FIX/checks.err" >&2; exit 1; fi
    cat "$FIX/checks.json"; exit 1 ;;
  "run view")
    echo "$*" > "$FIX/runargs"
    [ -e "$FIX/hang" ] && exec sleep 30
    [ -e "$FIX/nolog" ] && { echo "HTTP 500" >&2; exit 1; }
    cat "$FIX/log" ;;
esac
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

fails=0; n=0
reset() { rm -rf "$FIX"; mkdir -p "$FIX"; }
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }
last() { tail -n 1 <<<"$out"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
U=https://github.com/o/r/pull/7
L=https://github.com/o/r/actions/runs/99/job/5
tok="ghp_$(printf 'A%.0s' {1..30})"

reset; run "$script"; [ $rc -eq 2 ]; check "no args exits 2" $?
reset; run "$script" https://example.com/x; [ $rc -eq 2 ]; check "bad URL exits 2" $?

reset; echo "[{\"name\":\"build\",\"bucket\":\"pass\",\"link\":\"$L\"},{\"name\":\"opt\",\"bucket\":\"skipping\",\"link\":\"\"}]" > "$FIX/checks.json"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: pass" ] && grep -q "^pass.build" <<<"$out" && grep -q "^skipping.opt" <<<"$out"; check "pass" $?

reset; echo "[{\"name\":\"test\",\"bucket\":\"fail\",\"link\":\"$L\"},{\"name\":\"build\",\"bucket\":\"pass\",\"link\":\"$L\"}]" > "$FIX/checks.json"
{ for i in $(seq 1 30); do printf 'test\tRun tests\tline %s\n' "$i"; done; printf 'test\tRun tests\ttoken %s\n' "$tok"; } > "$FIX/log"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: fail" ]; check "fail with log: last line, exit 0" $?
grep -q "failed step: Run tests" <<<"$out"; check "fail with log: step shown" $?
grep -q "\[redacted\]" <<<"$out" && ! grep -q "$tok" <<<"$out"; check "fail with log: token redacted" $?
! grep -q "line 5$" <<<"$out" && grep -q "line 30" <<<"$out"; check "fail with log: tail only" $?
grep -q -- "--job 5" "$FIX/runargs"; check "fail with log: scoped to failed job" $?

reset; echo "[{\"name\":\"test\",\"bucket\":\"fail\",\"link\":\"$L\"}]" > "$FIX/checks.json"; touch "$FIX/nolog"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: fail" ] && grep -q "log unavailable" <<<"$out"; check "fail with unreadable log" $?

reset; echo "[{\"name\":\"test\",\"bucket\":\"fail\",\"link\":\"$L\"}]" > "$FIX/checks.json"; touch "$FIX/hang"
start=$SECONDS; RT_CHECKS_LOG_TIMEOUT=1 run "$script" $U
[ $rc -eq 0 ] && grep -q "log unavailable" <<<"$out" && [ $((SECONDS-start)) -lt 10 ]; check "hanging log is cut at the timeout" $?

reset; echo "[{\"name\":\"build\",\"bucket\":\"pass\",\"link\":\"$L\"},{\"name\":\"lint\",\"bucket\":\"pending\",\"link\":\"$L\"}]" > "$FIX/checks.json"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: pending" ]; check "pending" $?

reset; echo '[]' > "$FIX/checks.json"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: none" ]; check "none" $?

reset; echo "no required checks reported on the 'x' branch" > "$FIX/checks.err"
run "$script" $U; [ $rc -eq 0 ] && [ "$(last)" = "rt-checks: none" ]; check "none (gh says no required checks)" $?

reset; echo "dial tcp: lookup api.github.com: no such host" > "$FIX/checks.err"
run "$script" $U; [ $rc -eq 1 ] && grep -q "no such host" <<<"$out"; check "unreachable GitHub exits 1 with gh stderr" $?

echo "$((n-fails))/$n passed"; [ $fails -eq 0 ]
