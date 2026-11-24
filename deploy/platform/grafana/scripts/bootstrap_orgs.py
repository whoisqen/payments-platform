#!/usr/bin/env python3
"""Create the Grafana organizations of config/platform.yaml (access.grafana_orgs); idempotent, standard library only.

Grafana cannot create organizations by file provisioning, so this runs as an Argo CD PostSync Job (deploy/platform/grafana/manifests/
org-bootstrap.yaml). Organization ids are what the provisioning refers to, so an organization must get the id the config gives it:
organizations are created in id order, and the run fails (it never renames, deletes or guesses) when
  - an id exists under another name, or a name exists under another id,
  - an id is missing while a higher one exists (the id can no longer be handed out in order),
  - Grafana returns another id than the config expects.

  bootstrap_orgs.py --orgs orgs.json [--dry-run]

orgs.json: {"orgs": [{"id": 1, "name": "Main Org."}, {"id": 2, "name": "Engineering"}]}
Environment: GRAFANA_URL (default http://grafana.monitoring.svc), GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD (the secret grafana-admin).
--dry-run reads and prints the plan and creates nothing. The password is never printed.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request


class BootstrapError(Exception):
    pass


class Api:
    def __init__(self, url, user, password, opener=urllib.request.urlopen):
        self.url = url.rstrip("/")
        self.auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
        self.opener = opener

    def call(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.url + path, data=data, method=method)
        request.add_header("Authorization", self.auth)
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with self.opener(request, timeout=15) as response:
                return json.loads(response.read() or b"null")
        except urllib.error.HTTPError as error:
            raise BootstrapError(f"{method} {path}: HTTP {error.code}") from None
        except (urllib.error.URLError, OSError) as error:
            raise ConnectionError(f"{method} {path}: {error}") from None


def wait_for_grafana(api, attempts=60, pause=5, sleep=time.sleep, log=print):
    for attempt in range(attempts):
        try:
            api.call("GET", "/api/health")
            return
        except (ConnectionError, BootstrapError):
            if attempt + 1 == attempts:
                break
            sleep(pause)
    raise BootstrapError("Grafana did not answer")


def plan(existing, wanted):
    """Actions to reach `wanted` ([{id, name}]) from `existing` ([{id, name}] of Grafana): the ids to create, in order."""
    by_id = {o["id"]: o["name"] for o in existing}
    by_name = {o["name"]: o["id"] for o in existing}
    ids = [o["id"] for o in wanted]
    if len(set(ids)) != len(ids) or len({o["name"] for o in wanted}) != len(wanted):
        raise BootstrapError("the config repeats an organization id or name")
    create = []
    for org in sorted(wanted, key=lambda o: o["id"]):
        if org["id"] in by_id:
            if by_id[org["id"]] != org["name"]:
                raise BootstrapError(f"organization {org['id']} is named {by_id[org['id']]!r}, the config says {org['name']!r}")
        elif org["name"] in by_name:
            raise BootstrapError(f"organization {org['name']!r} has id {by_name[org['name']]}, the config says {org['id']}")
        else:
            create.append(org)
    highest = max(by_id, default=0)
    for org in create:
        if org["id"] <= highest:
            raise BootstrapError(f"organization {org['id']} ({org['name']!r}) is missing but id {highest} exists: ids cannot be filled in")
        highest = org["id"]
    return create


def run(api, wanted, dry_run=False, log=print):
    existing = api.call("GET", "/api/orgs")
    create = plan([{"id": o["id"], "name": o["name"]} for o in existing], wanted)
    if not create:
        log("grafana-orgs: all organizations exist")
        return 0
    known = max((o["id"] for o in existing), default=0)
    for org in create:
        # Ids are handed out in sequence: every gap below the wanted id would be taken by this organization instead
        if org["id"] != known + 1:
            log(f"grafana-orgs: note: {org['name']!r} expects id {org['id']}, the next free id may differ")
        if dry_run:
            log(f"grafana-orgs: would create {org['name']!r} with id {org['id']}")
            known = org["id"]
            continue
        created = api.call("POST", "/api/orgs", {"name": org["name"]})
        got = created.get("orgId")
        if got != org["id"]:
            raise BootstrapError(f"organization {org['name']!r} got id {got}, the config expects {org['id']}; fix the config or the organization by hand")
        log(f"grafana-orgs: created {org['name']!r} with id {got}")
        known = got
    return 0


def main(argv, env=os.environ, opener=urllib.request.urlopen, sleep=time.sleep):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--orgs", required=True, help="JSON file with the organizations")
    parser.add_argument("--dry-run", action="store_true", help="print what would be created and change nothing")
    args = parser.parse_args(argv)
    with open(args.orgs, encoding="utf-8") as handle:
        wanted = json.load(handle)["orgs"]
    try:
        api = Api(env.get("GRAFANA_URL", "http://grafana.monitoring.svc"), env["GRAFANA_ADMIN_USER"], env["GRAFANA_ADMIN_PASSWORD"], opener)
    except KeyError as missing:
        print(f"grafana-orgs: {missing.args[0]} is not set", file=sys.stderr)
        return 2
    try:
        wait_for_grafana(api, sleep=sleep)
        return run(api, wanted, dry_run=args.dry_run)
    except BootstrapError as error:
        print(f"grafana-orgs: FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
