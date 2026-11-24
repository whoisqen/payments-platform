import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_victoria  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_victoria.render(CFG)
DOCS = list(yaml.safe_load_all(OUT[render_victoria.OUT / "vmbackup.yaml"]))
CLASS = yaml.safe_load(OUT[render_victoria.OUT / "storageclass.yaml"])
JOBS = [d for d in DOCS if d and d["kind"] == "CronJob"]
VALUES = yaml.safe_load((ROOT / "deploy" / "platform" / "victoria-metrics" / "values.yaml").read_text(encoding="utf-8"))


class RenderVictoriaTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run tools/config/render_victoria.py: {path}")

    def test_one_job_per_storage_node(self):
        self.assertEqual(len(JOBS), VALUES["vmstorage"]["replicaCount"])
        self.assertEqual(len({j["metadata"]["name"] for j in JOBS}), len(JOBS))

    def test_each_job_runs_on_the_node_of_its_pod_and_reads_its_volume_only(self):
        for i, job in enumerate(JOBS):
            pod = f"vm-victoria-metrics-cluster-vmstorage-{i}"
            spec = job["spec"]["jobTemplate"]["spec"]["template"]["spec"]
            term = spec["affinity"]["podAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"][0]
            self.assertEqual(term["labelSelector"]["matchLabels"]["statefulset.kubernetes.io/pod-name"], pod)
            self.assertEqual(term["topologyKey"], "kubernetes.io/hostname")
            self.assertEqual(spec["volumes"][0]["persistentVolumeClaim"], {"claimName": f"vmstorage-volume-{pod}", "readOnly": True})
            self.assertTrue(spec["containers"][0]["volumeMounts"][0]["readOnly"])

    def test_backups_go_to_the_bucket_of_terraform_in_a_path_per_node(self):
        prefix, region = CFG["naming"]["prefix"], CFG["regions"]["working"]
        area, direction, number = region.split("-")
        bucket = f"{prefix}-shared-services-{area}{direction[0]}{number}-vmbackup"
        for i, job in enumerate(JOBS):
            args = job["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]["args"]
            self.assertIn(f"-dst=s3://{bucket}/vmstorage-{i}", args)
            self.assertTrue(any(a.startswith("-snapshot.createURL=http://vm-victoria-metrics-cluster-vmstorage-") for a in args))

    def test_the_jobs_do_not_overlap_and_run_without_privileges(self):
        self.assertEqual(len({j["spec"]["schedule"] for j in JOBS}), len(JOBS))
        for job in JOBS:
            spec = job["spec"]["jobTemplate"]["spec"]["template"]["spec"]
            self.assertEqual(job["spec"]["concurrencyPolicy"], "Forbid")
            self.assertTrue(spec["securityContext"]["runAsNonRoot"])
            self.assertTrue(spec["containers"][0]["securityContext"]["readOnlyRootFilesystem"])
            self.assertIn("@sha256:", spec["containers"][0]["image"])

    def test_the_storage_class_is_encrypted_and_keeps_the_volume(self):
        self.assertEqual(CLASS["metadata"]["name"], VALUES["vmstorage"]["persistentVolume"]["storageClassName"])
        self.assertEqual(CLASS["parameters"]["encrypted"], "true")
        self.assertTrue(CLASS["parameters"]["kmsKeyId"].startswith("arn:aws:kms:"))
        self.assertEqual(CLASS["reclaimPolicy"], "Retain")


if __name__ == "__main__":
    unittest.main()
