#!/usr/bin/env python3
"""Tiny live-view server: http://127.0.0.1:8099/ serves the current X display as a PNG
(refreshed on demand).

Lets a running desktop be watched remotely (over an SSH tunnel / a browser tab) while
long unattended Wine runs happen, instead of taking screenshots by hand.

usage: shotserve.py [port] [display]
       port     default 8099
       display  default $DISP or :2   (the VNC display - a real X server, so root
                capture works; on Xwayland :0 root grabs come back black)
"""
import http.server
import os
import subprocess
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
DISPLAY = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("DISP", ":2")
CACHE = "/tmp/shotserve%s.png" % ("" if PORT == 8099 else str(PORT))
LAST = [0.0]
MIN_INTERVAL = 1.5


def shot() -> bytes:
    """Return the current display pixels as PNG bytes, at most every MIN_INTERVAL s."""
    if time.time() - LAST[0] > MIN_INTERVAL:
        env = dict(os.environ)
        env["DISPLAY"] = DISPLAY
        subprocess.run(
            ["import", "-display", DISPLAY, "-window", "root", CACHE],
            env=env, capture_output=True, timeout=60, check=True,
        )
        LAST[0] = time.time()
    with open(CACHE, "rb") as fh:
        return fh.read()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path.startswith("/latest.png") or self.path == "/":
            try:
                data = shot()
            except Exception as e:  # noqa: BLE001
                self.send_error(500, str(e))
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_error(404)

    def log_message(self, *a):  # keep quiet
        pass


print(f"live view of DISPLAY={DISPLAY} on http://127.0.0.1:{PORT}/latest.png", flush=True)
http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
