#!/usr/bin/env python3
"""Stand-in for a service binary in the offline tests: `fake_service.py PORT MODE`, MODE ok|crash|stubborn|late."""
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, MODE = int(sys.argv[1]), sys.argv[2]
STARTED = time.monotonic()


class Health(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        ready = MODE != "late" or time.monotonic() - STARTED > 0.6
        code = 200 if self.path in ("/health", "/health/ready") and ready else 503
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')


if MODE == "crash":
    sys.exit(3)
if MODE == "stubborn":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
else:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
HTTPServer(("127.0.0.1", PORT), Health).serve_forever()
