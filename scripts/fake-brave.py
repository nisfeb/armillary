"""fake-brave.py PORT: a stand-in for Brave Search. It answers every GET
with what it received, so a test sees the path, the query as it arrived
and the key header."""
import json, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urlparse(self.path)
        body = json.dumps({'path': u.path, 'raw_query': u.query,
                           'query': {k: v[0] for k, v in parse_qs(u.query).items()},
                           'token': self.headers.get('x-subscription-token', ''),
                           'web': {'results': [{'title': 'stub', 'url': 'https://x', 'description': 'd'}]}}).encode()
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 3402), H).serve_forever()
