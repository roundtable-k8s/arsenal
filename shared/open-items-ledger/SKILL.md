---
name: open-items-ledger
description: >
  Protocol for the per-domain open-items ledger at
  /vault/Agents/Briefings/Ledger/<domain>.json (default root; override with
  RT_BRIEFINGS_DIR). Replaces prose memory as the
  carry-forward mechanism for tracked items: Day-N counters are computed from
  first_seen, items are re-verified before being carried, and resolutions are
  recorded machine-readably so they can never be silently lost. Use when producing a daily report or briefing summary for a domain.
---

# Open-Items Ledger — Carry-Forward Protocol

Your domain has a ledger file: `$BRIEFINGS_DIR/Ledger/<domain>.json`.
It is the **single source of truth for tracked items** — not yesterday's
report, not your memory, not your task prompt. Follow this protocol every
time you produce a daily report or briefing summary.

## What this knight can and cannot do

- The vault is mounted read-only unless the Knight lists the sub-path in `spec.vault.writablePaths` (no default: an absent or empty list means no writable paths); entries are relative to the vault root with a trailing slash (e.g. `Agents/Briefings/`, mounted at `/vault/Agents/Briefings`), never absolute `/vault/...` paths, and a write anywhere else fails with `Read-only file system`.
- The ledger lives under `$BRIEFINGS_DIR/Ledger` (default `/vault/Agents/Briefings/Ledger`), so `Agents/Briefings/` must be in `writablePaths` for it to be updated. If you set `RT_BRIEFINGS_DIR` to another path under `/vault`, list that path relative to the vault root (drop the `/vault/` prefix) instead.
- `/data` is the knight's own persistent volume and is always writable.
- If it fails, stop and report in the task result which entry is missing; do not work around it (no Docker Hub pulls, no installing packages from the open internet, no writing to another path).
## When to use

- Writing the daily report or briefing summary for your domain: the ledger is read and updated before anything is reported.
- When an item from a previous run may still be open and must be re-verified before it is carried forward.
- Not for one-off tasks that track no recurring items.

## Vault layout

Paths in this skill are built from these roots (defined once, here). Each can be
overridden by the environment variable when it is set:

| Root | Default | Override |
|---|---|---|
| Briefings | `/vault/Agents/Briefings` | `RT_BRIEFINGS_DIR` |
| Reports | `/vault/Agents/Roundtable` | `RT_REPORTS_DIR` |
| Night Watch | `/vault/Agents/NightWatch` | `RT_NIGHTWATCH_DIR` |

```bash
BRIEFINGS_DIR="${RT_BRIEFINGS_DIR:-/vault/Agents/Briefings}"
REPORTS_DIR="${RT_REPORTS_DIR:-/vault/Agents/Roundtable}"
NIGHTWATCH_DIR="${RT_NIGHTWATCH_DIR:-/vault/Agents/NightWatch}"
```

## The file

```json
{
  "domain": "infra",
  "knight": "tristan",
  "meta": { "last_report": "2026-07-05", "last_summary_received": "2026-07-05" },
  "items": [
    {
      "id": "short-stable-slug",
      "claim": "one-line statement of the issue",
      "severity": "low | medium | high",
      "first_seen": "YYYY-MM-DD or null",
      "last_verified": "YYYY-MM-DD",
      "verification": { "command": "read-only command", "expect": "what confirms it" },
      "status": "open | resolved",
      "resolved_on": "YYYY-MM-DD or null",
      "notes": "one line of context"
    }
  ]
}
```

- `first_seen: null` means unknown/pre-ledger — never invent a date.
- `verification: null` means not mechanically checkable (personal items) —
  such claims are always rendered `[unverified]`.

## Ownership

**You write only your own domain's file.** The verifier step updates
`last_verified` timestamps and `meta.last_summary_received`; the synthesizer
only reads. Keep the file valid JSON — if you can, sanity-check with
`jq . <file>` after writing.

## Protocol — at the start of every report

1. **Read your ledger file.** If it is missing, say so in your report,
   create a minimal one from what you observe today, and flag it.
2. **For every `open` item, re-verify it today:**
   - It has a `verification.command` → run it (read-only). Still reproduces →
     keep it open and set `last_verified` to today. No longer reproduces →
     set `status: resolved`, `resolved_on` today, and lead your summary with
     a `RESOLVED:` bullet for it.
   - `verification: null` (personal) → carry it, but it renders
     `[unverified]`; never claim it was confirmed.
   - The command errors → keep the item open, don't update `last_verified`,
     and note the verification failure in your report.
3. **Never carry an open item you did not re-verify today.** An item whose
   `last_verified` is more than 2 days old must be re-verified or explicitly
   flagged as unverifiable — never silently carried.

## Day-N counters

`Day N = today − first_seen`, **computed at write time, every time.**

- Never increment yesterday's counter, never copy a counter from a prior
  report or briefing, never estimate one.
- `first_seen: null` → no Day-N number at all; describe the item without one.
- If your computed Day-N contradicts what yesterday's briefing printed,
  yours is correct — the ledger beats prose history.

## New and recurring items

- **New item found today:** append it with `first_seen` = today, the exact
  command that found it as `verification.command`, and `status: open`.
- **Resolved items stay in the file.** They are the anti-resurrection
  record. Never delete them and never flip one back to `open`. If the same
  problem genuinely recurs, add a **new item** with a fresh `first_seen` and
  a note referencing the old id — its history restarts; it is not "Day 140".

## Stale-Item Decay

Items that linger without progress accumulate briefing noise. Apply these
decay rules every report:

### 7-day threshold
An `open` item with `last_verified` ≥ 7 days old (and no verification
command, or `verification: null`):
- **Downgrade severity**: high→medium, medium→low.
- **low-severity items** at 7+ days stale: **auto-resolve** with
  `resolved_on` = today, `notes` = "auto-resolved: low-severity item
  unverified for 7+ days".

### 14-day threshold
Any `open` item with `first_seen` ≥ 14 days ago, regardless of severity
or reconfirmation status:
- **Auto-resolve** with `notes` = "auto-resolved: 14-day staleness
  threshold (last_verified YYYY-MM-DD)".
- Move to resolved — the item consumed 14 days of briefing space without
  forward motion.

### 30-day hard cap
Any `open` item with `first_seen` ≥ 30 days ago: **force-resolve**.
No exceptions — it has consumed a month of daily attention.

### Items immune to decay
These patterns never auto-decay:
- CISA KEV entries (id starts with `cve-` and the CVE is actively in KEV)
- Active cluster infrastructure failures (node down, CrashLoopBackOff)
- Legal/tax deadlines with fixed statutory due dates
- Items the user explicitly set `notes` to contain `"decay: false"`

The script only recognises `cve-` ids and `decay: false` as immune. For active infrastructure failures and legal/tax deadlines, add `decay: false` to the item's `notes` when you create it, or `--apply` will auto-resolve it at 14 days.

### Decay reporting
When staleness auto-resolves an item, list it in your summary's
`resolved` array so the synthesizer can print it as ✅ RESOLVED:
```json
{"id": "old-item-id", "evidence": "Stale-item decay (N days unreconfirmed)"}
```

Decay is a cleanup mechanism, not a bug fix. The item didn't get solved —
it just stopped being worth daily attention.

## Checking the ledger

`scripts/ledger-check <ledger.json> [--today YYYY-MM-DD] [--apply]` validates the
file (stderr, exit 1 on problems), prints one line per open item
(`<id> day=<N|none> last_verified_age=<N> action=<keep|downgrade|resolve-7d|resolve-14d|resolve-30d|reverify>`)
and, with `--apply`, writes the decay results from the rules above through a temp
file and `mv`. Run it before writing the report and after editing the file. Do not
compute Day-N by hand. It does not re-verify items; running `verification.command`
stays with you. A downgrade adds `[downgraded YYYY-MM-DD]` to `notes`, so a second
`--apply` on the same day changes nothing.

## Finishing

- Update `meta.last_report` to today when you write your vault report.
- Your summary must agree with the ledger: every `RESOLVED:` bullet matches
  an item resolved today; every carried item is `open` with
  `last_verified` = today (or explicitly `[unverified]`).

## Tests

```bash
bash shared/open-items-ledger/tests/test.sh
```
