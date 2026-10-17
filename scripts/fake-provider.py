#!/usr/bin/env python3
"""An OpenAI-compatible stub provider, for the gate and for hand smoking.

Usage: fake-provider.py PORT KEY

It listens on 127.0.0.1:PORT and wants `Authorization: Bearer KEY` on
every /v1 route. The ship reaches it as http://127.0.0.1:PORT/v1.

It also answers the key provisioning API a lease is made through, under
/api/v1/keys, which wants any non-empty `Authorization: Bearer ...`:

  POST   /api/v1/keys          mints sk-or-stub-<n> with hash h<n>
  GET    /api/v1/keys/<hash>   the record
  PATCH  /api/v1/keys/<hash>   moves `limit` and `disabled`
  DELETE /api/v1/keys/<hash>   forgets it
  POST   /stub/spend/<hash>    {"usd": n} adds to that key's usage

A leased key works as the bearer on the chat route: each completion adds
one cent to its usage, and a key that is disabled or has reached its
limit is refused 401, the way OpenRouter refuses one.

Models it knows:
  stub/alpha  priced, answers "ok: <the last user message>"
  stub/beta   priced, the same
  stub/free   unpriced, so an import leaves its prices at zero
  stub/error  answers 500 with a message, so the gate sees a pass through
  stub/slow   sleeps past the ship's two minute deadline, so the gate sees a 504
  stub/whisper  speech to text, listed only under
              GET /v1/models?output_modalities=transcription, the way
              OpenRouter lists its transcription models; POST
              /v1/audio/transcriptions answers OpenRouter's shape, with
              usage.cost 0.000508, and /stub/requests then shows the
              model, the format and how many base64 bytes came

GET /stub/requests answers how many bodies it has seen and the last one,
so a gate can assert the ship swapped `model` and dropped `stream`.
A chat whose body asks usage.include gets usage.cost back, the call's
price at the stub's own per-token prices, as OpenRouter answers it.
"""

import email.policy
import json
import sys
import time
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SPEECH = [{"id": "stub/whisper", "pricing": {"prompt": "0.0001", "completion": "0"}}]
MODELS = [
    {"id": "stub/alpha", "pricing": {"prompt": "0.000003", "completion": "0.000015"}},
    {"id": "stub/beta", "pricing": {"prompt": "0.0000015", "completion": "0.000006"}},
    {"id": "stub/free"},
]

STATE = {"count": 0, "last": None, "n": 0, "keys": 0}

# the leases this stub has minted: hash -> record, and the plaintext key
# back to its hash, since a completion arrives under the key
LEASES = {}
BY_KEY = {}
PER_REQUEST_USD = 0.01


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def six(n):
    """a money figure with no scientific notation in it"""
    return float("%.6f" % float(n or 0))


def record(rec):
    out = dict(rec)
    out["usage"] = six(out["usage"])
    out["usage_daily"] = out["usage"]
    out["usage_weekly"] = out["usage"]
    out["usage_monthly"] = out["usage"]
    if out.get("limit") is not None:
        out["limit"] = six(out["limit"])
        out["limit_remaining"] = six(max(0.0, out["limit"] - out["usage"]))
    return out


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

    def bearer(self):
        head = self.headers.get("authorization", "")
        return head[7:] if head.startswith("Bearer ") else ""

    def provisioning_ok(self):
        """any non-empty bearer is a provisioning key here"""
        return bool(self.bearer())

    def leased(self):
        """the lease record this request's bearer names, or None"""
        return LEASES.get(BY_KEY.get(self.bearer(), ""), None)

    def hash_of(self, prefix):
        rest = self.path.rstrip("/")[len(prefix):]
        return rest if rest and "/" not in rest else ""

    def read_raw(self):
        length = int(self.headers.get("content-length") or 0)
        return self.rfile.read(length) if length else b""

    def read_body(self):
        raw = self.read_raw()
        try:
            return json.loads(raw.decode() or "{}")
        except ValueError:
            return {}

    def do_GET(self):
        if self.path.startswith("/api/v1/keys/"):
            if not self.provisioning_ok():
                self.send(401, {"error": {"message": "no provisioning key"}})
                return
            rec = LEASES.get(self.hash_of("/api/v1/keys/"))
            if rec is None:
                self.send(404, {"error": {"message": "no such key"}})
                return
            self.send(200, {"data": record(rec)})
            return
        if self.path == "/stub/requests":
            self.send(200, {"count": STATE["count"], "last": STATE["last"]})
            return
        if self.path.rstrip("/") == "/v1/credits":
            # OpenRouter's account credits, management key only
            if not self.provisioning_ok():
                self.send(401, {"error": {"message": "no provisioning key"}})
                return
            self.send(200, {"data": {"total_credits": 50, "total_usage": 10.5}})
            return
        if self.path.rstrip("/") == "/v1/endpoints/zdr":
            # OpenRouter's list of endpoints that keep nothing: alpha has one
            self.send(200, {"data": [{"model_id": "stub/alpha", "provider_name": "Stub ZDR", "name": "stub/alpha-zdr"}]})
            return
        if self.path == "/v1/models?output_modalities=transcription":
            if not self.bearer_ok():
                self.send(401, {"error": {"message": "bad key"}})
                return
            self.send(200, {"data": SPEECH})
            return
        if self.path.rstrip("/") == "/box/v1/models":
            # a server that is not OpenRouter: its whisper model sits in
            # the one list with its chat model, marked as nothing
            self.send(200, {"data": [{"id": "whisper-1"}, {"id": "llama3.1:8b"}]})
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
        if path == "/api/v1/keys":
            if not self.provisioning_ok():
                self.send(401, {"error": {"message": "no provisioning key"}})
                return
            body = self.read_body()
            STATE["keys"] += 1
            n = STATE["keys"]
            key = "sk-or-stub-%d" % n
            rec = {
                "hash": "h%d" % n,
                "name": body.get("name") or "",
                "label": body.get("name") or "",
                "limit": body.get("limit"),
                "limit_reset": None,
                "disabled": False,
                "usage": 0,
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
            LEASES[rec["hash"]] = rec
            BY_KEY[key] = rec["hash"]
            self.send(201, {"key": key, "data": record(rec)})
            return
        if path.startswith("/stub/spend/"):
            rec = LEASES.get(self.hash_of("/stub/spend/"))
            if rec is None:
                self.send(404, {"error": {"message": "no such key"}})
                return
            body = self.read_body()
            rec["usage"] = six(rec["usage"] + float(body.get("usd") or 0))
            rec["updated_at"] = now_iso()
            self.send(200, {"data": record(rec)})
            return
        if path == "/alpha/decisions":
            # OpenRouter's decisions route: an answer per question and
            # what it cost, except for the model that reports no cost
            body = self.read_body()
            STATE["count"] += 1
            STATE["last"] = body
            if not self.bearer_ok():
                self.send(401, {"error": {"message": "bad key"}})
                return
            usage = {"input_tokens": 12}
            if body.get("model") != "typesafe/nocost":
                usage["cost"] = 0.0002
            self.send(200, {"id": "dec-%d" % STATE["count"],
                            "answers": {k: {"yes": 0.7} for k in (body.get("questions") or {})},
                            "usage": usage})
            return
        ctype = self.headers.get("content-type") or ""
        if path == "/v1/audio/transcriptions" and ctype.startswith("multipart/form-data"):
            # OpenAI's own transcription shape, which a server that is
            # not OpenRouter reads
            raw = self.read_raw()
            STATE["count"] += 1
            if not self.bearer_ok():
                self.send(401, {"error": {"message": "bad key"}})
                return
            msg = BytesParser(policy=email.policy.HTTP).parsebytes(
                b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + raw)
            fields = {p.get_param("name", header="content-disposition"): p for p in msg.iter_parts()}
            text = lambda k: fields[k].get_payload(decode=True).decode() if k in fields else None
            audio = fields.get("file")
            data = audio.get_payload(decode=True) if audio else b""
            STATE["last"] = {"multipart": True, "model": text("model"), "language": text("language"),
                             "response_format": text("response_format"),
                             "filename": audio.get_filename() if audio else None, "bytes": len(data),
                             "zeros": data == b"\0" * len(data)}
            self.send(200, {"text": "ok: heard %d bytes in a form" % len(data)})
            return
        if path not in ("/v1/chat/completions", "/v1/embeddings", "/v1/audio/transcriptions"):
            self.send(404, {"error": {"message": "no such route"}})
            return
        body = self.read_body()
        STATE["count"] += 1
        STATE["last"] = body
        if path == "/v1/audio/transcriptions":
            # the audio is kept out of /stub/requests: its size says enough
            audio = body.get("input_audio") or {}
            STATE["last"] = {"model": body.get("model"), "format": audio.get("format"),
                             "bytes": len(audio.get("data") or "")}
        lease = self.leased()
        if lease is not None:
            # a leased key spends like the real thing: a flat cent a
            # call, refused once it is switched off or over its cap
            if lease["disabled"]:
                self.send(401, {"error": {"message": "key disabled"}})
                return
            cap = lease.get("limit")
            if cap is not None and lease["usage"] >= float(cap):
                self.send(401, {"error": {"message": "key limit reached"}})
                return
            lease["usage"] = six(lease["usage"] + PER_REQUEST_USD)
            lease["updated_at"] = now_iso()
        elif not self.bearer_ok():
            self.send(401, {"error": {"message": "bad key"}})
            return
        if path == "/v1/audio/transcriptions":
            audio = body.get("input_audio") or {}
            if not audio.get("data") or not audio.get("format"):
                self.send(400, {"error": {"message": "input_audio.data and input_audio.format are required"}})
                return
            self.send(200, {"text": "ok: heard %d bytes" % len(audio["data"]),
                            "usage": {"seconds": 9.2, "total_tokens": 113, "input_tokens": 83,
                                      "output_tokens": 30, "cost": 0.000508}})
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
        if model == "stub/slow5":
            time.sleep(5)
        if model in ("stub/decider", "stub/badjson"):
            # a chat model asked for decisions: the answers as JSON after
            # a think block and among prose, the way a local model writes
            # them; badjson answers in words alone
            asked = {}
            for message in body.get("messages") or []:
                if message.get("role") == "user":
                    try:
                        asked = json.loads(message.get("content") or "{}").get("questions") or {}
                    except ValueError:
                        asked = {}
            answers = {}
            for k, q in asked.items():
                if q.get("type") == "noul":
                    answers[k] = {"noul": 0.8}
                else:
                    opts = sorted((q.get("criteria") or {}).keys()) or q.get("options") or ["x"]
                    answers[k] = {"choice": opts[0], "probabilities": {o: (0.9 if i == 0 else 0.1) for i, o in enumerate(opts)}}
            text = ("<think>weighing it</think>Here are the answers: " + json.dumps(answers) + " Done."
                    if model == "stub/decider" else "I would rather not decide.")
            STATE["n"] += 1
            self.send(200, {"id": "stub-%d" % STATE["n"], "model": model,
                            "choices": [{"message": {"role": "assistant", "content": text}}],
                            "usage": {"prompt_tokens": 40, "completion_tokens": 20}})
            return
        last = ""
        for message in body.get("messages") or []:
            if message.get("role") == "user":
                last = message.get("content") or ""
        STATE["n"] += 1
        usage = {"prompt_tokens": 7 + len(last.split()), "completion_tokens": 5}
        if (body.get("usage") or {}).get("include") is True:
            # OpenRouter's usage accounting: what the call cost at the
            # provider's own price, the way the ship is meant to charge it
            price = next((m.get("pricing") or {} for m in MODELS if m["id"] == model), {})
            usage["cost"] = six(usage["prompt_tokens"] * float(price.get("prompt") or 0)
                                + usage["completion_tokens"] * float(price.get("completion") or 0))
        self.send(
            200,
            {
                "id": "stub-%d" % STATE["n"],
                "model": model,
                "choices": [
                    {"message": {"role": "assistant", "content": "ok: " + last}}
                ],
                "usage": usage,
            },
        )


    def do_PATCH(self):
        if not self.path.startswith("/api/v1/keys/"):
            self.send(404, {"error": {"message": "no such route"}})
            return
        if not self.provisioning_ok():
            self.send(401, {"error": {"message": "no provisioning key"}})
            return
        rec = LEASES.get(self.hash_of("/api/v1/keys/"))
        if rec is None:
            self.send(404, {"error": {"message": "no such key"}})
            return
        body = self.read_body()
        if "limit" in body:
            rec["limit"] = body["limit"]
        if "disabled" in body:
            rec["disabled"] = bool(body["disabled"])
        if "name" in body:
            rec["name"] = body["name"]
        rec["updated_at"] = now_iso()
        self.send(200, {"data": record(rec)})

    def do_DELETE(self):
        if not self.path.startswith("/api/v1/keys/"):
            self.send(404, {"error": {"message": "no such route"}})
            return
        if not self.provisioning_ok():
            self.send(401, {"error": {"message": "no provisioning key"}})
            return
        h = self.hash_of("/api/v1/keys/")
        rec = LEASES.pop(h, None)
        if rec is None:
            self.send(404, {"error": {"message": "no such key"}})
            return
        for key, held in list(BY_KEY.items()):
            if held == h:
                del BY_KEY[key]
        self.send(200, {"data": {"deleted": True}})


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    port = int(sys.argv[1])
    # threaded, so a slow model does not hold the next call behind it
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.key = sys.argv[2]
    print("stub provider on 127.0.0.1:%d" % port, flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
