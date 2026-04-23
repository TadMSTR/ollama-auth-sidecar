"""
Mock upstream server for ollama-auth-sidecar integration tests.

Endpoints:
  GET/POST /           — echo all received request headers as JSON
  GET/POST /stream     — emit 5 NDJSON chunks over 3 seconds (tests streaming)
  GET/POST /slow       — sleep for SLOW_SECONDS (default 10) before responding (tests timeouts)
  GET      /health     — return 200 "ok"

Header names are lowercased in JSON output for consistent assertions.
"""

import http.server
import json
import os
import time


SLOW_SECONDS = int(os.environ.get("SLOW_SECONDS", "10"))


class MockHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: N802
        # Write to stderr with timestamp so CI captures it
        print(f"[mock-upstream] {self.address_string()} - {fmt % args}", flush=True)

    def _headers_dict(self):
        return {k.lower(): v for k, v in self.headers.items()}

    def do_GET(self):  # noqa: N802
        self._handle()

    def do_POST(self):  # noqa: N802
        self._handle()

    def _handle(self):
        path = self.path.split("?")[0]

        if path == "/health":
            self._respond(200, "ok\n", "text/plain")

        elif path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(5):
                chunk = json.dumps({"chunk": i, "headers": self._headers_dict()}) + "\n"
                self.wfile.write(chunk.encode())
                self.wfile.flush()
                time.sleep(0.6)

        elif path == "/slow":
            time.sleep(SLOW_SECONDS)
            self._respond(200, json.dumps({"slept": SLOW_SECONDS}), "application/json")

        else:
            body = json.dumps(self._headers_dict())
            self._respond(200, body, "application/json")

    def _respond(self, status, body, content_type):
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", 8080), MockHandler)
    print("[mock-upstream] listening on :8080", flush=True)
    server.serve_forever()
