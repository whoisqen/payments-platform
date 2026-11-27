import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stacks as st  # noqa: E402

CFG = {"regions": {"working": "eu-central-1"}, "vault": {"cell": "cell-0"}}
STACK = 'include "root" {{\n  path = find_in_parent_folders("terragrunt.hcl")\n}}\n{body}\n'
COMMON = 'include "envcommon" {{\n  path = "${{dirname(find_in_parent_folders("terragrunt.hcl"))}}/_envcommon/{name}.hcl"\n}}\n'


def dep(path):
    return f'dependency "x" {{\n  config_path = "{path}"\n}}\n'


class Fixture:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def stack(self, rel, body=""):
        self.write(f"infra/live/{rel}/terragrunt.hcl", STACK.format(body=body))


def repo():
    f = Fixture()
    f.write("infra/live/terragrunt.hcl", "")
    f.write("infra/live/dev/env.hcl", 'cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))\n'
            'own = yamldecode(file("${get_repo_root()}/config/environments/dev.yaml"))\n')
    f.write("infra/live/_envcommon/data/aurora.hcl", 'terraform {\n  source = "${get_repo_root()}/infra/modules//aurora-global"\n}\n')
    f.write("infra/modules/aurora-global/main.tf", 'module "k" {\n  source = "../kms"\n}\n')
    f.write("infra/modules/kms/main.tf", "")
    f.stack("dev/eu-central-1/kms")
    f.stack("dev/eu-central-1/vpc")
    f.stack("dev/eu-central-1/cell-0/eks", dep("../../vpc"))
    f.stack("dev/eu-central-1/cell-0/aurora", COMMON.format(name="data/aurora") + dep("../../kms") + dep("../../vpc"))
    f.stack("dev/eu-central-1/vault", 'locals {\n  vault_cell = include.envcommon.locals.env_cfg.cfg.vault.cell\n}\n' + dep("../${local.vault_cell}/eks"))
    f.stack("dev/us-east-1/edge", dep("../../${local.cfg.regions.working}/kms"))
    f.stack("stage/eu-central-1/kms")
    return f


class StacksTest(unittest.TestCase):
    def setUp(self):
        self.f = repo()
        self.root = self.f.root

    def tearDown(self):
        self.f.tmp.cleanup()

    def build(self, changed=None, stack=None):
        return st.build(self.root, "dev", CFG, changed, stack)

    def test_everything_from_zero_in_dependency_levels(self):
        lv = self.build()["levels"]
        self.assertEqual(lv[0], ["infra/live/dev/eu-central-1/kms", "infra/live/dev/eu-central-1/vpc"])
        flat = [s for level in lv for s in level]
        self.assertLess(flat.index("infra/live/dev/eu-central-1/cell-0/eks"), flat.index("infra/live/dev/eu-central-1/vault"))
        self.assertNotIn("infra/live/stage/eu-central-1/kms", flat)

    def test_interpolated_dependencies_resolve_from_config(self):
        g = st.parse_stack(self.root, "infra/live/dev/eu-central-1/vault", CFG)
        self.assertEqual(g["deps"], ["infra/live/dev/eu-central-1/cell-0/eks"])
        g = st.parse_stack(self.root, "infra/live/dev/us-east-1/edge", CFG)
        self.assertEqual(g["deps"], ["infra/live/dev/eu-central-1/kms"])

    def test_unknown_interpolation_fails(self):
        self.f.stack("dev/eu-central-1/odd", dep("../${local.nowhere}/eks"))
        with self.assertRaises(st.StackError):
            self.build()

    def test_stack_file_change_selects_only_that_stack(self):
        out = self.build(["infra/live/dev/eu-central-1/vpc/terragrunt.hcl"])
        self.assertEqual(out["levels"], [["infra/live/dev/eu-central-1/vpc"]])

    def test_envcommon_and_module_changes_reach_their_stacks(self):
        for f in ("infra/live/_envcommon/data/aurora.hcl", "infra/modules/aurora-global/main.tf", "infra/modules/kms/main.tf"):
            self.assertEqual(self.build([f])["levels"], [["infra/live/dev/eu-central-1/cell-0/aurora"]], f)

    def test_env_and_config_changes_reach_every_stack(self):
        for f in ("infra/live/dev/env.hcl", "config/platform.yaml", "config/environments/dev.yaml", "infra/live/terragrunt.hcl"):
            self.assertEqual(sum(len(x) for x in self.build([f])["levels"]), 6, f)

    def test_other_environment_change_selects_nothing(self):
        self.assertEqual(self.build(["infra/live/stage/eu-central-1/kms/terragrunt.hcl", "docs/x.md"])["levels"], [])

    def test_deps_are_limited_to_the_selection(self):
        out = self.build(["infra/live/dev/eu-central-1/vpc/terragrunt.hcl", "infra/live/dev/eu-central-1/cell-0/eks/terragrunt.hcl"])
        self.assertEqual(out["levels"], [["infra/live/dev/eu-central-1/vpc"], ["infra/live/dev/eu-central-1/cell-0/eks"]])
        self.assertEqual(out["deps"]["infra/live/dev/eu-central-1/cell-0/eks"], ["infra/live/dev/eu-central-1/vpc"])

    def test_removed_stack_is_reported(self):
        out = self.build(["infra/live/dev/eu-central-1/gone/terragrunt.hcl"])
        self.assertEqual(out["removed"], ["infra/live/dev/eu-central-1/gone"])

    def test_cycle_fails(self):
        self.f.stack("dev/eu-central-1/a", dep("../b"))
        self.f.stack("dev/eu-central-1/b", dep("../a"))
        with self.assertRaises(st.StackError):
            self.build()

    def test_dispatch_stack_is_validated(self):
        self.assertEqual(self.build(stack="infra/live/dev/eu-central-1/vpc")["levels"], [["infra/live/dev/eu-central-1/vpc"]])
        for bad in ("infra/live/dev/eu-central-1/nope", "infra/live/dev/../prod/eu-central-1/vpc", "infra/live/cde-prod/eu-central-1/vpc",
                    "infra/live/management/eu-central-1/org-trail", "/etc/passwd"):
            with self.assertRaises(st.StackError, msg=bad):
                st.validate_stack(bad, self.root)


class RealRepositoryTest(unittest.TestCase):
    def test_every_dependency_of_the_live_tree_resolves_and_is_acyclic(self):
        cfg = st.load_cfg(st.ROOT)
        for env in st.APPLY_ENVS:
            out = st.build(st.ROOT, env, cfg)
            for stack, deps in out["deps"].items():
                for d in deps:
                    self.assertTrue((st.ROOT / d / "terragrunt.hcl").is_file(), f"{stack} -> {d}")


if __name__ == "__main__":
    unittest.main()
