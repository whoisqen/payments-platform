import sys
import unittest
from pathlib import Path

CI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI))
import changed_images as ci  # noqa: E402

CFG = ci.parse_paths((CI / "image-paths.yaml").read_text(encoding="utf-8"))


class ChangedImagesTest(unittest.TestCase):
    def test_config_shape(self):
        self.assertEqual(set(CFG["images"]), set(ci.SERVICES))
        self.assertIn("docker/_common/", CFG["rebuild_all"])

    def test_locker_only(self):
        self.assertEqual(ci.images_for(["vendor/card-vault/src/main.rs"], CFG), (["locker"], False))

    def test_hyperswitch_crate_builds_the_three_services(self):
        images, everything = ci.images_for(["vendor/hyperswitch/crates/router/src/lib.rs"], CFG)
        self.assertEqual(images, ["router", "drainer", "scheduler"])
        self.assertFalse(everything)

    def test_common_dir_rebuilds_all(self):
        self.assertEqual(ci.images_for(["docker/_common/budgets.yaml"], CFG), (ci.SERVICES, True))

    def test_unclaimed_vendor_path_rebuilds_all(self):
        self.assertTrue(ci.images_for(["vendor/new-thing/a.rs"], CFG)[1])

    def test_docs_and_readme_build_nothing(self):
        self.assertEqual(ci.images_for(["docs/a.md", "docker/README.md", "infra/x.tf"], CFG), ([], False))

    def test_compose_stack_builds_nothing(self):
        self.assertEqual(ci.images_for(["docker/compose/compose.yaml", "docker/compose/migrate.sh"], CFG), ([], False))
        self.assertTrue(ci.areas_for(["docker/compose/compose.yaml"], CFG)["compose"])

    def test_node_and_workflows_areas(self):
        a = ci.areas_for(["tests/load/lib/run.js", ".github/workflows/ci.yml"], CFG)
        self.assertTrue(a["node"] and a["workflows"])
        self.assertFalse(ci.areas_for(["tools/ci/images_yaml.py"], CFG)["node"])

    def test_areas(self):
        a = ci.areas_for(["infra/github/main.tf", "scripts/dr/failover.py"], CFG)
        self.assertTrue(a["terraform"] and a["python"] and a["shell"])
        self.assertFalse(a["helm"] or a["policy"])

    def test_each_vendored_rust_workspace_has_its_own_area(self):
        hyperswitch = ci.areas_for(["vendor/hyperswitch/crates/router_env/src/logger.rs"], CFG)
        self.assertTrue(hyperswitch["rust_hyperswitch"])
        self.assertFalse(hyperswitch["rust_card_vault"])
        vault = ci.areas_for(["vendor/card-vault/src/main.rs"], CFG)
        self.assertTrue(vault["rust_card_vault"])
        self.assertFalse(vault["rust_hyperswitch"])

    def test_directory_prefix_does_not_match_sibling(self):
        self.assertFalse(ci.matches("docker/router-x/Dockerfile", "docker/router/"))

    def test_parse_rejects_unknown_syntax(self):
        with self.assertRaises(ValueError):
            ci.parse_paths("a:\n  b: c\n")


if __name__ == "__main__":
    unittest.main()
