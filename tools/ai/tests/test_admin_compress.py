import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from admin_agent import compress, config  # noqa: E402

LIM = config.load()["limits"]


class LogCompressionTest(unittest.TestCase):
    def test_templates_counts_and_span(self):
        lines = [f"2026-11-24T10:00:{i:02d}Z INFO request {i} user 550e8400-e29b-41d4-a716-44665544000{i % 10} took {i * 3}ms from 10.0.0.{i}" for i in range(30)]
        lines += ["2026-11-24T10:01:00Z ERROR db timeout after 30s", "2026-11-24T10:02:00Z ERROR db timeout after 31s"]
        out = compress.compress_logs(lines, LIM)
        self.assertIn("32 lines, 2 templates, 1 error templates", out)
        self.assertLess(out.index("ERROR"), out.index("x30"))  # errors first
        self.assertIn("x2 ERROR first=2026-11-24T10:01:00Z last=2026-11-24T10:02:00Z", out)

    def test_stack_trace_folded(self):
        lines = ["ERROR boom"] + [f"    at com.x.Cls.m{i}(Cls.java:{i})" for i in range(40)] + ["INFO next"]
        out = compress.compress_logs(lines, LIM)
        self.assertIn("+37 frames folded", out)
        self.assertLess(len(out), 700)

    def test_top_n_limit(self):
        lines = [f"ERROR distinct failure kind{chr(97 + i)}{chr(97 + j)}" for i in range(10) for j in range(10)]
        out = compress.compress_logs(lines, dict(LIM, top_templates=5))
        self.assertIn("showing top 5", out)
        self.assertIn("more templates", out)


class MetricsTest(unittest.TestCase):
    def test_downsampled(self):
        res = {"data": {"resultType": "matrix", "result": [{"metric": {"job": "router"}, "values": [[t, str(t % 7)] for t in range(500)]}]}}
        out = compress.compress_metrics(res, LIM)
        self.assertIn("n=500", out)
        self.assertEqual(out.split("series=[")[1].count(","), LIM["metric_points"] - 1)


class BudgetTest(unittest.TestCase):
    def test_cut(self):
        text, cut = compress.cut_to_tokens("x" * 4000, 100)
        self.assertTrue(cut)
        self.assertLessEqual(compress.estimate_tokens(text), 100 + 20)

    def test_session_budget_exhausts(self):
        b = compress.SessionBudget(tool_tokens=50, session_tokens=80)
        first = b.fit("a" * 1000)
        second = b.fit("b" * 1000)
        third = b.fit("c")
        self.assertIn("truncated", first)
        self.assertIn("truncated", second)
        self.assertIn("budget exhausted", third)
        self.assertTrue(b.exhausted)


class CleanTest(unittest.TestCase):
    def test_newline_and_tab_stay(self):
        self.assertEqual(compress.clean("a\tb\nc"), "a\tb\nc")

    def test_c0_controls_removed(self):
        self.assertEqual(compress.clean("a\x00b\x07c\rd\x1fe"), "abcde")

    def test_c1_controls_removed(self):
        self.assertEqual(compress.clean("a\x7fb\x85c\x9fd"), "abcd")

    def test_zero_width_removed(self):
        self.assertEqual(compress.clean("a​b‍c⁠d﻿e"), "abcde")

    def test_bidi_removed(self):
        self.assertEqual(compress.clean("a‮b⁦c⁩d؜e‏f"), "abcdef")

    def test_ansi_escape_start_removed(self):
        self.assertEqual(compress.clean("\x1b[31mred"), "[31mred")

    def test_surrogate_removed(self):
        self.assertEqual(compress.clean("a\ud800b"), "ab")


if __name__ == "__main__":
    unittest.main()
