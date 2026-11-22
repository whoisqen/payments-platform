#!/usr/bin/env python3
"""Validate policy.yaml against schema.json (a small JSON Schema subset, no jsonschema dependency) and the golden rules of section 24."""
import json
import re
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
UNITS = {"ms": 0.001, "s": 1, "m": 60, "h": 3600}


def seconds(text):
    m = re.fullmatch(r"([0-9]+)(ms|s|m|h)", text)
    return int(m.group(1)) * UNITS[m.group(2)] if m else None


def type_ok(value, name):
    if name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, {"string": str, "boolean": bool, "object": dict, "array": list}[name])


def check(value, schema, root, path, errors):
    if "$ref" in schema:
        node = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        return check(value, node, root, path, errors)
    if "anyOf" in schema:
        for sub in schema["anyOf"]:
            sub_errors = []
            check(value, sub, root, path, sub_errors)
            if not sub_errors:
                return
        errors.append(f"{path}: matches none of the allowed forms")
        return
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: must be {schema['const']!r}")
        return
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(type_ok(value, n) for n in names):
            errors.append(f"{path}: expected {'/'.join(names)}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in {schema['enum']}")
    if "pattern" in schema and isinstance(value, str) and not re.search(schema["pattern"], value):
        errors.append(f"{path}: {value!r} does not match {schema['pattern']}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: above {schema['maximum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing {key}")
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            errors.append(f"{path}: needs at least {schema['minProperties']} entries")
        props = schema.get("properties", {})
        for key, item in value.items():
            if "propertyNames" in schema and not re.search(schema["propertyNames"]["pattern"], key):
                errors.append(f"{path}: bad name {key!r}")
            sub = props.get(key)
            if sub is None and isinstance(schema.get("additionalProperties"), dict):
                sub = schema["additionalProperties"]
            if sub is None:
                if schema.get("additionalProperties") is False:
                    errors.append(f"{path}: unexpected field {key!r}")
                continue
            check(item, sub, root, f"{path}.{key}", errors)
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            check(item, schema["items"], root, f"{path}[{i}]", errors)


def rules(policy):
    errors = []
    deadline = seconds(policy["defaults"]["request_deadline"])
    for name, dep in policy["dependencies"].items():
        attempts = dep["max_attempts"]
        retries = attempts if isinstance(attempts, int) else None
        if dep["kind"] == "charge" and retries != 0:
            errors.append(f"{name}: a charge is never retried automatically")
        if not dep["idempotent"] and retries != 0:
            errors.append(f"{name}: only idempotent operations may be retried")
        if attempts == "unlimited" and dep.get("bounded_by") != "timeout":
            errors.append(f"{name}: unlimited retries must be bounded_by timeout")
        base, cap = seconds(dep["base"]), seconds(dep["cap"])
        if retries != 0:
            if not base or not cap or base > cap:
                errors.append(f"{name}: needs 0 < base <= cap when it retries")
        timeout = seconds(dep["timeout"]) if dep["timeout"] != "sdk-default" else None
        if timeout == 0:
            errors.append(f"{name}: timeout must be positive")
        if dep.get("schedule") and retries is not None and len(dep["schedule"]) != retries:
            errors.append(f"{name}: schedule has {len(dep['schedule'])} entries for {retries} attempts")
        if dep["kind"] in ("read", "write") and timeout and retries is not None and name not in ("psp-sync", "kafka-consumer"):
            worst = timeout * (retries + 1) + (cap or 0) * retries
            if worst > deadline:
                errors.append(f"{name}: worst case {worst:g}s exceeds the request deadline {deadline:g}s")
    return errors


def validate(policy, schema):
    errors = []
    check(policy, schema, schema, "$", errors)
    return errors or rules(policy)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    policy_path = Path(argv[0]) if argv else HERE / "policy.yaml"
    schema = json.loads((HERE / "schema.json").read_text())
    errors = validate(yaml.safe_load(policy_path.read_text()), schema)
    for err in errors:
        print(f"resilience: error: {err}")
    print(f"resilience: {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
