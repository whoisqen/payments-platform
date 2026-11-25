import re

KNOWN = {
    "$schema", "$id", "$ref", "$defs", "definitions", "title", "description", "default", "type", "enum", "const",
    "properties", "required", "additionalProperties", "patternProperties", "items", "minItems", "maxItems",
    "uniqueItems", "minLength", "maxLength", "pattern", "minimum", "maximum", "exclusiveMinimum",
    "exclusiveMaximum", "minProperties", "maxProperties", "propertyNames", "if", "then", "else", "allOf", "anyOf", "oneOf", "not",
}
TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "null": lambda v: v is None,
}


def _resolve(ref, root):
    if not ref.startswith("#/"):
        raise ValueError(f"unsupported $ref {ref}")
    node = root
    for part in ref[2:].split("/"):
        node = node[part.replace("~1", "/").replace("~0", "~")]
    return node


def errors(value, schema, root=None, path="$"):
    # unknown keywords raise so a schema never silently passes unchecked
    root = schema if root is None else root
    if schema is True or schema == {}:
        return []
    if schema is False:
        return [f"{path}: nothing is allowed here"]
    unknown = set(schema) - KNOWN
    if unknown:
        raise ValueError(f"{path}: unsupported schema keyword(s) {sorted(unknown)}")
    out = []
    if "$ref" in schema:
        out += errors(value, _resolve(schema["$ref"], root), root, path)
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(TYPES[t](value) for t in types):
            return out + [f"{path}: expected {'/'.join(types)}, got {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        out.append(f"{path}: {value!r} not in {schema['enum']}")
    if "const" in schema and value != schema["const"]:
        out.append(f"{path}: {value!r} is not {schema['const']!r}")
    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            out.append(f"{path}: {value!r} does not match {schema['pattern']}")
        if len(value) < schema.get("minLength", 0):
            out.append(f"{path}: shorter than {schema['minLength']}")
        if len(value) > schema.get("maxLength", len(value)):
            out.append(f"{path}: longer than {schema['maxLength']}")
    if TYPES["number"](value):
        if "minimum" in schema and value < schema["minimum"]:
            out.append(f"{path}: {value} below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            out.append(f"{path}: {value} above maximum {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            out.append(f"{path}: {value} not above {schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            out.append(f"{path}: {value} not below {schema['exclusiveMaximum']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            out.append(f"{path}: fewer than {schema['minItems']} items")
        if len(value) > schema.get("maxItems", len(value)):
            out.append(f"{path}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems") and len({repr(v) for v in value}) != len(value):
            out.append(f"{path}: items are not unique")
        if "items" in schema:
            for i, item in enumerate(value):
                out += errors(item, schema["items"], root, f"{path}[{i}]")
    if isinstance(value, dict):
        props = schema.get("properties", {})
        pats = schema.get("patternProperties", {})
        for key in schema.get("required", []):
            if key not in value:
                out.append(f"{path}: missing required {key}")
        if len(value) < schema.get("minProperties", 0):
            out.append(f"{path}: fewer than {schema['minProperties']} properties")
        if len(value) > schema.get("maxProperties", len(value)):
            out.append(f"{path}: more than {schema['maxProperties']} properties")
        if "propertyNames" in schema:
            for key in value:
                out += errors(key, schema["propertyNames"], root, f"{path}[{key!r}]")
        for key, sub in value.items():
            matched = False
            if key in props:
                matched = True
                out += errors(sub, props[key], root, f"{path}.{key}")
            for pat, psch in pats.items():
                if re.search(pat, key):
                    matched = True
                    out += errors(sub, psch, root, f"{path}.{key}")
            if not matched:
                extra = schema.get("additionalProperties", True)
                if extra is False:
                    out.append(f"{path}: unexpected property {key}")
                elif isinstance(extra, dict):
                    out += errors(sub, extra, root, f"{path}.{key}")
    for sub in schema.get("allOf", []):
        out += errors(value, sub, root, path)
    if "anyOf" in schema and all(errors(value, s, root, path) for s in schema["anyOf"]):
        out.append(f"{path}: matches none of anyOf")
    if "oneOf" in schema and sum(not errors(value, s, root, path) for s in schema["oneOf"]) != 1:
        out.append(f"{path}: does not match exactly one of oneOf")
    if "not" in schema and not errors(value, schema["not"], root, path):
        out.append(f"{path}: matches a forbidden schema")
    if "if" in schema:
        branch = "then" if not errors(value, schema["if"], root, path) else "else"
        if branch in schema:
            out += errors(value, schema[branch], root, path)
    return out
