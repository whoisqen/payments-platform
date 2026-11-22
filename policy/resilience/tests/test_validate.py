import copy
import json
import sys
import unittest
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import validate  # noqa: E402

SCHEMA = json.loads((HERE.parent / "schema.json").read_text())
POLICY = yaml.safe_load((HERE.parent / "policy.yaml").read_text())


def mutated(dep, **changes):
    doc = copy.deepcopy(POLICY)
    doc["dependencies"][dep].update(changes)
    return doc


class ResiliencePolicyTest(unittest.TestCase):
    def test_committed_policy_is_valid(self):
        self.assertEqual(validate.validate(POLICY, SCHEMA), [])

    def test_missing_required_field_fails(self):
        doc = copy.deepcopy(POLICY)
        del doc["dependencies"]["aurora"]["timeout"]
        self.assertTrue(any("missing timeout" in e for e in validate.validate(doc, SCHEMA)))

    def test_jitter_must_be_full(self):
        errors = validate.validate(mutated("aurora", jitter="none"), SCHEMA)
        self.assertTrue(any("jitter" in e for e in errors))

    def test_charge_is_never_retried(self):
        errors = validate.validate(mutated("psp-authorize", max_attempts=1, base="1s", cap="2s"), SCHEMA)
        self.assertTrue(any("charge" in e for e in errors))

    def test_non_idempotent_cannot_retry(self):
        errors = validate.validate(mutated("memorydb", idempotent=False), SCHEMA)
        self.assertTrue(any("idempotent" in e for e in errors))

    def test_budget_above_ten_percent_fails(self):
        doc = copy.deepcopy(POLICY)
        doc["defaults"]["retry_budget_ratio"] = 0.25
        self.assertTrue(any("above 0.1" in e for e in validate.validate(doc, SCHEMA)))

    def test_cap_below_base_fails(self):
        errors = validate.validate(mutated("aurora", base="1s", cap="500ms"), SCHEMA)
        self.assertTrue(any("base <= cap" in e for e in errors))

    def test_unlimited_needs_bound(self):
        doc = mutated("kafka-producer")
        del doc["dependencies"]["kafka-producer"]["bounded_by"]
        self.assertTrue(any("bounded_by" in e for e in validate.validate(doc, SCHEMA)))

    def test_worst_case_beyond_deadline_fails(self):
        errors = validate.validate(mutated("aurora", timeout="20s"), SCHEMA)
        self.assertTrue(any("request deadline" in e for e in errors))

    def test_webhook_schedule_matches_attempts(self):
        errors = validate.validate(mutated("outgoing-webhooks", max_attempts=4), SCHEMA)
        self.assertTrue(any("schedule" in e for e in errors))

    def test_bad_dependency_name_fails(self):
        doc = copy.deepcopy(POLICY)
        doc["dependencies"]["Bad_Name"] = doc["dependencies"].pop("aurora")
        self.assertTrue(any("bad name" in e for e in validate.validate(doc, SCHEMA)))


if __name__ == "__main__":
    unittest.main()
