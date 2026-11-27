#!/usr/bin/env python3
"""render-template.py — Render a Handlebars-style markdown template with JSON data.

Usage:
    python3 render-template.py --template <path> --data <json-file> [--output <path>] [--strict]
    python3 render-template.py --template <path> --data-stdin [--strict] < data.json

Exit codes: 0 rendered (warnings may be on stderr), 1 error, or with --strict
an unresolved placeholder remains (nothing is written).
"""

import argparse
import json
import re
import sys
from pathlib import Path

# {{#each key}}...{{/each}} | {{name}} or {{a.b}} | stray block tag (unmatched/nested)
# | any other {{...}} tag outside the grammar ({{#if}}, {{ x }}, ...), reported as unresolved
_TOKEN = re.compile(
    r"\{\{#each\s+([\w.]+)\}\}(.*?)\{\{/each\}\}"
    r"|\{\{([\w.]+)\}\}"
    r"|(\{\{#each\s+[\w.]+\}\}|\{\{/each\}\})"
    r"|(\{\{[^}]*\}\})",
    re.DOTALL,
)
_MISSING = object()


def _lookup(scope, dotted):
    """Walk a dotted path through nested dicts; _MISSING if any step is absent."""
    cur = scope
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return _MISSING
        cur = cur[part]
    return cur


def _resolve(name, data, item, has_item):
    """`this` / `this.x.y` resolve inside an #each item; anything else against the root data."""
    if name == "this" or name.startswith("this."):
        if not has_item:
            return _MISSING
        rest = name[len("this."):]
        return item if name == "this" else _lookup(item, rest)
    return _lookup(data, name)


def _format(value):
    """Scalars render as text; null renders empty; lists/objects are not scalars (_MISSING)."""
    if value is None:
        return ""
    if isinstance(value, bool):  # before int: bool is an int subclass
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return json.dumps(value)
    if isinstance(value, str):
        return value
    return _MISSING


def _render(template, data, item, has_item, unresolved):
    def sub(m):
        if m.group(1) is not None:
            key, block = m.group(1), m.group(2)
            items = _resolve(key, data, item, has_item)
            if not isinstance(items, list):
                unresolved.append("{{#each " + key + "}}")
                return ""
            return "".join(_render(block, data, it, True, unresolved) for it in items)
        if m.group(3) is not None:
            value = _format(_resolve(m.group(3), data, item, has_item))
            if value is _MISSING:
                unresolved.append(m.group(0))
                return m.group(0)
            return value
        tag = m.group(4) if m.group(4) is not None else m.group(5)
        unresolved.append(tag)
        return tag

    return _TOKEN.sub(sub, template)


def render_simple(template: str, data: dict):
    """Render {{var}}, {{a.b}}, {{#each list}}...{{/each}} with {{this}}/{{this.x}}.

    Returns (rendered_text, unresolved_tokens), tokens de-duplicated in first-seen order.
    """
    unresolved = []
    rendered = _render(template, data, None, False, unresolved)
    return rendered, list(dict.fromkeys(unresolved))


def die(message: str):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def load_data(args) -> dict:
    source = "stdin" if args.data_stdin else args.data
    try:
        raw = sys.stdin.read() if args.data_stdin else Path(args.data).read_text()
    except OSError as e:
        die(f"cannot read {source}: {e.strerror}")
    except ValueError as e:
        die(f"{source} is not valid UTF-8: {e}")
    try:
        data = json.loads(raw)
    except ValueError as e:
        die(f"invalid JSON in {source}: {e}")
    if not isinstance(data, dict):
        die(f"data in {source} must be a JSON object, got {type(data).__name__}")
    return data


def main():
    parser = argparse.ArgumentParser(
        description="Render a Handlebars-style markdown template with JSON data."
    )
    parser.add_argument("--template", required=True, help="Path to template file")
    parser.add_argument("--data", help="Path to JSON data file")
    parser.add_argument("--data-stdin", action="store_true", help="Read JSON from stdin")
    parser.add_argument("--output", help="Output file path (default: stdout)")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 and write nothing if any placeholder is unresolved",
    )
    args = parser.parse_args()

    template_path = Path(args.template)
    if not template_path.exists():
        die(f"Template not found: {template_path}")
    try:
        template = template_path.read_text()
    except (OSError, ValueError) as e:
        die(f"cannot read template {template_path}: {e}")

    if not args.data_stdin and not args.data:
        die("--data or --data-stdin required")
    data = load_data(args)

    rendered, unresolved = render_simple(template, data)
    for token in unresolved:
        print(f"warning: unresolved placeholder {token}", file=sys.stderr)
    if args.strict and unresolved:
        die(f"{len(unresolved)} unresolved placeholder(s) with --strict; nothing written")

    if args.output:
        Path(args.output).write_text(rendered)
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        print(rendered)


if __name__ == "__main__":
    main()
