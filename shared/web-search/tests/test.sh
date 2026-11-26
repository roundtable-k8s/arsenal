#!/usr/bin/env bash
# Tests for search.sh: argument handling and the error path. No external network:
# the unreachable case points SEARXNG_URL at a localhost port nothing listens on.
#   bash shared/web-search/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
search="$here/../scripts/search.sh"

dead=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

out=$(bash "$search" 2>&1); rc=$?
check "missing query exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "missing query prints usage" $([[ "$out" == *"Usage: search.sh"* ]]; echo $?)

out=$(SEARXNG_URL="http://127.0.0.1:$dead" bash "$search" "hello world"); rc=$?
check "refused exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "refused is one ERROR line naming cause" $([[ "$out" == "ERROR: SearXNG unreachable at http://127.0.0.1:$dead: connection refused"* && "$(echo "$out" | wc -l)" -eq 1 ]]; echo $?)
check "refused mentions egress" $([[ "$out" == *"spec.egress.allowedHosts"* ]]; echo $?)
check "refused appends curl's error text in [detail]" $([[ "$out" == *"[curl: (7)"*"]" ]]; echo $?)

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
