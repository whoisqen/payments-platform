import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "tools" / "ci"))

import digest_compare  # noqa: E402
import images_yaml  # noqa: E402
from contracts import minischema, model  # noqa: E402


def d(n):
    return "sha256:" + format(n, "x").rjust(64, "0")


def run(mod, *argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = mod.main(list(argv))
    return rc, out.getvalue()


class Promotion(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.dev = self.root / "dev" / "images.yaml"
        self.stage = self.root / "stage" / "images.yaml"
        self.build = self.root / "digests.json"
        self.build.write_text(json.dumps({s: d(i + 1) for i, s in enumerate(images_yaml.SERVICES)}))

    def publish_to_dev(self):
        rc, out = run(images_yaml, "digests", str(self.build))
        self.assertEqual(rc, 0)
        pairs = [line for line in out.splitlines() if line]
        self.assertEqual(len(pairs), len(images_yaml.SERVICES))
        self.assertEqual(run(images_yaml, "set", str(self.dev), *pairs)[0], 0)

    def test_dev_to_stage_by_digest(self):
        self.publish_to_dev()
        before = self.root / "stage-before.yaml"
        self.stage.parent.mkdir()
        rc, out = run(images_yaml, "copy", str(self.dev), str(self.stage))
        self.assertEqual(rc, 0)
        self.assertIn("changed", out)
        self.assertEqual(images_yaml.load(self.stage), images_yaml.load(self.dev))
        before.write_text("")
        self.assertEqual(run(images_yaml, "verify", str(self.dev), str(before), str(self.stage))[0], 0)

    def test_copy_is_idempotent(self):
        self.publish_to_dev()
        self.stage.parent.mkdir()
        run(images_yaml, "copy", str(self.dev), str(self.stage))
        rc, out = run(images_yaml, "copy", str(self.dev), str(self.stage))
        self.assertEqual((rc, out.strip()), (0, "images-yaml: unchanged"))

    def test_partial_promotion_moves_only_named_services(self):
        self.publish_to_dev()
        self.stage.parent.mkdir()
        run(images_yaml, "copy", str(self.dev), str(self.stage))
        run(images_yaml, "set", str(self.dev), f"router={d(99)}")
        before = self.root / "before.yaml"
        before.write_text(self.stage.read_text())
        run(images_yaml, "copy", str(self.dev), str(self.stage), "--services", "router")
        self.assertEqual(images_yaml.load(self.stage)["router"], d(99))
        self.assertEqual(images_yaml.load(self.stage)["drainer"], images_yaml.load(before)["drainer"])

    def test_dry_run_writes_nothing(self):
        self.publish_to_dev()
        rc, out = run(images_yaml, "copy", str(self.dev), str(self.stage), "--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("would change", out)
        self.assertFalse(self.stage.exists())

    def test_digest_not_from_dev_is_a_violation(self):
        self.publish_to_dev()
        self.stage.parent.mkdir()
        self.stage.write_text(images_yaml.render({"router": d(777)}))
        before = self.root / "before.yaml"
        before.write_text("")
        rc, out = run(images_yaml, "verify", str(self.dev), str(before), str(self.stage))
        self.assertEqual(rc, 1)
        self.assertIn("router", out)

    def test_rollback_to_a_digest_that_ran_in_stage_is_allowed_with_history(self):
        self.publish_to_dev()
        old = self.root / "history.txt"
        old.write_text(f"router {d(500)}\n")
        self.stage.parent.mkdir()
        self.stage.write_text(images_yaml.render({"router": d(500)}))
        before = self.root / "before.yaml"
        before.write_text(images_yaml.render({"router": d(1)}))
        self.assertEqual(run(images_yaml, "verify", str(self.dev), str(before), str(self.stage))[0], 1)
        self.assertEqual(run(images_yaml, "verify", str(self.dev), str(before), str(self.stage), "--history", str(old))[0], 0)

    def test_tags_and_unknown_services_are_rejected(self):
        for pair in ("router=latest", "router=sha256:abc", "nope=" + d(1)):
            with self.subTest(pair=pair), self.assertRaises(ValueError):
                run(images_yaml, "set", str(self.dev), pair)
        self.assertFalse(self.dev.exists())

    def test_malformed_images_yaml_is_refused(self):
        with self.assertRaises(ValueError):
            images_yaml.parse("images:\n  router: latest\n")

    def test_render_parse_roundtrip_keeps_service_order(self):
        imgs = {s: d(i + 1) for i, s in enumerate(reversed(images_yaml.SERVICES))}
        text = images_yaml.render(imgs)
        self.assertEqual(images_yaml.parse(text), imgs)
        self.assertEqual([ln.split(":")[0].strip() for ln in text.splitlines()[1:]], images_yaml.SERVICES)

    def test_promoted_digests_land_in_the_stage_chart_values(self):
        self.publish_to_dev()
        self.stage.parent.mkdir()
        run(images_yaml, "copy", str(self.dev), str(self.stage))
        promoted = images_yaml.load(self.stage)
        for release in model.releases("stage", "eu-central-1"):
            for label, chart, vals in model.schema_targets("stage", "eu-central-1", release):
                if chart not in promoted:
                    continue
                vals = {**vals, "image": {**vals.get("image", {}), "digest": promoted[chart]}}
                with self.subTest(label=label):
                    schema = model.load_json(model.CHARTS / chart / "values.schema.json")
                    self.assertEqual(minischema.errors(vals, schema), [])
                    self.assertEqual(vals["image"]["digest"], images_yaml.load(self.dev)[chart])

    def test_committed_images_files_are_well_formed_and_dev_first(self):
        for env in model.environments():
            f = model.ENVS / env / "images.yaml"
            if f.is_file():
                with self.subTest(env=env):
                    self.assertTrue(set(images_yaml.load(f)) <= set(images_yaml.SERVICES))
        self.assertFalse((model.ENVS / "stage" / "images.yaml").is_file() and not (model.ENVS / "dev" / "images.yaml").is_file())


class DigestCompare(unittest.TestCase):
    def files(self, rebuilt, reference):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        a, b = Path(tmp.name) / "a.json", Path(tmp.name) / "b.json"
        a.write_text(json.dumps(rebuilt))
        b.write_text(json.dumps(reference))
        return str(a), str(b)

    def test_identical_rebuild_passes(self):
        a, b = self.files({"router": d(1)}, {"router": d(1)})
        rc, out = run(digest_compare, "compare", "--rebuilt", a, "--reference", b)
        self.assertEqual(rc, 0)
        self.assertIn("0 mismatch", out)

    def test_different_digest_fails_and_names_the_service(self):
        a, b = self.files({"router": d(1), "drainer": d(2)}, {"router": d(1), "drainer": d(3)})
        rc, out = run(digest_compare, "compare", "--rebuilt", a, "--reference", b)
        self.assertEqual(rc, 1)
        self.assertIn("drainer", out)
        self.assertIn("1 mismatch", out)

    def test_service_without_reference_is_only_a_warning(self):
        a, b = self.files({"router": d(1)}, {})
        rc, out = run(digest_compare, "compare", "--rebuilt", a, "--reference", b)
        self.assertEqual(rc, 0)
        self.assertIn("warning", out)

    def test_metadata_digest_validation(self):
        self.assertEqual(digest_compare.metadata_digest({"containerimage.digest": d(4)}), d(4))
        for bad in ({}, {"containerimage.digest": "latest"}, {"containerimage.digest": 5}):
            with self.assertRaises(ValueError):
                digest_compare.metadata_digest(bad)


if __name__ == "__main__":
    unittest.main()
