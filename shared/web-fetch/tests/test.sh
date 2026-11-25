#!/usr/bin/env bash
# Tests for fetch.sh using a local python http.server.
#   bash shared/web-fetch/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fetch="$here/../scripts/fetch.sh"
work="$(mktemp -d)"; trap 'kill "${srv:-0}" 2>/dev/null; rm -rf "$work"' EXIT
echo '<html><body><p>hello fetch</p></body></html>' > "$work/index.html"

port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
(cd "$work" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) & srv=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.1; done
dead=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

out=$(bash "$fetch" "http://127.0.0.1:$port/index.html"); rc=$?
check "success exits 0" $([ "$rc" -eq 0 ]; echo $?)
check "success prints text" $([[ "$out" == *"hello fetch"* ]]; echo $?)

out=$(bash "$fetch" "http://127.0.0.1:$port/missing.html"); rc=$?
check "404 exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "404 prints status" $([ "$out" = "ERROR: http://127.0.0.1:$port/missing.html: HTTP 404" ]; echo $?)

out=$(bash "$fetch" "http://127.0.0.1:$dead/"); rc=$?
check "refused exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "refused is one ERROR line naming cause" $([[ "$out" == "ERROR: http://127.0.0.1:$dead/: connection refused"* && "$(echo "$out" | wc -l)" -eq 1 ]]; echo $?)
check "refused mentions egress" $([[ "$out" == *"spec.egress.allowedHosts"* ]]; echo $?)

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
