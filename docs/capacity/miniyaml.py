import re

_INT = re.compile(r"^-?\d+$")
_FLOAT = re.compile(r"^-?\d+\.\d+$")


def _scalar(text):
    if text in ("null", "~", ""):
        return None
    if text in ("true", "false"):
        return text == "true"
    if _INT.match(text):
        return int(text)
    if _FLOAT.match(text):
        return float(text)
    return text.strip("\"'")


# Reads nested mappings with scalars only, so the calculator runs without PyYAML in the default venv.
def loads(text):
    root = {}
    stack = [(-1, root)]
    for raw in text.splitlines():
        line = raw.split(" #")[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        key, _, value = line.strip().partition(":")
        while stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if value.strip() == "":
            parent[key] = {}
            stack.append((indent, parent[key]))
        else:
            parent[key] = _scalar(value.strip())
    return root
