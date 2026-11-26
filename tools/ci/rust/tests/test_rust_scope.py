import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import rust_scope as rs  # noqa: E402

HS = "vendor/hyperswitch"
MANIFESTS = {
    f"{HS}/crates/router_env/Cargo.toml": '[package]\nname = "router_env"\nversion = "0.1.0"\n[dependencies]\nname = "x"\n',
    f"{HS}/crates/router/Cargo.toml": '[package]\nname = "router"\n',
}


class ScopeTest(unittest.TestCase):
    def scope(self, files):
        return rs.scope(files, HS, MANIFESTS.get)

    def test_changed_crates_only(self):
        files = [f"{HS}/crates/router_env/src/logger.rs", f"{HS}/crates/router/src/lib.rs", f"{HS}/crates/router/src/x.rs"]
        self.assertEqual(self.scope(files), ["-p", "router", "-p", "router_env"])

    def test_lockfile_means_workspace(self):
        self.assertEqual(self.scope([f"{HS}/Cargo.lock"]), ["--workspace"])

    def test_unknown_crate_means_workspace(self):
        self.assertEqual(self.scope([f"{HS}/crates/ghost/src/lib.rs"]), ["--workspace"])

    def test_other_paths_and_docs_ignored(self):
        self.assertEqual(self.scope(["vendor/card-vault/src/main.rs", f"{HS}/crates/router/README.md", f"{HS}/docs/a.md"]), [])

    def test_single_crate_workspace(self):
        self.assertEqual(rs.scope(["vendor/card-vault/src/main.rs"], "vendor/card-vault", {}.get), ["--workspace"])

    def test_package_name_not_taken_from_dependencies(self):
        self.assertEqual(rs.crate_name('[dependencies]\nname = "x"\n'), None)
        self.assertEqual(rs.crate_name(MANIFESTS[f"{HS}/crates/router_env/Cargo.toml"]), "router_env")

    def test_all_flag(self):
        self.assertEqual(rs.main(["--workspace", HS, "--all"]), 0)


if __name__ == "__main__":
    unittest.main()
