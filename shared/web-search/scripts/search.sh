#!/usr/bin/env bash
# Web search via SearXNG — no API key needed
# Usage: search.sh "query" [count]
set -euo pipefail

QUERY="${1:?Usage: search.sh \"query\" [count]}"
COUNT="${2:-5}"
SEARXNG_URL="${SEARXNG_URL:-http://searxng.selfhosted.svc.cluster.local:8080}"

ENCODED_QUERY=$(printf '%s' "$QUERY" | sed 's/ /+/g; s/[^a-zA-Z0-9+._-]/%&/g')

ERRFILE=$(mktemp); trap 'rm -f "$ERRFILE"' EXIT
rc=0
RESPONSE=$(curl -sf --max-time 15 "${SEARXNG_URL}/search?q=${ENCODED_QUERY}&format=json" 2>"$ERRFILE") || rc=$?

if [ "$rc" -ne 0 ] || [ -z "$RESPONSE" ]; then
  detail=$(tr '\n' ' ' < "$ERRFILE" | sed 's/ *$//')
  case "$rc" in
    6)  why="DNS lookup failed" ;;
    7)  why="connection refused" ;;
    22) why="HTTP error from SearXNG" ;;
    28) why="timed out" ;;
    *)  why="curl exit $rc" ;;
  esac
  hint=""
  case "$rc" in
    6|7|28) hint=" (blocked by the knight's egress policy? add the host to spec.egress.allowedHosts or allowedServices)" ;;
  esac
  echo "ERROR: SearXNG unreachable at ${SEARXNG_URL}: ${why}${hint}${detail:+ [${detail}]}"
  exit 1
fi

# Parse results without jq — extract title, url, content triplets
echo "$RESPONSE" | grep -oP '"title"\s*:\s*"[^"]*"|"url"\s*:\s*"[^"]*"|"content"\s*:\s*"[^"]*"' \
  | paste - - - \
  | head -n "$COUNT" \
  | while IFS=$'\t' read -r title url content; do
    t=$(echo "$title" | sed 's/.*"title"\s*:\s*"//;s/"$//')
    u=$(echo "$url" | sed 's/.*"url"\s*:\s*"//;s/"$//')
    c=$(echo "$content" | sed 's/.*"content"\s*:\s*"//;s/"$//')
    echo "---"
    echo "Title: $t"
    echo "URL: $u"
    echo "Snippet: $c"
  done
