import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "promote"))
import select_revision as sr  # noqa: E402

A, B, C = "a" * 40, "b" * 40, "c" * 40


def payload(**kw):
    return json.dumps({"environment": "dev", "app": "x", "cell": "c1", "revisions": [A], **kw})


class ValidateTest(unittest.TestCase):
    def test_good(self):
        self.assertEqual(sr.validate("smoke-green-dev", payload(revisions=[A, B, A])), [A, B])

    def test_environment_mismatch(self):
        with self.assertRaises(sr.PayloadError):
            sr.validate("smoke-green-stage", payload())

    def test_bad_action(self):
        for action in ("", "smoke-green-", "smoke-green-dev;id", "other"):
            with self.assertRaises(sr.PayloadError):
                sr.validate(action, payload())

    def test_not_json_or_not_object(self):
        for raw in ("", "nope", "[]", "null"):
            with self.assertRaises(sr.PayloadError):
                sr.validate("smoke-green-dev", raw)

    def test_bad_revisions(self):
        bad = [[], "a" * 40, [A[:39]], [A.upper()], [A + "0"], ["--upload-pack=x"], [A, 5], [None], [A + "\n"]]
        for revisions in bad:
            with self.assertRaises(sr.PayloadError, msg=revisions):
                sr.validate("smoke-green-dev", payload(revisions=revisions))

    def test_missing_revisions(self):
        with self.assertRaises(sr.PayloadError):
            sr.validate("smoke-green-dev", json.dumps({"environment": "dev"}))


class SyncedTest(unittest.TestCase):
    def test_picks_the_ancestor(self):
        self.assertEqual(sr.synced([A, B], lambda s: s == B, lambda s: s), B)

    def test_newest_of_several(self):
        order = {C: 0, B: 1, A: 2}
        self.assertEqual(sr.synced([A, B, C], lambda s: s != C, lambda s: sorted(s, key=order.get)), B)

    def test_none_on_main(self):
        with self.assertRaises(sr.PayloadError):
            sr.synced([A], lambda s: False, lambda s: s)


if __name__ == "__main__":
    unittest.main()
