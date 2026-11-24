"""Audit fixes: redaction of raw diff lines, evasion forms, redact-before-cut, guardrail, comment output, trigger rules.

Every secret and card number is built at run time, so no source line holds a real-looking value."""
import base64
import datetime
import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import review  # noqa: E402
import sanitize  # noqa: E402
from tests.test_sanitize import make_pan  # noqa: E402

CFG = review.load_yaml(review.CONFIG)
CDE = review.load_yaml(review.CDE_PATHS)["cde_paths"]
PAN = make_pan("4", 16)
SECRET = "".join(["hunter", "2", "hunter", "2"])


def diff_of(path, body, start=1):
    n = body.count("\n")
    return f"diff --git a/{path} b/{path}\nindex 1..2 100644\n--- a/{path}\n+++ b/{path}\n@@ -{start},{n} +{start},{n} @@\n{body}"


def redacted(text, **kw):
    return sanitize.Redactor().redact(text, **kw)


class RawDiffTest(unittest.TestCase):
    def annotate(self, body):
        text, numbered = review.annotate(diff_of("a.txt", body), sanitize.Redactor())
        return text, numbered

    def test_card_on_a_removed_line(self):
        for line in (f"-card {PAN}", f"-{PAN}", f"--{PAN}", f"-id_{PAN}", f"-x{PAN}", f"-n-{PAN}"):
            text, _ = self.annotate(f" keep\n{line}\n+new\n")
            self.assertNotIn(PAN, text, line)
            self.assertNotIn(PAN[:8], text, line)
            self.assertIn("<REDACTED:pan:1>", text)

    def test_removed_secret_assignment(self):
        text, _ = self.annotate(f"-password = {SECRET}\n+password = var.x\n")
        self.assertNotIn(SECRET, text)

    def test_line_numbers_survive_multiline_redaction(self):
        key = "-----BEGIN PRIVATE" + " KEY-----"
        end = "-----END PRIVATE" + " KEY-----"
        body = (f" a\n+{key}\n+MIIEvQIBADANBg\n-old line\n+{end}\n+ db_password: |\n+   {SECRET}\n+   {SECRET}\n"
                f"+card {PAN[:4]}\n+{PAN[4:]}\n+tail\n")
        raw = review.annotate(diff_of("a.txt", body))
        red = review.annotate(diff_of("a.txt", body), sanitize.Redactor())
        self.assertEqual(raw[1], red[1])
        self.assertEqual(raw[0].count("\n"), red[0].count("\n"))
        self.assertIn("+tail", red[0])
        self.assertNotIn(SECRET, red[0])

    def test_unicode_line_separators_do_not_shift_numbers(self):
        body = " a b\u000cc\n+d\n"
        _, numbered = review.annotate(diff_of("a.txt", body), sanitize.Redactor())
        self.assertEqual(numbered, {1, 2})

    def test_hunk_header_context_is_redacted(self):
        d = f"diff --git a/a b/a\n@@ -1,1 +1,1 @@ password = {SECRET}\n x\n"
        self.assertNotIn(SECRET, review.annotate(d, sanitize.Redactor())[0])


class EvasionTest(unittest.TestCase):
    def assert_pan_gone(self, text):
        out = redacted(text)
        self.assertIn("<REDACTED:pan:", out, text)
        self.assertNotIn(PAN[:6] + PAN[6:10], out)

    def test_separators_and_prefixes(self):
        groups = [PAN[i:i + 4] for i in range(0, 16, 4)]
        for sep in ("-", " ", ".", "/", "_", "\t"):
            self.assert_pan_gone(f"card {sep.join(groups)} end")
        for prefix in ("x", "id_", "id-", "n:", "#"):
            self.assert_pan_gone(prefix + PAN)

    def test_non_ascii_digits_and_invisible_characters(self):
        fullwidth = "".join(chr(0xFF10 + int(c)) for c in PAN)
        arabic = "".join(chr(0x0660 + int(c)) for c in PAN)
        self.assert_pan_gone(f"pan {fullwidth}")
        self.assert_pan_gone(f"pan {arabic}")
        self.assert_pan_gone("pan " + "​".join(PAN))
        self.assert_pan_gone("pan " + "⁠".join(PAN[i:i + 4] for i in range(0, 16, 4)))

    def test_pan_after_a_longer_number_group(self):
        self.assert_pan_gone(f"2024-01-02 {PAN[:4]} {PAN[4:8]} {PAN[8:12]} {PAN[12:]}")

    def test_decimals_and_long_digit_runs_stay(self):
        for text in (f"0.{PAN}", "1" * 23, "order 1234567890123456789012"):
            self.assertEqual(redacted(text), text)

    def test_json_escaped_secret(self):
        out = redacted('{\\"db_password\\": \\"' + SECRET + '\\", \\"x\\": 1}')
        self.assertNotIn(SECRET, out)
        out = redacted('{"password": "a\\u0062cdefgh1"}')
        self.assertIn("<REDACTED:secret:1>", out)

    def test_escaped_newline_is_not_a_line_break(self):
        self.assertEqual(redacted("a\\nb\\\\nc").count("\n"), 0)


class AssignmentTest(unittest.TestCase):
    def test_quoted_span_with_spaces_commas_and_quotes(self):
        for value in ("correct horse, battery staple", "it's a long one", 'with \\"inner\\" quotes here'):
            out = redacted(f'password: "{value}" # note')
            self.assertEqual(out, 'password: "<REDACTED:secret:1>" # note', value)
        self.assertEqual(redacted("secret = 'two words, here'"), "secret = '<REDACTED:secret:1>'")

    def test_yaml_block_scalar(self):
        text = f"a: 1\nsecret_value: |\n  {SECRET}\n  more {SECRET}\nnext: 2\n"
        out = redacted(text, keep_lines=True)
        self.assertEqual(out, "a: 1\nsecret_value: |\n  <REDACTED:secret:1>\n\nnext: 2\n")
        self.assertEqual(redacted("token: >-\n  {{ .Values.token }}\nz: 1\n"), "token: >-\n  {{ .Values.token }}\nz: 1\n")
        self.assertEqual(redacted(f"- passphrase: |\n    {SECRET}\n- other: x\n").count("REDACTED"), 1)

    def test_more_key_names(self):
        for key in ("pass", "passwd", "passphrase", "credentials", "dsn", "secret_value", "auth_token", "db.pass", "SENTRY_DSN"):
            self.assertIn("<REDACTED:secret:1>", redacted(f"{key}: {SECRET}"), key)
        self.assertEqual(redacted(f"bypass: {SECRET}"), f"bypass: {SECRET}")

    def test_token_formats(self):
        for token in ("sk-ant-" + "api03-" + "abcdEFGH" * 4, "whsec_" + "abcd1234" * 3):
            self.assertEqual(redacted(f"k {token}"), "k <REDACTED:token:1>")

    def test_base64_that_decodes_to_a_secret(self):
        for plain in (f"password={SECRET}{SECRET}", "AKIA" + "IOSFODNN7EXAMPLE and more text", f"card {PAN} and some more text to pad"):
            out = redacted("blob: " + base64.b64encode(plain.encode()).decode())
            self.assertIn("<REDACTED:b64-secret:1>", out)
        harmless = base64.b64encode(b"just some long harmless text for a config file").decode()
        self.assertEqual(redacted(harmless), harmless)

    def test_kubernetes_secret_data(self):
        value = base64.b64encode(b"x" * 12).decode()
        manifest = f"apiVersion: v1\nkind: Secret\nmetadata:\n  name: a\ndata:\n  user: {value}\n  pw: cGFzcw==\nstringData:\n  k: plain-value-here\n"
        out = redacted(manifest)
        self.assertNotIn(value, out)
        self.assertNotIn("cGFzcw==", out)
        self.assertNotIn("plain-value-here", out)
        self.assertIn("name: a", out)
        config_map = manifest.replace("Secret", "ConfigMap")
        self.assertEqual(redacted(config_map), config_map)
        self.assertNotIn("cGFzcw==", redacted("data:\n  pw: cGFzcw==\n", k8s_secret=True))
        template = "kind: Secret\ndata:\n  pw: {{ .Values.pw | b64enc }}\n"
        self.assertEqual(redacted(template), template)

    def test_kubernetes_secret_is_scoped_per_document(self):
        text = "kind: ConfigMap\ndata:\n  a: some-config-value\n---\nkind: Secret\ndata:\n  b: c29tZXRoaW5n\n"
        out = redacted(text)
        self.assertIn("some-config-value", out)
        self.assertNotIn("c29tZXRoaW5n", out)

    def test_every_new_rule_is_idempotent(self):
        text = (f"password: \"two words {SECRET}\"\nsecret_value: |\n  {SECRET}\nkind: Secret\ndata:\n  k: cGFzc3dvcmQ=\n"
                f"blob: {base64.b64encode(('password=' + SECRET).encode()).decode()}\nid_{PAN}\nsk-ant-{'a1' * 12}\n")
        once = redacted(text)
        self.assertEqual(redacted(once), once)


class CutTest(unittest.TestCase):
    def test_redaction_comes_before_the_cut(self):
        for pad in range(0, 12):
            body = f"+{'x' * (100 + pad)} {PAN}\n+tail\n"
            diffs = {"a.py": diff_of("a.py", body)}
            cfg = {**CFG, "limits": {**CFG["limits"], "max_file_diff_bytes": 100 + pad + 12}}
            reviewed, _, _ = review.select(diffs, [], cfg, CDE, sanitize.Redactor())
            text = reviewed["a.py"]["text"]
            self.assertNotRegex(text, r"\d{6}", pad)
            self.assertNotIn(PAN[:4], text)

    def test_trailing_digits_are_dropped(self):
        self.assertEqual(review.drop_trailing_digits("abc 411111"), "abc ")
        self.assertEqual(review.drop_trailing_digits("abc 4111 1111 11"), "abc ")
        self.assertEqual(review.drop_trailing_digits("abc 41111"), "abc 41111")
        self.assertEqual(review.drop_trailing_digits("abc 123456 x"), "abc 123456 x")

    def test_body_is_redacted_then_cut(self):
        limit = CFG["limits"]["max_body_chars"]
        for pad in range(0, 10):
            pr = {"title": "t", "body": "y" * (limit - 8 + pad) + " " + PAN + " " + SECRET}
            _, user = review.build_prompt(CFG, pr, {}, [], sanitize.Redactor(), "D")
            self.assertNotIn(PAN[:6], user)
            self.assertNotIn(SECRET[:6], user)


class FakeClient:
    def __init__(self, reply=None, stop="end_turn"):
        self.calls, self.reply, self.stop = [], reply or {"summary": "s", "findings": []}, stop

    def converse(self, **kw):
        self.calls.append(kw)
        return {"output": {"message": {"content": [{"text": json.dumps(self.reply)}]}}, "stopReason": self.stop}


def cfg_guardrail(**g):
    return {**CFG, "model": {**CFG["model"], "guardrail": g}}


class GuardrailTest(unittest.TestCase):
    def test_config_is_attached(self):
        client = FakeClient()
        review.converse(client, cfg_guardrail(id="gr-1", version=2), "sys", "usr")
        sent = client.calls[0]
        self.assertEqual(sent["guardrailConfig"]["guardrailIdentifier"], "gr-1")
        self.assertEqual(sent["guardrailConfig"]["guardrailVersion"], "2")
        self.assertEqual(sent["modelId"], CFG["model"]["id"])

    def test_empty_id_is_not_set_and_warns(self):
        client, out = FakeClient(), io.StringIO()
        with redirect_stdout(out):
            review.converse(client, cfg_guardrail(id="", version=""), "sys", "usr")
        self.assertNotIn("guardrailConfig", client.calls[0])
        self.assertIn("::warning::", out.getvalue())
        self.assertNotIn("usr", out.getvalue())

    def test_version_is_required_with_an_id(self):
        with self.assertRaises(ValueError):
            review.converse_args(cfg_guardrail(id="gr-1", version=""), "s", "u")

    def test_intervention_is_an_error_without_content(self):
        with self.assertRaises(review.GuardrailBlocked) as ctx:
            review.converse(FakeClient(stop="guardrail_intervened"), cfg_guardrail(id="g", version="1"), "s", "u")
        self.assertNotIn("u", str(ctx.exception).replace("guardrail", "").replace("intervened", "").replace("the", ""))

    def test_the_shipped_config_has_the_keys(self):
        self.assertIn("guardrail", CFG["model"])
        self.assertIn("min_minutes_between_reviews", CFG["trigger"])


class CommentTest(unittest.TestCase):
    def render(self, **f):
        finding = {"file": "a.py", "line": 5, "severity": "high", "title": "t", "evidence": "e", "fix": "f", **f}
        return review.render(CFG, "sum", [finding], 0, [], False, "m", "a" * 40)

    def test_markdown_images_links_and_urls_are_removed(self):
        body = self.render(evidence="see ![x](http://evil.example/p.png) and [click](http://evil.example) or https://evil.example/a?b=1 or www.evil.example/z")
        self.assertNotIn("evil.example", body)
        self.assertNotIn("![", body)
        self.assertIn("click", body)

    def test_markup_is_escaped_in_every_field(self):
        raw = "a`b [c](d) *e* _f_ | g <h> @user #1"
        body = self.render(title=raw, evidence=raw, fix=raw)
        lines = [ln for ln in body.splitlines() if "a\\`b" in ln]
        self.assertEqual(len(lines), 3)
        for ln in lines:
            self.assertNotIn("](", ln)
            self.assertIn("\\*e\\*", ln)
            self.assertIn("\\|", ln)
            self.assertIn("&lt;h&gt;", ln)
            self.assertNotIn("@user", ln)
        self.assertEqual(review.clean("a\n- b\n# c"), "a - b \\# c")
        self.assertEqual(review.clean("a\\b"), "a\\\\b")

    def test_a_secret_in_a_model_field_is_redacted(self):
        self.assertNotIn(PAN, self.render(fix=f"card {PAN}"))

    def test_file_paths_are_fenced(self):
        body = self.render(file="a`b.py")
        self.assertIn("`` a`b.py:5 ``", body)
        self.assertEqual(review.code("x.py"), "`x.py`")
        self.assertEqual(review.code("a``b"), "``` a``b ```")
        out = review.render(CFG, "", [], 0, ["p`q.py"], True, "m")
        self.assertIn("`` p`q.py ``", out)

    def test_no_redaction_count_and_head_marker(self):
        body = self.render()
        self.assertNotIn("redacted", body.lower())
        self.assertIn(f"<!-- ai-review-head: {'a' * 40} -->", body)
        self.assertTrue(body.startswith(CFG["comment"]["marker"]))

    def test_existing_comment_is_matched_by_the_actions_bot_login(self):
        marker = CFG["comment"]["marker"]
        comments = [{"id": 1, "body": marker, "user": {"login": "someone", "type": "Bot"}},
                    {"id": 2, "body": marker, "user": {"login": "evil-app[bot]", "type": "Bot"}},
                    {"id": 3, "body": "x", "user": {"login": "github-actions[bot]"}},
                    {"id": 4, "body": marker + " old", "user": {"login": "github-actions[bot]"}}]
        with mock.patch.object(review, "github", return_value=comments):
            self.assertEqual(review.find_comment("o/r", 1, "t", marker)["id"], 4)
        with mock.patch.object(review, "github", return_value=comments[:3]):
            self.assertIsNone(review.find_comment("o/r", 1, "t", marker))

    def test_upsert_creates_when_only_a_foreign_marker_exists(self):
        marker = CFG["comment"]["marker"]
        calls = []

        def fake(method, path, token, payload=None):
            calls.append(method)
            return [{"id": 1, "body": marker, "user": {"login": "x[bot]"}}] if method == "GET" else None
        with mock.patch.object(review, "github", fake):
            self.assertEqual(review.upsert_comment("o/r", 1, "t", marker, "b"), "created")
        self.assertEqual(calls, ["GET", "POST"])

    def test_last_review_reads_sha_and_time(self):
        comment = {"body": f"x\n<!-- ai-review-head: {'b' * 40} -->", "updated_at": "2026-11-25T10:00:00Z"}
        last = review.last_review(comment)
        self.assertEqual(last["sha"], "b" * 40)
        self.assertEqual(last["updated_at"], datetime.datetime(2026, 11, 25, 10, tzinfo=datetime.timezone.utc))
        self.assertIsNone(review.last_review(None))


class TriggerTest(unittest.TestCase):
    now = datetime.datetime(2026, 11, 25, 12, 0, tzinfo=datetime.timezone.utc)
    trigger = {"run_label": "ai-review:run", "min_minutes_between_reviews": 30}

    def decide(self, action, label=None, last=None, head="h2"):
        return review.decide_trigger(action, label, head, last, self.now, self.trigger)

    def last(self, minutes, sha="h1"):
        return {"sha": sha, "updated_at": self.now - datetime.timedelta(minutes=minutes)}

    def test_opened_and_ready_always_review(self):
        for action in (None, "opened", "ready_for_review"):
            self.assertIsNone(self.decide(action, last=self.last(1)))

    def test_run_label_only(self):
        self.assertIsNone(self.decide("labeled", "ai-review:run", self.last(1)))
        self.assertIn("does not start", self.decide("labeled", "bug"))

    def test_push_rules(self):
        self.assertIsNone(self.decide("synchronize"))
        self.assertIsNone(self.decide("synchronize", last=self.last(31)))
        self.assertIsNone(self.decide("synchronize", last={"sha": None, "updated_at": self.now - datetime.timedelta(hours=2)}))
        self.assertIn("min ago", self.decide("synchronize", last=self.last(5)))
        self.assertIn("already", self.decide("synchronize", last=self.last(500, sha="h2")))

    def test_other_events(self):
        self.assertIn("does not start", self.decide("edited"))


if __name__ == "__main__":
    unittest.main()
