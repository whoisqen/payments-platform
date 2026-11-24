import sys
import unittest
from pathlib import Path

CI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI / "migrations"))
import migration_check as mc  # noqa: E402

R = "vendor/hyperswitch/migrations"
OLD = "2026-01-01-000000_old"
GOOD_VALUES = "snapshot:\n  enabled: true\n  retentionDays: 35\nmigrate:\n  mode: x\n"
GOOD_JOB = "initContainers:\n  - name: pre-migration-snapshot\n    env:\n      - name: SNAPSHOT_RETENTION_DAYS\n"


def run(files, up="ALTER TABLE t ADD COLUMN c text;", existing=(OLD,), contract=False, guard=None, meta=None, status="A"):
    """files: {dir: [file names]}; every dir is new unless listed in existing."""
    changes = [(status, f"{R}/{d}/{f}") for d, fs in files.items() for f in fs]
    present = {f"{R}/{d}/{f}" for d, fs in files.items() for f in fs}
    text = {f"{R}/{d}/up.sql": up for d in files}
    if meta is not None:
        text.update({f"{R}/{d}/metadata.toml": meta for d in files})
        present |= set(text)
    return mc.check({R: set(existing), "vendor/card-vault/migrations": set()}, changes, lambda p: text.get(p, ""), lambda p: p in present, contract, guard)


NEW = "2026-02-01-000000_add_c"
BOTH = {NEW: ["up.sql", "down.sql"]}


class CheckTest(unittest.TestCase):
    def test_expand_migration_passes(self):
        self.assertEqual(run(BOTH), ([], []))

    def test_down_missing(self):
        errors, _ = run({NEW: ["up.sql"]})
        self.assertTrue(any("down.sql is missing" in e for e in errors))

    def test_bad_name(self):
        errors, _ = run({"20260201_add": ["up.sql", "down.sql"]})
        self.assertTrue(any("name must be" in e for e in errors))

    def test_duplicate_timestamp(self):
        errors, _ = run({"2026-01-01-000000_other": ["up.sql", "down.sql"]})
        self.assertTrue(any("one directory per timestamp" in e for e in errors))

    def test_two_new_with_same_timestamp(self):
        errors, _ = run({NEW: ["up.sql", "down.sql"], "2026-02-01-000000_b": ["up.sql", "down.sql"]})
        self.assertTrue(any("one directory per timestamp" in e for e in errors))

    def test_out_of_order(self):
        errors, _ = run({"2025-12-31-235959_late": ["up.sql", "down.sql"]})
        self.assertTrue(any("older than the newest" in e for e in errors))

    def test_destructive_needs_label(self):
        errors, _ = run(BOTH, up="ALTER TABLE t DROP COLUMN c;")
        self.assertTrue(any("contract-migration" in e for e in errors))

    def test_rename_is_destructive(self):
        errors, _ = run(BOTH, up="ALTER TABLE t RENAME COLUMN a TO b;")
        self.assertTrue(any("rename" in e for e in errors))

    def test_set_not_null_is_destructive(self):
        errors, _ = run(BOTH, up="ALTER TABLE t ALTER COLUMN a SET NOT NULL;")
        self.assertTrue(any("set not null" in e for e in errors))

    def test_comment_is_ignored(self):
        self.assertEqual(run(BOTH, up="-- DROP TABLE t;\nALTER TABLE t ADD COLUMN c text;"), ([], []))

    def test_mixed_expand_and_contract(self):
        errors, _ = run(BOTH, up="ALTER TABLE t ADD COLUMN c text;\nALTER TABLE t DROP COLUMN a;", contract=True, guard=lambda: [])
        self.assertTrue(any("split expand and contract" in e for e in errors))

    def test_contract_with_label_and_snapshot(self):
        self.assertEqual(run(BOTH, up="ALTER TABLE t DROP COLUMN a;", contract=True, guard=lambda: []), ([], []))

    def test_contract_without_snapshot(self):
        errors, _ = run(BOTH, up="DROP TABLE t;", contract=True, guard=lambda: ["no snapshot"])
        self.assertTrue(any("no snapshot" in e for e in errors))

    def test_concurrently_needs_metadata(self):
        errors, _ = run(BOTH, up="CREATE INDEX CONCURRENTLY i ON t (c);")
        self.assertTrue(any("run_in_transaction = false" in e for e in errors))

    def test_concurrently_with_metadata(self):
        self.assertEqual(run(BOTH, up="CREATE INDEX CONCURRENTLY i ON t (c);", meta="run_in_transaction = false\n"), ([], []))

    def test_metadata_without_concurrently_warns(self):
        errors, warnings = run(BOTH, meta="run_in_transaction = false\n")
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1)

    def test_modified_existing_is_a_warning(self):
        errors, warnings = run({OLD: ["up.sql", "down.sql"]}, status="M")
        self.assertEqual(errors, [])
        self.assertTrue(any("modified" in w for w in warnings))

    def test_initial_setup_name(self):
        self.assertEqual(mc.stamp("00000000000000_diesel_initial_setup"), "00000000000000")


class SnapshotGuardTest(unittest.TestCase):
    def test_good(self):
        self.assertEqual(mc.snapshot_guard(GOOD_VALUES, GOOD_JOB), [])

    def test_wrong_init_container_name(self):
        errors = mc.snapshot_guard(GOOD_VALUES, GOOD_JOB.replace("pre-migration-snapshot", "snapshot"))
        self.assertEqual(len(errors), 1)
        self.assertIn("pre-migration-snapshot", errors[0])

    def test_disabled_or_short_retention(self):
        errors = mc.snapshot_guard(GOOD_VALUES.replace("true", "false").replace("35", "7"), GOOD_JOB)
        self.assertEqual(len(errors), 2)


class ChangesTest(unittest.TestCase):
    def test_new_dirs(self):
        changes = [("A", f"{R}/{NEW}/up.sql"), ("M", f"{R}/{OLD}/up.sql"), ("A", "README.md")]
        self.assertEqual(mc.new_dirs({R: {OLD}}, changes), [(R, NEW)])


if __name__ == "__main__":
    unittest.main()
