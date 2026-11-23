import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from contracts import model  # noqa: E402

# (chart, values path to the container+probes block) for every service chart
SERVICES = [("router", ()), ("drainer", ()), ("locker", ()), ("control-center", ()),
            ("scheduler", ("producer",)), ("scheduler", ("consumer",))]


def block(vals, path):
    for k in path:
        vals = vals[k]
    return vals


def defaults(chart):
    return model.load_yaml(model.CHARTS / chart / "values.yaml")


class ServiceHealth(unittest.TestCase):
    def test_every_service_chart_is_covered(self):
        charts = {p.name for p in model.CHARTS.iterdir() if (p / "values.schema.json").is_file()}
        service = {c for c, _ in SERVICES}
        self.assertEqual(charts - service, {"migrations", "payments-cell", "payments-edge", "payments-locker"})

    def test_probes_are_declared_with_reachable_paths(self):
        for chart, path in SERVICES:
            b = block(defaults(chart), path)
            for kind in ("startup", "liveness", "readiness"):
                with self.subTest(chart=chart, path=path, probe=kind):
                    p = b["probes"][kind]
                    self.assertTrue(p["path"].startswith("/"))
                    self.assertGreater(p["periodSeconds"], 0)

    def test_container_port_is_valid_and_matches_the_service_port(self):
        for chart, path in SERVICES:
            vals = defaults(chart)
            b = block(vals, path)
            with self.subTest(chart=chart, path=path):
                port = b["container"]["port"]
                self.assertTrue(1 <= port <= 65535)
                self.assertEqual(b["service"]["port"], port)

    def test_startup_window_covers_boot_and_readiness_is_not_slower_than_liveness_window(self):
        for chart, path in SERVICES:
            p = block(defaults(chart), path)["probes"]
            with self.subTest(chart=chart, path=path):
                window = p["startup"]["periodSeconds"] * p["startup"]["failureThreshold"]
                self.assertGreaterEqual(window, 150)
                self.assertLessEqual(p["readiness"]["periodSeconds"], p["liveness"]["periodSeconds"])

    def test_router_and_drainer_use_the_deep_readiness_check(self):
        for chart in ("router", "drainer"):
            self.assertEqual(defaults(chart)["probes"]["readiness"]["path"], "/health/ready")

    def test_environment_layers_do_not_override_probes_or_ports(self):
        for env in model.environments():
            for region in model.regions(env):
                for rel in model.releases(env, region):
                    chart, vals = model.layered(env, region, rel)
                    for svc in ("router", "drainer", "locker", "scheduler"):
                        sub = vals.get(svc, {})
                        with self.subTest(release=f"{env}/{region}/{rel}", svc=svc):
                            self.assertNotIn("probes", sub)
                            self.assertNotIn("port", sub.get("container", {}))
                    if chart == "control-center":
                        self.assertNotIn("probes", model.load_yaml(model.ENVS / env / region / rel / "values.yaml"))


if __name__ == "__main__":
    unittest.main()
