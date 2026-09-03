#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        pass

    def _read_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length)

    def _send(self, status, body=b"", headers=None):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PROPFIND(self):
        body = self._read_body()
        if self.path == "/redirect":
            self._send(307, headers={"Location": "/dav"})
        elif self.path == "/see-other":
            self._send(303, headers={"Location": "/get-target"})
        elif self.path == "/loop":
            self._send(307, headers={"Location": "/loop"})
        elif self.path == "/cross-origin":
            port = self.server.server_address[1]
            self._send(307, headers={"Location": f"http://localhost:{port}/auth-check"})
        elif self.path == "/missing-location":
            self._send(307)
        elif self.path == "/lowercase-location":
            self._send(307, headers={"location": "/dav"})
        elif self.path == "/large":
            self._send(207, b"x" * 4096)
        elif self.path == "/dav":
            self._send(207, self.command.encode() + b":" + body, {"X-Fixture": "ready"})
        elif self.path == "/auth-check":
            marker = b"present" if self.headers.get("Authorization") else b"absent"
            self._send(207, marker)
        else:
            self._send(404)

    def do_GET(self):
        self._send(200, self.command.encode())

    def do_DELETE(self):
        self._send(204)

    def do_OPTIONS(self):
        self._send(200, self.command.encode(), {"DAV": "1, 2, calendar-access"})

    def do_POST(self):
        self._send(200, self.command.encode())


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
