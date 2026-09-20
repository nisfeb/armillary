#!/usr/bin/env python3
"""fake-stripe.py PORT SECRET SHIP_URL
A stand-in for the parts of Stripe armillary talks to: Checkout
Sessions, Invoices, Products, Prices and Subscriptions, plus the pages
that pretend to be a person paying. No dependencies and no disk: the
store is a dict that dies with the process.

SECRET signs the webhooks it posts to SHIP_URL, the way Stripe signs
real ones; pass "-" to post them unsigned. SHIP_URL is the ship's own
base, such as http://localhost:8080, and the webhook lands on
<SHIP_URL>/apps/armillary/hooks/stripe.

Threaded on purpose: paying posts a webhook, the ship answers it by
reading the session back from here, and a single-threaded server would
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
HOOK = SHIP + '/apps/armillary/hooks/stripe'

LOCK = threading.Lock()
STORE = {
    'sessions': {},
    'invoices': {},
    'products': {},
    'prices': {},
    'subscriptions': {},
    'hooks': [],
    'n': 0,
}


def nid(prefix):
    with LOCK:
        STORE['n'] += 1
        return '%s_%d' % (prefix, STORE['n'])


def form(body):
    """a form body as a flat dict, the keys exactly as Stripe names them"""
    out = {}
    for pair in body.split('&'):
        if not pair:
            continue
        k, _, v = pair.partition('=')
        out[urllib.parse.unquote_plus(k)] = urllib.parse.unquote_plus(v)
    return out


def sign(payload, when):
    mac = hmac.new(SECRET.encode(), ('%d.%s' % (when, payload)).encode(), hashlib.sha256)
    return 't=%d,v1=%s' % (when, mac.hexdigest())


def post_hook(event_type, obj):
    """what Stripe sends: the type and the object, nothing else trusted"""
    payload = json.dumps({'type': event_type, 'data': {'object': obj}})
    STORE['hooks'].append({'type': event_type, 'id': obj.get('id')})
    heads = {'content-type': 'application/json'}
    if SECRET != '-':
        heads['stripe-signature'] = sign(payload, int(time.time()))
    req = urllib.request.Request(HOOK, data=payload.encode(), headers=heads, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status
    except Exception as e:                                    # noqa: BLE001
        print('hook %s failed: %s' % (event_type, e), flush=True)
        return 0


def pay(sid):
    """mark a session paid and tell the ship, the way a card would"""
    s = STORE['sessions'].get(sid)
    if not s:
        return None
    if s['payment_status'] != 'paid':
        s['payment_status'] = 'paid'
        s['payment_intent'] = nid('pi')
        if s['mode'] == 'subscription':
            s['customer'] = nid('cus')
            s['subscription'] = nid('sub')
            STORE['subscriptions'][s['subscription']] = {
                'id': s['subscription'],
                'customer': s['customer'],
                'price': s.get('price', ''),
                'plan': s.get('plan', ''),
                'cancel_at_period_end': False,
            }
            make_invoice(s['subscription'])
    threading.Thread(target=fire, args=(sid,), daemon=True).start()
    return s


def fire(sid):
    s = STORE['sessions'][sid]
    post_hook('checkout.session.completed', {'id': sid})
    if s['mode'] == 'subscription':
        for iid, inv in STORE['invoices'].items():
            if inv['subscription'] == s['subscription']:
                post_hook('invoice.paid', {'id': iid})


def make_invoice(sub_id):
    sub = STORE['subscriptions'][sub_id]
    iid = nid('in')
    STORE['invoices'][iid] = {
        'id': iid,
        'status': 'paid',
        'paid': True,
        'customer': sub['customer'],
        'subscription': sub_id,
        'lines': {'data': [{
            'price': {'id': sub['price']},
            'period': {'end': int(time.time()) + 30 * 86400},
        }]},
    }
    return iid


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
        self.send(404, {'error': {'message': 'stub: no such route'}})

    def bearer_ok(self):
        auth = self.headers.get('authorization', '')
        if not auth.lower().startswith('bearer ') or len(auth) < 9:
            self.send(401, {'error': {'message': 'stub: a key is required'}})
            return False
        return True

    def body(self):
        n = int(self.headers.get('content-length') or 0)
        return self.rfile.read(n).decode() if n else ''

    # ---- GET ----
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == '/stub/state':
            return self.send(200, STORE)
        if path.startswith('/stub/pay/'):
            sid = path[len('/stub/pay/'):]
            s = pay(sid)
            if not s:
                return self.miss()
            page = ('<!doctype html><html><body><h1>stub: paid</h1>'
                    '<p>Session <code>%s</code>.</p></body></html>' % sid)
            return self.send(200, page.encode(), 'text/html; charset=utf-8')
        if path.startswith('/v1/checkout/sessions/'):
            if not self.bearer_ok():
                return None
            s = STORE['sessions'].get(path[len('/v1/checkout/sessions/'):])
            return self.send(200, s) if s else self.miss()
        if path.startswith('/v1/invoices/'):
            if not self.bearer_ok():
                return None
            inv = STORE['invoices'].get(path[len('/v1/invoices/'):])
            return self.send(200, inv) if inv else self.miss()
        return self.miss()

    # ---- POST ----
    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        raw = self.body()
        if path.startswith('/stub/pay/'):
            s = pay(path[len('/stub/pay/'):])
            return self.send(200, s) if s else self.miss()
        if path.startswith('/stub/renew/'):
            sub_id = path[len('/stub/renew/'):]
            if sub_id not in STORE['subscriptions']:
                return self.miss()
            iid = make_invoice(sub_id)
            threading.Thread(target=post_hook,
                             args=('invoice.paid', {'id': iid}), daemon=True).start()
            return self.send(200, {'invoice': iid})
        if path.startswith('/stub/delete/'):
            sub_id = path[len('/stub/delete/'):]
            if sub_id not in STORE['subscriptions']:
                return self.miss()
            threading.Thread(target=post_hook,
                             args=('customer.subscription.deleted', {'id': sub_id}),
                             daemon=True).start()
            return self.send(200, {'deleted': sub_id})
        if not self.bearer_ok():
            return None
        f = form(raw)
        if path == '/v1/checkout/sessions':
            return self.session(f)
        if path == '/v1/products':
            pid = nid('prod')
            STORE['products'][pid] = {'id': pid, 'name': f.get('name', '')}
            return self.send(200, STORE['products'][pid])
        if path == '/v1/prices':
            pid = nid('price')
            STORE['prices'][pid] = {
                'id': pid,
                'product': f.get('product', ''),
                'unit_amount': int(f.get('unit_amount') or 0),
                'currency': f.get('currency', 'usd'),
                'recurring': {'interval': f.get('recurring[interval]', '')},
            }
            return self.send(200, STORE['prices'][pid])
        if path.startswith('/v1/subscriptions/'):
            sub_id = path[len('/v1/subscriptions/'):]
            sub = STORE['subscriptions'].get(sub_id)
            if not sub:
                return self.miss()
            sub['cancel_at_period_end'] = f.get('cancel_at_period_end') == 'true'
            return self.send(200, sub)
        return self.miss()

    def session(self, f):
        mode = f.get('mode', 'payment')
        sid = nid('cs')
        price_id = f.get('line_items[0][price]', '')
        qty = int(f.get('line_items[0][quantity]') or 1)
        if mode == 'subscription':
            price = STORE['prices'].get(price_id, {})
            total = int(price.get('unit_amount') or 0) * qty
        else:
            total = int(f.get('line_items[0][price_data][unit_amount]') or 0) * qty
        STORE['sessions'][sid] = {
            'id': sid,
            'url': 'http://127.0.0.1:%d/stub/pay/%s' % (PORT, sid),
            'mode': mode,
            'payment_status': 'unpaid',
            'amount_total': total,
            'amount_subtotal': total,
            'metadata': {'ship': f.get('metadata[ship]', '')},
            'customer': None,
            'subscription': None,
            'payment_intent': None,
            'price': price_id,
            'plan': f.get('subscription_data[metadata][plan]', ''),
            'success_url': f.get('success_url', ''),
            'cancel_url': f.get('cancel_url', ''),
            'expires_at': int(f.get('expires_at') or 0),
        }
        return self.send(200, STORE['sessions'][sid])


if __name__ == '__main__':
    print('fake stripe on %d, hooks to %s, %s' %
          (PORT, HOOK, 'signed' if SECRET != '-' else 'unsigned'), flush=True)
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
