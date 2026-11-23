import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import deployed_tags as dt  # noqa: E402

A = "sha256:" + "a" * 64
B = "sha256:" + "b1c2" + "0" * 60


class DeployedTagsTest(unittest.TestCase):
    def test_tag_is_the_environment_and_twelve_hex_of_the_digest(self):
        self.assertEqual(dt.tags({"router": A, "drainer": B}, "prod"),
                         [("drainer", B, "prod-b1c200000000"), ("router", A, "prod-aaaaaaaaaaaa")])

    def test_unknown_environment_is_rejected(self):
        with self.assertRaises(ValueError):
            dt.tags({"router": A}, "qa")

    def test_empty_file_gives_no_tags(self):
        self.assertEqual(dt.tags({}, "stage"), [])


if __name__ == "__main__":
    unittest.main()
