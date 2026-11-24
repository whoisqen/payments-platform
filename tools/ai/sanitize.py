#!/usr/bin/env python3
"""Redact secrets and card data from text before it reaches any model. Importable library; the CLI filters stdin to stdout."""
import argparse
import hashlib
import re
import sys
from collections import Counter

PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----|\Z)")
JWT = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*")
URL_PASSWORD = re.compile(r"(\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s:/@'\"]+:)([^\s@/'\"]+)(@)")
BEARER = re.compile(r"(?i)(\b(?:Bearer|Basic)\s+)([A-Za-z0-9._~+/=-]{16,})")
AWS_ACCESS_KEY = re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")
AWS_SECRET_KEY = re.compile(r"(?i)(aws_secret_access_key[\"']?\s*[=:]\s*[\"']?)([A-Za-z0-9/+=]{40})(?![A-Za-z0-9/+=])")
TOKENS = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|xox[abprs]-[A-Za-z0-9-]{10,}"
    r"|(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36})(?![A-Za-z0-9])"
)
# the name must end with the keyword, so `secret_name` and `token_endpoint` are not assignments of a secret
SECRET_ASSIGNMENT = re.compile(
    r"(?i)((?<!REDACTED:)(?<![\w.-])[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|access[_-]?key)[\"']?\s*[=:]\s*)"
    r"([\"']?)([^\s\"',;]{8,})(?=\2)"
)
CARD_CANDIDATE = re.compile(r"(?<![\w.-])\d(?:[ -]?\d){12,18}(?![\w-])")
EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")

# a value that is a reference or a template, not a literal
REFERENCE_VALUE = re.compile(r"^(?:[$<{(\[%@&*!]|\.{1,2}/|https?://|[A-Za-z_][\w-]*(?:\.[\w\[\]*-]+)+$|[A-Za-z_]\w*\(|REDACTED)")
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
    return not REFERENCE_VALUE.match(value) and value.lower() not in NON_SECRET_WORDS


class Redactor:
    """Replaces each secret with `<REDACTED:kind:n>`; one value always gets the same placeholder, and the counts add up across calls."""

    def __init__(self, redact_emails=False):
        self.redact_emails = redact_emails
        self.counts = Counter()
        self._seen = {}

    @property
    def total(self):
        return sum(self.counts.values())

    def _placeholder(self, kind, value):
        # only a digest is kept, so the object never holds a secret
        key = (kind, hashlib.sha256(value.encode("utf-8", "replace")).hexdigest())
        if key not in self._seen:
            self._seen[key] = 1 + sum(1 for k, _ in self._seen if k == kind)
        self.counts[kind] += 1
        return f"<REDACTED:{kind}:{self._seen[key]}>"

    def _whole(self, kind):
        return lambda m: self._placeholder(kind, m.group(0))

    def _secret_assignment(self, m):
        value = m.group(3)
        if not looks_literal(value):
            return m.group(0)
        return m.group(1) + m.group(2) + self._placeholder("secret", value)

    def _card(self, m):
        digits = re.sub(r"\D", "", m.group(0))
        return self._placeholder("pan", digits) if is_card_number(digits) else m.group(0)

    def redact(self, text):
        if not text:
            return text
        text = PRIVATE_KEY.sub(self._whole("private-key"), text)
        text = JWT.sub(self._whole("jwt"), text)
        text = URL_PASSWORD.sub(lambda m: m.group(1) + self._placeholder("url-password", m.group(2)) + m.group(3)
                                if looks_literal(m.group(2)) else m.group(0), text)
        text = BEARER.sub(lambda m: m.group(1) + self._placeholder("bearer", m.group(2)), text)
        text = AWS_ACCESS_KEY.sub(self._whole("aws-access-key"), text)
        text = AWS_SECRET_KEY.sub(lambda m: m.group(1) + self._placeholder("aws-secret-key", m.group(2)), text)
        text = TOKENS.sub(self._whole("token"), text)
        text = SECRET_ASSIGNMENT.sub(self._secret_assignment, text)
        text = CARD_CANDIDATE.sub(self._card, text)
        if self.redact_emails:
            text = EMAIL.sub(self._whole("email"), text)
        return text


def redact(text, redact_emails=False):
    r = Redactor(redact_emails=redact_emails)
    out = r.redact(text)
    return out, dict(r.counts)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--emails", action="store_true", help="redact e-mail addresses too")
    args = p.parse_args(argv)
    r = Redactor(redact_emails=args.emails)
    sys.stdout.write(r.redact(sys.stdin.read()))
    print(f"redacted {r.total} value(s): {dict(r.counts)}", file=sys.stderr)


if __name__ == "__main__":
    main()
