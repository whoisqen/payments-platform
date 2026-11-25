"""Read-only data sources. Raw output only: nothing here is trusted or sent to the model; tools.py runs it through the pipeline."""
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request

from .awsctx import ScopeError
from ..config import check_https_host


class Sources:
    """Real sources of one environment, all on the assumed session. Tests replace this class with a fake of the same methods."""

    def __init__(self, env_cfg, cfg, aws, timeout=20):
        self.env, self.cfg, self.aws, self.timeout = env_cfg, cfg, aws, timeout
        self.hosts = cfg["allowed_hosts"]

    def _get_json(self, url):
        check_https_host(url, self.hosts, "request URL")
        headers = {"Accept": "application/json", "X-Scope-OrgID": str(self.env["tenant_id"])}
        req = urllib.request.Request(url, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=self.timeout) as r:  # noqa: S310 - https and host allow-list checked above
            return json.loads(r.read().decode("utf-8", "replace"))

    def loki(self, query, minutes, limit):
        now = time.time_ns()
        qs = urllib.parse.urlencode({"query": query, "limit": limit, "direction": "backward", "start": now - minutes * 60 * 10**9, "end": now})
        data = self._get_json(f"{self.env['loki_url']}/loki/api/v1/query_range?{qs}")
        return [line for stream in data.get("data", {}).get("result", []) for _ts, line in stream.get("values", [])]

    def cloudwatch(self, group, filter_pattern, minutes, limit):
        now = int(time.time() * 1000)
        resp = self.aws.client("logs").filter_log_events(logGroupName=group, filterPattern=filter_pattern or "", startTime=now - minutes * 60000,
                                                         endTime=now, limit=min(limit, 10000))
        return [e["message"] for e in resp.get("events", [])]

    def metrics(self, query, minutes, step):
        now = int(time.time())
        qs = urllib.parse.urlencode({"query": query, "start": now - minutes * 60, "end": now, "step": step})
        return self._get_json(f"{self.env['victoria_url']}/api/v1/query_range?{qs}")

    def alerts(self):
        return self._get_json(f"{self.env['alertmanager_url']}/api/v2/alerts?active=true&silenced=false&inhibited=false")

    def _kubectl(self, argv):
        env = self.aws.subprocess_env(os.environ)
        done = subprocess.run(["kubectl", *argv], capture_output=True, text=True, timeout=self.timeout + 5, check=False, env=env)  # noqa: S603
        if done.returncode:
            raise RuntimeError(f"kubectl failed: {done.stderr.strip()[:300]}")
        return done.stdout

    def verify_context(self):
        """The kubectl context must point at the configured cluster ARN (and server, when configured)."""
        ctx = self.env["kube_context"]
        view = json.loads(self._kubectl(["config", "view", "--minify", "--context", ctx, "-o", "json"]))
        cluster = (view.get("clusters") or [{}])[0]
        name, server = cluster.get("name"), (cluster.get("cluster") or {}).get("server")
        if name != self.env["kube_cluster_arn"]:
            raise ScopeError(f"kubectl context {ctx} points at cluster {name!r}, expected {self.env['kube_cluster_arn']}")
        if self.env.get("kube_server") and server != self.env["kube_server"]:
            raise ScopeError(f"kubectl context {ctx} points at server {server!r}, expected {self.env['kube_server']}")

    def kubectl_get(self, args):
        """`args` is a validated argv tail for `kubectl get`; no shell, fixed context, bounded time, assumed credentials."""
        return json.loads(self._kubectl(["--context", self.env["kube_context"], f"--request-timeout={self.timeout}s", "get", *args, "-o", "json"]))
