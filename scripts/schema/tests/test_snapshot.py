import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "pre-migration-snapshot.sh"
ARN = "arn:aws:rds:eu-central-1:123456789012:cluster:pay-prod-euc1-cell-1-aurora-payments"
FAKE_AWS = """#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$2" in
  start-backup-job) echo job-1 ;;
  describe-backup-job)
    if [[ "$*" == *RecoveryPointArn* ]]; then echo arn:aws:backup:rp-1; else echo "${FAKE_STATE:-COMPLETED}"; fi ;;
  describe-recovery-point) echo "${FAKE_RP:-COMPLETED}" ;;
esac
"""


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        bindir = Path(self.tmp.name) / "bin"
        bindir.mkdir()
        aws = bindir / "aws"
        aws.write_text(FAKE_AWS)
        aws.chmod(aws.stat().st_mode | stat.S_IXUSR)
        self.log = Path(self.tmp.name) / "calls.log"
        self.env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "FAKE_LOG": str(self.log)}

    def run_script(self, *args, **env):
        return subprocess.run(["bash", str(SCRIPT), *args], env={**self.env, **env}, capture_output=True, text=True)

    def base(self, *extra):
        return ["--store", "aurora", "--resource-arn", ARN, "--label", "add-card-index", *extra]

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_dry_run_makes_no_aws_call(self):
        r = self.run_script(*self.base("--dry-run"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("would-start-backup", r.stdout)
        self.assertEqual(self.calls(), [])

    def test_retention_and_tag_are_set(self):
        r = self.run_script(*self.base("--role-arn", "arn:aws:iam::123456789012:role/backup", "--poll-seconds", "0"))
        self.assertEqual(r.returncode, 0, r.stderr)
        start = self.calls()[0]
        self.assertIn("DeleteAfterDays=35", start)
        self.assertIn("change=add-card-index", start)
        self.assertIn("available", r.stdout)

    def test_same_change_uses_same_token(self):
        args = self.base("--role-arn", "arn:aws:iam::123456789012:role/backup", "--poll-seconds", "0")
        self.run_script(*args)
        self.run_script(*args)
        starts = [c for c in self.calls() if c.startswith("backup start-backup-job")]
        tokens = {c.split("--idempotency-token ")[1].split()[0] for c in starts}
        self.assertEqual(len(starts), 2)
        self.assertEqual(len(tokens), 1)

    def test_failed_job_blocks_the_migration(self):
        r = self.run_script(*self.base("--role-arn", "arn:aws:iam::123456789012:role/backup"), FAKE_STATE="FAILED")
        self.assertEqual(r.returncode, 1)

    def test_unavailable_recovery_point_blocks_the_migration(self):
        r = self.run_script(*self.base("--role-arn", "arn:aws:iam::123456789012:role/backup", "--poll-seconds", "0"), FAKE_RP="PARTIAL")
        self.assertEqual(r.returncode, 1)

    def test_timeout_while_running(self):
        r = self.run_script(*self.base("--role-arn", "arn:aws:iam::123456789012:role/backup", "--wait-seconds", "0"), FAKE_STATE="RUNNING")
        self.assertEqual(r.returncode, 1)
        self.assertIn("timeout", r.stdout)

    def test_bad_input_is_rejected_before_any_call(self):
        for bad in (["--label", "Bad Label"], ["--resource-arn", "not-an-arn"], ["--store", "redis"]):
            args = self.base("--dry-run")
            i = args.index(bad[0])
            args[i + 1] = bad[1]
            self.assertEqual(self.run_script(*args).returncode, 2, bad)
        self.assertEqual(self.calls(), [])

    def test_role_required_without_dry_run(self):
        self.assertEqual(self.run_script(*self.base()).returncode, 2)

    def test_opensearch_is_not_supported(self):
        args = self.base("--dry-run")
        args[1] = "opensearch"
        self.assertEqual(self.run_script(*args).returncode, 2)


if __name__ == "__main__":
    unittest.main()
