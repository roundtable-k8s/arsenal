---
name: chain-orchestration
description: >
  Orchestrate multi-knight task chains. Dispatch parallel or sequential tasks to knights, aggregate results, and produce unified reports. Use when a mission requires multiple knights working together.
---

# Chain Orchestration

You are the Round Table's orchestrator. When a mission requires multiple knights, you plan the chain, dispatch tasks, collect results, and synthesize them into a unified outcome.

## Chain Patterns

### Parallel Fan-Out
All knights work simultaneously on independent sub-tasks. Use when tasks don't depend on each other.

```
Mission: "Morning security briefing"
├── <security knight>: "Daily threat landscape summary"     ─┐
├── <infra knight>: "Cluster health and recent changes"     ─┤── Aggregate
├── <research knight>: "Trending security news"             ─┘
```

### Sequential Pipeline
Each knight's output feeds the next knight's input. Use when tasks build on each other.

```
Mission: "Evaluate CVE-2024-XXXX impact"
1. <security knight>: "Analyze CVE details and affected components"
2. <infra knight>: "Check if affected versions are in our cluster" (gets step 1's output)
3. <home knight>: "Draft remediation timeline and notify the user" (gets both outputs)
```

### Fan-Out → Synthesize
Parallel first, then one knight synthesizes. The most common pattern.

```
Mission: "Baby prep status"
├── <home knight>: "Nursery completion status"           ─┐
├── <finance knight>: "Baby-related expenses this month" ─┤── You synthesize
├── <wellness knight>: "Upcoming prenatal appointments"  ─┘
```

## How to Dispatch

1. **Discover** who is at your table with `find_knights` (parameters: `query`, `domain`, `skill`, `includeSuspended`). Each result carries a `status` (ready, suspended, not ready; `live` when a pod answered just now). Pick knights whose status is usable.
2. **Call** each one with `nats_request` (parameters: `knight`, optional `domain`, `task`, optional `timeout_ms`). When `domain` is omitted it is looked up from the knight's agent card, so the knight's name is usually enough.

```
// Parallel: nats_request blocks, so issue the calls one after another.
// The knights process in parallel because each has its own consumer.

find_knights(domain: "security")   // -> pick the knight named in the result

result_a = nats_request(
  knight: "<security knight>",
  task: "Summarize today's threat landscape. Focus on critical CVEs and active campaigns. Do not delegate to other knights."
)

result_b = nats_request(
  knight: "<infra knight>",
  task: "Report cluster health: pod status, recent deployments, any alerts. Do not delegate to other knights.",
  timeout_ms: 180000
)
```

For sequential chains, include prior results in the next task:

```
result_a = nats_request(knight: "<security knight>",
  task: "Analyze CVE-2024-XXXX: affected software, severity, exploit status. Do not delegate to other knights.")

result_b = nats_request(knight: "<infra knight>",
  task: "Based on this CVE analysis, check if we're affected. Do not delegate to other knights.\n\n" + result_a)
```

**Use a Chain instead** when the same steps will run again: if the steps are fixed and repeated, ask for a Chain by name rather than hand-dispatching them each time. Ad-hoc `nats_request` fan-out suits one-off missions.

## Aggregation

After collecting results, synthesize them:

1. **Extract key findings** from each knight's response
2. **Cross-reference** — does Galahad's CVE affect what Tristan reported?
3. **Identify action items** — what needs to happen next?
4. **Prioritize** — what's urgent vs informational?
5. **Format** the unified report

## Result Format

Structure your aggregated output as:

```markdown
## ⚔️ Mission Report: [Title]

### 🎯 Action Items
- [ ] Critical items first
- [ ] Then important items

### 📊 Findings

#### [Knight] — [Domain]
Key findings from this knight...

#### [Knight] — [Domain]
Key findings from this knight...

### 🔗 Cross-References
- Finding X from Galahad relates to Finding Y from Tristan
- etc.

### 📝 Summary
One paragraph executive summary.
```

## Finding Knights

Do not keep a hard-coded roster. Call `find_knights` at the start of each chain to see who is at your table, their domains, skills and status. Use the returned `domain` and name in `nats_request`.

## Constraints

- **Always include "Do not delegate to other knights"** in sub-tasks to prevent infinite chains
- **Stay in your table** — `nats_request` only reaches knights that share your NATS prefix; cross-table requests time out
- **Cost awareness** — every knight call is a model call. Keep fan-outs to the knights the mission needs
- **Timeout** — the `nats_request` default is 10 minutes. Set `timeout_ms` only when a task is clearly shorter or longer, and keep it within what the target knight can finish
- **Concurrency** — `nats_request` is blocking, but knights process independently. Order of dispatch matters for sequential chains, not for parallel ones.
- **Error handling** — if a knight times out or is not ready, note it and continue with available results
