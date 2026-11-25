#!/usr/bin/env bash
# Fetch and extract text from a URL
# Usage: fetch.sh "url" [max_chars]
set -euo pipefail

URL="${1:?Usage: fetch.sh \"url\" [max_chars]}"
MAX_CHARS="${2:-10000}"

ERRFILE=$(mktemp); trap 'rm -f "$ERRFILE"' EXIT

rc=0
OUT=$(curl -sL -A "Mozilla/5.0 (compatible; Knight-Agent/1.0)" \
  --max-time 15 -w $'\n%{http_code}' \
  "$URL" 2>"$ERRFILE") || rc=$?

if [ "$rc" -ne 0 ]; then
  case "$rc" in
    6)  why="DNS lookup failed" ;;
    7)  why="connection refused" ;;
    28) why="timed out" ;;
    35|60) why="TLS error" ;;
    *)  why="curl exit $rc" ;;
  esac
  detail=$(tr '\n' ' ' < "$ERRFILE" | sed 's/ *$//')
  hint=""
  case "$rc" in
    6|7|28) hint=" (blocked by the knight's egress policy? add the host to spec.egress.allowedHosts)" ;;
  esac
  echo "ERROR: ${URL}: ${why}${hint}${detail:+ [${detail}]}"
  exit 1
fi

STATUS="${OUT##*$'\n'}"
CONTENT="${OUT%$'\n'*}"

if [ "$STATUS" -ge 400 ] 2>/dev/null; then
  echo "ERROR: ${URL}: HTTP ${STATUS}"
  exit 1
fi

if [ -z "$CONTENT" ]; then
  echo "ERROR: ${URL}: empty response (HTTP ${STATUS})"
  exit 1
fi

# Strip scripts, styles, HTML tags, normalize whitespace
echo "$CONTENT" \
  | sed 's/<script[^>]*>.*<\/script>//gI' \
  | sed 's/<style[^>]*>.*<\/style>//gI' \
  | sed 's/<[^>]*>/ /g' \
  | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g' \
  | tr -s ' \n\t' ' ' \
  | head -c "$MAX_CHARS"

echo  # trailing newline
