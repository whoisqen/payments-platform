import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

CI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI))
import changed_images as ci  # noqa: E402

CFG = ci.parse_paths((CI / "image-paths.yaml").read_text(encoding="utf-8"))
AREAS = ci.parse_paths((CI / "areas.yaml").read_text(encoding="utf-8"))
ROOT = CI.parents[1]
RUST = {"rust_hyperswitch", "rust_card_vault", "rust_cell_lookup"}


def areas(files, **kw):
    return ci.areas_for(files, AREAS, **kw)


def unclaimed(tops):
    claims = [e for entries in AREAS["areas"].values() for e in entries]
    claims += [e for k, entries in AREAS["common"].items() if k != "rust_mise_tools" for e in entries]
    claims += AREAS["lint_only"]
    return sorted(t for t in tops if not any(c == t or c.startswith(t) for c in claims))


def on(result):
    return {k for k, v in result[0].items() if v}


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

    def test_kind_stage_builds_nothing(self):
        self.assertEqual(ci.images_for(["scripts/kind/up.sh", "tools/ci/kind/kind_images.py"], CFG), ([], False))
        self.assertTrue(areas(["scripts/kind/cluster.yaml", "deploy/local/helmfile.yaml"])[0]["kind"])

    def test_node_and_workflows_areas(self):
        a = areas(["tests/load/lib/run.js", ".github/workflows/images.yml"])[0]
        self.assertTrue(a["node"] and a["workflows"])
        self.assertFalse(areas(["tools/lint/spec-lint"])[0]["node"])

    def test_areas(self):
        a = areas(["infra/github/main.tf", "scripts/dr/failover.py"])[0]
        self.assertTrue(a["terraform"] and a["python"])
        self.assertFalse(a["helm"] or a["policy"])

    def test_each_vendored_rust_workspace_has_its_own_area(self):
        hyperswitch = areas(["vendor/hyperswitch/crates/router_env/src/logger.rs"])[0]
        self.assertTrue(hyperswitch["rust_hyperswitch"])
        self.assertFalse(hyperswitch["rust_card_vault"])
        vault = areas(["vendor/card-vault/src/main.rs"])[0]
        self.assertTrue(vault["rust_card_vault"])
        self.assertFalse(vault["rust_hyperswitch"])

    def test_directory_prefix_does_not_match_sibling(self):
        self.assertFalse(ci.matches("docker/router-x/Dockerfile", "docker/router/"))

    def test_parse_rejects_unknown_syntax(self):
        with self.assertRaises(ValueError):
            ci.parse_paths("a:\n  b: c\n")

    def test_areas_file_is_not_an_image_input(self):
        self.assertNotIn("tools/ci/areas.yaml", CFG["rebuild_all"])
        self.assertNotIn("areas", CFG)
        self.assertEqual(ci.images_for(["tools/ci/areas.yaml"], CFG), ([], False))

    def test_paths_output_ignores_the_areas_file(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            ci.main(["--paths", "router"])
        self.assertNotIn("areas.yaml", buf.getvalue())

    def test_lint_only_change_runs_no_area(self):
        self.assertEqual(areas(["docs/a.md", "specs/001-x/spec.md", "README.md", "renovate.json5"]), ({k: False for k in AREAS["areas"]}, False))

    def test_platform_config_runs_python_only(self):
        self.assertEqual(on(areas(["config/platform.yaml"])), {"python"})
        self.assertEqual(on(areas(["config/environments/dev.yaml"])), {"python"})

    def test_shared_tooling_runs_every_area_but_rust(self):
        everything_but_rust = set(AREAS["areas"]) - RUST
        for f in ["Makefile", "mise.toml", "tools/ci/next_version.py", ".github/workflows/ci.yml", ".github/workflows/security.yml"]:
            with self.subTest(f=f):
                self.assertEqual(areas([f]), ({k: k not in RUST for k in AREAS["areas"]}, False))
                self.assertEqual(on(areas([f])), everything_but_rust)

    def test_other_workflow_runs_only_the_workflows_area(self):
        self.assertEqual(on(areas([".github/workflows/nightly.yml"])), {"workflows"})

    def test_root_toolchain_runs_both_rust_areas_on_every_crate(self):
        for f in ["rust-toolchain", "rust-toolchain.toml"]:
            with self.subTest(f=f):
                self.assertEqual(areas([f]), ({k: k in RUST for k in AREAS["areas"]}, True))

    def test_vendor_lockfile_runs_only_its_own_workspace(self):
        a, rust_all = areas(["vendor/hyperswitch/Cargo.lock"])
        self.assertEqual({k for k, v in a.items() if v}, {"rust_hyperswitch"})
        self.assertFalse(rust_all)
        self.assertEqual(on(areas(["vendor/card-vault/Cargo.lock"])), {"rust_card_vault"})

    def test_mise_rust_line_adds_rust_to_the_shared_tooling_areas(self):
        self.assertEqual(areas(["mise.toml"], mise_rust=True), ({k: True for k in AREAS["areas"]}, True))

    def test_mise_line_detection(self):
        tools = AREAS["common"]["rust_mise_tools"]
        diff = "--- a/mise.toml\n+++ b/mise.toml\n@@ -1 +1 @@\n"
        self.assertTrue(ci.mise_rust_lines_changed(diff + '-cargo-nextest = "0.9.1"\n+cargo-nextest = "0.9.2"\n', tools))
        self.assertTrue(ci.mise_rust_lines_changed(diff + '+rust = "1.94.1"\n', tools))
        self.assertTrue(ci.mise_rust_lines_changed(diff + '-"rust" = "1.94.0"\n', tools))
        self.assertFalse(ci.mise_rust_lines_changed(diff + '+"github:EmbarkStudios/cargo-deny" = "0.18.4"\n', tools))
        self.assertFalse(ci.mise_rust_lines_changed(diff + '+ruff = "0.17.7"\n+rustfmt-note = "x"\n', tools))
        self.assertFalse(ci.mise_rust_lines_changed(diff + ' rust = "1.94.1"\n', tools))

    def test_mise_diff_argument(self):
        diff = Path(self.tmp) / "mise.diff"
        diff.write_text('+cargo-nextest = "0.9.153"\n', encoding="utf-8")
        files = Path(self.tmp) / "files"
        files.write_text("mise.toml\n", encoding="utf-8")
        out = self.run_main(["--files-from", str(files), "--mise-diff", str(diff)])
        self.assertTrue(out["area_rust_hyperswitch"] and out["area_rust_card_vault"] and out["area_rust_cell_lookup"] and out["rust_all"])

    def test_full_label_runs_every_area_and_every_crate(self):
        self.assertEqual(areas(["docs/a.md"], labels=["hotfix", "ci:full"]), ({k: True for k in AREAS["areas"]}, True))
        self.assertEqual(areas(["docs/a.md"], labels=["hotfix"]), ({k: False for k in AREAS["areas"]}, False))

    def test_labels_argument(self):
        files = Path(self.tmp) / "files"
        files.write_text("docs/a.md\n", encoding="utf-8")
        out = self.run_main(["--files-from", str(files), "--labels", "dependencies, ci:full"])
        self.assertTrue(all(v for k, v in out.items() if k.startswith("area_")) and out["rust_all"])

    def test_daily_mode_runs_every_area_but_rust(self):
        out = self.run_main(["--mode", "full"])
        self.assertEqual({k[5:] for k, v in out.items() if k.startswith("area_") and v}, set(AREAS["areas"]) - RUST)
        self.assertFalse(out["rust_all"])

    def test_weekly_mode_runs_only_rust_on_every_crate(self):
        out = self.run_main(["--mode", "rust"])
        self.assertEqual({k[5:] for k, v in out.items() if k.startswith("area_") and v}, RUST)
        self.assertTrue(out["rust_all"])

    def test_unknown_diff_runs_everything(self):
        out = self.run_main(["--head", "HEAD"])
        self.assertTrue(all(v for k, v in out.items() if k.startswith("area_")) and out["rust_all"] and out["all"])

    def test_rust_areas_and_rules_name_known_areas(self):
        self.assertEqual(set(AREAS["rust_areas"]), RUST)
        self.assertLessEqual(RUST, set(AREAS["areas"]))
        self.assertEqual(set(AREAS["common"]), {"python_only", "all_but_rust", "rust", "rust_mise_tools"})

    def test_every_area_is_an_output_of_the_changes_job(self):
        wf = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        outputs = set(re.findall(r"^      (area_\w+|rust_all): \$\{\{ steps\.paths\.outputs\.\1 \}\}$", wf, re.M))
        self.assertEqual(outputs, {f"area_{k}" for k in AREAS["areas"]} | {"rust_all"})

    def test_every_top_level_entry_is_claimed(self):
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True)
        if out.returncode != 0 or not out.stdout:
            self.skipTest("not a git checkout")
        tops = {p.split("/", 1)[0] + ("/" if "/" in p else "") for p in out.stdout.splitlines()}
        self.assertEqual(unclaimed(tops), [], "add each new top-level entry to an area, to common or to lint_only in tools/ci/areas.yaml")

    def test_guard_catches_an_unclaimed_entry(self):
        self.assertEqual(unclaimed({"docs/", "config/", "vendor/", "Makefile", "newdir/", "new-file.toml"}), ["new-file.toml", "newdir/"])

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def run_main(self, argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            ci.main(argv)
        return json.loads(buf.getvalue())


if __name__ == "__main__":
    unittest.main()
