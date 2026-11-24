"""Compression of tool data before it reaches the model: log templates, stack-trace folding, metric summaries, token budgets."""
import json
import math
import re
from collections import OrderedDict

TS = re.compile(r"^\s*(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\s*")
UUID = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
HEX = re.compile(r"\b(?:0x)?[0-9a-fA-F]{8,}\b")
IPV4 = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b")
NUMBER = re.compile(r"(?<![A-Za-z_])-?\d+(?:\.\d+)?")
ERROR_LEVEL = re.compile(r"(?i)\b(error|fatal|panic|critical|exception|failed|timeout)\b")
FRAME = re.compile(r"^\s+(?:at\s|File\s|\.{3}|\d+\s+more|goroutine\s|/\S+\.\w+:\d+)|^\s*Caused by:|^Traceback \(most recent call last\)|^\s+\S+\(.*\)\s*$")


def estimate_tokens(text):
    return math.ceil(len(text) / 4)


def cut_to_tokens(text, max_tokens):
    """Hard cut at the budget; says how much was dropped."""
    if estimate_tokens(text) <= max_tokens:
        return text, False
    keep = max(0, max_tokens * 4 - 45)
    return text[:keep] + f"\n[truncated: {len(text) - keep} chars over budget]", True


def template_of(line):
    line = TS.sub("", line, count=1)
    line = UUID.sub("<uuid>", line)
    line = IPV4.sub("<ip>", line)
    line = HEX.sub("<id>", line)
    line = NUMBER.sub("<n>", line)
    return re.sub(r"\s+", " ", line).strip()[:400]


def fold_stack_traces(lines, keep):
    """Join each run of frame lines to the line before it, keeping `keep` frames and counting the rest."""
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        j = i + 1
        frames = []
        while j < len(lines) and FRAME.match(lines[j]):
            frames.append(lines[j].strip())
            j += 1
        if frames:
            more = len(frames) - keep
            tail = " | ".join(frames[:keep]) + (f" | (+{more} frames folded)" if more > 0 else "")
            line = f"{line} [trace: {tail}]"
        out.append(line)
        i = j
    return out


def compress_logs(lines, limits):
    lines = [l for l in lines if l.strip()]
    total = len(lines)
    entries = fold_stack_traces(lines, limits["stack_frames_kept"])
    groups = OrderedDict()
    for e in entries:
        m = TS.match(e)
        ts = m.group(1) if m else None
        g = groups.setdefault(template_of(e), {"count": 0, "first": ts, "last": ts, "example": e[:limits["max_template_examples_chars"]], "error": bool(ERROR_LEVEL.search(e))})
        g["count"] += 1
        if ts:
            g["first"] = min(g["first"] or ts, ts)
            g["last"] = max(g["last"] or ts, ts)
    ranked = sorted(groups.values(), key=lambda g: (not g["error"], -g["count"]))
    top = ranked[:limits["top_templates"]]
    out = [f"logs: {total} lines, {len(groups)} templates, {sum(1 for g in groups.values() if g['error'])} error templates; showing top {len(top)} (errors first)"]
    for g in top:
        span = f" first={g['first']} last={g['last']}" if g["first"] else ""
        out.append(f"- x{g['count']}{' ERROR' if g['error'] else ''}{span}: {g['example']}")
    if len(ranked) > len(top):
        rest = ranked[len(top):]
        out.append(f"- (+{len(rest)} more templates, {sum(g['count'] for g in rest)} lines omitted)")
    return "\n".join(out)


def _downsample(values, n):
    if len(values) <= n:
        return values
    step = len(values) / n
    return [values[int(i * step)] for i in range(n)]


def summarize_series(values, points):
    nums = [v for v in values if v is not None and not math.isnan(v)]
    if not nums:
        return "no data"
    s = sorted(nums)
    p95 = s[min(len(s) - 1, int(0.95 * len(s)))]
    fmt = lambda v: f"{v:.6g}"  # noqa: E731
    spark = ",".join(fmt(v) for v in _downsample(nums, points))
    return f"n={len(nums)} min={fmt(s[0])} avg={fmt(sum(nums) / len(nums))} p95={fmt(p95)} max={fmt(s[-1])} last={fmt(nums[-1])} series=[{spark}]"


def compress_metrics(result, limits, max_series=20):
    """`result` is a Prometheus-style query response (vector or matrix); output is one summary line per series."""
    data = result.get("data", result) if isinstance(result, dict) else {}
    series = data.get("result", []) if isinstance(data, dict) else []
    out = [f"metrics: {len(series)} series ({data.get('resultType', '?') if isinstance(data, dict) else '?'})"]
    for s in series[:max_series]:
        labels = ",".join(f"{k}={v}" for k, v in sorted((s.get("metric") or {}).items()))
        if "values" in s:
            vals = [_f(v[1]) for v in s["values"]]
            ts = s["values"]
            span = f" from={ts[0][0]} to={ts[-1][0]}" if ts else ""
        else:
            vals = [_f(s.get("value", [0, "nan"])[1])]
            span = ""
        out.append(f"- {{{labels}}}{span} {summarize_series(vals, limits['metric_points'])}")
    if len(series) > max_series:
        out.append(f"- (+{len(series) - max_series} more series omitted)")
    return "\n".join(out)


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return float("nan")


def compress_json(obj, max_items=40):
    """Compact JSON with long lists capped, for alerts and cluster objects."""
    def cap(o):
        if isinstance(o, list):
            return [cap(x) for x in o[:max_items]] + ([f"(+{len(o) - max_items} more)"] if len(o) > max_items else [])
        if isinstance(o, dict):
            return {k: cap(v) for k, v in o.items()}
        return o
    return json.dumps(cap(obj), separators=(",", ":"), sort_keys=True)


class SessionBudget:
    """Tracks estimated tokens handed to the model across tool results."""

    def __init__(self, tool_tokens, session_tokens):
        self.tool_tokens = tool_tokens
        self.remaining = session_tokens
        self.cut = 0

    @property
    def exhausted(self):
        return self.remaining <= 0

    def fit(self, text):
        if self.exhausted:
            return "[session tool-token budget exhausted: no more data is available; answer from what you have]"
        allowance = min(self.tool_tokens, self.remaining)
        text, cut = cut_to_tokens(text, allowance)
        self.cut += cut
        self.remaining -= allowance if cut else estimate_tokens(text)
        return text


# --- text hygiene: model text is untrusted when it reaches a terminal or a log ---------------------------------------
UNSAFE = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u061c\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]")


def clean(text):
    """Remove control and bidi characters (newline and tab stay)."""
    return UNSAFE.sub("", str(text))


def one_line(text, limit=300):
    return re.sub(r"\s+", " ", clean(text)).strip()[:limit]
