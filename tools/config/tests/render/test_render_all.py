import importlib.util
import unittest
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("render_all", CONFIG / "render" / "__main__.py")
render_all = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render_all)


class RenderAllTest(unittest.TestCase):
    def test_every_generator_is_run(self):
        found = {p.relative_to(CONFIG).as_posix() for p in [*CONFIG.glob("render_*.py"), *CONFIG.glob("render/render_*.py")]}
        self.assertEqual(found, set(render_all.GENERATORS))

    def test_every_generator_supports_check(self):
        for g in render_all.GENERATORS:
            self.assertIn("--check", (CONFIG / g).read_text(encoding="utf-8"), g)


if __name__ == "__main__":
    unittest.main()
