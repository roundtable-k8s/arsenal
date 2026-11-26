---
name: fleet-status
description: >
  Check the health and status of Round Table knights at your table using find_knights, confirming individual knights with nats_request only when needed. Use to verify fleet readiness before dispatching chains.
---

# Fleet Status Check

Check which knights at your table are online and usable. Use before dispatching critical chains or when asked about fleet health.

## How to Check

1. Call `find_knights` with `includeSuspended` left at its default (true). Each knight's `status` is the health answer: ready, suspended, not ready, or `live` when a pod answered just now. No model call is spent on this.
2. Only if you are about to depend on a specific knight, confirm it with a small `nats_request` (for example, "Reply with your current status in one word. Do not delegate to other knights."). Do not ping the whole fleet by default: each ping is a model call per knight.

## Quick Health Check

1. `find_knights()` to list every knight and its status.
2. Report suspended and not-ready knights as they are. A suspended knight is scaled to zero and wakes when a task arrives; it is not broken.
3. Confirm with `nats_request` only the knights the next chain needs. A request that times out (use a short `timeout_ms`) means that knight is not answering.

## Reporting Format

```markdown
## ⚔️ Fleet Status

| Knight | Domain | Status | Notes |
|--------|--------|--------|-------|
| <knight> | <domain> | 🟢 live | |
| <knight> | <domain> | 🟡 suspended | wakes on first task |
| <knight> | <domain> | 🔴 not ready | <reason, if known> |

**Fleet: <ready>/<total> usable** | Last check: [timestamp]
```

## When to Use

- Before dispatching a multi-knight chain
- When the user asks "how are the knights?"
- As part of morning mission briefing prep
- After deployments or operator changes
