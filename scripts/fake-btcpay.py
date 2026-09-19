#!/usr/bin/env python3
"""fake-btcpay.py PORT SECRET SHIP_URL
A stand-in for the parts of BTCPay Server armillary talks to: the
Greenfield invoice routes, plus the checkout page that pretends to be a
person paying on chain or over Lightning. No dependencies and no disk:
the store is a dict that dies with the process.

SECRET signs the webhooks it posts to SHIP_URL, the way a store webhook
signs real ones; pass "-" to post them unsigned. SHIP_URL is the ship's
own base, such as http://localhost:8080, and the webhook lands on
<SHIP_URL>/apps/armillary/hooks/btcpay.

The three buttons on the checkout page are the three ways an invoice
moves: settled at once, the way Lightning does; processing and then
settled, the way a chain payment does; and expired, the way an invoice
nobody paid does.

Threaded on purpose: paying posts a webhook, the ship answers it by
reading the invoice back from here, and a single-threaded server would
sit on its own tail.
"""
import hashlib
import hmac
import json
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])
SECRET = sys.argv[2]
SHIP = sys.argv[3].rstrip('/')
HOOK = SHIP + '/apps/armillary/hooks/btcpay'

LOCK = threading.Lock()
STORE = {
    'invoices': {},
    'hooks': [],
    'n': 0,
}


def nid(prefix):
    with LOCK:
        STORE['n'] += 1
        return '%s_%d' % (prefix, STORE['n'])


def sign(payload):
    mac = hmac.new(SECRET.encode(), payload.encode(), hashlib.sha256)
    return 'sha256=' + mac.hexdigest()


def post_hook(event_type, inv):
    """what a store webhook sends: the type and the invoice id"""
    payload = json.dumps({
        'type': event_type,
        'invoiceId': inv['id'],
        'storeId': inv['storeId'],
        'timestamp': int(time.time()),
        'metadata': inv['metadata'],
    })
    STORE['hooks'].append({'type': event_type, 'id': inv['id']})
    heads = {'content-type': 'application/json'}
    if SECRET != '-':
        heads['BTCPay-Sig'] = sign(payload)
    req = urllib.request.Request(HOOK, data=payload.encode(), headers=heads, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status
    except Exception as e:                                    # noqa: BLE001
        print('hook %s failed: %s' % (event_type, e), flush=True)
        return 0


def move(iid, status, event_type):
    """set an invoice's status and tell the ship, the way a payment would"""
    inv = STORE['invoices'].get(iid)
    if not inv:
        return None
    inv['status'] = status
    threading.Thread(target=post_hook, args=(event_type, inv), daemon=True).start()
    return inv


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>stub: BTCPay invoice</title></head><body>
<h1>Invoice %(id)s</h1>
<p>%(amount)s %(currency)s, status <code>%(status)s</code>.</p>
<form method="post" action="/stub/pay/%(id)s"><button>Pay now (Lightning)</button></form>
<form method="post" action="/stub/processing/%(id)s"><button>Pay on chain (processing)</button></form>
<form method="post" action="/stub/expire/%(id)s"><button>Let it expire</button></form>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        print('stub %s' % (fmt % args), flush=True)

    def send(self, code, obj, ctype='application/json'):
        body = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('content-type', ctype)
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def miss(self):
        self.send(404, {'message': 'stub: no such route'})

    def token_ok(self):
        auth = self.headers.get('authorization', '')
        if not auth.lower().startswith('token ') or len(auth) < 7:
            self.send(401, {'message': 'stub: an api key is required'})
            return False
        return True

    def body(self):
        n = int(self.headers.get('content-length') or 0)
        return self.rfile.read(n).decode() if n else ''

    def store_route(self, path, tail):
        """/api/v1/stores/<store>/invoices<tail>, or None when it is not one"""
        parts = path.strip('/').split('/')
        if len(parts) < 5 or parts[:3] != ['api', 'v1', 'stores']:
            return None
        if parts[4] != 'invoices':
            return None
        rest = parts[5:]
        if tail == 'one':
            return (parts[3], rest[0]) if len(rest) == 1 else None
        return (parts[3], None) if not rest else None

    # ---- GET ----
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == '/stub/state':
            return self.send(200, STORE)
        if path.startswith('/stub/pay/'):
            inv = STORE['invoices'].get(path[len('/stub/pay/'):])
            if not inv:
                return self.miss()
            return self.send(200, (PAGE % inv).encode(), 'text/html; charset=utf-8')
        one = self.store_route(path, 'one')
        if one:
            if not self.token_ok():
                return None
            inv = STORE['invoices'].get(one[1])
            return self.send(200, inv) if inv else self.miss()
        return self.miss()

    # ---- POST ----
    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        raw = self.body()
        for prefix, status, event in (
                ('/stub/pay/', 'Settled', 'InvoiceSettled'),
                ('/stub/processing/', 'Processing', 'InvoiceProcessing'),
                ('/stub/expire/', 'Expired', 'InvoiceExpired')):
            if path.startswith(prefix):
                inv = move(path[len(prefix):], status, event)
                return self.send(200, inv) if inv else self.miss()
        if not self.token_ok():
            return None
        many = self.store_route(path, 'many')
        if many:
            return self.invoice(many[0], raw)
        return self.miss()

    def invoice(self, store, raw):
        try:
            doc = json.loads(raw) if raw else {}
        except ValueError:
            return self.send(400, {'message': 'stub: a JSON body is required'})
        iid = nid('inv')
        now = int(time.time())
        checkout = doc.get('checkout') or {}
        minutes = int(checkout.get('expirationMinutes') or 60)
        STORE['invoices'][iid] = {
            'id': iid,
            'storeId': store,
            'checkoutLink': 'http://127.0.0.1:%d/stub/pay/%s' % (PORT, iid),
            'status': 'New',
            'additionalStatus': 'None',
            'amount': str(doc.get('amount', '0')),
            'currency': doc.get('currency', 'USD'),
            'metadata': doc.get('metadata') or {},
            'checkout': checkout,
            'createdTime': now,
            'expirationTime': now + minutes * 60,
        }
        return self.send(200, STORE['invoices'][iid])


if __name__ == '__main__':
    print('fake btcpay on %d, hooks to %s, %s' %
          (PORT, HOOK, 'signed' if SECRET != '-' else 'unsigned'), flush=True)
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
