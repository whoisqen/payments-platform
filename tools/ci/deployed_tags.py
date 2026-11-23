#!/usr/bin/env python3
"""Print `service digest tag` for every image of an environment's images.yaml; the tag <env>-<12 hex of the digest> keeps the image in the registry."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import images_yaml  # noqa: E402


def tags(images, env):
    if env not in images_yaml.ENVS:
        raise ValueError(f"unknown environment: {env}")
    return [(s, d, f"{env}-{d.split(':', 1)[1][:12]}") for s, d in sorted(images.items())]


def main(argv):
    if len(argv) != 2:
        print("usage: deployed_tags.py <images.yaml> <environment>", file=sys.stderr)
        return 2
    for service, digest, tag in tags(images_yaml.load(argv[0]), argv[1]):
        print(service, digest, tag)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
