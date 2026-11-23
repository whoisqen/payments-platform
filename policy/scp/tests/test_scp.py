import fnmatch
import json
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
# SCP limit 5120 characters, backup policy limit 10000 characters, both counted without whitespace.
SCP_LIMIT = 5120
BACKUP_LIMIT = 10000
REGIONS = ["eu-central-1", "us-east-1", "us-east-2"]


def load(path):
    return json.loads(path.read_text())


def minified(doc):
    return json.dumps(doc, separators=(",", ":"))


def statements(doc):
    return {s["Sid"]: s for s in doc["Statement"]}


SCPS = sorted(ROOT.glob("*.json"))


class ScpStructure(unittest.TestCase):
    def test_four_scps_leave_room_under_the_five_per_target_limit(self):
        self.assertLessEqual(len(SCPS), 4)

    def test_every_scp_is_a_valid_deny_only_document_within_the_size_limit(self):
        for path in SCPS:
            with self.subTest(path.name):
                doc = load(path)
                self.assertEqual(doc["Version"], "2012-10-17")
                self.assertLessEqual(len(minified(doc)), SCP_LIMIT)
                sids = [s["Sid"] for s in doc["Statement"]]
                self.assertEqual(len(sids), len(set(sids)))
                for s in doc["Statement"]:
                    self.assertEqual(s["Effect"], "Deny")


class RegionAllowList(unittest.TestCase):
    def test_only_the_three_regions_of_the_region_model_are_allowed(self):
        s = statements(load(ROOT / "region-allow-list.json"))["DenyOutsideAllowedRegions"]
        self.assertEqual(s["Condition"]["StringNotEquals"]["aws:RequestedRegion"], REGIONS)

    def test_eu_west_1_is_not_mentioned(self):
        self.assertNotIn("eu-west-1", (ROOT / "region-allow-list.json").read_text())

    def test_global_services_are_exempt_through_notaction(self):
        s = statements(load(ROOT / "region-allow-list.json"))["DenyOutsideAllowedRegions"]
        self.assertNotIn("Action", s)
        self.assertIn("iam:*", s["NotAction"])
        self.assertIn("organizations:*", s["NotAction"])


class SecurityBaseline(unittest.TestCase):
    def setUp(self):
        self.s = statements(load(ROOT / "security-baseline.json"))

    def actions(self, sid):
        a = self.s[sid]["Action"]
        return [a] if isinstance(a, str) else a

    def test_cloudtrail_config_and_guardduty_cannot_be_disabled(self):
        self.assertIn("cloudtrail:StopLogging", self.actions("DenyDisablingCloudTrail"))
        self.assertIn("config:StopConfigurationRecorder", self.actions("DenyDisablingConfig"))
        self.assertIn("guardduty:DeleteDetector", self.actions("DenyDisablingGuardDuty"))

    def test_leaving_the_organization_is_denied(self):
        self.assertEqual(self.actions("DenyLeavingTheOrganization"), ["organizations:LeaveOrganization"])

    def test_imds_must_be_v2(self):
        cond = self.s["RequireImdsV2WithHopLimitOne"]["Condition"]["StringNotEquals"]
        self.assertEqual(cond["ec2:MetadataHttpTokens"], "required")

    def test_no_iam_users_or_access_keys(self):
        acts = self.actions("DenyIamUsersAndAccessKeys")
        self.assertIn("iam:CreateUser", acts)
        self.assertIn("iam:CreateAccessKey", acts)

    def test_public_s3_is_blocked(self):
        self.assertIn("s3:PutAccountPublicAccessBlock", self.actions("DenyPublicS3AccessBlockChanges"))
        self.assertIn("public-read", self.s["DenyPublicS3Acls"]["Condition"]["StringEquals"]["s3:x-amz-acl"])


class ApplyRoleException(unittest.TestCase):
    """The exception for the Terraform apply role names the role of each account, not any account."""

    def setUp(self):
        cfg = yaml.safe_load((ROOT.parent.parent / "config" / "platform.yaml").read_text())
        self.cfg = cfg
        s = statements(load(ROOT / "security-baseline.json"))
        self.patterns = {
            sid: s[sid]["Condition"]["ArnNotLike"]["aws:PrincipalArn"]
            for sid in ("DenyChangingImdsOptionsExceptTerraform", "DenyPublicS3AccessBlockChanges")
        }

    def excepted(self, sid, arn):
        return any(fnmatch.fnmatchcase(arn, p) for p in self.patterns[sid])

    def test_no_pattern_matches_any_account(self):
        for sid, patterns in self.patterns.items():
            for p in patterns:
                with self.subTest(sid=sid, pattern=p):
                    self.assertNotIn("iam::*", p)
                    self.assertRegex(p, r"^arn:aws:iam::\d{12}:role/")

    def test_patterns_are_derived_from_the_platform_config(self):
        prefix, accounts = self.cfg["naming"]["prefix"], self.cfg["accounts"]
        want = sorted(f"arn:aws:iam::{accounts[env]}:role/{prefix}-{env}-glob-tf-apply-*" for env in ("dev", "stage", "prod") if env in accounts)
        for sid, patterns in self.patterns.items():
            self.assertEqual(sorted(patterns), want, sid)

    def test_apply_role_of_its_own_account_is_excepted(self):
        prefix, accounts = self.cfg["naming"]["prefix"], self.cfg["accounts"]
        for sid in self.patterns:
            self.assertTrue(self.excepted(sid, f"arn:aws:iam::{accounts['stage']}:role/{prefix}-stage-glob-tf-apply-network"))

    def test_same_role_name_in_another_account_is_not_excepted(self):
        prefix = self.cfg["naming"]["prefix"]
        for sid in self.patterns:
            self.assertFalse(self.excepted(sid, f"arn:aws:iam::999999999999:role/{prefix}-stage-glob-tf-apply-network"))

    def test_other_roles_of_the_account_are_not_excepted(self):
        accounts = self.cfg["accounts"]
        for sid in self.patterns:
            self.assertFalse(self.excepted(sid, f"arn:aws:iam::{accounts['stage']}:role/terraform-apply"))
            self.assertFalse(self.excepted(sid, f"arn:aws:iam::{accounts['stage']}:role/{self.cfg['naming']['prefix']}-stage-glob-tf-plan"))


class DenyTagEdit(unittest.TestCase):
    def test_protected_tags_are_editable_only_by_automation(self):
        s = statements(load(ROOT / "deny-tag-edit.json"))["DenyEditingProtectedTagsExceptAutomation"]
        keys = s["Condition"]["ForAnyValue:StringEquals"]["aws:TagKeys"]
        self.assertEqual(sorted(keys), ["backup-tier", "data-class", "managed-by", "pci-scope"])
        self.assertTrue(all(":role/" in a for a in s["Condition"]["ArnNotLike"]["aws:PrincipalArn"]))


class DynamoDbRecoveryRegions(unittest.TestCase):
    def setUp(self):
        self.s = statements(load(ROOT / "deny-dynamodb-writes-recovery-regions.json"))[
            "DenyDynamoDbWritesInRecoveryRegionsExceptReplication"
        ]

    def test_writes_are_denied_in_both_recovery_regions_only(self):
        self.assertEqual(self.s["Condition"]["StringEquals"]["aws:RequestedRegion"], ["us-east-1", "us-east-2"])

    def test_every_write_api_is_listed(self):
        for a in ("PutItem", "UpdateItem", "DeleteItem", "BatchWriteItem", "TransactWriteItems", "ExecuteStatement"):
            self.assertIn("dynamodb:" + a, self.s["Action"])

    def test_only_the_replication_service_role_is_excepted(self):
        principal = self.s["Condition"]["ArnNotLike"]["aws:PrincipalArn"]
        self.assertIn("AWSServiceRoleForDynamoDBReplication", principal)

    def test_reads_are_not_denied(self):
        self.assertFalse([a for a in self.s["Action"] if a.split(":")[1].startswith(("Get", "Query", "Scan", "Describe"))])


class TagPolicy(unittest.TestCase):
    def test_every_key_declares_its_key_name(self):
        tags = load(ROOT / "tag-policies" / "required-tags.json")["tags"]
        self.assertEqual(len(tags), 11)
        for name, spec in tags.items():
            self.assertEqual(spec["tag_key"]["@@assign"], name)


class BackupPolicy(unittest.TestCase):
    def setUp(self):
        self.doc = load(ROOT / "backup-policies" / "backup-tiers.json")

    def test_size_limit(self):
        self.assertLessEqual(len(minified(self.doc)), BACKUP_LIMIT)

    def test_a_plan_exists_for_every_tier_and_selects_by_the_backup_tier_tag(self):
        self.assertEqual(sorted(self.doc["plans"]), ["bronze", "gold", "silver"])
        for tier, plan in self.doc["plans"].items():
            for sel in plan["selections"]["tags"].values():
                self.assertEqual(sel["tag_key"]["@@assign"], "backup-tier")
                self.assertEqual(sel["tag_value"]["@@assign"], [tier])

    def test_gold_is_hourly_with_continuous_backup_35_days_and_copies_to_both_recovery_regions(self):
        rule = self.doc["plans"]["gold"]["rules"]["hourly-35d"]
        self.assertEqual(rule["schedule_expression"]["@@assign"], "cron(0 * ? * * *)")
        self.assertEqual(rule["lifecycle"]["delete_after_days"]["@@assign"], "35")
        self.assertIs(rule["enable_continuous_backup"]["@@assign"], True)
        copies = " ".join(rule["copy_actions"])
        self.assertIn("us-east-1", copies)
        self.assertIn("us-east-2", copies)
        self.assertNotIn("eu-west-1", copies)

    def test_gold_keeps_a_monthly_copy_for_seven_years(self):
        rule = self.doc["plans"]["gold"]["rules"]["monthly-7y"]
        self.assertEqual(rule["lifecycle"]["delete_after_days"]["@@assign"], "2555")

    def test_cold_storage_respects_the_ninety_day_minimum(self):
        rule = self.doc["plans"]["gold"]["rules"]["monthly-7y"]["lifecycle"]
        cold = int(rule["move_to_cold_storage_after_days"]["@@assign"])
        self.assertGreaterEqual(int(rule["delete_after_days"]["@@assign"]) - cold, 90)


if __name__ == "__main__":
    unittest.main()
