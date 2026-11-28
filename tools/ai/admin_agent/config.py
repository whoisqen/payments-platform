"""Load and validate config/admin-agent.yaml; one place decides which environments, models, hosts and resources are allowed."""
import re
import unicodedata
import urllib.parse
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "config" / "admin-agent.yaml"
CDE_PATHS = ROOT / "policy" / "cde-paths.yaml"
REFUSED_ENVS = {"cde-prod"}
SAFE_ENVS = {"dev", "stage"}  # while prod_in_cde_scope is true nothing else is reachable
ENDPOINT = re.compile(r"^https://vpce-[a-z0-9-]+\.bedrock-runtime\.eu-[a-z0-9-]+\.vpce\.amazonaws\.com$")
ROLE_ARN = re.compile(r"^arn:aws:iam::(\d{12}):role/[A-Za-z0-9+=,.@_/-]+$")
ACCOUNT = re.compile(r"^\d{12}$")
REGION = re.compile(r"^[a-z]{2}-[a-z]+-\d$")
INDEX_PREFIX = re.compile(r"^[a-z0-9][a-z0-9-]*-$")
OPENSEARCH_FIELDS = ("timestamp", "namespace", "app", "level", "message")
FIELD = re.compile(r"^[@A-Za-z0-9_.]{1,100}$")
LABEL_VALUE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
REQUIRED_ENV_KEYS = ("kube_context", "kube_cluster_arn", "role_arn", "account_id", "tenant_id", "namespaces", "victoria_url",
                     "alertmanager_url", "log_groups", "ssm_region")


class ConfigError(Exception):
    pass


def _fold(value):
    return unicodedata.normalize("NFKC", str(value)).casefold()


def _compact(value):
    return re.sub(r"[^a-z0-9]", "", _fold(value))


def _tokens(value):
    return [t for t in re.split(r"[^a-z0-9]+", _fold(value)) if t]


def cde_names_from_policy(path=CDE_PATHS):
    """Workload-like names from the CDE path classes: the last non-glob segment of each path."""
    if not Path(path).exists():
        return []
    names = []
    for p in (yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}).get("cde_paths", []):
        parts = [s for s in p.split("/") if s and s != "**"]
        if parts and "*" not in parts[-1]:
            names.append(parts[-1].replace("_", "-").lower())
    return names


def denied_names(cfg):
    scope = cfg["cde_scope"]
    return sorted({n.lower() for n in [*scope["denied_workloads"], *scope["denied_namespaces"], *scope.get("policy_names", [])]})


def is_denied(value, cfg):
    """True when the text names a CDE workload or namespace. Unicode is folded (NFKC) and punctuation ignored, so `c.e-x` and
    full-width forms do not pass. Fails closed: a long denied name anywhere in the text counts, short names count as whole tokens."""
    compact, toks = _compact(value), _tokens(value)
    if "cde" in compact:
        return True
    for name in denied_names(cfg):
        c, nt = _compact(name), _tokens(name)
        if len(c) >= 5 and c in compact:
            return True
        if nt and any(toks[i:i + len(nt)] == nt for i in range(len(toks) - len(nt) + 1)):
            return True
    return False


def deny_names(cfg):
    """Workload names (not namespaces) of the CDE scope; they contain only [a-z0-9-], so no regex escaping is needed."""
    return sorted({*cfg["cde_scope"]["denied_workloads"], *cfg["cde_scope"].get("policy_names", [])})


def deny_regex(cfg):
    """Anchored-match alternation for `app!~` matchers: each name alone or followed by a dash suffix."""
    return "(" + "|".join(deny_names(cfg)) + ")(-.*)?"


def valid_label(value, cfg, allowed=None):
    """Structured identifier from the model: strict charset, not denied, and in the allow list when one is given."""
    if not isinstance(value, str) or not LABEL_VALUE.match(value) or is_denied(value, cfg):
        return False
    return allowed is None or value in allowed


def check_https_host(url, allowed_hosts, what):
    u = urllib.parse.urlsplit(str(url))
    if u.scheme != "https" or not u.hostname or u.username or u.password:
        raise ConfigError(f"{what} must be an https URL without credentials")
    if u.hostname not in allowed_hosts:
        raise ConfigError(f"{what} host {u.hostname} is not in allowed_hosts")


def _walk(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield k
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)
    else:
        yield node


def load(path=CONFIG, policy=CDE_PATHS):
    cfg = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    for key in ("bedrock", "models", "environments", "cde_scope", "kubectl", "limits", "actions", "queries", "allowed_hosts", "audit", "opensearch"):
        if not cfg.get(key):
            raise ConfigError(f"missing section: {key}")
    if not isinstance(cfg.get("prod_in_cde_scope"), bool):
        raise ConfigError("prod_in_cde_scope must be set explicitly to true or false")
    cfg["cde_scope"]["policy_names"] = cde_names_from_policy(policy)
    for key in ("denied_workloads", "denied_namespaces"):
        if not cfg["cde_scope"].get(key):
            raise ConfigError(f"cde_scope.{key} must not be empty")
    b = cfg["bedrock"]
    if not ENDPOINT.match(str(b.get("endpoint_url", ""))):
        raise ConfigError("bedrock.endpoint_url must match https://vpce-*.bedrock-runtime.eu-*.vpce.amazonaws.com")
    if "secrets" in [r.lower() for r in cfg["kubectl"]["resources"]]:
        raise ConfigError("kubectl.resources must not list secrets")
    try:
        re.compile(cfg["kubectl"]["secret_key_pattern"])
    except re.error as e:
        raise ConfigError(f"kubectl.secret_key_pattern is invalid: {e}") from e
    hosts = cfg["allowed_hosts"]
    o = cfg["opensearch"]
    check_https_host(o.get("url"), hosts, "opensearch.url")
    for name, env in (cfg.get("environments") or {}).items():
        if env.get("opensearch_url") is not None:
            check_https_host(env["opensearch_url"], hosts, f"environments.{name}.opensearch_url")
    if not REGION.match(str(o.get("region", ""))):
        raise ConfigError("opensearch.region must be an AWS region")
    if not INDEX_PREFIX.match(str(o.get("index_prefix", ""))):
        raise ConfigError("opensearch.index_prefix must be lower-case letters, digits and dashes ending in a dash")
    fields = o.get("fields") or {}
    for key in OPENSEARCH_FIELDS:
        if not FIELD.match(str(fields.get(key, ""))):
            raise ConfigError(f"opensearch.fields.{key} must be a field name")
    cde_accounts = [str(a) for a in cfg.get("cde_account_ids") or []]
    if any(not ACCOUNT.match(a) for a in cde_accounts):
        raise ConfigError("cde_account_ids must be 12-digit account ids")
    seen = {}
    for env, e in cfg["environments"].items():
        if env in REFUSED_ENVS or "cde" in env.lower():
            raise ConfigError(f"environment {env} is excluded")
        for key in REQUIRED_ENV_KEYS:
            if not e.get(key):
                raise ConfigError(f"environment {env}: {key} is required")
        m = ROLE_ARN.match(str(e["role_arn"]))
        if not m:
            raise ConfigError(f"environment {env}: role_arn must be an IAM role ARN")
        account = str(e["account_id"])
        if not ACCOUNT.match(account) or m.group(1) != account:
            raise ConfigError(f"environment {env}: account_id must be 12 digits and equal the account of role_arn")
        if account in cde_accounts:
            raise ConfigError(f"environment {env}: account {account} is a CDE account")
        if account in seen:
            raise ConfigError(f"environments {seen[account]} and {env} share account {account}")
        seen[account] = env
        e["account_id"] = account
        for key in ("victoria_url", "alertmanager_url"):
            check_https_host(e[key], hosts, f"environment {env}: {key}")
        for ns in e["namespaces"]:
            if not valid_label(ns, cfg):
                raise ConfigError(f"environment {env}: namespace {ns!r} is invalid or in the CDE scope")
        for v in _walk({k: x for k, x in e.items() if k not in ("kube_context", "kube_cluster_arn")}):
            if is_denied(v, cfg):
                raise ConfigError(f"environment {env} references a denied name: {v}")
    return cfg


def warnings(cfg):
    out = []
    if not str(cfg["bedrock"].get("guardrail_id") or "") or not str(cfg["bedrock"].get("guardrail_version") or ""):
        out.append("bedrock.guardrail_id/guardrail_version are empty: no Bedrock guardrail is applied")
    if not cfg.get("cde_account_ids"):
        out.append("cde_account_ids is empty: the CDE account cannot be refused at run time")
    return out


def pick_model(cfg, name):
    """The admin names the model; without a name the cheapest (first) entry is used and the caller reports it."""
    models = cfg["models"]
    if not name:
        return models[0], True
    for m in models:
        if name in (m["name"], m["id"]):
            return m, False
    raise ConfigError(f"model {name!r} is not allowed; allowed: {', '.join(m['name'] for m in models)}")


def pick_env(cfg, env):
    if env in REFUSED_ENVS or "cde" in str(env).lower():
        raise ConfigError(f"environment {env} is excluded from the admin agent")
    if env not in cfg["environments"]:
        raise ConfigError(f"unknown environment {env!r}; allowed: {', '.join(cfg['environments'])}")
    if cfg["prod_in_cde_scope"] and env not in SAFE_ENVS:
        raise ConfigError(f"environment {env} is refused while prod_in_cde_scope is true; only {', '.join(sorted(SAFE_ENVS))} are available")
    return cfg["environments"][env]
