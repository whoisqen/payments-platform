import socket
import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from component import harness, run, services  # noqa: E402

FAKE = str(HERE / "fake_service.py")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def fake_spec(port, mode):
    return {"bin_env": "FAKE_BIN", "cwd": ".", "args": [FAKE, str(port), mode], "port": port,
            "health": ["/health", "/health/ready"], "prefix": "FAKE", "env": {"FAKE__PORT": "{port}"}}


class RunTest(unittest.TestCase):
    def check(self, mode, timeout=5.0, grace=5.0):
        port = free_port()
        with mock.patch.dict(services.SPECS, {"fake": fake_spec(port, mode)}):
            return run.check("fake", str(HERE), services.runtime({}), timeout, "", {"FAKE_BIN": sys.executable}, grace)

    def test_healthy_service_passes(self):
        self.assertEqual(self.check("ok")[0], "ok")

    def test_late_readiness_is_awaited(self):
        self.assertEqual(self.check("late")[0], "ok")

    def test_crash_before_health_fails(self):
        status, detail = self.check("crash")
        self.assertEqual(status, "fail")
        self.assertIn("exited with code 3", detail)

    def test_service_ignoring_sigterm_fails(self):
        status, detail = self.check("stubborn", grace=0.5)
        self.assertEqual(status, "fail")
        self.assertIn("SIGTERM", detail)

    def test_missing_binary_is_skipped(self):
        status, detail = run.check("router", str(HERE), services.runtime({}), 1, "", {})
        self.assertEqual(status, "skip")
        self.assertIn("COMPONENT_ROUTER_BIN", detail)


class HarnessTest(unittest.TestCase):
    def test_timeout_names_the_last_answer(self):
        port = free_port()
        with self.assertRaises(harness.ServiceError) as ctx:
            harness.wait_healthy(f"http://127.0.0.1:{port}/health", 0.3, interval=0.05)
        self.assertIn("not healthy", str(ctx.exception))

    def test_child_does_not_inherit_ci_secrets(self):
        with mock.patch.dict("os.environ", {"AWS_SECRET_ACCESS_KEY": "x", "GH_TOKEN": "y"}):
            svc = harness.Service("env", [sys.executable, "-c", "import os,sys; sys.exit(1 if 'GH_TOKEN' in os.environ or 'AWS_SECRET_ACCESS_KEY' in os.environ else 0)"])
            with svc:
                self.assertEqual(svc.proc.wait(10), 0)


class SpecsTest(unittest.TestCase):
    def test_ports_are_unique(self):
        ports = [s["port"] for s in services.SPECS.values()]
        self.assertEqual(len(ports), len(set(ports)))

    def test_env_uses_the_config_prefix_of_the_binary(self):
        for name, spec in services.SPECS.items():
            for key in spec["env"]:
                self.assertTrue(key.startswith(spec["prefix"] + "__") or key == "SCHEDULER_FLOW", f"{name}: {key}")

    def test_render_fills_every_placeholder(self):
        values = services.runtime({})
        for name in services.SPECS:
            for v in services.render(name, values).values():
                self.assertNotIn("{", v)

    def test_keys_are_fresh_per_run(self):
        self.assertNotEqual(services.runtime({})["master_key"], services.runtime({})["master_key"])

    def test_bind_to_loopback_only(self):
        for name in services.SPECS:
            hosts = [v for k, v in services.SPECS[name]["env"].items() if k.endswith("SERVER__HOST")]
            self.assertEqual(hosts, ["127.0.0.1"], name)


if __name__ == "__main__":
    unittest.main()
