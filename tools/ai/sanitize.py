#!/usr/bin/env python3
"""Redact secrets and card data from text before it reaches any model. Importable library; it never prints or stores the text."""
import base64
import binascii
import hashlib
import re
import unicodedata
from collections import Counter

PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----|\Z)")
JWT = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*")
URL_PASSWORD = re.compile(r"(\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s:/@'\"]+:)([^\s@/'\"]+)(@)")
BEARER = re.compile(r"(?i)(\b(?:Bearer|Basic)\s+)([A-Za-z0-9._~+/=-]{16,})")
AWS_ACCESS_KEY = re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")
AWS_SECRET_KEY = re.compile(r"(?i)(aws_secret_access_key[\"']?\s*[=:]\s*[\"']?)([A-Za-z0-9/+=]{40})(?![A-Za-z0-9/+=])")
TOKENS = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|xox[abprs]-[A-Za-z0-9-]{10,}"
    r"|(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}"
    r"|sk-ant-[A-Za-z0-9_-]{20,}|whsec_[A-Za-z0-9]{16,})(?![A-Za-z0-9])"
)
# The name must end with a keyword (`secret_name` and `token_endpoint` are not secrets); `pass` and `dsn` only as a whole name or segment.
NAME = (r"(?:[A-Za-z0-9_.-]*(?:password|passwd|passphrase|pwd|secret[_-]?value|secret|token|api[_-]?key|private[_-]?key"
        r"|access[_-]?key|credentials?)|(?:[A-Za-z0-9_.-]*[_.-])?(?:pass|dsn))")
SECRET_ASSIGNMENT = re.compile(
    r"(?i)((?<!REDACTED:)(?<![\w.-])" + NAME + r"[\"']?\s*[=:]\s*)"
    r"(?:\"(?P<dq>(?:[^\"\\\n]|\\.)*)\"(?P<dqt>[^\s,;}\])]*)|'(?P<sq>(?:[^'\\\n]|\\.)*)'(?P<sqt>[^\s,;}\])]*)|(?P<bare>[^\s\"',;]{8,}))"
)
BLOCK_HEADER = re.compile(r"(?i)^(?P<indent>[ \t-]*)" + NAME + r"[\"']?\s*:\s*[|>][-+0-9]*\s*(?:#.*)?$")
K8S_KIND = re.compile(r"(?mi)^\s*kind:\s*[\"']?Secret[\"']?\s*(?:#.*)?$")
K8S_DATA_HEADER = re.compile(r"^(?P<indent>[ \t]*)(?:data|stringData)\s*:\s*(?:#.*)?$")
K8S_ENTRY = re.compile(r"^(?P<head>[ \t]*[\w.\-/]+[\"']?\s*:\s*)(?P<value>\S.*?)\s*$")
BASE64_VALUE = re.compile(r"(?<![A-Za-z0-9+/_=-])[A-Za-z0-9+/_-]{40,}={0,2}(?![A-Za-z0-9+/_=-])")
# 13 or more digits, optionally separated by one whitespace, dot, dash, slash or underscore; letters, '-' and '_' before the run are allowed
CARD_CANDIDATE = re.compile(r"(?<!\d)\d(?:[\s.\-/_]?\d){12,}(?!\d)")
EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
JSON_ESCAPE = re.compile(r"\\(?:([\"'\\/])|u([0-9a-fA-F]{4}))")

# a value that is a reference or a template, not a literal: `${...}`, `{{...}}`, `<...>` (also our placeholders), `var.x`, `module.x`
REFERENCE_VALUE = re.compile(r"^(?:\$\{[^{}]*\}|\{\{[^{}]*\}\}|<[^<>]*>|(?:var|module)\.[\w.\[\]-]+)$")
NON_SECRET_WORDS = {"changeme", "example", "undefined", "required", "optional", "sensitive", "password", "disabled", "enabled"}

# brand prefixes with their valid lengths; Luhn alone passes one random number in ten
CARD_BRANDS = (
    (re.compile(r"4"), (13, 16, 19)),
    (re.compile(r"5[1-5]|222[1-9]|22[3-9]|2[3-6]|27[01]|2720"), (16,)),
    (re.compile(r"3[47]"), (15,)),
    (re.compile(r"6011|65|64[4-9]|622"), (16, 17, 18, 19)),
    (re.compile(r"3[689]|30[0-5]"), (14, 15, 16, 17, 18, 19)),
    (re.compile(r"35(?:2[89]|[3-8])"), (16, 17, 18, 19)),
    (re.compile(r"62"), (16, 17, 18, 19)),
)

_INVISIBLE = dict.fromkeys(map(ord, "\u200b\u200c\u200d\u200e\u200f\u2060\u2061\u2062\u2063\u2064\ufeff\u00ad\u180e"
                               "\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"))
# characters that str.splitlines() treats as line ends but git does not
_LINE_BREAKS = {0x0b: " ", 0x0c: " ", 0x1c: " ", 0x1d: " ", 0x1e: " ", 0x85: " ", 0x2028: " ", 0x2029: " "}


def normalize(text):
    """NFKC, no zero-width or bidi characters, non-ASCII digits as ASCII digits, no exotic line breaks; newlines are kept."""
    text = text.translate(_INVISIBLE)
    if not text.isascii():
        text = unicodedata.normalize("NFKC", text).translate(_INVISIBLE)
        text = "".join(str(unicodedata.decimal(c)) if not c.isascii() and unicodedata.category(c) == "Nd" else c for c in text)
    return text.translate(_LINE_BREAKS)


def _unescape(m):
    if m.group(1):
        return m.group(1)
    cp = int(m.group(2), 16)
    if cp < 32 or cp in (0x85, 0x2028, 0x2029):
        return " "
    return m.group(0) if 0xD800 <= cp <= 0xDFFF else chr(cp)


def unescape(text):
    """Undo JSON string escapes that hide a secret (quote, backslash, slash, \\uXXXX); `\\n` and `\\r` never become line breaks."""
    return JSON_ESCAPE.sub(_unescape, text) if "\\" in text else text


def luhn_valid(digits):
    if not digits.isdigit():
        return False
    total = 0
    for i, ch in enumerate(reversed(digits)):
        n = int(ch)
        if i % 2:
            n = n * 2 - 9 if n > 4 else n * 2
        total += n
    return total % 10 == 0


def is_card_number(digits):
    return luhn_valid(digits) and any(p.match(digits) and len(digits) in lengths for p, lengths in CARD_BRANDS)


def looks_literal(value):
    value = value.strip()
    return not REFERENCE_VALUE.match(value) and value.lower() not in NON_SECRET_WORDS


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


class Redactor:
    """Replaces each secret with `<REDACTED:kind:n>`; one value always gets the same placeholder. Only digests are kept."""

    def __init__(self, redact_emails=False):
        self.redact_emails = redact_emails
        self.counts = Counter()
        self._seen = {}
        self._keep = False

    @property
    def total(self):
        return sum(self.counts.values())

    def _placeholder(self, kind, value):
        key = (kind, hashlib.sha256(value.encode("utf-8", "replace")).hexdigest())
        if key not in self._seen:
            self._seen[key] = 1 + sum(1 for k, _ in self._seen if k == kind)
        self.counts[kind] += 1
        return f"<REDACTED:{kind}:{self._seen[key]}>"

    def _pad(self, matched, repl):
        # with keep_lines a replacement keeps the number of line breaks of what it replaces
        return repl + "\n" * matched.count("\n") if self._keep else repl

    def _whole(self, kind):
        return lambda m: self._pad(m.group(0), self._placeholder(kind, m.group(0)))

    def _secret_assignment(self, m):
        for quote, val, tail in (('"', "dq", "dqt"), ("'", "sq", "sqt")):
            if m.group(val) is not None:
                value, rest = m.group(val), m.group(tail)
                if not rest and (len(value) < 8 or not looks_literal(value)):
                    return m.group(0)
                return m.group(1) + quote + self._placeholder("secret", value + rest) + quote
        value = m.group("bare")
        return m.group(1) + self._placeholder("secret", value) if looks_literal(value) else m.group(0)

    def _block_scalars(self, text):
        """`password: |` followed by indented lines: the whole block is the secret."""
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            if not BLOCK_HEADER.match(lines[i]):
                i += 1
                continue
            lead = _indent(lines[i])
            j = i + 1
            while j < len(lines) and (not lines[j].strip() or _indent(lines[j]) > lead):
                j += 1
            body = [k for k in range(i + 1, j) if lines[k].strip()]
            value = "\n".join(lines[k].strip() for k in body)
            if body and len(value) >= 8 and looks_literal(value):
                lines[body[0]] = lines[body[0]][:_indent(lines[body[0]])] + self._placeholder("secret", value)
                for k in range(i + 1, j):
                    if k != body[0]:
                        lines[k] = ""
            i = j
        return "\n".join(lines)

    def _k8s_secret_data(self, text, force):
        """Every value under `data:` or `stringData:` of a `kind: Secret` document is the secret."""
        out = []
        for doc in re.split(r"(?m)^(?=---[ \t]*$)", text):
            if not (force or K8S_KIND.search(doc)):
                out.append(doc)
                continue
            lines = doc.split("\n")
            i = 0
            while i < len(lines):
                h = K8S_DATA_HEADER.match(lines[i])
                if not h:
                    i += 1
                    continue
                base = len(h.group("indent"))
                i += 1
                while i < len(lines) and (not lines[i].strip() or _indent(lines[i]) > base):
                    e = K8S_ENTRY.match(lines[i])
                    i += 1
                    if not e:
                        continue
                    value = e.group("value")
                    if value[0] in "|>":
                        key_indent = _indent(lines[i - 1])
                        j = i
                        while j < len(lines) and (not lines[j].strip() or _indent(lines[j]) > key_indent):
                            j += 1
                        body = [k for k in range(i, j) if lines[k].strip()]
                        joined = "\n".join(lines[k].strip() for k in body)
                        if body and looks_literal(joined):
                            lines[body[0]] = lines[body[0]][:_indent(lines[body[0]])] + self._placeholder("k8s-secret", joined)
                            for k in range(i, j):
                                if k != body[0]:
                                    lines[k] = ""
                        i = j
                    elif value.strip("\"'") and looks_literal(value.strip("\"'")):
                        lines[i - 1] = e.group("head") + self._placeholder("k8s-secret", value)
            out.append("\n".join(lines))
        return "".join(out)

    def _base64(self, m):
        token = m.group(0)
        raw = token.rstrip("=").replace("-", "+").replace("_", "/")
        try:
            decoded = base64.b64decode(raw + "=" * (-len(raw) % 4), validate=True).decode("utf-8", "ignore")
        except (binascii.Error, ValueError):
            return token
        probe = Redactor(redact_emails=self.redact_emails)
        probe.redact(decoded)
        return self._placeholder("b64-secret", token) if probe.total else token

    def _card(self, m):
        s = m.group(0)
        if is_card_number(re.sub(r"\D", "", s)):
            return self._pad(s, self._placeholder("pan", re.sub(r"\D", "", s)))
        # a longer run (a date, an id) in front of a real number: try windows of whole digit groups
        groups = list(re.finditer(r"\d+", s))
        out, pos, i = [], 0, 0
        while i < len(groups):
            found = None
            if i == 0 or s[groups[i - 1].end():groups[i].start()] != ".":  # `0.4111...` is a decimal, not a card
                total = 0
                for j in range(i, len(groups)):
                    total += len(groups[j].group(0))
                    if total > 19:
                        break
                    if total >= 13 and is_card_number("".join(g.group(0) for g in groups[i:j + 1])):
                        found = j
            if found is None:
                i += 1
                continue
            start, end = groups[i].start(), groups[found].end()
            digits = "".join(g.group(0) for g in groups[i:found + 1])
            out.append(s[pos:start] + self._pad(s[start:end], self._placeholder("pan", digits)))
            pos, i = end, found + 1
        out.append(s[pos:])
        return "".join(out)

    def _rules(self, text, k8s_secret):
        text = PRIVATE_KEY.sub(self._whole("private-key"), text)
        text = JWT.sub(self._whole("jwt"), text)
        text = URL_PASSWORD.sub(lambda m: m.group(1) + self._placeholder("url-password", m.group(2)) + m.group(3)
                                if looks_literal(m.group(2)) else m.group(0), text)
        text = BEARER.sub(lambda m: m.group(1) + self._placeholder("bearer", m.group(2)), text)
        text = AWS_ACCESS_KEY.sub(self._whole("aws-access-key"), text)
        text = AWS_SECRET_KEY.sub(lambda m: m.group(1) + self._placeholder("aws-secret-key", m.group(2)), text)
        text = TOKENS.sub(self._whole("token"), text)
        text = self._block_scalars(text)
        text = self._k8s_secret_data(text, k8s_secret)
        text = SECRET_ASSIGNMENT.sub(self._secret_assignment, text)
        text = BASE64_VALUE.sub(self._base64, text)
        text = CARD_CANDIDATE.sub(self._card, text)
        if self.redact_emails:
            text = EMAIL.sub(self._whole("email"), text)
        return text

    def redact(self, text, keep_lines=False, k8s_secret=False):
        """With keep_lines the result has exactly as many line breaks as the input; k8s_secret treats the text as a Kubernetes Secret."""
        if not text:
            return text
        self._keep = keep_lines
        # the rules run on the text as written and, when it holds backslashes, again with JSON escapes undone
        text = self._rules(normalize(text), k8s_secret)
        if "\\" in text:
            text = self._rules(unescape(text), k8s_secret)
        return text


def redact(text, redact_emails=False):
    r = Redactor(redact_emails=redact_emails)
    out = r.redact(text)
    return out, dict(r.counts)
