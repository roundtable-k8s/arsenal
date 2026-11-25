# Issue format

Every issue the orchestrator writes follows these rules and this format, so
that issue pickup can turn it into one pull request without asking anyone.

## What makes a good issue here

- One pull request, testable, no human decision needed. If it needs a decision,
  skip it and list it in your report under "needs the owner".
- Verified against the code: name the files, types and functions that exist
  today. If you cannot verify something, say so in Context.
- Additive and safe: nothing that changes a default the live factory depends
  on. Risky behaviour goes behind an opt-in field with the old path as default.

## Format (use exactly these sections)

```
Part of #<epic> (if one fits).

## Goal
<one or two sentences: the outcome>

## Context
<what exists today with file paths; what is missing; related issues/PRs>

## Tasks
- [ ] <concrete step naming files/packages>

## Acceptance criteria
- <observable, testable checks; end with the repo's test commands>

## Out of scope
- <what this deliberately does not do>
```

Title in conventional style (`feat(scope): …`, `fix(scope): …`, `docs(…): …`,
`refactor(…): …`, `test(…): …`).
