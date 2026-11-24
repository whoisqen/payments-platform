import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sanitize  # noqa: E402


def make_pan(prefix, length):
    body = prefix + "0" * (length - len(prefix) - 1)
    for check in "0123456789":
        if sanitize.luhn_valid(body + check):
            return body + check
    raise AssertionError


def break_luhn(pan):
    return pan[:-1] + str((int(pan[-1]) + 1) % 10)


class LuhnTest(unittest.TestCase):
    def test_valid_and_invalid(self):
        self.assertTrue(sanitize.luhn_valid("79927398713"))
        self.assertFalse(sanitize.luhn_valid("79927398710"))
        self.assertFalse(sanitize.luhn_valid("12a4"))
        self.assertFalse(sanitize.luhn_valid(""))

    def test_brands(self):
        for prefix, length in (("4", 16), ("4", 13), ("51", 16), ("2221", 16), ("2720", 16), ("34", 15), ("37", 15),
                               ("6011", 16), ("65", 19), ("36", 14), ("3528", 16), ("62", 17)):
            self.assertTrue(sanitize.is_card_number(make_pan(prefix, length)), (prefix, length))

    def test_unknown_prefix_or_length_is_not_a_card(self):
        self.assertFalse(sanitize.is_card_number(make_pan("1", 16)))
        self.assertFalse(sanitize.is_card_number(make_pan("4", 14)))
        self.assertFalse(sanitize.is_card_number(make_pan("34", 16)))


class CardTest(unittest.TestCase):
    def test_plain_spaced_and_dashed(self):
        pan = make_pan("4", 16)
        spaced = " ".join(pan[i:i + 4] for i in range(0, 16, 4))
        dashed = "-".join(pan[i:i + 4] for i in range(0, 16, 4))
        for form in (pan, spaced, dashed):
            out, counts = sanitize.redact(f"card {form} end")
            self.assertEqual(out, "card <REDACTED:pan:1> end")
            self.assertEqual(counts, {"pan": 1})

    def test_amex_grouping(self):
        pan = make_pan("37", 15)
        out, _ = sanitize.redact(f"{pan[:4]} {pan[4:10]} {pan[10:]}")
        self.assertEqual(out, "<REDACTED:pan:1>")

    def test_luhn_failure_is_kept(self):
        text = f"id {break_luhn(make_pan('4', 16))}"
        self.assertEqual(sanitize.redact(text), (text, {}))

    def test_timestamps_ids_and_versions_are_kept(self):
        for text in ("ts=1700000000123", "order 12345678901234567890123", "v1.2.3.4567890123456",
                     "uuid 12345678-1234-1234-1234-123456789012", "0.4111111111111111"):
            self.assertEqual(sanitize.redact(text)[0], text, text)

    def test_digits_inside_a_longer_number_are_kept(self):
        pan = make_pan("4", 16)
        self.assertEqual(sanitize.redact(pan + "7")[0], pan + "7")

    def test_same_card_same_placeholder_other_card_next_number(self):
        a, b = make_pan("4", 16), make_pan("51", 16)
        out, counts = sanitize.redact(f"{a} {b} {a}")
        self.assertEqual(out, "<REDACTED:pan:1> <REDACTED:pan:2> <REDACTED:pan:1>")
        self.assertEqual(counts, {"pan": 3})


class SecretTest(unittest.TestCase):
    def check(self, text, kind, keep=""):
        out, counts = sanitize.redact(text)
        self.assertEqual(counts, {kind: 1}, out)
        self.assertIn(f"<REDACTED:{kind}:1>", out)
        return out

    def test_aws_access_key(self):
        out = self.check("key AKIA" + "IOSFODNN7EXAMPLE here", "aws-access-key")
        self.assertNotIn("AKIA", out)
        self.check("ASIA" + "IOSFODNN7EXAMPLE", "aws-access-key")

    def test_aws_role_and_user_ids_are_kept(self):
        for text in ("AROAIOSFODNN7EXAMPLE", "AIDAIOSFODNN7EXAMPLE", "AKIA-short", "AKIA" + "IOSFODNN7EXAMPLEXX"):
            self.assertEqual(sanitize.redact(text)[0], text)

    def test_aws_secret_key(self):
        secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        out = self.check(f"aws_secret_access_key = {secret}", "aws-secret-key")
        self.assertTrue(out.startswith("aws_secret_access_key = "))
        self.assertNotIn(secret, out)
        self.check(f'"aws_secret_access_key": "{secret}"', "aws-secret-key")

    def test_github_slack_stripe_tokens(self):
        for token in ("ghp_" + "a1B2" * 9, "github_pat_" + "A1b2C3" * 5, "xoxb-" + "1234567890-abcdefghij",
                      "sk_live_" + "abcd1234" * 3, "glpat-" + "x" * 20):
            self.check(f"t={token}", "token")

    def test_private_key_block(self):
        text = "a\n-----BEGIN RSA PRIV" + "ATE KEY-----\nMIIEow\nabc\n-----END RSA PRIV" + "ATE KEY-----\nb"
        self.assertEqual(sanitize.redact(text)[0], "a\n<REDACTED:private-key:1>\nb")

    def test_truncated_private_key_is_redacted_to_the_end(self):
        out = sanitize.redact("x\n-----BEGIN PRIV" + "ATE KEY-----\nMIIEow\nabc")[0]
        self.assertEqual(out, "x\n<REDACTED:private-key:1>")

    def test_public_key_and_certificate_are_kept(self):
        text = "-----BEGIN PUBLIC KEY-----\nMIIB\n-----END PUBLIC KEY-----"
        self.assertEqual(sanitize.redact(text)[0], text)

    def test_jwt(self):
        jwt = "ey" + "JhbgciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r"
        self.check(f"token {jwt}", "jwt")
        self.check("ey" + "JhbgciOiJub25lIn0.eyJzdWIiOiIxMjM0NTY3ODkwIn0.", "jwt")

    def test_bearer_header_keeps_the_scheme(self):
        out = self.check("Authorization: Bearer abcdef0123456789abcdef", "bearer")
        self.assertEqual(out, "Authorization: Bearer <REDACTED:bearer:1>")
        self.check("authorization: basic dXNlcjpwYXNzd29yZDEyMzQ1", "bearer")

    def test_bearer_prose_is_kept(self):
        text = "the bearer of this letter"
        self.assertEqual(sanitize.redact(text)[0], text)

    def test_password_in_url(self):
        out = self.check("postgres://admin:s3cr3t" + "Pass@db.internal:5432/pay", "url-password")
        self.assertEqual(out, "postgres://admin:<REDACTED:url-password:1>@db.internal:5432/pay")

    def test_url_templates_and_userinfo_without_password_are_kept(self):
        for text in ("postgres://admin:${DB_PASSWORD}@db/pay", "https://user@example.com/x", "https://example.com:8443/a@b",
                     "postgres://admin:{{ .Values.pw }}@db/pay", "redis://:@host"):
            self.assertEqual(sanitize.redact(text)[0], text, text)

    def test_secret_assignments(self):
        for text in ("password = hunter2" + "hunter2", 'db_pass' + 'word: "correct-horse-battery"', '"client_secret": "' + "abcd" + '1234efgh"',
                     "API_KEY=" + "01234567" + "89abcdef", "export GITHUB_" + "TOKEN=notarealtoken1"):
            out, counts = sanitize.redact(text)
            self.assertEqual(counts, {"secret": 1}, text)
            self.assertIn("<REDACTED:secret:1>", out)

    def test_assignment_keeps_the_name_and_the_quotes(self):
        self.assertEqual(sanitize.redact('db_pass' + 'word: "correct-horse-battery"')[0], 'db_password: "<REDACTED:secret:1>"')

    def test_references_and_templates_are_not_secrets(self):
        for text in ("password = var.db_password", "token: ${{ secrets.GITHUB_TOKEN }}", "secret: ${SECRET_VALUE}",
                     "password: <your-password>", "password: {{.Values.password}}", "token = module.x.token_value", "password: changeme",
                     "secret_name: pay-prod-db-credentials", "token_endpoint: /oauth/token", "secretKeyRef: db-secret-name",
                     "password: short", "tokenizer = something-long-enough", "bypass: something-long-enough", "password: {{ .Values.pw }}"):
            self.assertEqual(sanitize.redact(text), (text, {}), text)

    def test_only_the_listed_reference_forms_are_kept(self):
        for text in ("password = random_password.db.result", "secret: $(SECRET_VALUE)", "api_key = lookup(var.keys, env)",
                     "password = ./secrets/file", "token = local.some_token_value"):
            self.assertEqual(sanitize.redact(text)[1], {"secret": 1}, text)

    def test_idempotent(self):
        text = "password = hunter2" + "hunter2 AKIA" + "IOSFODNN7EXAMPLE " + make_pan("4", 16)
        once = sanitize.redact(text)[0]
        self.assertEqual(sanitize.redact(once), (once, {}))


class RedactorTest(unittest.TestCase):
    def test_placeholders_are_stable_across_calls_and_counts_add_up(self):
        r = sanitize.Redactor()
        self.assertEqual(r.redact("AKIA" + "IOSFODNN7EXAMPLE"), "<REDACTED:aws-access-key:1>")
        self.assertEqual(r.redact("ASIA" + "IOSFODNN7EXAMPLF AKIA" + "IOSFODNN7EXAMPLE"),
                         "<REDACTED:aws-access-key:2> <REDACTED:aws-access-key:1>")
        self.assertEqual(r.counts["aws-access-key"], 3)
        self.assertEqual(r.total, 3)

    def test_kinds_are_numbered_separately(self):
        r = sanitize.Redactor()
        out = r.redact("AKIA" + "IOSFODNN7EXAMPLE " + make_pan("4", 16))
        self.assertEqual(out, "<REDACTED:aws-access-key:1> <REDACTED:pan:1>")

    def test_no_secret_is_stored(self):
        r = sanitize.Redactor()
        r.redact("AKIA" + "IOSFODNN7EXAMPLE")
        self.assertNotIn("AKIA" + "IOSFODNN7EXAMPLE", repr(r.__dict__))

    def test_emails_only_when_asked(self):
        text = "mail me at jane.doe+pay@example.co.uk"
        self.assertEqual(sanitize.redact(text), (text, {}))
        out, counts = sanitize.redact(text, redact_emails=True)
        self.assertEqual(out, "mail me at <REDACTED:email:1>")
        self.assertEqual(counts, {"email": 1})

    def test_url_userinfo_is_not_taken_for_an_email(self):
        text = "git@github.com:org/repo.git"
        self.assertEqual(sanitize.redact(text, redact_emails=False)[0], text)

    def test_empty_and_none(self):
        self.assertEqual(sanitize.redact("")[0], "")
        self.assertIsNone(sanitize.Redactor().redact(None))

    def test_multiline_diff_text(self):
        text = "+  password = \"hunter2" + "hunter2\"\n+  region = \"eu-central-1\"\n"
        self.assertEqual(sanitize.redact(text)[0], '+  password = "<REDACTED:secret:1>"\n+  region = "eu-central-1"\n')


if __name__ == "__main__":
    unittest.main()
