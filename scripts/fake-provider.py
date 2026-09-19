#!/usr/bin/env python3
"""An OpenAI-compatible stub provider, for the gate and for hand smoking.

Usage: fake-provider.py PORT KEY

It listens on 127.0.0.1:PORT and wants `Authorization: Bearer KEY` on
every /v1 route. The ship reaches it as http://127.0.0.1:PORT/v1.

Models it knows:
  stub/alpha  priced, answers "ok: <the last user message>"
  stub/beta   priced, the same
  stub/free   unpriced, so an import leaves its prices at zero
  stub/error  answers 500 with a message, so the gate sees a pass through
  stub/slow   sleeps past the ship's two minute deadline, so the gate sees a 504

GET /stub/requests answers how many bodies it has seen and the last one,
so a gate can assert the ship swapped `model` and dropped `stream`.
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

MODELS = [
    {"id": "stub/alpha", "pricing": {"prompt": "0.000003", "completion": "0.000015"}},
    {"id": "stub/beta", "pricing": {"prompt": "0.0000015", "completion": "0.000006"}},
    {"id": "stub/free"},
]

STATE = {"count": 0, "last": None, "n": 0}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def bearer_ok(self):
        head = self.headers.get("authorization", "")
        return head == "Bearer " + self.server.key

    def read_body(self):
        length = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode() or "{}")
        except ValueError:
            return {}

    def do_GET(self):
        if self.path == "/stub/requests":
            self.send(200, {"count": STATE["count"], "last": STATE["last"]})
            return
        if self.path.rstrip("/") == "/v1/models":
            if not self.bearer_ok():
                self.send(401, {"error": {"message": "bad key"}})
                return
            self.send(200, {"data": MODELS})
            return
        self.send(404, {"error": {"message": "no such route"}})

    def do_POST(self):
        path = self.path.rstrip("/")
        if path not in ("/v1/chat/completions", "/v1/embeddings"):
            self.send(404, {"error": {"message": "no such route"}})
            return
        body = self.read_body()
        STATE["count"] += 1
        STATE["last"] = body
        if not self.bearer_ok():
            self.send(401, {"error": {"message": "bad key"}})
            return
        if path == "/v1/embeddings":
            self.send(
                200,
                {
                    "data": [{"embedding": [0.1, 0.2]}],
                    "usage": {"prompt_tokens": 9},
                },
            )
            return
        if body.get("stream") is True:
            self.send(400, {"error": {"message": "stream is not supported here"}})
            return
        model = body.get("model") or ""
        if model == "stub/error":
            self.send(500, {"error": {"message": "stub failure"}})
            return
        if model == "stub/slow":
            time.sleep(130)
        last = ""
        for message in body.get("messages") or []:
            if message.get("role") == "user":
                last = message.get("content") or ""
        STATE["n"] += 1
        self.send(
            200,
            {
                "id": "stub-%d" % STATE["n"],
                "model": model,
                "choices": [
                    {"message": {"role": "assistant", "content": "ok: " + last}}
                ],
                "usage": {
                    "prompt_tokens": 7 + len(last.split()),
                    "completion_tokens": 5,
                },
            },
        )


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    port = int(sys.argv[1])
    server = HTTPServer(("127.0.0.1", port), Handler)
    server.key = sys.argv[2]
    print("stub provider on 127.0.0.1:%d" % port, flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
