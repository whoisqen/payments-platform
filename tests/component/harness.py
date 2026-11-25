import os
import signal
import subprocess
import time
import urllib.error
import urllib.request


class ServiceError(Exception):
    pass


def _opener():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def get(url, timeout=2.0):
    try:
        with _opener().open(urllib.request.Request(url, method="GET"), timeout=timeout) as r:
            return r.status, r.read(1 << 16)
    except urllib.error.HTTPError as err:
        return err.code, b""


def wait_healthy(url, timeout, proc=None, interval=0.25, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + timeout
    last = "no answer"
    while clock() < deadline:
        if proc is not None and proc.poll() is not None:
            raise ServiceError(f"exited with code {proc.returncode} before it was healthy")
        try:
            status, _ = get(url)
            if status == 200:
                return
            last = f"HTTP {status}"
        except OSError as err:
            last = type(err).__name__
        sleep(interval)
    raise ServiceError(f"not healthy within {timeout:.0f}s ({last})")


class Service:
    def __init__(self, name, argv, env=None, cwd=None, log_path=os.devnull):
        self.name, self.argv, self.env, self.cwd, self.log_path = name, argv, env or {}, cwd, log_path
        self.proc = None
        self._log = None

    def start(self):
        self._log = open(self.log_path, "ab")
        # the child gets only PATH and HOME from the runner plus its own settings, never the CI secrets
        base = {k: os.environ[k] for k in ("PATH", "HOME", "LANG") if k in os.environ}
        self.proc = subprocess.Popen(self.argv, env={**base, **self.env}, cwd=self.cwd, stdout=self._log,
                                     stderr=subprocess.STDOUT, start_new_session=True)
        return self.proc

    def stop(self, grace=15.0):
        if self.proc is None:
            return None
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(grace)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
                self._close()
                raise ServiceError(f"did not stop within {grace:.0f}s of SIGTERM") from None
        self._close()
        return self.proc.returncode

    def _close(self):
        if self._log:
            self._log.close()
            self._log = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        if self.proc is not None and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        self._close()
