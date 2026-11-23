import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from contracts import minischema, model  # noqa: E402


def schema(chart):
    return model.load_json(model.CHARTS / chart / "values.schema.json")


class ValuesAgainstSchema(unittest.TestCase):
    def test_every_environment_release_satisfies_its_chart_schema(self):
        checked = 0
        for env in model.environments():
            for region in model.regions(env):
                for release in model.releases(env, region):
                    for label, chart, vals in model.schema_targets(env, region, release):
                        with self.subTest(values=label, chart=chart):
                            self.assertEqual(minischema.errors(vals, schema(chart)), [])
                            checked += 1
        self.assertGreaterEqual(checked, 50)

    def test_chart_defaults_and_ci_values_satisfy_the_schema(self):
        for sch in sorted(model.CHARTS.glob("*/values.schema.json")):
            chart = sch.parent
            files = [f for f in (chart / "values.yaml", chart / "ci" / "lint-values.yaml") if f.is_file()]
            vals = {}
            for f in files:
                vals = model.merge(vals, model.load_yaml(f))
            vals = model.with_digest(vals) if chart.name not in ("payments-edge", "payments-cell", "payments-locker") else vals
            with self.subTest(chart=chart.name):
                self.assertEqual([e for e in minischema.errors(vals, model.load_json(sch)) if "required global" not in e
                                  and "required gateway" not in e], [])

    def test_every_values_chart_has_a_schema(self):
        for chart in sorted(model.CHARTS.iterdir()):
            if (chart / "values.yaml").is_file():
                with self.subTest(chart=chart.name):
                    self.assertTrue((chart / "values.schema.json").is_file())

    def test_every_release_directory_maps_to_a_chart_and_has_values(self):
        for env in model.environments():
            for region in model.regions(env):
                for release in model.releases(env, region):
                    with self.subTest(release=f"{env}/{region}/{release}"):
                        self.assertTrue((model.CHARTS / model.chart_for(release)).is_dir())
                        self.assertTrue((model.ENVS / env / region / release / "values.yaml").is_file())

    def test_no_values_file_carries_a_tag_or_inline_secret(self):
        for f in sorted(model.ENVS.rglob("*.yaml")):
            text = f.read_text(encoding="utf-8").lower()
            with self.subTest(file=str(f.relative_to(model.REPO))):
                self.assertNotIn("password:", text)
                self.assertNotIn("secret_key", text)
                self.assertNotIn("tag:", text)


class SchemaValidatorItself(unittest.TestCase):
    def test_router_schema_rejects_a_tag_in_place_of_a_digest(self):
        vals = model.with_digest(model.load_yaml(model.CHARTS / "router" / "values.yaml"))
        vals["image"]["digest"] = "latest"
        self.assertTrue(any("digest" in e for e in minischema.errors(vals, schema("router"))))

    def test_missing_digest_is_reported(self):
        vals = model.load_yaml(model.CHARTS / "router" / "values.yaml")
        self.assertTrue(any("missing required digest" in e for e in minischema.errors(vals, schema("router"))))

    def test_unexpected_property_and_wrong_type_are_reported(self):
        vals = model.with_digest(model.load_yaml(model.CHARTS / "router" / "values.yaml"))
        vals["image"]["extra"] = 1
        vals["service"]["port"] = "8080"
        found = minischema.errors(vals, schema("router"))
        self.assertTrue(any("unexpected property extra" in e for e in found), found)
        self.assertTrue(any("expected integer" in e for e in found), found)

    def test_edge_schema_rejects_a_bad_cell_name(self):
        _, vals = model.layered("dev", "eu-central-1", "edge")
        vals["routing"]["cells"][0]["name"] = "cell-9"
        self.assertTrue(any("cell-9" in e for e in minischema.errors(vals, schema("payments-edge"))))

    def test_unsupported_keyword_raises_instead_of_passing(self):
        with self.assertRaises(ValueError):
            minischema.errors(1, {"multipleOf": 2})

    def test_conditionals_and_enums(self):
        sch = {"if": {"properties": {"a": {"const": 1}}, "required": ["a"]}, "then": {"required": ["b"]}}
        self.assertEqual(minischema.errors({"a": 2}, sch), [])
        self.assertEqual(len(minischema.errors({"a": 1}, sch)), 1)
        self.assertEqual(len(minischema.errors("x", {"enum": ["y"]})), 1)


if __name__ == "__main__":
    unittest.main()
