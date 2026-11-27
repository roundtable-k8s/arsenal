---
name: daily-reports
description: >
  Shared output contract for knight daily reports. Defines the JSON envelope and markdown template ALL knights must use when producing daily briefings.
---

# Daily Reports — Output Contract

This skill defines **HOW** every knight structures daily report output. Your domain-specific report skill defines **WHAT** to report — this defines the envelope.

**This is mandatory.** All knights MUST use this format for daily briefings so the user gets consistent, mergeable reports every morning.

## What this knight can and cannot do

- The vault is mounted read-only unless the Knight lists the sub-path in `spec.vault.writablePaths` (no default: an absent or empty list means no writable paths); entries are relative to the vault root (e.g. `Agents/Briefings/`, mounted at `/vault/Agents/Briefings`; the trailing slash is the convention, not required), never absolute `/vault/...` paths, and a write anywhere else fails with `Read-only file system`.
- The reports and briefings this contract produces go under `$REPORTS_DIR` / `$BRIEFINGS_DIR` (defaults `/vault/Agents/Roundtable`, `/vault/Agents/Briefings`); the one you write to must be in `writablePaths` as `Agents/Roundtable/` or `Agents/Briefings/` (for an `RT_REPORTS_DIR` / `RT_BRIEFINGS_DIR` override, the path relative to the vault root).
- `/data` is the knight's own persistent volume and is always writable.
- If it fails, stop and report in the task result which entry is missing; do not work around it (no Docker Hub pulls, no installing packages from the open internet, no writing to another path).

## Architecture

```
Domain skill (e.g. security/daily-security-report)
  → decides WHAT to report (threats, vulnerabilities, etc.)
  → fills in sections with domain expertise

This skill (shared/daily-reports)
  → defines HOW to structure the output
  → JSON envelope format
  → Markdown vault template
```

## JSON Output Contract

Every daily report MUST be a JSON object matching this schema. See [`assets/contract.schema.json`](assets/contract.schema.json) for the formal schema.

```json
{
  "knight": "sir-lancelot",
  "run_id": "daily-2026-02-15",
  "report_type": "daily-briefing",
  "timestamp": "2026-02-15T09:00:00Z",
  "summary": "2-3 sentence executive summary of today's findings.",
  "sections": [
    {
      "title": "Section Name",
      "priority": "high",
      "content": "Markdown content with findings, analysis, etc.",
      "data_sources": ["NOAA SWPC", "NVD API"],
      "confidence": "high"
    }
  ],
  "highlights": [
    "Top bullet point for the morning briefing",
    "Another key takeaway",
    "Third important thing"
  ],
  "follow_up_needed": false,
  "follow_up_questions": []
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `knight` | string | ✅ | Knight identifier (e.g. `sir-lancelot`) |
| `run_id` | string | ✅ | Format: `daily-YYYY-MM-DD` |
| `report_type` | string | ✅ | Always `daily-briefing` for daily reports |
| `timestamp` | string | ✅ | ISO-8601 when the report was generated |
| `summary` | string | ✅ | 2-3 sentence executive summary |
| `sections` | array | ✅ | One or more report sections (see below) |
| `highlights` | array | ✅ | 1-5 bullet points for the morning briefing |
| `follow_up_needed` | boolean | ✅ | Does the user need to act on anything? |
| `follow_up_questions` | array | ✅ | Questions the user might want answered (empty array if none) |

### Section Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | ✅ | Section heading |
| `priority` | enum | ✅ | `high`, `medium`, or `low` |
| `content` | string | ✅ | Markdown-formatted content |
| `data_sources` | array | ✅ | Sources consulted (APIs, sites, feeds) |
| `confidence` | enum | ✅ | `high`, `medium`, or `low` |

### Resolutions (mandatory — see `shared/evidence-verification`)

If anything reported on a previous day is now fixed/closed/no longer present,
the `highlights` array MUST lead with an entry starting exactly `RESOLVED: `
for each such item. Resolutions are first-class signal: downstream synthesis
only sees your highlights, and a dropped resolution becomes a phantom issue
that is carried forward indefinitely. RESOLVED entries never count against
any highlight-count guidance.

### Priority Guidelines

- **high** — Requires the user's attention today. Actionable items, active threats, significant changes.
- **medium** — Worth knowing. Trends, updates, scheduled events.
- **low** — Background context. Routine observations, no action needed.

### Confidence Guidelines

- **high** — Data from authoritative primary sources, verified.
- **medium** — Reasonable analysis but some uncertainty or incomplete data.
- **low** — Speculative, single-source, or stale data.

## Markdown Vault Template

After generating the JSON, use [`assets/vault-template.md`](assets/vault-template.md) to render a markdown report for saving to the user's Obsidian vault. Use `shared/report-generator` to render it.

## Example: Security Knight Daily Report

```json
{
  "knight": "sir-gareth",
  "run_id": "daily-2026-02-15",
  "report_type": "daily-briefing",
  "timestamp": "2026-02-15T06:30:00-06:00",
  "summary": "No critical vulnerabilities in tracked infrastructure. Solar activity elevated with G1 storm watch issued. Home network stable with normal traffic patterns.",
  "sections": [
    {
      "title": "Infrastructure Security",
      "priority": "low",
      "content": "All monitored services operational. No new CVEs affecting our stack in the last 24h. SSL certificates valid with nearest expiry in 47 days.",
      "data_sources": ["NVD API", "Uptime Kuma", "SSL Labs"],
      "confidence": "high"
    },
    {
      "title": "Space Weather",
      "priority": "medium",
      "content": "G1 geomagnetic storm watch issued for Feb 16. Kp index currently 3. Aurora possible at higher latitudes. No expected impact on communications.",
      "data_sources": ["NOAA SWPC"],
      "confidence": "high"
    }
  ],
  "highlights": [
    "All systems green — no critical vulnerabilities",
    "G1 storm watch for tomorrow, aurora possible",
    "SSL certs healthy, nearest expiry in 47 days"
  ],
  "follow_up_needed": false,
  "follow_up_questions": []
}
```

## Example: Finance Knight with Follow-up

```json
{
  "knight": "sir-bedivere",
  "run_id": "daily-2026-02-15",
  "report_type": "daily-briefing",
  "timestamp": "2026-02-15T06:45:00-06:00",
  "summary": "Portfolio up 1.2% this week. Unusual volume detected on two holdings. Bitcoin approaching key resistance level at $52k.",
  "sections": [
    {
      "title": "Portfolio Overview",
      "priority": "medium",
      "content": "Weekly performance: +1.2%. S&P 500 tracking sideways. No earnings reports due this week for held positions.",
      "data_sources": ["Yahoo Finance", "SEC EDGAR"],
      "confidence": "high"
    },
    {
      "title": "Anomaly Alert",
      "priority": "high",
      "content": "Unusual options activity detected on $AAPL and $MSFT. Volume 3x average with heavy call buying for March expiry. Could indicate institutional positioning ahead of announcements.",
      "data_sources": ["Unusual Whales", "Yahoo Finance"],
      "confidence": "medium"
    }
  ],
  "highlights": [
    "Portfolio +1.2% this week",
    "⚠️ Unusual options activity on AAPL and MSFT",
    "Bitcoin nearing $52k resistance",
    "No earnings this week for held positions"
  ],
  "follow_up_needed": true,
  "follow_up_questions": [
    "Want me to dig deeper into the AAPL/MSFT options activity?",
    "Should I set alerts for Bitcoin breaking $52k?"
  ]
}
```

## Validate before you finish

Before saving or delivering the JSON, check it against the contract (needs `jq` only):

```bash
shared/daily-reports/scripts/validate-report report.json   # or "-" for stdin
```

Exit 0 and a last line `validate-report: ok` means the report is valid. Exit 1 lists every problem on stderr with its JSON path and ends stdout with `Outcome: failed report invalid: <first problem>`; a report that prints `Outcome: failed` is **not delivered** — fix it and re-run. Exit 2 means bad arguments or an unreadable file.

Tests for the validator (including a check that it matches `assets/contract.schema.json`): `bash shared/daily-reports/tests/test.sh`.

## Integration

Knights producing daily reports should:

1. Gather data per their domain skill's instructions
2. Structure output using this contract
3. Save JSON to their output location
4. Render markdown using the vault template for Obsidian
