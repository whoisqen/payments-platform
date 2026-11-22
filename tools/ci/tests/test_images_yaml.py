import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import digest_compare as dc  # noqa: E402
import images_yaml as iy  # noqa: E402

A = "sha256:" + "a" * 64
B = "sha256:" + "b" * 64


class ImagesYamlTest(unittest.TestCase):
    def test_round_trip_keeps_service_order(self):
        text = iy.render({"locker": B, "router": A})
        self.assertEqual(text.splitlines()[1].strip().split(":")[0], "router")
        self.assertEqual(iy.parse(text), {"locker": B, "router": A})

    def test_tag_instead_of_digest_is_rejected(self):
        with self.assertRaises(ValueError):
            iy.update({}, {"router": "v1.2.3"})

    def test_unknown_service_is_rejected(self):
        with self.assertRaises(ValueError):
            iy.update({}, {"nginx": A})

    def test_promotion_must_use_previous_environment_digest(self):
        self.assertEqual(iy.promotion_violations({"router": A}, {"router": B}, {"router": A}), [])
        self.assertEqual(len(iy.promotion_violations({"router": A}, {"router": A}, {"router": B})), 1)

    def test_rollback_to_a_digest_that_ran_before_is_allowed(self):
        self.assertEqual(iy.promotion_violations({"router": A}, {"router": A}, {"router": B}, {B}), [])

    def test_history_file_is_read_by_the_cli(self):
        with tempfile.TemporaryDirectory() as d:
            files = {n: Path(d) / n for n in ("src", "before", "after", "hist")}
            files["src"].write_text(iy.render({"router": A}))
            files["before"].write_text(iy.render({"router": A}))
            files["after"].write_text(iy.render({"router": B}))
            files["hist"].write_text(f"- router: {B}\n")
            args = ["verify", str(files["src"]), str(files["before"]), str(files["after"])]
            self.assertEqual(iy.main(args), 1)
            self.assertEqual(iy.main(args + ["--history", str(files["hist"])]), 0)

    def test_unchanged_entry_is_not_a_violation(self):
        self.assertEqual(iy.promotion_violations({}, {"router": B}, {"router": B}), [])

    def test_set_is_idempotent_and_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "dev" / "images.yaml"
            self.assertEqual(iy.main(["set", str(f), f"router={A}", "--dry-run"]), 0)
            self.assertFalse(f.exists())
            iy.main(["set", str(f), f"router={A}"])
            first = f.read_text()
            iy.main(["set", str(f), f"router={A}"])
            self.assertEqual(f.read_text(), first)

    def test_copy_takes_only_requested_services(self):
        with tempfile.TemporaryDirectory() as d:
            src, dst = Path(d) / "dev.yaml", Path(d) / "stage.yaml"
            src.write_text(iy.render({"router": A, "locker": B}))
            iy.main(["copy", str(src), str(dst), "--services", "locker"])
            self.assertEqual(iy.parse(dst.read_text()), {"locker": B})


class DigestCompareTest(unittest.TestCase):
    def test_metadata_digest(self):
        self.assertEqual(dc.metadata_digest({"containerimage.digest": A}), A)
        with self.assertRaises(ValueError):
            dc.metadata_digest({"image.name": "x"})

    def test_compare_flags_mismatch_and_skips_unknown(self):
        mism, skipped = dc.compare({"router": A, "locker": B, "drainer": A}, {"router": A, "locker": A})
        self.assertEqual([m[0] for m in mism], ["locker"])
        self.assertEqual(skipped, ["drainer"])

    def test_cli_exit_code(self):
        with tempfile.TemporaryDirectory() as d:
            r, f = Path(d) / "r.json", Path(d) / "f.json"
            r.write_text(json.dumps({"router": A}))
            f.write_text(json.dumps({"router": B}))
            self.assertEqual(dc.main(["compare", "--rebuilt", str(r), "--reference", str(f)]), 1)
            f.write_text(json.dumps({"router": A}))
            self.assertEqual(dc.main(["compare", "--rebuilt", str(r), "--reference", str(f)]), 0)


    def test_digests_artifact_validated(self):
        with tempfile.TemporaryDirectory() as d:
            good = Path(d) / "good.json"
            good.write_text(json.dumps({"router": A}), encoding="utf-8")
            self.assertEqual(iy.main(["digests", str(good)]), 0)
            for bad in ({"router": "x=y"}, {"unknown": A}, {"router": 1}, ["router"]):
                f = Path(d) / "bad.json"
                f.write_text(json.dumps(bad), encoding="utf-8")
                with self.assertRaises((ValueError, TypeError)):
                    iy.main(["digests", str(f)])

if __name__ == "__main__":
    unittest.main()
