#!/usr/bin/env bash
# Tests for search.sh. No external network: a python3 stub server on 127.0.0.1
# (random port) answers each case, chosen by the first path segment of SEARXNG_URL;
# the unreachable case points at a localhost port nothing listens on.
#   bash shared/web-search/tests/test.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
search="$here/../scripts/search.sh"

tmp=$(mktemp -d)
stub_pid=""
trap '[ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import http.server

BODIES = {
    "two": (200, '{"results":[{"url":"http://a","title":"Alpha","content":"first"},'
                 '{"url":"http://b","title":"Beta","content":"second"}]}'),
    "quote": (200, r'{"results":[{"url":"http://a","title":"Say \"hi\" now","content":"x"}]}'),
    "nocontent": (200, '{"results":[{"url":"http://a","title":"No content"},'
                       '{"url":"http://b","title":"Second","content":"b"}]}'),
    "tfirst": (200, '{"results":[{"title":"Alpha","url":"http://a","content":"first"}]}'),
    "empty": (200, '{"results":[]}'),
    "503": (503, '{"error":"busy"}'),
    "blank": (200, ""),
    "html": (200, "<html>proxy login</html>"),
}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        mode = self.path.lstrip("/").split("/")[0]
        code, body = BODIES.get(mode, (404, ""))
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
PY

python3 "$tmp/stub.py" > "$tmp/port" 2>/dev/null &
stub_pid=$!
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
base="http://127.0.0.1:$(cat "$tmp/port")"

dead=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')

# A PATH holding every tool except jq (symlinks in a shim dir), to exercise the grep fallback.
nojq="$tmp/nojq-bin"; mkdir "$nojq"
( IFS=:; for d in $PATH; do for f in "$d"/*; do
    name=${f##*/}
    [ "$name" != jq ] && [ -x "$f" ] && [ ! -e "$nojq/$name" ] && ln -s "$f" "$nojq/$name"
  done; done )
bash_bin=$(command -v bash)

fails=0; n=0
check() { n=$((n+1)); if [ "$2" -eq 0 ]; then echo "ok $n - $1"; else echo "not ok $n - $1"; fails=$((fails+1)); fi; }

# run MODE QUERY [COUNT] sets rc and out
run() { out=$(SEARXNG_URL="$base/$1" bash "$search" "$2" ${3:+"$3"} 2>&1); rc=$?; }

out=$(bash "$search" 2>&1); rc=$?
check "missing query exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "missing query prints usage" $([[ "$out" == *"Usage: search.sh"* ]]; echo $?)

out=$(SEARXNG_URL="http://127.0.0.1:$dead" bash "$search" "hello world"); rc=$?
check "refused exits 1" $([ "$rc" -eq 1 ]; echo $?)
check "refused is one ERROR line naming cause" $([[ "$out" == "ERROR: SearXNG unreachable at http://127.0.0.1:$dead: connection refused"* && "$(echo "$out" | wc -l)" -eq 1 ]]; echo $?)
check "refused mentions egress" $([[ "$out" == *"spec.egress.allowedHosts"* ]]; echo $?)
check "refused appends curl's error text in [detail]" $([[ "$out" == *"[curl: (7)"*"]" ]]; echo $?)

run two "hello world"
expect=$'---\nTitle: Alpha\nURL: http://a\nSnippet: first\n---\nTitle: Beta\nURL: http://b\nSnippet: second'
check "two results print in order with title, url, snippet" $([ "$rc" -eq 0 ] && [ "$out" == "$expect" ]; echo $?)

run two "hello world" 1
expect=$'---\nTitle: Alpha\nURL: http://a\nSnippet: first'
check "count argument limits results" $([ "$rc" -eq 0 ] && [ "$out" == "$expect" ]; echo $?)

run quote "q"
expect=$'---\nTitle: Say "hi" now\nURL: http://a\nSnippet: x'
check "escaped quote in title prints as a quote" $([ "$rc" -eq 0 ] && [ "$out" == "$expect" ]; echo $?)

run nocontent "q"
expect=$'---\nTitle: No content\nURL: http://a\nSnippet: \n---\nTitle: Second\nURL: http://b\nSnippet: b'
check "missing content does not shift the next result" $([ "$rc" -eq 0 ] && [ "$out" == "$expect" ]; echo $?)

run empty "nothing here"
check "empty list prints No results and exits 0" $([ "$rc" -eq 0 ] && [ "$out" == 'No results for "nothing here"' ]; echo $?)

run 503 "q"
check "HTTP 503 is reported as HTTP error, exit 1" $([ "$rc" -eq 1 ] && [ "$out" == "ERROR: SearXNG at $base/503 returned HTTP 503" ]; echo $?)

run blank "q"
check "empty 200 body is reported as empty response, exit 1" $([ "$rc" -eq 1 ] && [ "$out" == "ERROR: SearXNG at $base/blank returned an empty response" ]; echo $?)

run html "q"
check "non-JSON 200 body is reported as invalid JSON, exit 1" $([ "$rc" -eq 1 ] && [ "$out" == "ERROR: SearXNG at $base/html returned invalid JSON" ]; echo $?)

if PATH="$nojq" command -v jq >/dev/null 2>&1; then
  echo "skip - no-jq fallback (jq is still on PATH)"
else
  out=$(PATH="$nojq" SEARXNG_URL="$base/tfirst" "$bash_bin" "$search" "q" 2>&1); rc=$?
  expect=$'---\nTitle: Alpha\nURL: http://a\nSnippet: first'
  check "no-jq fallback parses a result" $([ "$rc" -eq 0 ] && [ "$out" == "$expect" ]; echo $?)

  out=$(PATH="$nojq" SEARXNG_URL="$base/empty" "$bash_bin" "$search" "q" 2>&1); rc=$?
  check "no-jq fallback prints No results for empty list" $([ "$rc" -eq 0 ] && [ "$out" == 'No results for "q"' ]; echo $?)

  out=$(PATH="$nojq" SEARXNG_URL="$base/503" "$bash_bin" "$search" "q" 2>&1); rc=$?
  check "no-jq fallback reports HTTP 503" $([ "$rc" -eq 1 ] && [ "$out" == "ERROR: SearXNG at $base/503 returned HTTP 503" ]; echo $?)
fi

echo "$n tests, $fails failed"; [ "$fails" -eq 0 ]
