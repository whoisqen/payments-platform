#!/usr/bin/env python3
"""Write the individual values of config/platform.yaml into the deploy and policy files that carry them.

Usage: render.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]


def load():
    return yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))


def env_of(path):
    m = re.match(r"deploy/envs/([^/]+)/", path.relative_to(ROOT).as_posix())
    return m.group(1) if m else None


def render_text(path, text, cfg):
    rel = path.relative_to(ROOT).as_posix()
    owner, repo = cfg["owner"]["github_org"], cfg["owner"]["github_repo"]
    reg = cfg["registry"]
    if rel.startswith("deploy/"):
        text = re.sub(r"(repoURL: https://github\.com/)[^/\s]+/[^/\s]+", rf"\g<1>{owner}/{repo}", text)
        text = re.sub(r"(githubConfigUrl: https://github\.com/)[^/\s]+", rf"\g<1>{owner}", text)
    if rel.startswith("observability/"):
        text = re.sub(r"https://github\.com/[^/\s\"']+/[^/\s\"']+/blob/", f"https://github.com/{owner}/{repo}/blob/", text)
    if rel.startswith("deploy/charts/"):
        text = re.sub(
            r"[0-9A-Za-z]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[a-z0-9-]+/",
            f"{reg['ecr_prefix']}/{reg['ecr_repo_prefix']}/", text)
    account = reg["ecr_prefix"].split(".")[0]
    if rel == "policy/kyverno/restrict-registries/restrict-registries.yaml":
        text = re.sub(r"\^[0-9]{12}(?=\\\\\.dkr)", f"^{account}", text)
    if rel == "policy/kyverno/require-signed-images/require-signed-images.yaml":
        text = re.sub(r'glob: "[0-9]{12}\.dkr', f'glob: "{account}.dkr', text)
    env = env_of(path)
    if env in cfg["deploy"]:
        d = cfg["deploy"][env]
        for key, name in (("dataCidrs", "data_cidrs"), ("endpointCidrs", "endpoint_cidrs")):
            block = "".join(f"    - {c}\n" for c in d[name])
            text = re.sub(rf"(  {key}:\n)(?:    - .*\n)+", lambda m, b=block: m.group(1) + b, text)
        text = re.sub(r"(    - )api\.[a-z0-9.-]+\.payments\.example\.com", rf"\g<1>{d['gateway_host']}", text)
        text = re.sub(r"(router\.payments\.svc\.[a-z0-9-]+\.)[a-z0-9.-]+\.example\.internal", rf"\g<1>{d['cluster_domain']}", text)
        text = re.sub(r"(aurora-[a-z0-9-]+\.cluster-(?:ro-)?)[a-z0-9]+(\.[a-z0-9-]+\.rds\.amazonaws\.com)", rf"\g<1>{d['rds_suffix']}\g<2>", text)
        text = re.sub(r"(memorydb-[a-z0-9-]+\.)[a-z0-9]+(\.memorydb\.)", rf"\g<1>{d['memorydb_suffix']}\g<2>", text)
    return text


def targets():
    for pattern in ("deploy/**/*.yaml", "observability/**/*.yaml", "observability/**/*.py", "policy/kyverno/restrict-registries/restrict-registries.yaml",
                    "policy/kyverno/require-signed-images/require-signed-images.yaml"):
        yield from sorted(ROOT.glob(pattern))


def main(argv):
    cfg, changed = load(), []
    for path in targets():
        if "/templates/" in path.as_posix():
            continue
        old = path.read_text(encoding="utf-8")
        new = render_text(path, old, cfg)
        if new != old:
            changed.append(path.relative_to(ROOT).as_posix())
            if "--check" not in argv:
                path.write_text(new, encoding="utf-8")
    verb = "would change" if "--check" in argv else "updated"
    for c in changed:
        print(f"render: {verb} {c}")
    print(f"render: {len(changed)} file(s) {verb}")
    return 1 if changed and "--check" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
