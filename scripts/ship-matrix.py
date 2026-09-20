#!/usr/bin/env python3
"""ship-matrix.py HOST JAR [PEER PJAR]
The account channel over ames, end to end: a customer ship opens its
account on a vendor, is minted an inference key through the view only it
may peek, buys credit through the stub rail, spends it on a completion
and revokes the key. HOST like http://localhost:8080 with JAR its owner
cookie jar; with PEER and PJAR the customer is that other ship, with two
arguments it is HOST itself, which the vendor allows.

The stub provider must already be listening on 127.0.0.1:3399 with the
key "stub-key", fake-stripe.py on 127.0.0.1:3400 and fake-btcpay.py on
127.0.0.1:3401, both with the secret "whsec_gate" and HOST as their ship
url: this script starts none of them. Exits 1 on any failure. Safe to
rerun: it sweeps the account, the provider and the plans it made, both
before it starts and after it finishes."""
import json, subprocess, sys, time

HOST, JAR = sys.argv[1], sys.argv[2]
TWO = len(sys.argv) > 4
PEER = sys.argv[3] if TWO else HOST
PJAR = sys.argv[4] if TWO else JAR
PORT = '3399'
STUB = 'http://127.0.0.1:' + PORT
SPORT = '3400'
SSTUB = 'http://127.0.0.1:' + SPORT
BPORT = '3401'
BSTUB = 'http://127.0.0.1:' + BPORT
WHSEC = 'whsec_gate'
STRIPE_KEY = 'sk_test_gate'
BTC_KEY = 'btcpay-gate-1234'
BTC_STORE = 'gatestore'
PLAN = {'id': 'gate-pro', 'name': 'Gate Pro', 'kind': 'subscription',
        'price': 2500000, 'credit': 3000000, 'interval': 'month'}
PLAN_CREDIT = PLAN['credit']
SESSION_CREDIT = 2500000                       # the plan's price, paid once
MARKUP = 130
COST_IN, COST_OUT = 3000000, 15000000
IN, OUT = 3900000, 19500000
DEBIT = 137                                    # 10 in and 5 out at those prices
TOPUP = 1000000
fails = []
count = [0]


def curl(method, url, body=None, jar=None, bearer=None, timeout=180):
    cmd = ['curl', '-s', '-m', str(timeout), '-X', method, '-w', '\n%{http_code}', url]
    if jar:
        cmd += ['-b', jar]
    if bearer:
        cmd += ['-H', 'authorization: Bearer ' + bearer]
    if body is not None:
        cmd += ['-H', 'content-type: application/json', '-d', json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    try:
        data = json.loads(text) if text else None
    except json.JSONDecodeError:
        data = text
    return int(code or 0), data


def check(label, cond, detail=''):
    count[0] += 1
    print(('  ok   ' if cond else '  FAIL ') + label + ('' if cond else '   ' + str(detail)[:400]))
    if not cond:
        fails.append(label)


def dictish(d):
    return d if isinstance(d, dict) else {}


def err_of(d):
    return dictish(dictish(d).get('error')).get('message', '')


def api(host):
    return host + '/apps/armillary/api'


def v1(host):
    return host + '/apps/armillary/v1'


def instance(host):
    return (host + '/grubbery/ball/apps/shell.shell/desks/armillary.desk'
                   '/desk/data/armillary.armillary_app')


def raw(host, jar, path):
    """a grub's text straight out of the ball browser"""
    return subprocess.run(['curl', '-s', '-m', '30', '-b', jar, instance(host) + path + '?raw=1'],
                          capture_output=True, text=True).stdout


def ball(host, jar, path):
    return subprocess.run(['curl', '-s', '-m', '30', '-b', jar,
                           host + '/grubbery/ball' + path + '?raw=1'],
                          capture_output=True, text=True).stdout


def message(text):
    return [{'role': 'user', 'content': text}]


def settle(seconds=1.0):
    time.sleep(seconds)


def self_of(host, jar):
    """which ship this is, from its own account route"""
    code, d = curl('GET', api(host) + '/account', jar=jar)
    return dictish(d).get('self', '')


def fresh(host, jar, tries=4):
    """GET /api/account?fresh=1, which peeks the vendor first"""
    last = {}
    for _ in range(tries):
        code, d = curl('GET', api(host) + '/account?fresh=1', jar=jar, timeout=120)
        last = dictish(d)
        if last.get('ship'):
            return last
    return last


def wait_view(host, jar, ok, tries=6):
    """peek until the view satisfies ok, or give up and answer what it says"""
    last = {}
    for _ in range(tries):
        last = fresh(host, jar, tries=1)
        if ok(last):
            return last
        settle(2)
    return last


def ledger_of(host, jar, ship):
    code, d = curl('GET', api(host) + '/accounts/' + ship, jar=jar)
    return dictish(d).get('ledger', []) if code == 200 else []


VENDOR = self_of(HOST, JAR)
CUST = self_of(PEER, PJAR)
GROUP = 'armillary-' + CUST.lstrip('~')
print('vendor %s, customer %s' % (VENDOR or '?', CUST or '?'))
if not VENDOR or not CUST:
    print('FAILED: could not read the ships (is the cookie jar current?)')
    sys.exit(1)
if TWO and VENDOR == CUST:
    print('FAILED: HOST and PEER are the same ship')
    sys.exit(1)


def settings(host, jar, **over):
    """the whole settings document, with the fields this call changes"""
    doc = {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
           'mode': 'stub', 'refuse_comets': False, 'stripe_key': '',
           'stripe_webhook_secret': '', 'stripe_url': 'https://api.stripe.com',
           'btcpay_url': '', 'btcpay_store': '', 'btcpay_key': '',
           'btcpay_webhook_secret': '', 'lease_provider': '',
           'stripe_minutes': 1440, 'btcpay_minutes': 60}
    doc.update(over)
    return curl('PUT', api(host) + '/settings', doc, jar=jar)


def stub_post(url):
    """a plain POST to a rail stub, no cookie and no body"""
    return curl('POST', url)


def page(url):
    out = subprocess.run(['curl', '-s', '-m', '120', '-w', '\n%{http_code}', url],
                         capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    return int(code or 0), text


def refs_of(host, jar, ship):
    return [r.get('ref') for r in ledger_of(host, jar, ship)]


def broom():
    # the customer's own keys go first, while it still has a vendor to
    # tell; a key this ship holds outlives the account otherwise
    code, held = curl('GET', api(PEER) + '/keys', jar=PJAR)
    for k in (held if isinstance(held, list) else []):
        curl('DELETE', api(PEER) + '/keys/' + str(k.get('id', '')), jar=PJAR)
        settle(0.3)
    curl('DELETE', api(PEER) + '/lease', jar=PJAR)
    curl('PUT', api(PEER) + '/vendor', {'ship': ''}, jar=PJAR)
    curl('DELETE', api(HOST) + '/accounts/' + CUST, jar=JAR)
    curl('PUT', api(HOST) + '/catalog', [], jar=JAR)
    curl('DELETE', api(HOST) + '/providers/stub', jar=JAR)
    curl('DELETE', api(HOST) + '/plans/' + PLAN['id'], jar=JAR)
    # null clears a secret, blank would keep it
    settings(HOST, JAR, stripe_key=None, stripe_webhook_secret=None,
             btcpay_key=None, btcpay_webhook_secret=None, lease_provider='')
    settle()


broom()

print('the vendor has something to sell')
code, d = curl('PUT', api(HOST) + '/settings',
               {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
                'mode': 'stub', 'refuse_comets': False}, jar=JAR)
check('the vendor is in stub mode', code == 200, (code, d))
settle()
code, d = curl('POST', api(HOST) + '/providers',
               {'id': 'stub', 'name': 'Stub', 'kind': 'openrouter',
                'base_url': STUB + '/v1', 'api_key': 'stub-key'}, jar=JAR)
check('the stub provider is there', code in (200, 409), (code, d))
settle()
code, d = curl('POST', api(HOST) + '/providers/stub/import', jar=JAR)
check('the catalog imports', code == 200, (code, d))
settle()
code, cat = curl('GET', api(HOST) + '/catalog', jar=JAR)
cat = cat if isinstance(cat, list) else []
for row in cat:
    if row.get('id') == 'stub/alpha':
        row['enabled'] = True
code, d = curl('PUT', api(HOST) + '/catalog', cat, jar=JAR)
check('stub/alpha is on sale', code == 200, (code, d))
settle()

print('hello')
code, d = curl('PUT', api(PEER) + '/vendor', {'ship': VENDOR}, jar=PJAR)
check('the customer names its vendor', code == 200, (code, d))
view = wait_view(PEER, PJAR, lambda v: v.get('ship') == CUST)
check('the view arrives with the customer as its ship', view.get('ship') == CUST, view)
check('a fresh account is empty', view.get('balance') == 0 and view.get('keys') == [], view)
check('the view names the vendor', view.get('vendor') == VENDOR, view.get('vendor'))
ships = ball(HOST, JAR, '/sys/ames/usergroups/' + GROUP + '.grp/who.ships')
check('the vendor made a group holding only that ship', CUST in ships and ships.count('~') == 1,
      (GROUP, ships[:200]))

print('a key over the channel')
code, k = curl('POST', api(PEER) + '/keys', {'name': 'phone'}, jar=PJAR, timeout=120)
secret = dictish(k).get('secret', '')
check('a mint answers a secret within thirty seconds', code == 200 and '.' in secret, (code, k))
kid = dictish(k).get('id', '')
code, d = curl('GET', api(PEER) + '/keys', jar=PJAR)
rows = d if isinstance(d, list) else []
check('the customer lists the key without its secret',
      len(rows) == 1 and rows[0].get('id') == kid and 'secret' not in rows[0], (code, d))
acct = wait_owner = None
for _ in range(10):
    code, acct = curl('GET', api(HOST) + '/accounts/' + CUST, jar=JAR)
    if len(dictish(acct).get('pending', [])) == 0 and len(dictish(acct).get('keys', [])) == 1:
        break
    settle(2)
check('the vendor holds one key and nothing pending',
      len(dictish(acct).get('keys', [])) == 1 and dictish(acct).get('pending') == [],
      {'keys': dictish(acct).get('keys'), 'pending': dictish(acct).get('pending')})
code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
check('the inference config is proxy mode with that key',
      code == 200 and dictish(inf).get('mode') == 'proxy' and dictish(inf).get('key') == secret,
      (code, inf))
check('the inference config names the proxy and what it sells',
      str(dictish(inf).get('base_url', '')).endswith('/apps/armillary/v1')
      and 'stub/alpha' in dictish(inf).get('models', []), inf)

print('no credit, no answer')
code, d = curl('POST', v1(HOST) + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi')}, bearer=secret)
check('a completion with no credit is 402', code == 402 and 'balance' in err_of(d), (code, d))

print('the stub rail')
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': TOPUP},
                jar=PJAR, timeout=120)
url = dictish(co).get('url', '')
nonce = dictish(co).get('nonce', '')
check('a checkout answers a stub pay url', code == 200 and '/pay/stub' in url, (code, co))
pay = HOST + '/apps/armillary/pay/stub'
code, d = curl('GET', pay + '?ship=' + CUST + '&nonce=' + nonce)
check('the pay page answers without a cookie', code == 200 and 'Pay' in str(d), (code, str(d)[:200]))
code, d = curl('POST', pay, {'ship': CUST, 'nonce': nonce})
check('paying answers paid', code == 200 and str(d).strip() == 'paid', (code, d))
settle(2)
code, d = curl('POST', pay, {'ship': CUST, 'nonce': nonce})
check('paying twice answers paid again', code == 200 and str(d).strip() == 'paid', (code, d))
settle(2)
credits = [r for r in ledger_of(HOST, JAR, CUST) if r.get('kind') == 'credit']
check('the ledger holds exactly one credit',
      len(credits) == 1 and credits[0].get('amount') == TOPUP
      and credits[0].get('ref') == 'stub-' + nonce, credits)
code, d = curl('POST', pay, {'ship': CUST, 'nonce': 'not-a-nonce'})
check('an unknown nonce is 404', code == 404, (code, d))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == TOPUP)
check('the customer sees the dollar', view.get('balance') == TOPUP, view.get('balance'))

print('spending it')
code, d = curl('POST', v1(HOST) + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hello there world')}, bearer=secret)
content = ''
if isinstance(d, dict) and d.get('choices'):
    content = dictish(dictish(d['choices'][0]).get('message')).get('content', '')
check('the completion answers with the stub text',
      code == 200 and content == 'ok: hello there world', (code, d))
settle(2)
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == TOPUP - DEBIT)
check('the view shows the charge', view.get('balance') == TOPUP - DEBIT,
      (TOPUP - DEBIT, view.get('balance')))

print('revoking it')
code, d = curl('DELETE', api(PEER) + '/keys/' + kid, jar=PJAR)
check('the customer revokes its key', code == 200, (code, d))
gone = 0
for _ in range(20):
    gone, _d = curl('POST', v1(HOST) + '/chat/completions',
                    {'model': 'stub/alpha', 'messages': message('hi')}, bearer=secret)
    if gone == 403:
        break
    settle(2)
check('the revoked key is refused', gone == 403, gone)
code, d = curl('GET', api(PEER) + '/keys', jar=PJAR)
check('the customer forgot it too', d == [], d)

print('the rings')
inbox = raw(HOST, JAR, '/tr/inbox')
try:
    rows = json.loads(inbox)
except ValueError:
    rows = []
ops = set(r.get('op') for r in rows if isinstance(r, dict))
check('the ship traffic ring answers', isinstance(rows, list) and len(rows) > 0, inbox[:200])
for op in ('hello', 'mint-key', 'got-key', 'checkout', 'drop-key'):
    check('the ship traffic ring holds ' + op, op in ops, sorted(ops))
bare = secret.split('.', 1)[1] if '.' in secret else 'nothing-like-a-secret'
check('the ship traffic ring never carries a secret', bare not in inbox, inbox[:200])
log = raw(HOST, JAR, '/tr/log')
check('the audit ring never carries a secret',
      bare not in log and 'stub-key' not in log, log[:200])

print('the card rail')
# whatever the stub rail and the completion left behind is the floor the
# card rail adds to
BASE = dictish(fresh(PEER, PJAR)).get('balance', 0)
CARD = 10000000
code, d = settings(HOST, JAR, stripe_key=STRIPE_KEY, stripe_webhook_secret=WHSEC,
                   stripe_url=SSTUB, public_url=HOST, mode='live')
check('the vendor goes live against the Stripe stub', code == 200, (code, d))
settle(2)

code, d = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': 1000000},
               jar=PJAR, timeout=180)
check('a top-up below the minimum is 502 with the reason',
      code == 502 and 'minimum' in err_of(d), (code, d))
view = wait_view(PEER, PJAR, lambda v: any(
    r.get('status') == 'refused' for r in dictish(v.get('checkouts')).values()))
refused = [r for r in dictish(view.get('checkouts')).values() if r.get('status') == 'refused']
check('the refusal shows in the view with its note',
      len(refused) >= 1 and 'minimum' in str(refused[0].get('note')), refused[:1])

code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': CARD},
                jar=PJAR, timeout=180)
url = dictish(co).get('url', '')
nonce = dictish(co).get('nonce', '')
check('a top-up checkout answers a Stripe session url',
      code == 200 and url.startswith(SSTUB + '/stub/pay/'), (code, co))
SID = url.rsplit('/', 1)[-1]
code, d = stub_post(url)
check('paying the session answers the record',
      code == 200 and dictish(d).get('payment_status') == 'paid', (code, str(d)[:200]))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == BASE + CARD, tries=15)
check('the credit lands within thirty seconds', view.get('balance') == BASE + CARD,
      (BASE + CARD, view.get('balance')))
row = dictish(view.get('checkouts')).get(nonce, {})
check('the checkout row is paid and holds the session id',
      row.get('status') == 'paid' and row.get('sid') == SID, row)

code, d = stub_post(url)
check('paying twice answers paid again', code == 200, (code, str(d)[:120]))
settle(6)
credits = [r for r in ledger_of(HOST, JAR, CUST) if r.get('ref') == SID]
check('a replayed event credits once', len(credits) == 1, credits)

code, text = page(HOST + '/apps/armillary/pay/return?ship=' + CUST + '&sid=' + SID)
check('the return page for a paid session says it was received',
      code == 200 and 'received' in text.lower(), (code, text[:200]))

code, acct = curl('GET', api(HOST) + '/accounts/' + CUST, jar=JAR)
CUSTOMER = dictish(dictish(acct).get('account')).get('stripe_customer', '')
check('the ship has one Stripe customer on its account row',
      CUSTOMER.startswith('cus_'), dictish(acct).get('account'))
code, st = curl('GET', SSTUB + '/stub/state')
srec = dictish(dictish(st).get('sessions', {})).get(SID, {})
check('and the session was opened on it', srec.get('customer') == CUSTOMER, srec)

print('a late settlement that fails')
BALF = dictish(fresh(PEER, PJAR)).get('balance', 0)
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': 6000000},
                jar=PJAR, timeout=180)
furl = dictish(co).get('url', '')
fnonce = dictish(co).get('nonce', '')
check('a second top-up checkout opens', code == 200 and '/stub/pay/' in furl, (code, co))
code, d = stub_post(SSTUB + '/stub/fail/' + furl.rsplit('/', 1)[-1])
check('the stub reports the payment failed', code == 200, (code, str(d)[:120]))
view = wait_view(PEER, PJAR, lambda v: dictish(
    dictish(v.get('checkouts')).get(fnonce)).get('status') == 'failed', tries=15)
check('the checkout row says failed',
      dictish(dictish(view.get('checkouts')).get(fnonce)).get('status') == 'failed',
      dictish(view.get('checkouts')).get(fnonce))
check('and nothing was credited', view.get('balance') == BALF, (BALF, view.get('balance')))

print('a subscription')
code, d = curl('POST', api(HOST) + '/plans', PLAN, jar=JAR)
check('the vendor writes a subscription plan', code in (200, 409), (code, d))
settle()
code, d = curl('POST', api(HOST) + '/plans/' + PLAN['id'] + '/stripe', {}, jar=JAR)
check('the plan gets a Stripe price',
      code == 200 and str(dictish(d).get('stripe_price', '')).startswith('price_'), (code, d))
settle(2)
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'plan': PLAN['id']},
                jar=PJAR, timeout=180)
suburl = dictish(co).get('url', '')
check('a subscription checkout answers a session url',
      code == 200 and suburl.startswith(SSTUB + '/stub/pay/'), (code, co))
code, d = stub_post(suburl)
check('paying the subscription answers the record', code == 200, (code, str(d)[:120]))
want = BASE + CARD + SESSION_CREDIT + PLAN_CREDIT
view = wait_view(PEER, PJAR, lambda v: dictish(v.get('subscription')).get('active'), tries=15)
check('the view shows the subscription active',
      dictish(view.get('subscription')).get('active') is True, view.get('subscription'))
check('the view never carries the Stripe ids',
      'id' not in dictish(view.get('subscription')), view.get('subscription'))
check('the view names the plan', view.get('plan') == PLAN['id'], view.get('plan'))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == want, tries=15)
check('the session and the first invoice both credited',
      view.get('balance') == want, (want, view.get('balance')))
code, acct = curl('GET', api(HOST) + '/accounts/' + CUST, jar=JAR)
SUB = dictish(dictish(acct).get('subscription')).get('id', '')
check('the owner sees the Stripe subscription id', SUB.startswith('sub_'), dictish(acct).get('subscription'))
check('and the ship still has the one customer it started with',
      dictish(dictish(acct).get('account')).get('stripe_customer') == CUSTOMER,
      dictish(acct).get('account'))
code, st = curl('GET', SSTUB + '/stub/state')
srec = dictish(dictish(st).get('sessions', {})).get(suburl.rsplit('/', 1)[-1], {})
check('the subscription session carried the same customer',
      srec.get('customer') == CUSTOMER, srec)

before = set(refs_of(HOST, JAR, CUST))
code, d = stub_post(SSTUB + '/stub/renew/' + SUB)
check('the stub renews the subscription', code == 200, (code, d))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == want + PLAN_CREDIT, tries=15)
check('a renewal credits the plan again', view.get('balance') == want + PLAN_CREDIT,
      (want + PLAN_CREDIT, view.get('balance')))
fresh_refs = set(refs_of(HOST, JAR, CUST)) - before
check('the renewal carries a new ref', len(fresh_refs) == 1, sorted(fresh_refs))

code, d = curl('POST', api(PEER) + '/cancel-subscription', {}, jar=PJAR, timeout=120)
check('the customer asks to cancel', code == 202, (code, d))
cancelled = False
for _ in range(15):
    settle(2)
    code, st = curl('GET', SSTUB + '/stub/state')
    cancelled = dictish(dictish(st).get('subscriptions', {}).get(SUB, {})).get('cancel_at_period_end')
    if cancelled:
        break
check('Stripe was told to cancel at period end', cancelled is True, cancelled)
code, d = stub_post(SSTUB + '/stub/delete/' + SUB)
check('the stub reports the subscription deleted', code == 200, (code, d))
view = wait_view(PEER, PJAR, lambda v: not dictish(v.get('subscription')).get('active'), tries=15)
check('the subscription clears on the account',
      dictish(view.get('subscription')).get('active') is False and view.get('plan') == '',
      (view.get('subscription'), view.get('plan')))

print('the bitcoin rail')
# whatever the card rail left behind is the floor the bitcoin rail adds to
BASE2 = dictish(fresh(PEER, PJAR)).get('balance', 0)
BTC = 7000000
code, d = settings(HOST, JAR, stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB,
                   public_url=HOST, mode='live', btcpay_url=BSTUB, btcpay_store=BTC_STORE,
                   btcpay_key=BTC_KEY, btcpay_webhook_secret=WHSEC)
check('the vendor goes live against the BTCPay stub', code == 200, (code, d))
settle(2)

code, d = curl('POST', api(PEER) + '/checkout', {'rail': 'btcpay', 'plan': PLAN['id']},
               jar=PJAR, timeout=180)
check('a subscription on the bitcoin rail is 502 with the reason',
      code == 502 and 'card only' in err_of(d), (code, d))
view = wait_view(PEER, PJAR, lambda v: any(
    r.get('rail') == 'btcpay' and r.get('status') == 'refused'
    for r in dictish(v.get('checkouts')).values()))
refused = [r for r in dictish(view.get('checkouts')).values()
           if r.get('rail') == 'btcpay' and r.get('status') == 'refused']
check('the bitcoin refusal shows in the view with its note',
      len(refused) >= 1 and 'card only' in str(refused[0].get('note')), refused[:1])

code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'btcpay', 'amount': BTC},
                jar=PJAR, timeout=180)
burl = dictish(co).get('url', '')
bnonce = dictish(co).get('nonce', '')
check('a bitcoin top-up answers a BTCPay checkout url',
      code == 200 and burl.startswith(BSTUB + '/stub/pay/'), (code, co))
INV = burl.rsplit('/', 1)[-1]

before = len(ledger_of(HOST, JAR, CUST))
code, d = stub_post(BSTUB + '/stub/processing/' + INV)
check('the stub marks the invoice processing', code == 200, (code, str(d)[:120]))
view = wait_view(PEER, PJAR, lambda v: dictish(
    dictish(v.get('checkouts')).get(bnonce)).get('status') == 'processing', tries=15)
check('the row shows processing',
      dictish(dictish(view.get('checkouts')).get(bnonce)).get('status') == 'processing',
      dictish(view.get('checkouts')).get(bnonce))
check('and a payment seen on chain credits nothing yet',
      len(ledger_of(HOST, JAR, CUST)) == before, before)

code, d = stub_post(BSTUB + '/stub/pay/' + INV)
check('the stub settles the invoice', code == 200, (code, str(d)[:120]))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == BASE2 + BTC, tries=15)
check('the bitcoin credit lands within thirty seconds',
      view.get('balance') == BASE2 + BTC, (BASE2 + BTC, view.get('balance')))
row = dictish(dictish(view.get('checkouts')).get(bnonce))
check('the checkout row is paid and holds the invoice id',
      row.get('status') == 'paid' and row.get('sid') == INV, row)

code, d = stub_post(BSTUB + '/stub/pay/' + INV)
check('settling twice answers the record again', code == 200, (code, str(d)[:120]))
settle(6)
credits = [r for r in ledger_of(HOST, JAR, CUST) if r.get('ref') == INV]
check('a replayed invoice credits once', len(credits) == 1, credits)

code, text = page(HOST + '/apps/armillary/pay/return?ship=' + CUST +
                  '&nonce=' + bnonce + '&rail=btcpay')
check('the bitcoin return page for a settled invoice says it was received',
      code == 200 and 'received' in text.lower(), (code, text[:200]))

code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'btcpay', 'amount': BTC},
                jar=PJAR, timeout=180)
eurl = dictish(co).get('url', '')
enonce = dictish(co).get('nonce', '')
check('a second bitcoin top-up answers its own url',
      code == 200 and eurl.startswith(BSTUB + '/stub/pay/'), (code, co))
code, d = stub_post(BSTUB + '/stub/expire/' + eurl.rsplit('/', 1)[-1])
check('the stub expires the invoice', code == 200, (code, str(d)[:120]))
view = wait_view(PEER, PJAR, lambda v: dictish(
    dictish(v.get('checkouts')).get(enonce)).get('status') == 'expired', tries=15)
check('the expired row says so',
      dictish(dictish(view.get('checkouts')).get(enonce)).get('status') == 'expired',
      dictish(view.get('checkouts')).get(enonce))

settings(HOST, JAR, stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB)
settle()

print('leases')


def tick():
    """prod the vendor's housekeeping and give it room to run"""
    curl('POST', api(HOST) + '/tick', {}, jar=JAR, timeout=120)
    settle(4)


def lease_row():
    code, acct = curl('GET', api(HOST) + '/accounts/' + CUST, jar=JAR)
    return dictish(dictish(acct).get('lease')), acct


def stub_key(h):
    code, d = curl('GET', STUB + '/api/v1/keys/' + h, bearer='prov-key')
    return code, dictish(dictish(d).get('data'))


code, d = curl('PUT', api(HOST) + '/providers/stub',
               {'name': 'Stub', 'kind': 'openrouter', 'base_url': STUB + '/v1',
                'api_key': '', 'provisioning_key': 'prov-key'}, jar=JAR)
check('the stub provider carries a provisioning key', code == 200, (code, d))
settle()
code, co = curl('POST', api(PEER) + '/lease', {}, jar=PJAR, timeout=120)
check('a lease with no lease provider is 404',
      code == 404 and 'no lease' in err_of(co), (code, co))
code, d = settings(HOST, JAR, lease_provider='stub')
check('the vendor names its lease provider', code == 200, (code, d))
settle(2)

# the proxy is what a disabled lease falls back to, so this ship needs a
# key again: the revoke earlier left it with none
code, k = curl('POST', api(PEER) + '/keys', {'name': 'lease-gate'}, jar=PJAR, timeout=120)
PSECRET = dictish(k).get('secret', '')
check('the customer holds an inference key again', code == 200 and '.' in PSECRET, (code, k))

BASE3 = dictish(fresh(PEER, PJAR)).get('balance', 0)
code, lease = curl('POST', api(PEER) + '/lease', {}, jar=PJAR, timeout=120)
LKEY = dictish(lease).get('key', '')
check('a lease answers a provider key',
      code == 200 and LKEY.startswith('sk-or-stub-'), (code, lease))
check('the lease names the provider base url and what it sells',
      dictish(lease).get('base_url') == STUB + '/v1'
      and 'stub/alpha' in dictish(lease).get('models', []), lease)
LHASH = dictish(lease).get('hash', '')
code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
check('the inference config is lease mode with that key',
      code == 200 and dictish(inf).get('mode') == 'lease'
      and dictish(inf).get('key') == LKEY, (code, inf))
check('and points at the provider, not the proxy',
      dictish(inf).get('base_url') == STUB + '/v1', inf)

code, d = curl('POST', STUB + '/v1/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi')}, bearer=LKEY)
check('a completion straight at the provider with the leased key is 200',
      code == 200, (code, str(d)[:200]))

row, acct = lease_row()
check('the owner sees the lease hash', row.get('hash') == LHASH, row)
check('the owner never sees the key',
      'key' not in row and LKEY not in json.dumps(acct), row)

code, d = curl('POST', STUB + '/stub/spend/' + LHASH, {'usd': 0.10})
check('the stub records ten cents of spend', code == 200, (code, str(d)[:120]))
tick()
code, rec = stub_key(LHASH)
SPENT = int(round(float(rec.get('usage', 0)) * 1000000))
WANT = (SPENT * MARKUP + 99) // 100
view = wait_view(PEER, PJAR, lambda v: dictish(v.get('lease')).get('usage') == SPENT, tries=10)
lv = dictish(view.get('lease'))
check('the lease view carries what the key has spent', lv.get('usage') == SPENT, (SPENT, lv))
debits = [r for r in ledger_of(HOST, JAR, CUST) if r.get('mode') == 'lease']
check('one lease debit at the markup was written',
      len(debits) == 1 and debits[0].get('amount') == WANT
      and debits[0].get('model') == 'openrouter', (WANT, debits))
check('and its cost is what the provider charged us',
      debits and debits[0].get('cost') == SPENT, debits[:1])
BAL3 = view.get('balance', 0)
check('the balance fell by the debit', BAL3 == BASE3 - WANT, (BASE3 - WANT, BAL3))
check('the cap tracks what the balance still buys',
      lv.get('limit') == SPENT + (BAL3 * 100) // MARKUP,
      (SPENT + (BAL3 * 100) // MARKUP, lv.get('limit')))

print('a lease that runs out')
over = (BAL3 * 100) // MARKUP + 1000000
code, d = curl('POST', STUB + '/stub/spend/' + LHASH, {'usd': over / 1000000.0})
check('the stub records spending past the balance', code == 200, (code, str(d)[:120]))
tick()
view = wait_view(PEER, PJAR, lambda v: dictish(v.get('lease')).get('disabled') is True, tries=10)
check('the view says the lease is disabled',
      dictish(view.get('lease')).get('disabled') is True, view.get('lease'))
code, rec = stub_key(LHASH)
check('and the provider was told so', rec.get('disabled') is True, rec)
code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
check('the inference config falls back to the proxy',
      code == 200 and dictish(inf).get('mode') == 'proxy', (code, inf))
code, d = curl('POST', STUB + '/v1/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi')}, bearer=LKEY)
check('the provider refuses the leased key', code == 401, (code, str(d)[:120]))

print('a credit brings it back')
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': 10000000},
                jar=PJAR, timeout=120)
url = dictish(co).get('url', '')
nonce = dictish(co).get('nonce', '')
check('a top-up checkout answers a stub pay url', code == 200 and '/pay/stub' in url, (code, co))
code, d = curl('POST', HOST + '/apps/armillary/pay/stub', {'ship': CUST, 'nonce': nonce})
check('paying it answers paid', code == 200 and str(d).strip() == 'paid', (code, d))
settle(2)
tick()
view = wait_view(PEER, PJAR, lambda v: dictish(v.get('lease')).get('disabled') is False, tries=10)
lv = dictish(view.get('lease'))
check('the lease is enabled again', lv.get('disabled') is False, lv)
check('with a cap above what it has already spent',
      lv.get('limit', 0) > lv.get('usage', 0), lv)
code, rec = stub_key(LHASH)
check('and the provider has the higher cap',
      int(round(float(rec.get('limit', 0)) * 1000000)) == lv.get('limit'),
      (lv.get('limit'), rec.get('limit')))
code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
check('the inference config is lease mode again',
      dictish(inf).get('mode') == 'lease', inf)

print('a disputed payment')
code, d = settings(HOST, JAR, stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB,
                   public_url=HOST, mode='live', lease_provider='stub')
check('the vendor goes live again for the dispute', code == 200, (code, d))
settle(2)
BEFORE_D = dictish(fresh(PEER, PJAR)).get('balance', 0)
code, dp = stub_post(SSTUB + '/stub/dispute/' + SID)
DP = dictish(dp).get('id', '')
check('the stub opens a dispute on the first top-up',
      code == 200 and DP.startswith('dp_'), (code, dp))
view = wait_view(PEER, PJAR, lambda v: v.get('balance') == BEFORE_D - CARD, tries=15)
check('the disputed credit comes back off the balance',
      view.get('balance') == BEFORE_D - CARD, (BEFORE_D - CARD, view.get('balance')))
check('and the balance is below zero, which is the point',
      view.get('balance', 0) < 0, view.get('balance'))
refunds = [r for r in ledger_of(HOST, JAR, CUST) if r.get('ref') == 'dispute-' + DP]
check('a refund row names the dispute and the rail',
      len(refunds) == 1 and refunds[0].get('rail') == 'stripe'
      and refunds[0].get('amount') == CARD, refunds)
code, d = stub_post(SSTUB + '/stub/dispute/' + SID)
check('a second delivery is the same dispute', dictish(d).get('id') == DP, d)
settle(8)
again = [r for r in ledger_of(HOST, JAR, CUST) if r.get('ref') == 'dispute-' + DP]
check('and it changes nothing',
      len(again) == 1 and dictish(fresh(PEER, PJAR)).get('balance') == BEFORE_D - CARD,
      (len(again), dictish(fresh(PEER, PJAR)).get('balance')))
tick()
view = wait_view(PEER, PJAR, lambda v: dictish(v.get('lease')).get('disabled') is True, tries=10)
check('the lease reads disabled after the tick',
      dictish(view.get('lease')).get('disabled') is True, view.get('lease'))
code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
check('and the inference config says proxy', dictish(inf).get('mode') == 'proxy', inf)
code, d = curl('POST', v1(HOST) + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi')}, bearer=PSECRET, timeout=120)
check('a completion is 402 while the balance is under water',
      code == 402 and 'balance' in err_of(d), (code, str(d)[:200]))
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': 20000000},
                jar=PJAR, timeout=180)
purl = dictish(co).get('url', '')
check('a top-up checkout opens on the card rail',
      code == 200 and '/stub/pay/' in purl, (code, co))
code, d = stub_post(purl)
check('paying it answers the record', code == 200, (code, str(d)[:120]))
view = wait_view(PEER, PJAR, lambda v: v.get('balance', 0) > 0, tries=15)
check('the top-up puts the balance back above zero',
      view.get('balance', 0) > 0, view.get('balance'))
code, d = curl('POST', v1(HOST) + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi')}, bearer=PSECRET, timeout=120)
check('and a completion is 200 again', code == 200, (code, str(d)[:200]))
settings(HOST, JAR, stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB,
         lease_provider='stub')
settle(2)

print('giving the lease back')
code, d = curl('DELETE', api(PEER) + '/lease', jar=PJAR, timeout=120)
check('the customer drops its lease', code == 200, (code, d))
gone = 0
for _ in range(20):
    gone, rec = stub_key(LHASH)
    if gone == 404:
        break
    settle(2)
check('the provider no longer holds the key', gone == 404, gone)
row, acct = lease_row()
check('the owner sees no lease', row == {}, row)
inf = {}
for _ in range(10):
    code, inf = curl('GET', api(PEER) + '/inference', jar=PJAR, timeout=120)
    if dictish(inf).get('mode') != 'lease':
        break
    settle(2)
check('the inference config is back to the proxy',
      code == 200 and dictish(inf).get('mode') == 'proxy', (code, inf))

print('the report')
code, rep = curl('GET', api(HOST) + '/report?days=30', jar=JAR)
r = dictish(rep)
c = dictish(r.get('credits'))
check('the report answers 200', code == 200, (code, rep))
check('it counts the ship that moved money', r.get('accounts', 0) >= 1, r.get('accounts'))
check('it shows what the lease spent', r.get('lease_spend', 0) >= WANT, (WANT, r.get('lease_spend')))
check('it counts the proxy request', r.get('requests', 0) >= 1, r.get('requests'))
check('it splits the credits by rail',
      c.get('stub', 0) > 0 and c.get('stripe', 0) > 0 and c.get('btcpay', 0) > 0, c)
models = [t.get('model') for t in (r.get('top_models') or [])]
check('and names the models that were charged for',
      'stub/alpha' in models and 'openrouter' in models, models)
check('the margin is charged less cost',
      int(r.get('margin', 0)) == int(r.get('charged', 0)) - int(r.get('cost', 0)),
      (r.get('margin'), r.get('charged'), r.get('cost')))

print('a checkout that runs out of time')
code, d = settings(HOST, JAR, lease_provider='stub', stripe_minutes=0)
check('the vendor gives a card checkout no time at all', code == 200, (code, d))
settle(2)
code, co = curl('POST', api(PEER) + '/checkout', {'rail': 'stripe', 'amount': 6000000},
                jar=PJAR, timeout=120)
enonce = dictish(co).get('nonce', '')
check('the checkout still opens', code == 200 and enonce, (code, co))
settle(2)
tick()
view = wait_view(PEER, PJAR, lambda v: dictish(
    dictish(v.get('checkouts')).get(enonce)).get('status') == 'expired', tries=10)
check('the tick expires it',
      dictish(dictish(view.get('checkouts')).get(enonce)).get('status') == 'expired',
      dictish(view.get('checkouts')).get(enonce))

print('compaction leaves fresh rows alone')
before = len(ledger_of(HOST, JAR, CUST))
tick()
settle(2)
check('a ledger with nothing older than ninety days is untouched',
      len(ledger_of(HOST, JAR, CUST)) == before, (before, len(ledger_of(HOST, JAR, CUST))))

settings(HOST, JAR, stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB)
settle()
code, d = curl('GET', api(HOST) + '/settings', jar=JAR)
check('the vendor is back in stub mode', dictish(d).get('mode') == 'stub', d)
check('and offers no leases', dictish(d).get('lease_provider') == '', d)
log = raw(HOST, JAR, '/tr/log')
inbox = raw(HOST, JAR, '/tr/inbox')
check('neither ring ever carried the leased key',
      LKEY not in log and LKEY not in inbox, LKEY)
log = raw(HOST, JAR, '/tr/log')
check('the audit ring holds both rails and no secret',
      'stripe.' in log and 'btcpay.' in log and STRIPE_KEY not in log
      and WHSEC not in log and BTC_KEY not in log, log[:200])

broom()
print()
if fails:
    print('FAILED: ' + ', '.join(fails))
    sys.exit(1)
print('ALL OK (%d checks)' % count[0])
