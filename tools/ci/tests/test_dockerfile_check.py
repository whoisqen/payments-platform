import sys
import unittest
from pathlib import Path

CI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI))
import dockerfile_check as dk  # noqa: E402

D = "@sha256:" + "a" * 64
GOOD = f"FROM rust{D} AS b\nFROM b AS c\nFROM distroless{D}\nUSER 10001:10001\nENTRYPOINT [\"/app/x\"]\n"


class DockerfileCheckTest(unittest.TestCase):
    def test_good_file(self):
        self.assertEqual(dk.check(GOOD), [])

    def test_tag_without_digest(self):
        self.assertTrue(any("digest" in e for e in dk.check(GOOD.replace(D, ":1.2", 1))))

    def test_latest_tag(self):
        self.assertTrue(any("latest" in e for e in dk.check(GOOD.replace(f"rust{D}", "rust:latest", 1))))

    def test_root_or_missing_user(self):
        self.assertTrue(dk.check(GOOD.replace("USER 10001:10001", "USER root")))
        self.assertTrue(dk.check(GOOD.replace("USER 10001:10001\n", "")))

    def test_add_url(self):
        self.assertTrue(any("ADD" in e for e in dk.check(GOOD + "ADD https://x.test/a /a\n")))

    def test_shell_form_entrypoint(self):
        self.assertTrue(any("exec form" in e for e in dk.check(GOOD + "ENTRYPOINT /app/x\n")))

    def test_curl_pipe_sh_across_continuation(self):
        self.assertTrue(dk.check(GOOD + "RUN curl -s https://x.test \\\n | sh\n"))

    def test_repository_dockerfiles_pass(self):
        self.assertEqual(dk.main([]), 0)


if __name__ == "__main__":
    unittest.main()
