#!/usr/bin/env python3
"""Validate a JSON document against a JSON Schema: validate.py <schema> <document>.

Uses the jsonschema package when it is installed; otherwise a small built-in
validator for the keywords status.schema.json uses (type, properties, required,
additionalProperties, items, enum, pattern, minimum, minLength, anyOf, $ref to
#/$defs). Exits 1 and prints the problems when the document does not validate.
"""
import json
import re
import sys

TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}
KNOWN = {"$schema", "$id", "$defs", "title", "description", "type", "properties",
         "required", "additionalProperties", "items", "enum", "pattern", "minimum",
         "minLength", "anyOf", "$ref"}


def check(schema, value, root, path, errors):
    unknown = set(schema) - KNOWN
    if unknown:
        raise SystemExit(f"validate.py: unsupported schema keywords at {path}: {sorted(unknown)}")
    if "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/$defs/"):
            raise SystemExit(f"validate.py: unsupported $ref {ref}")
        check(root["$defs"][ref[len("#/$defs/"):]], value, root, path, errors)
    if "anyOf" in schema:
        if not any(not collect(s, value, root, path) for s in schema["anyOf"]):
            errors.append(f"{path}: matches none of anyOf")
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(TYPES[t](value) for t in types):
            errors.append(f"{path}: {json.dumps(value)[:80]} is not of type {types}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{path}: {value!r} does not match {schema['pattern']}")
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{path}: shorter than {schema['minLength']}")
    if TYPES["number"](value) and "minimum" in schema and value < schema["minimum"]:
        errors.append(f"{path}: {value} < {schema['minimum']}")
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            check(schema["items"], item, root, f"{path}[{i}]", errors)
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing required {key!r}")
        props = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if key in props:
                check(props[key], item, root, f"{path}.{key}", errors)
            elif extra is False:
                errors.append(f"{path}: unexpected property {key!r}")
            elif isinstance(extra, dict):
                check(extra, item, root, f"{path}.{key}", errors)


def collect(schema, value, root, path):
    errors = []
    check(schema, value, root, path, errors)
    return errors


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: validate.py <schema> <document>")
    with open(sys.argv[1]) as f:
        schema = json.load(f)
    with open(sys.argv[2]) as f:
        doc = json.load(f)
    try:
        import jsonschema
    except ImportError:
        errors = collect(schema, doc, schema, "$")
    else:
        validator = jsonschema.Draft202012Validator(schema)
        errors = [f"${''.join(f'[{p!r}]' for p in e.absolute_path)}: {e.message}"
                  for e in validator.iter_errors(doc)]
    for e in errors:
        print(e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
