---
name: web-search
description: >
  Search the web using the cluster SearXNG metasearch engine. Use when you need to find current information, research topics, or verify facts. Aggregates Google, Brave, DuckDuckGo, and more.
---

# Web Search (SearXNG)

Search the web via the self-hosted SearXNG metasearch engine. No API keys needed — it aggregates multiple search engines with no rate limits.

## Quick Reference

```bash
# Basic search (returns top 5)
bash /skills/shared/web-search/scripts/search.sh "your query here"

# With result count
bash /skills/shared/web-search/scripts/search.sh "your query here" 10
```

## Direct API Usage

```bash
curl -s "http://searxng.selfhosted.svc.cluster.local:8080/search?q=QUERY&format=json" \
  | grep -o '"title":"[^"]*"\|"url":"[^"]*"\|"content":"[^"]*"'
```

## Tips

- Use specific, targeted queries — SearXNG ranks by relevance across engines
- Add `site:github.com` or `site:reddit.com` for source-specific results
- Results include title, URL, and content snippet
- `search.sh` parses with `jq` when it is installed (the knight images ship it) and falls back to grep otherwise

## Network access

Knights run with default-deny egress. The `SEARXNG_URL`'s host (default `searxng.selfhosted.svc.cluster.local`) must be listed in the knight's
`spec.egress.allowedHosts` (or `allowedServices` for in-cluster services). When a
request fails the script prints one `ERROR:` line and exits 1. A connection refused,
DNS failure or timeout (`ERROR: SearXNG unreachable at ...`) usually means the host is
blocked. An HTTP error (`returned HTTP <code>`), an empty body or a non-JSON body
(`returned an empty response` / `returned invalid JSON`) means SearXNG itself failed.

## Output and exit codes

- Results: one block per result, `---`, `Title:`, `URL:`, `Snippet:`. Exit 0.
- No matches: `No results for "<query>"`. Exit 0.
- Any failure: a single `ERROR:` line. Exit 1.

## Scripts

See [scripts/search.sh](scripts/search.sh) for implementation.
