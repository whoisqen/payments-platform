import json
import re
import sys
from pathlib import Path

# Top-level keys of CreateExperimentTemplate that the platform templates may use.
TOP_KEYS = {"description", "targets", "actions", "stopConditions", "roleArn", "tags", "logConfiguration", "experimentOptions"}
REQUIRED_TOP = {"description", "actions", "stopConditions", "roleArn", "tags"}
TARGET_KEYS = {"resourceType", "resourceArns", "resourceTags", "filters", "selectionMode", "parameters"}
ACTION_KEYS = {"actionId", "description", "parameters", "targets", "startAfter"}

# actionId -> (required parameters, target key and its resource type or None when the action has no target).
ACTIONS = {
    "aws:network:disrupt-connectivity": ({"scope", "duration"}, ("Subnets", "aws:ec2:subnet")),
    "aws:ec2:terminate-instances": (set(), ("Instances", "aws:ec2:instance")),
    "aws:ec2:send-spot-instance-interruptions": ({"durationBeforeInterruption"}, ("SpotInstances", "aws:ec2:spot-instance")),
    "aws:rds:failover-db-cluster": (set(), ("Clusters", "aws:rds:cluster")),
    "aws:ssm:send-automation-document": ({"documentArn"}, None),
}
# Tags the targets may select on: the default tags of infra/live/terragrunt.hcl (section 22) and the tag Karpenter puts on its nodes.
# There is no az or role tag; an AZ is chosen with a filter on the resource attribute below.
TARGET_TAG_KEYS = {"environment", "cell", "component", "karpenter.sh/nodepool"}
# resourceType -> filter paths that select by attribute (DescribeSubnets / DescribeInstances fields).
FILTER_PATHS = {
    "aws:ec2:subnet": {"AvailabilityZone"},
    "aws:ec2:instance": {"Placement.AvailabilityZone", "State.Name"},
    "aws:ec2:spot-instance": {"Placement.AvailabilityZone", "State.Name"},
    "aws:rds:cluster": set(),
}
ISO_DURATION = re.compile(r"^PT(\d+H)?(\d+M)?(\d+S)?$")
SELECTION = re.compile(r"^(ALL|RANDOM|COUNT\(\d+\)|PERCENT\(\d+\))$")


def validate(path):
    errors = []
    t = json.loads(Path(path).read_text())
    unknown = set(t) - TOP_KEYS
    if unknown:
        errors.append(f"unknown top-level keys {sorted(unknown)}")
    missing = REQUIRED_TOP - set(t)
    if missing:
        errors.append(f"missing keys {sorted(missing)}")
    desc = t.get("description", "")
    if not desc.startswith("Hypothesis:") or len(desc) > 512:
        errors.append("description must start with 'Hypothesis:' and be at most 512 characters")
    if "Stop:" not in desc:
        errors.append("description must name the stop condition ('Stop:')")
    if not t.get("stopConditions") or any(
        s.get("source") != "aws:cloudwatch:alarm" or not s.get("value", "").startswith("arn:aws:cloudwatch:") for s in t["stopConditions"]
    ):
        errors.append("stopConditions need a CloudWatch alarm ARN")
    if not str(t.get("roleArn", "")).startswith("arn:aws:iam::"):
        errors.append("roleArn must be an IAM role ARN")
    tags = t.get("tags", {})
    if tags.get("environment") != "stage" or not tags.get("failure-mode"):
        errors.append("tags need environment=stage and a failure-mode")
    errors += _targets(t.get("targets", {}))
    errors += _actions(t.get("actions", {}), t.get("targets", {}))
    return errors


def _targets(targets):
    errors = []
    for name, tg in targets.items():
        if set(tg) - TARGET_KEYS:
            errors.append(f"target {name}: unknown keys {sorted(set(tg) - TARGET_KEYS)}")
        if "resourceType" not in tg or not ("resourceArns" in tg or "resourceTags" in tg):
            errors.append(f"target {name}: needs resourceType and resourceArns or resourceTags")
        bad_tags = set(tg.get("resourceTags", {})) - TARGET_TAG_KEYS
        if bad_tags:
            errors.append(f"target {name}: resourceTags {sorted(bad_tags)} are not applied by infra")
        allowed = FILTER_PATHS.get(tg.get("resourceType"), set())
        bad_paths = {f.get("path") for f in tg.get("filters", [])} - allowed
        if bad_paths:
            errors.append(f"target {name}: filter paths {sorted(bad_paths)} not valid for {tg.get('resourceType')}")
        if not SELECTION.match(tg.get("selectionMode", "")):
            errors.append(f"target {name}: bad selectionMode")
    return errors


def _actions(actions, targets):
    errors = []
    if not actions:
        errors.append("no actions")
    for name, a in actions.items():
        if set(a) - ACTION_KEYS:
            errors.append(f"action {name}: unknown keys {sorted(set(a) - ACTION_KEYS)}")
        spec = ACTIONS.get(a.get("actionId"))
        if spec is None:
            errors.append(f"action {name}: unsupported actionId {a.get('actionId')!r}")
            continue
        required, target = spec
        params = a.get("parameters", {})
        if required - set(params):
            errors.append(f"action {name}: missing parameters {sorted(required - set(params))}")
        for key in ("duration", "durationBeforeInterruption", "maxDuration"):
            if key in params and not ISO_DURATION.match(params[key]):
                errors.append(f"action {name}: {key} is not an ISO 8601 duration")
        if "documentParameters" in params:
            try:
                json.loads(params["documentParameters"])
            except ValueError:
                errors.append(f"action {name}: documentParameters is not a JSON string")
        if target is None:
            continue
        ref = a.get("targets", {}).get(target[0])
        if ref not in targets:
            errors.append(f"action {name}: target key {target[0]} must reference a defined target")
        elif targets[ref].get("resourceType") != target[1]:
            errors.append(f"action {name}: target {ref} must be {target[1]}")
    return errors


if __name__ == "__main__":
    failed = False
    for p in sys.argv[1:]:
        errs = validate(p)
        failed |= bool(errs)
        print(f"{'FAIL' if errs else 'ok  '} {p}")
        for e in errs:
            print(f"     {e}")
    sys.exit(1 if failed else 0)
