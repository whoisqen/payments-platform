import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import next_version as nv  # noqa: E402


def commits(*subjects, body=""):
    return [nv.parse_commit("a" * 40, s, body) for s in subjects]


class NextVersionTest(unittest.TestCase):
    def test_fix_bumps_patch(self):
        self.assertEqual(nv.next_version("v1.2.3", commits("fix(router): handle timeout")), ("v1.2.4", "patch"))

    def test_feat_bumps_minor_and_resets_patch(self):
        self.assertEqual(nv.next_version("v1.2.3", commits("fix: a", "feat(infra): b")), ("v1.3.0", "minor"))

    def test_bang_bumps_major(self):
        self.assertEqual(nv.next_version("v1.2.3", commits("feat(router)!: drop v0 api")), ("v2.0.0", "major"))

    def test_breaking_footer_bumps_major(self):
        c = commits("fix: a", body="BREAKING CHANGE: field renamed")
        self.assertEqual(nv.next_version("v1.2.3", c), ("v2.0.0", "major"))

    def test_other_types_still_raise_patch(self):
        self.assertEqual(nv.next_version("v1.2.3", commits("docs: a", "chore(ci): b")), ("v1.2.4", "patch"))

    def test_first_release(self):
        self.assertEqual(nv.next_version(None, commits("feat: a")), ("v0.1.0", "minor"))

    def test_rel_tag_is_rejected(self):
        with self.assertRaises(ValueError):
            nv.next_version("rel-2026.11.22.1", commits("fix: a"))

    def test_changelog_groups_and_sorts_sections(self):
        text = nv.changelog("v1.3.0", commits("feat(infra): add a", "fix(router): b", "docs: c", "feat!: d"))
        self.assertLess(text.index("Breaking changes"), text.index("Features"))
        self.assertLess(text.index("Features"), text.index("Fixes"))
        self.assertIn("**infra**: add a", text)
        self.assertIn("Other changes", text)

    def test_parse_log_round_trip(self):
        raw = f"{'b' * 40}{nv.SEP}feat(ci): x{nv.SEP}body{nv.END}\n{'c' * 40}{nv.SEP}fix: y{nv.SEP}{nv.END}"
        parsed = nv.parse_log(raw)
        self.assertEqual([c["type"] for c in parsed], ["feat", "fix"])

    def test_non_conventional_subject_is_other(self):
        self.assertEqual(nv.parse_commit("a" * 40, "Merge stuff", "")["type"], "other")


if __name__ == "__main__":
    unittest.main()
