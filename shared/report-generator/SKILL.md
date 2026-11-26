---
name: report-generator
description: >
  Generate formatted markdown reports from templates and structured data. Use when producing standardized output documents like briefings, assessments, or digests.
---

# Report Generator

Renders markdown reports using templates with variable substitution. Templates use `{{variable}}` placeholders and `{{#each list}}...{{/each}}` for iteration.

## When to Use

- Producing standardized briefings or assessments
- Any output that should follow a consistent format
- When a template exists in a skill's `assets/` directory

## How It Works

1. Load a template from the requesting skill's `assets/` directory
2. Substitute variables from your structured data
3. Output the rendered markdown

## Template Syntax

```markdown
# Report — {{title}}

## Summary
{{summary}}

## Items
{{#each items}}
### {{this.name}}
- Severity: {{this.severity}}
- Details: {{this.details}}
{{/each}}

---
*Generated {{generated_at}}*
```

## Usage

Templates are co-located with the skill that uses them under `assets/`. To render:

1. Read the template file
2. Replace `{{variable}}` with your data
3. Expand `{{#each}}` blocks for arrays
4. Write the result to the output location

## Values

- Strings render as-is. Integers and floats render as JSON writes them (`3`, `2.5`).
- Booleans render as `true` / `false`. `null` renders as an empty string.
- Dotted paths reach nested objects: `{{a.b}}`. Inside `{{#each}}`, `{{this}}` is the
  item itself and `{{this.a.b}}` is a path inside it. Other names inside a block
  resolve against the top-level data.
- Lists and objects are not scalars. A placeholder that points at one is unresolved.
- `{{#each}}` needs a list. Nested `{{#each}}` blocks are not supported. They are
  reported as unresolved, not rendered.

## Unresolved Placeholders

A placeholder that cannot be resolved is left in the output as written, and the renderer
prints one warning per distinct token on stderr:

```
warning: unresolved placeholder {{this.missing}}
```

Pass `--strict` to fail instead: the script exits 1, prints
`Error: N unresolved placeholder(s) with --strict; nothing written`, and writes no output.
Use `--strict` when a report is going to a vault or another consumer.

## Exit Codes

- `0` — rendered. Warnings may be on stderr.
- `1` — error: the template or data file is missing, the data is not valid JSON, the
  top-level data is not a JSON object, or `--strict` found an unresolved placeholder.
  Errors print one `Error: ...` line to stderr, with no traceback.

## Scripts

See [scripts/render-template.py](scripts/render-template.py) for a Python renderer.
Run its tests with `bash shared/report-generator/tests/test.sh`.
