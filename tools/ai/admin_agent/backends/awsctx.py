"""One assumed-role boto3 session per environment: every AWS client of the agent is built from it, never from ambient credentials."""
import re


class ScopeError(Exception):
    pass


def session_name(who):
    return ("admin-agent-" + re.sub(r"[^\w+=,.@-]", "-", who or "unknown"))[:64]


class AwsContext:
    """Holds the assumed session, the verified identity and the credentials handed to subprocesses (kubectl)."""

    def __init__(self, session, identity, creds, region):
        self.session, self.identity, self.creds, self.region = session, identity, creds, region

    def client(self, service, **kw):
        kw.setdefault("region_name", self.region)
        return self.session.client(service, **kw)

    @property
    def who(self):
        return self.identity["session_name"]

    def subprocess_env(self, base):
        """Environment for kubectl: nothing ambient from AWS, only the assumed credentials."""
        env = {k: v for k, v in base.items() if not k.startswith("AWS_")}
        env.update(AWS_ACCESS_KEY_ID=self.creds["AccessKeyId"], AWS_SECRET_ACCESS_KEY=self.creds["SecretAccessKey"],
                   AWS_SESSION_TOKEN=self.creds["SessionToken"], AWS_REGION=self.region, AWS_DEFAULT_REGION=self.region)
        return env


def connect(cfg, env_name, env_cfg, local_user, boto3_module=None):
    """Assume the environment role, then check with GetCallerIdentity that the account is the configured one and not a CDE account."""
    if boto3_module is None:
        import boto3 as boto3_module
    role_arn = env_cfg.get("role_arn")
    if not role_arn:
        raise ScopeError(f"environment {env_name}: role_arn is required")
    resp = boto3_module.client("sts").assume_role(RoleArn=role_arn, RoleSessionName=session_name(local_user), DurationSeconds=3600)
    c = resp["Credentials"]
    region = env_cfg["ssm_region"]
    session = boto3_module.Session(aws_access_key_id=c["AccessKeyId"], aws_secret_access_key=c["SecretAccessKey"],
                                   aws_session_token=c["SessionToken"], region_name=region)
    ident = session.client("sts").get_caller_identity()
    account, arn = str(ident.get("Account")), str(ident.get("Arn"))
    if account in {str(a) for a in cfg.get("cde_account_ids") or []}:
        raise ScopeError(f"account {account} is a CDE account: refused")
    if account != str(env_cfg["account_id"]):
        raise ScopeError(f"environment {env_name} expects account {env_cfg['account_id']} but the credentials belong to {account}")
    m = re.match(r"^arn:aws:sts::\d{12}:assumed-role/[^/]+/(.+)$", arn)
    if not m:
        raise ScopeError("the caller identity is not an assumed role")
    identity = {"account": account, "arn": arn, "session_name": m.group(1)}
    return AwsContext(session, identity, c, region)
