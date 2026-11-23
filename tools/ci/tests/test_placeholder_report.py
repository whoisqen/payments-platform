import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import placeholder_report as pr  # noqa: E402


class PlaceholderReportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def test_finds_placeholders_in_scanned_dirs_only(self):
        self.write("deploy/a/values.yaml", "x: 1\nname: REPLACE_NAME\n")
        self.write("infra/live/b/main.hcl", "k = \"REPLACE_KEY\"\n")
        self.write("infra/modules/c.tf", "REPLACE_IGNORED\n")
        found = pr.scan(self.root)
        self.assertEqual(found, [("deploy/a/values.yaml", 2, "REPLACE_NAME"), ("infra/live/b/main.hcl", 1, "REPLACE_KEY")])

    def test_missing_dirs_and_exit_code_is_zero_with_findings(self):
        self.assertEqual(pr.scan(self.root), [])
        self.write("deploy/x.yaml", "REPLACE_A REPLACE_B\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = pr.main([str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("2 REPLACE_ placeholders", buf.getvalue())

    def test_env_filter_keeps_only_that_environment_and_skips_chart_defaults(self):
        self.write("deploy/charts/locker/values.yaml", "id: REPLACE_LOCKER_POD_SG_ID\n")
        self.write("deploy/envs/dev/eu-central-1/locker/values.yaml", "id: REPLACE_LOCKER_POD_SG_ID\n")
        self.write("deploy/envs/stage/eu-central-1/locker/values.yaml", "id: REPLACE_LOCKER_POD_SG_ID\n")
        self.write("infra/live/dev/env.hcl", "x = \"REPLACE_ROLE_ARN\"\n")
        self.assertEqual(len(pr.scan(self.root)), 4)
        self.assertEqual([f for f, _, _ in pr.scan(self.root, env="dev")], ["deploy/envs/dev/eu-central-1/locker/values.yaml", "infra/live/dev/env.hcl"])

    def test_strict_fails_only_when_a_placeholder_remains(self):
        self.write("deploy/envs/dev/values.yaml", "id: REPLACE_X\n")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(pr.main([str(self.root), "--env", "dev", "--strict"]), 1)
            self.assertEqual(pr.main([str(self.root), "--env", "stage", "--strict"]), 0)
            self.assertEqual(pr.main([str(self.root), "--env", "dev"]), 0)

    def test_each_line_names_where_the_value_comes_from_and_who_supplies_it(self):
        self.write("deploy/envs/dev/a.yaml", "a: REPLACE_LOCKER_POD_SG_ID\nb: REPLACE_ACCOUNT_ID\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            pr.main([str(self.root), "--env", "dev"])
        out = buf.getvalue()
        self.assertIn("locker_pod_security_group_id of the eks stack", out)
        self.assertIn("supplied by pipeline", out)
        self.assertIn("REPLACE_ACCOUNT_ID (not in infra/live outputs; supplied by owner)", out)


if __name__ == "__main__":
    unittest.main()
