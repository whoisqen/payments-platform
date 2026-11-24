"""python3 -m tools.ai.admin_agent --env dev [--model sonnet] [--question Q] [--no-dry-run]"""
import argparse
import getpass
import json
import os
import sys
import time

import sanitize  # noqa: E402

from . import actions as actions_mod
from . import config as config_mod
from .agent import Session
from .compress import SessionBudget
from .backends import awsctx
from .backends.sources import Sources
from .compress import clean
from .tools import Audit, ToolLayer


def make_client(aws, cfg):
    from botocore.config import Config
    b = cfg["bedrock"]
    return aws.client("bedrock-runtime", region_name=b["region"], endpoint_url=b["endpoint_url"],
                      config=Config(read_timeout=b["timeout_seconds"], retries={"max_attempts": 2}))


def open_private(path):
    """Append-only text file readable by the owner only (0600), also when it already existed."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.fchmod(fd, 0o600)
    return os.fdopen(fd, "a", encoding="utf-8")


class CloudWatchSink:
    """Optional audit sink. Receives metadata only: arguments and details are dropped, so no model or log text leaves the machine."""

    def __init__(self, client, group, stream):
        self.client, self.group, self.stream = client, group, stream
        try:
            client.create_log_stream(logGroupName=group, logStreamName=stream)
        except Exception as e:  # noqa: BLE001 - an existing stream is fine
            if type(e).__name__ != "ResourceAlreadyExistsException":
                raise

    def send(self, line):
        rec = {k: v for k, v in json.loads(line).items() if k not in ("args", "detail")}
        self.client.put_log_events(logGroupName=self.group, logStreamName=self.stream,
                                   logEvents=[{"timestamp": int(time.time() * 1000), "message": json.dumps(rec, sort_keys=True)}])


def build_parser():
    p = argparse.ArgumentParser(prog="admin_agent", description=__doc__)
    p.add_argument("--env", required=True, help="environment from config/admin-agent.yaml (cde-prod is refused; prod while prod_in_cde_scope is true)")
    p.add_argument("--model", help="allowed model name or id; default is the cheapest allowed")
    p.add_argument("--budget-tokens", type=int, help="model tokens (input + output) for the session")
    p.add_argument("--dry-run", action=argparse.BooleanOptionalAction, default=True, help="confirmed actions only print what they would do (default); --no-dry-run executes")
    p.add_argument("--question", help="ask once and exit; otherwise read questions from the terminal")
    p.add_argument("--config", default=str(config_mod.CONFIG))
    p.add_argument("--audit-file", help="append the audit log here as well as stdout")
    p.add_argument("--transcript", help="write the sanitised transcript here")
    return p


def main(argv=None, client=None, sources=None, ask=input, out=print, executor=None, aws=None):
    args = build_parser().parse_args(argv)
    try:
        cfg = config_mod.load(args.config)
        env_cfg = config_mod.pick_env(cfg, args.env)
        model, defaulted = config_mod.pick_model(cfg, args.model)
    except config_mod.ConfigError as e:
        print(f"admin_agent: {e}", file=sys.stderr)
        return 2
    if defaulted:
        print(f"admin_agent: no --model given; using the cheapest allowed model {model['name']}", file=sys.stderr)
    budget_tokens = args.budget_tokens or cfg["limits"]["default_session_tokens"]
    if budget_tokens <= 0:
        print("admin_agent: --budget-tokens must be positive", file=sys.stderr)
        return 2
    for w in config_mod.warnings(cfg):
        print(f"admin_agent: warning: {w}", file=sys.stderr)
    try:
        aws = aws or awsctx.connect(cfg, args.env, env_cfg, getpass.getuser())
        sources = sources or Sources(env_cfg, cfg, aws, cfg["kubectl"]["timeout_seconds"])
        sources.verify_context()
    except (awsctx.ScopeError, RuntimeError) as e:
        print(f"admin_agent: {e}", file=sys.stderr)
        return 2
    who = aws.who  # from GetCallerIdentity (assumed-role session name), not USER/LOGNAME
    redactor = sanitize.Redactor()
    files = []
    sink = None
    ac = cfg["audit"]
    if ac.get("cloudwatch_log_group"):
        sink = CloudWatchSink(aws.client("logs"), ac["cloudwatch_log_group"], f"{args.env}/{who}"[:512])
    audit_file = open_private(args.audit_file) if args.audit_file else None
    transcript_file = open_private(args.transcript) if args.transcript else None
    files = [f for f in (audit_file, transcript_file) if f]

    def write_audit(line):
        out(line)
        if audit_file:
            audit_file.write(line + "\n")
            audit_file.flush()
        if sink:
            try:
                sink.send(line)
            except Exception as e:  # noqa: BLE001 - the local audit line is already written
                print(f"admin_agent: audit sink failed: {type(e).__name__}", file=sys.stderr)

    def write_transcript(line):
        if transcript_file:
            transcript_file.write(line + "\n")
            transcript_file.flush()

    try:
        audit = Audit(who, args.env, write_audit, redactor, aws.identity["account"])
        registry = actions_mod.ActionRegistry(cfg["actions"], args.env, env_cfg, cfg)
        lim = cfg["limits"]
        tools = ToolLayer(cfg, args.env, env_cfg, sources, registry, audit, redactor, SessionBudget(lim["tool_result_tokens"], lim["session_tool_tokens"]))
        session = Session(client or make_client(aws, cfg), model["id"], tools, redactor, cfg, budget_tokens, write_transcript)
        executor = executor or actions_mod.ssm_executor(aws, env_cfg["ssm_region"])
        retype = cfg.get("require_env_retype", [])

        def handle(question):
            tools.new_turn()
            out(session.ask(question))
            prop = tools.proposals.pop(0) if tools.proposals else None  # one proposal per turn
            tools.proposals.clear()
            if prop is None:
                return
            if args.env in retype and args.dry_run:
                out(f"{args.env} actions need --no-dry-run; the proposal was not offered")
                audit.log("action:" + prop.action_id, prop.params, "refused", detail="prod needs --no-dry-run")
                return
            if actions_mod.confirm(prop, registry, args.dry_run, ask, retype):
                try:
                    result = actions_mod.execute(registry, prop.action_id, prop.params, args.dry_run, executor)
                    audit.log("action:" + prop.action_id, prop.params, "confirmed" if not args.dry_run else "confirmed-dry-run")
                except Exception as e:  # noqa: BLE001
                    result = f"action failed: {type(e).__name__}"
                    audit.log("action:" + prop.action_id, prop.params, "failed")
                out(clean(redactor.redact(result)))
            else:
                audit.log("action:" + prop.action_id, prop.params, "declined")
                out("declined")

        if args.question:
            handle(args.question)
        else:
            while True:
                try:
                    q = ask("> ").strip()
                except EOFError:
                    break
                if not q:
                    break
                handle(q)
        return 0
    finally:
        for f in files:
            f.close()
