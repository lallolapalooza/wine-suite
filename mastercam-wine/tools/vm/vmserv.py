#!/usr/bin/env python3
"""Tiny HTTP file channel for the Windows guest.

Host side: serves <share>/ for GET and stores PUT bodies in <share>/.
Guest side: curl http://192.168.122.1:8000/<name>   and   curl -T <file> http://192.168.122.1:8000/<name>

usage: vmserv.py [port] [share_dir]
"""
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHARE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "vmshare")
os.makedirs(SHARE, exist_ok=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=SHARE, **kw)

    def do_PUT(self):
        name = os.path.basename(self.path.split("?")[0])
        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length) if length else b""
        with open(os.path.join(SHARE, name), "wb") as f:
            f.write(data)
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b"stored %d bytes\n" % len(data))
        self.log_message("PUT %s (%d bytes)", name, length)

    def do_GET(self):
        if self.path.split("?")[0] in ("/", ""):
            listing = "\n".join(sorted(os.listdir(SHARE))) + "\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(listing)))
            self.end_headers()
            self.wfile.write(listing.encode())
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stderr.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print("serving %s on 0.0.0.0:%d" % (SHARE, PORT), flush=True)
    Server(("0.0.0.0", PORT), Handler).serve_forever()
