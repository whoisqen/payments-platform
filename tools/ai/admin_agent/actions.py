"""Named runbook actions. The model can only propose; a human types a per-proposal code to run one; dry-run is the default."""
import hashlib
import json
import re
import secrets

from .config import is_denied
from .compress import clean


class ActionError(Exception):
    pass


class ActionRegistry:
    def __init__(self, actions, env_name, env_cfg, cfg):
        self.actions = actions
        self.env_name = env_name
        self.env_cfg = env_cfg
        self.cfg = cfg

    def validate(self, action_id, params):
        spec = self.actions.get(action_id)
        if spec is None:
            raise ActionError(f"unknown action {action_id!r}; allowed: {', '.join(self.actions)}")
        params = params if isinstance(params, dict) else {}
        extra = set(params) - set(spec["params"])
        if extra:
            raise ActionError(f"unexpected parameters: {sorted(extra)}")
        clean = {}
        for name, rule in spec["params"].items():
            if name not in params:
                raise ActionError(f"missing parameter {name}")
            v = params[name]
            if rule["type"] == "integer":
                if isinstance(v, bool) or not isinstance(v, int) or not rule["min"] <= v <= rule["max"]:
                    raise ActionError(f"{name} must be an integer in {rule['min']}..{rule['max']}")
            else:
                if not isinstance(v, str) or not re.fullmatch(rule["pattern"], v):
                    raise ActionError(f"{name} does not match {rule['pattern']}")
                if name == "namespace" and v not in self.env_cfg["namespaces"]:
                    raise ActionError(f"namespace {v} is not allowed in {self.env_name}")
                if is_denied(v, self.cfg):
                    raise ActionError(f"{name} is refused")
            clean[name] = v
        return clean

    def describe(self, action_id, params):
        return f"{action_id} in {self.env_name} {' '.join(f'{k}={v}' for k, v in sorted(params.items()))}"


def params_hash(env, account, action_id, params):
    blob = json.dumps({"env": env, "account": account, "action": action_id, "params": params}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:8]


class Proposal:
    """A proposal with a fresh random nonce; the code to type is bound to the exact parameters shown next to it."""

    def __init__(self, registry, action_id, params, reason):
        self.action_id, self.params, self.reason = action_id, params, clean(reason)
        self.nonce = secrets.token_hex(3)
        self.phash = params_hash(registry.env_name, registry.env_cfg["account_id"], action_id, params)
        self.code = f"{self.nonce}-{self.phash}"

    def text(self, registry, dry_run):
        return (f"PROPOSED ACTION: {clean(registry.describe(self.action_id, self.params))}\n"
                f"Reason (from the model): {self.reason}\n"
                f"Account: {registry.env_cfg['account_id']}  Mode: {'DRY-RUN' if dry_run else 'EXECUTE'}\n"
                f"Confirmation code: {self.code}  (nonce {self.nonce}, parameter hash {self.phash})")


def confirm(proposal, registry, dry_run, ask, retype_envs=()):
    """True only when the human types this proposal's code (and, for the listed environments, the environment name); EOF declines."""
    try:
        answer = ask(f"{proposal.text(registry, dry_run)}\nType the confirmation code '{proposal.code}' to confirm, anything else to decline: ")
        if answer.strip() != proposal.code:
            return False
        if registry.env_name in retype_envs:
            return ask(f"Type the environment name '{registry.env_name}' to confirm: ").strip() == registry.env_name
    except EOFError:
        return False
    return True


def ssm_executor(aws, region):
    def run(document, params):
        resp = aws.client("ssm", region_name=region).start_automation_execution(DocumentName=document, Parameters={k: [str(v)] for k, v in params.items()})
        return resp["AutomationExecutionId"]
    return run


def execute(registry, action_id, params, dry_run, executor):
    """The environment and account are passed to the SSM document so it can refuse a mismatch."""
    spec = registry.actions[action_id]
    full = {**params, "environment": registry.env_name, "account_id": registry.env_cfg["account_id"]}
    if dry_run:
        return f"dry-run: would start SSM document {spec['document']} with {full}"
    return f"started SSM document {spec['document']}: execution {executor(spec['document'], full)}"
