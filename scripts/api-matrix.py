#!/usr/bin/env python3
"""api-matrix.py HOST JAR PROVIDER_PORT [STRIPE_PORT] [BTCPAY_PORT]
The HTTP gate for armillary: spec sections 4, 5, 7 and 8 against three
stubs. HOST like http://localhost:8080; JAR a curl cookie jar from
POST /~/login; PROVIDER_PORT the port fake-provider.py listens on with
the key "stub-key"; STRIPE_PORT the port fake-stripe.py listens on with
the secret "whsec_gate" and this HOST as its ship url, 3400 by default;
BTCPAY_PORT the port fake-btcpay.py listens on with the same secret and
the same ship url, 3401 by default. It starts nothing: the runner
starts all three stubs first. Exits 1 on any failure. Safe to rerun: it
deletes the account, the provider and the plans it made, both before it
starts and after it finishes."""
import hashlib, hmac, json, subprocess, sys, time

HOST, JAR, PORT = sys.argv[1], sys.argv[2], sys.argv[3]
SPORT = sys.argv[4] if len(sys.argv) > 4 else '3400'
BPORT = sys.argv[5] if len(sys.argv) > 5 else '3401'
SSTUB = 'http://127.0.0.1:' + SPORT
BSTUB = 'http://127.0.0.1:' + BPORT
WHSEC = 'whsec_gate'
STRIPE_KEY = 'sk_test_gate'
BTC_KEY = 'btcpay-gate-1234'
BTC_STORE = 'gatestore'
HOOK = HOST + '/apps/armillary/hooks/stripe'
BHOOK = HOST + '/apps/armillary/hooks/btcpay'
RETURN = HOST + '/apps/armillary/pay/return'
API = HOST + '/apps/armillary/api'
V1 = HOST + '/apps/armillary/v1'
STUB = 'http://127.0.0.1:' + PORT
INSTANCE = HOST + '/grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app'
SHIP = '~feb'
MARKUP = 130
COST_IN, COST_OUT = 3000000, 15000000          # stub/alpha, dollars per token as a string
IN, OUT = 3900000, 19500000                    # the same times the markup
fails = []
count = [0]


def curl(method, url, body=None, jar=JAR, bearer=None, timeout=180):
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


def settle(seconds=1.0):
    """a write answers before the writer applies, so a read waits"""
    time.sleep(seconds)


def self_of():
    """which ship this is, from its own account route"""
    code, d = curl('GET', API + '/account')
    return dictish(d).get('self', '')


def message(text):
    return [{'role': 'user', 'content': text}]


def dictish(d):
    return d if isinstance(d, dict) else {}


def err_of(d):
    return dictish(dictish(d).get('error')).get('message', '')


def ledger():
    code, d = curl('GET', API + '/accounts/' + SHIP)
    return dictish(d).get('ledger', []) if code == 200 else []


def settings(**over):
    """the whole settings document, with the fields this call changes"""
    doc = {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
           'mode': 'stub', 'refuse_comets': False, 'stripe_key': '',
           'stripe_webhook_secret': '', 'stripe_url': 'https://api.stripe.com',
           'btcpay_url': '', 'btcpay_store': '', 'btcpay_key': '',
           'btcpay_webhook_secret': '', 'lease_provider': '',
           'stripe_minutes': 1440, 'btcpay_minutes': 60}
    doc.update(over)
    return curl('PUT', API + '/settings', doc)


def signed(payload, skew=0):
    """a stripe-signature header over the raw body, as Stripe makes one"""
    when = int(time.time()) + skew
    mac = hmac.new(WHSEC.encode(), ('%d.%s' % (when, payload)).encode(), hashlib.sha256)
    return 't=%d,v1=%s' % (when, mac.hexdigest())


def hook(event_type, oid, sig=None):
    """post a webhook the way the stub does, signed unless told otherwise"""
    payload = json.dumps({'type': event_type, 'data': {'object': {'id': oid}}})
    cmd = ['curl', '-s', '-m', '180', '-X', 'POST', '-w', '\n%{http_code}',
           '-H', 'content-type: application/json',
           '-H', 'stripe-signature: ' + (signed(payload) if sig is None else sig),
           '-d', payload, HOOK]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    try:
        data = json.loads(text) if text else None
    except json.JSONDecodeError:
        data = text
    return int(code or 0), data


def btc_signed(payload):
    """a BTCPay-Sig header over the raw body, as a store webhook makes one"""
    mac = hmac.new(WHSEC.encode(), payload.encode(), hashlib.sha256)
    return 'sha256=' + mac.hexdigest()


def btc_hook(event_type, iid, sig=None):
    """post a BTCPay webhook the way the stub does, signed unless told otherwise"""
    payload = json.dumps({'type': event_type, 'invoiceId': iid, 'storeId': BTC_STORE})
    cmd = ['curl', '-s', '-m', '180', '-X', 'POST', '-w', '\n%{http_code}',
           '-H', 'content-type: application/json',
           '-H', 'BTCPay-Sig: ' + (btc_signed(payload) if sig is None else sig),
           '-d', payload, BHOOK]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    try:
        data = json.loads(text) if text else None
    except json.JSONDecodeError:
        data = text
    return int(code or 0), data


def page(url):
    out = subprocess.run(['curl', '-s', '-m', '60', '-w', '\n%{http_code}', url],
                         capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    return int(code or 0), text


def broom():
    for pid in ('pro', 'ten'):
        curl('DELETE', API + '/plans/' + pid)
    curl('PUT', API + '/vendor', {'ship': ''})
    curl('DELETE', API + '/accounts/' + SELF)
    curl('DELETE', API + '/accounts/' + SHIP)
    curl('DELETE', API + '/providers/stub')
    # null clears a secret, blank would keep it: the ship is left with
    # no rail secrets at all and back in stub mode
    settings(stripe_key=None, stripe_webhook_secret=None,
             btcpay_key=None, btcpay_webhook_secret=None, lease_provider='')
    # the catalog outlives a dropped provider on purpose, so the gate
    # clears it by hand or a rerun imports nothing
    curl('PUT', API + '/catalog', [])
    settle()


SELF = self_of()
if not SELF:
    print('FAILED: could not read the ship (is the cookie jar current?)')
    sys.exit(1)

broom()

print('the report')
code, rep = curl('GET', API + '/report')
r = dictish(rep)
c = dictish(r.get('credits'))
check('GET /api/report answers 200', code == 200, (code, rep))
check('the window defaults to thirty days', r.get('days') == 30, r.get('days'))
check('the report names every rail', sorted(c.keys()) == ['btcpay', 'other', 'owner', 'stripe', 'stub'],
      sorted(c.keys()))
for field in ('charged', 'cost', 'margin', 'refunds', 'requests', 'tokens_in',
              'tokens_out', 'lease_spend', 'accounts'):
    check('the report carries ' + field, field in r, sorted(r.keys()))
check('an empty ship reports zeros',
      r.get('charged') == 0 and r.get('cost') == 0 and r.get('requests') == 0
      and r.get('accounts') == 0 and r.get('top_models') == [], r)
code, rep = curl('GET', API + '/report?days=7')
check('the window follows days=7', dictish(rep).get('days') == 7, dictish(rep).get('days'))
code, rep = curl('GET', API + '/report?days=nonsense')
check('an unreadable window falls back to thirty', dictish(rep).get('days') == 30, dictish(rep).get('days'))

print('settings')
code, d = curl('GET', API + '/settings')
check('GET /api/settings answers the starter document', code == 200 and dictish(d).get('markup_pct') == MARKUP, (code, d))
code, d = curl('PUT', API + '/settings', {'markup_pct': MARKUP, 'min_topup': 5000000,
                                          'public_url': 'https://example.com', 'mode': 'stub',
                                          'refuse_comets': False})
check('PUT /api/settings answers 200', code == 200, (code, d))
settle()
code, d = curl('GET', API + '/settings')
check('settings round-trip', dictish(d).get('public_url') == 'https://example.com', d)
curl('PUT', API + '/settings', {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
                                'mode': 'stub', 'refuse_comets': False})
settle()

print('providers')
prov = {'id': 'stub', 'name': 'Stub', 'kind': 'openrouter',
        'base_url': STUB + '/v1', 'api_key': 'stub-key', 'provisioning_key': 'prov-key'}
code, d = curl('POST', API + '/providers', prov)
check('POST /api/providers adds a row', code == 200, (code, d))
settle()
code, d = curl('POST', API + '/providers', prov)
check('a duplicate id is 409', code == 409, (code, d))
code, d = curl('PUT', API + '/providers/nope', {'name': 'x', 'kind': 'openrouter', 'base_url': STUB + '/v1'})
check('an unknown id on PUT is 409', code == 409, (code, d))
code, d = curl('GET', API + '/providers')
check('GET /api/providers answers a list', code == 200 and isinstance(d, list) and len(d) >= 1, (code, d))
check('the masked read never carries the key', 'stub-key' not in json.dumps(d) and 'prov-key' not in json.dumps(d), d)
code, d = curl('PUT', API + '/providers/stub', {'name': 'Stub two', 'kind': 'openrouter',
                                                'base_url': STUB + '/v1', 'api_key': '',
                                                'provisioning_key': ''})
check('an edit with a blank key answers 200', code == 200, (code, d))
settle()
# nothing is in the catalog yet, so the test call names its own model;
# it answering at all proves the blank edit kept the stored key
code, d = curl('POST', API + '/providers/stub/test', {'model': 'stub/alpha'})
check('the provider still answers after a blank-key edit', code == 200 and dictish(d).get('status') == 200, (code, d))

print('import')
code, d = curl('POST', API + '/providers/stub/import')
check('the first import adds 3', code == 200 and dictish(d).get('added') == 3, (code, d))
settle()
code, d = curl('POST', API + '/providers/stub/import')
check('a second import adds 0', code == 200 and dictish(d).get('added') == 0, (code, d))
settle()

print('catalog')
code, cat = curl('GET', API + '/catalog')
check('GET /api/catalog answers the rows', code == 200 and isinstance(cat, list) and len(cat) == 3, (code, cat))
cat = cat if isinstance(cat, list) else []
byid = {r['id']: r for r in cat}
check('an imported row carries the cost and the marked up price',
      dictish(byid.get('stub/alpha')).get('cost_in') == COST_IN and dictish(byid.get('stub/alpha')).get('in') == IN,
      byid.get('stub/alpha'))
check('an unpriced row imports as zeros', dictish(byid.get('stub/free')).get('in') == 0, byid.get('stub/free'))
check('every imported row is disabled', all(r.get('enabled') is False for r in cat), cat)
bad = cat + [{'id': 'other/one', 'provider': 'nope', 'in': 1, 'out': 1}]
code, d = curl('PUT', API + '/catalog', bad)
check('a row on an unknown provider is 400 naming the row', code == 400 and 'row 3 provider: unknown' in err_of(d), (code, d))
dupe = cat + [{'id': 'stub/alpha', 'provider': 'stub', 'in': 1, 'out': 1}]
code, d = curl('PUT', API + '/catalog', dupe)
check('a duplicate id is 400 naming the row', code == 400 and 'row 3 id: duplicate' in err_of(d), (code, d))
for row in cat:
    if row['id'] in ('stub/alpha', 'stub/beta'):
        row['enabled'] = True
code, d = curl('PUT', API + '/catalog', cat)
check('enabling two rows answers 200', code == 200, (code, d))
settle()

print('the models listing')
code, d = curl('GET', V1 + '/models', jar=None)
check('GET /v1/models without a key is 403', code == 403, (code, d))
code, d = curl('GET', V1 + '/models')
data = dictish(d).get('data', [])
alpha = ([m for m in data if m.get('id') == 'stub/alpha'] or [{}])[0]
check('GET /v1/models lists the two enabled rows', code == 200 and len(data) == 2, (code, d))
check('the listing carries OpenRouter pricing strings',
      dictish(alpha.get('pricing')).get('prompt') == '0.0000039' and dictish(alpha.get('pricing')).get('completion') == '0.0000195',
      alpha)

print('accounts and keys')
# the owner does not open accounts: a ship's account exists because
# that ship spoke to the vendor over ames. A cold mint is refused.
code, d = curl('POST', API + '/accounts/~nec/keys', {'name': 'cold'})
check('a mint for a ship that never said hello is 404', code == 404 and 'hello' in str(d), (code, d))
# the account under test is the host's own, opened by its hello over the
# vendor route, which is the one ames path a single ship can take
curl('PUT', API + '/vendor', {'ship': SELF})
settle(); settle()
SHIP = SELF
code, k1 = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'one'})
check('a mint on an account the ship opened answers a secret', code == 200 and '.' in dictish(k1).get('secret', ''), (code, k1))
settle()
code, k2 = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'two'})
check('a second key is minted', code == 200 and dictish(k2).get('secret'), (code, k2))
settle()
code, d = curl('GET', API + '/accounts')
mine = ([a for a in (d if isinstance(d, list) else []) if a.get('ship') == SHIP] or [{}])[0]
check('GET /api/accounts lists the ship with two keys', code == 200 and mine.get('keys') == 2, (code, mine))
extra = []
for i in range(18):
    code, k = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'filler-%d' % i})
    settle(0.4)
    if code == 200:
        extra.append(dictish(k).get('id'))
code, d = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'twenty-one'})
check('the twenty first key is 409', code == 409 and 'over 20' in err_of(d), (code, d, len(extra)))
for kid in extra:
    curl('DELETE', API + '/accounts/' + SHIP + '/keys/' + kid)
    settle(0.3)
code, d = curl('GET', API + '/accounts')
mine = ([a for a in (d if isinstance(d, list) else []) if a.get('ship') == SHIP] or [{}])[0]
check('the account is back to two keys', mine.get('keys') == 2, mine)

SEC1 = dictish(k1).get('secret')
SEC2 = dictish(k2).get('secret')

print('the proxy')
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/alpha', 'messages': message('hi')},
               jar=None, bearer=SEC1)
check('a completion with no credit is 402', code == 402 and 'balance' in err_of(d), (code, d))
code, d = curl('POST', API + '/accounts/' + SHIP + '/credit', {'amount': 1000000, 'note': 'gate'})
check('the owner credits a dollar', code == 200, (code, d))
settle()
code, d = curl('POST', V1 + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hi'), 'stream': True}, jar=None, bearer=SEC1)
check('stream is 400', code == 400 and 'stream' in err_of(d), (code, d))
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/free', 'messages': message('hi')},
               jar=None, bearer=SEC1)
check('a disabled model is 404', code == 404 and 'not offered' in err_of(d), (code, d))
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/nope', 'messages': message('hi')},
               jar=None, bearer=SEC1)
check('an unknown model is 404', code == 404, (code, d))
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/alpha', 'messages': message('hi')},
               bearer=None)
check('the owner cookie is refused on the completion route', code == 403 and 'inference key' in err_of(d), (code, d))
before = len(ledger())
code, d = curl('PUT', API + '/catalog', cat + [{'id': 'stub/error', 'provider': 'stub', 'in': IN,
                                                'out': OUT, 'cost_in': COST_IN, 'cost_out': COST_OUT,
                                                'enabled': True}])
check('the error model is enabled for the pass through check', code == 200, (code, d))
settle()
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/error', 'messages': message('hi')},
               jar=None, bearer=SEC1)
check('an upstream 500 passes through with its message', code == 500 and err_of(d) == 'stub failure', (code, d))
settle()
check('an upstream error writes no debit', len(ledger()) == before, (before, len(ledger())))
curl('PUT', API + '/catalog', cat)
settle()

code, d = curl('POST', V1 + '/chat/completions',
               {'model': 'stub/alpha', 'messages': message('hello there world')}, jar=None, bearer=SEC1)
content = ''
if isinstance(d, dict) and d.get('choices'):
    content = dictish(dictish(d['choices'][0]).get('message')).get('content', '')
check('a completion answers 200 with the stub text', code == 200 and content == 'ok: hello there world', (code, d))
settle(2)
rows = ledger()
debits = [r for r in rows if r.get('kind') == 'debit']
want = 39 + 98
check('the ledger shows one debit at the marked up price',
      len(debits) == 1 and debits[0].get('amount') == want, (want, debits))
check('the debit carries the cost and the token counts',
      dictish(debits[0] if debits else {}).get('cost') == 30 + 75 and dictish(debits[0] if debits else {}).get('in') == 10,
      debits)
code, seen = curl('GET', STUB + '/stub/requests', jar=None)
last = dictish(dictish(seen).get('last'))
check('the upstream saw the swapped model and no stream',
      last.get('model') == 'stub/alpha' and 'stream' not in last, last)

print('embeddings')
code, d = curl('POST', V1 + '/embeddings', {'model': 'stub/alpha', 'input': 'hello'},
               jar=None, bearer=SEC1)
check('an embedding answers 200', code == 200 and dictish(d).get('data'), (code, d))
settle(2)
rows = ledger()
emb = [r for r in rows if r.get('kind') == 'debit' and r.get('out') == 0]
check('an embedding charges input only', len(emb) == 1 and emb[0].get('amount') == 36, emb)

print('revocation and close')
code, d = curl('DELETE', API + '/accounts/' + SHIP + '/keys/' + dictish(k1).get('id'))
check('a key is revoked', code == 200, (code, d))
settle()
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/alpha', 'messages': message('hi')},
               jar=None, bearer=SEC1)
check('the revoked key is 403', code == 403, (code, d))
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/alpha', 'messages': message('hi')},
               jar=None, bearer=SEC2)
check('the other key still works', code == 200, (code, d))
settle(2)
code, d = curl('POST', API + '/accounts/' + SHIP + '/refund', {'amount': 1000, 'note': 'gate', 'ref': 'gate-refund'})
check('a refund answers 200', code == 200, (code, d))
settle()
code, d = curl('POST', API + '/accounts/' + SHIP + '/refund', {'amount': 1000, 'note': 'gate', 'ref': 'gate-refund'})
check('a repeated ref is 409', code == 409 and 'already recorded' in err_of(d), (code, d))

code, acct = curl('GET', API + '/accounts/' + SHIP)
rows = dictish(acct).get('ledger', [])
fold = 0
for r in rows:
    fold += r.get('amount', 0) if r.get('kind') == 'credit' else -r.get('amount', 0)
check('the cached balance equals the fold over the ledger',
      dictish(dictish(acct).get('account')).get('balance') == fold, (fold, dictish(acct).get('account')))

code, d = curl('POST', API + '/accounts/' + SHIP + '/close')
check('the account closes', code == 200, (code, d))
settle()
code, d = curl('POST', V1 + '/chat/completions', {'model': 'stub/alpha', 'messages': message('hi')},
               jar=None, bearer=SEC2)
check('a key on a closed account is 403', code == 403, (code, d))
code, d = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'after'})
check('a mint on a closed account is 409', code == 409, (code, d))

print('the stub pay page')
PAY = HOST + '/apps/armillary/pay/stub'
code, d = curl('GET', PAY + '?ship=' + SHIP + '&nonce=gate-nonce', jar=None)
check('the pay page answers 200 without a cookie', code == 200 and 'Pay' in str(d), (code, str(d)[:200]))
code, d = curl('GET', PAY + '?ship=nope&nonce=gate-nonce', jar=None)
check('a pay page for a bad ship is 400', code == 400, (code, d))
code, d = curl('POST', PAY, {'ship': SHIP, 'nonce': 'gate-nonce'}, jar=None)
check('a nonce that is not a checkout is 404', code == 404 and 'no such checkout' in err_of(d), (code, d))
curl('PUT', API + '/settings', {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
                                'mode': 'live', 'refuse_comets': False})
settle()
code, d = curl('POST', PAY, {'ship': SHIP, 'nonce': 'gate-nonce'}, jar=None)
check('the stub rail is refused in live mode', code == 403 and 'stub mode only' in err_of(d), (code, d))
curl('PUT', API + '/settings', {'markup_pct': MARKUP, 'min_topup': 5000000, 'public_url': '',
                                'mode': 'stub', 'refuse_comets': False})
settle()

print('stripe: the settings')
code, d = settings(stripe_key=STRIPE_KEY, stripe_webhook_secret=WHSEC,
                   stripe_url=SSTUB, public_url=HOST, mode='live')
check('PUT /api/settings takes the two Stripe secrets', code == 200, (code, d))
settle()
code, d = curl('GET', API + '/settings')
check('the key reads masked', dictish(d).get('stripe_key', '').endswith('gate')
      and 'sk_test' not in dictish(d).get('stripe_key', ''), d)
check('the signing secret reads masked',
      dictish(d).get('stripe_webhook_secret', '').endswith('gate')
      and 'whsec_' not in dictish(d).get('stripe_webhook_secret', ''), d)
check('the stripe url is not masked', dictish(d).get('stripe_url') == SSTUB, d)
code, d = settings(stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB,
                   public_url=HOST, mode='live')
settle()
code, d = curl('GET', API + '/settings')
check('a blank secret keeps the stored one',
      dictish(d).get('stripe_key', '').endswith('gate')
      and dictish(d).get('stripe_webhook_secret', '').endswith('gate'), d)
code, d = settings(stripe_key=STRIPE_KEY, stripe_webhook_secret=None, stripe_url=SSTUB,
                   public_url=HOST, mode='live')
check('live mode with a key and no signing secret is 400 naming the field',
      code == 400 and 'stripe_webhook_secret' in err_of(d), (code, d))
settle()
code, d = curl('GET', API + '/settings')
check('and the refused save changed nothing',
      dictish(d).get('stripe_webhook_secret', '').endswith('gate'), d)
code, d = settings(stripe_key=STRIPE_KEY, stripe_webhook_secret=WHSEC, stripe_url=SSTUB,
                   public_url=HOST, mode='live')
check('with the signing secret beside it live mode saves', code == 200, (code, d))
settle()

print('stripe: the plans')
PLAN = {'id': 'pro', 'name': 'Pro', 'kind': 'subscription',
        'price': 2500000, 'credit': 3000000, 'interval': 'month'}
code, d = curl('POST', API + '/plans', PLAN)
check('POST /api/plans adds a plan', code == 200 and dictish(d).get('id') == 'pro', (code, d))
settle()
code, d = curl('POST', API + '/plans', PLAN)
check('a duplicate plan id is 409', code == 409, (code, d))
code, d = curl('POST', API + '/plans', {'id': 'bad', 'kind': 'subscription',
                                        'price': 1, 'credit': 1})
check('a subscription with no interval is 400 naming it',
      code == 400 and 'interval' in err_of(d), (code, d))
code, d = curl('POST', API + '/plans', {'id': 'ten', 'name': 'Ten', 'kind': 'topup',
                                        'price': 10000000, 'credit': 10000000})
check('a top-up plan needs no interval', code == 200, (code, d))
settle()
code, d = curl('GET', API + '/plans')
ids = [p.get('id') for p in (d if isinstance(d, list) else [])]
check('GET /api/plans lists them by id', code == 200 and ids == ['pro', 'ten'], (code, d))
code, d = curl('PUT', API + '/plans/pro', dict(PLAN, name='Pro two'))
check('PUT /api/plans/<id> edits it', code == 200 and dictish(d).get('name') == 'Pro two', (code, d))
code, d = curl('PUT', API + '/plans/nope', PLAN)
check('an unknown plan on PUT is 409', code == 409, (code, d))
settle()
code, d = curl('POST', API + '/plans/pro/stripe', {})
PRICE = dictish(d).get('stripe_price', '')
check('POST /api/plans/<id>/stripe fills stripe_price',
      code == 200 and PRICE.startswith('price_'), (code, d))
code, d = curl('POST', API + '/plans/ten/stripe', {})
check('a top-up plan needs no Stripe price', code == 400 and 'kind' in err_of(d), (code, d))
settle()
code, d = curl('PUT', API + '/plans/pro', dict(PLAN, name='Pro two'))
check('an edit keeps the Stripe price', dictish(d).get('stripe_price') == PRICE, d)
settle()

print('stripe: a subscription holds its plan')
# the only way onto an account is the channel, so the ship is briefly
# its own customer, which is what the single-ship shape is for. The
# account was closed above, and a closed account is not reopened by a
# hello, so it is dropped first and the hello makes a fresh one.
curl('DELETE', API + '/accounts/' + SELF)
settle()
code, d = curl('PUT', API + '/vendor', {'ship': SELF})
check('the ship is its own customer for this check', code == 200, (code, d))
settle(3)
code, co = curl('POST', API + '/checkout', {'rail': 'stripe', 'plan': 'pro'}, timeout=120)
url = dictish(co).get('url', '')
check('a subscription checkout answers a stub session url',
      code == 200 and '/stub/pay/' in url, (code, co))
code, d = curl('POST', url, jar=None)
check('paying the stub session answers the record', code == 200, (code, str(d)[:200]))
sub = {}
for _ in range(15):
    settle(2)
    code, acct = curl('GET', API + '/accounts/' + SELF)
    sub = dictish(dictish(acct).get('subscription'))
    if sub.get('active'):
        break
check('the account shows an active subscription with its Stripe id',
      sub.get('active') is True and str(sub.get('id', '')).startswith('sub_'), sub)
check('the owner detail names the plan', dictish(acct).get('plan') == 'pro', dictish(acct).get('plan'))
code, d = curl('DELETE', API + '/plans/pro')
check('a plan an open subscription names cannot be deleted',
      code == 409 and 'subscription' in err_of(d), (code, d))
code, d = curl('POST', API + '/accounts/' + SELF + '/clear-subscription')
check('the owner can clear a subscription', code == 200, (code, d))
settle(2)
code, d = curl('DELETE', API + '/plans/pro')
check('with the subscription cleared the plan goes', code == 200, (code, d))
curl('PUT', API + '/vendor', {'ship': ''})
curl('DELETE', API + '/accounts/' + SELF)
settle()

print('stripe: the webhook')
code, d = hook('checkout.session.completed', 'cs_nope', sig='t=1,v1=deadbeef')
check('a bad signature is 400', code == 400 and err_of(d) == 'signature', (code, d))
code, d = hook('checkout.session.completed', 'cs_nope', sig='')
check('a missing signature is 400 when the secret is set', code == 400, (code, d))
code, d = hook('payment_intent.succeeded', 'pi_1')
check('an unrelated event is 200 and does nothing', code == 200 and dictish(d).get('ok') is True, (code, d))
before = ledger()
code, d = hook('checkout.session.completed', 'cs_does_not_exist')
check('a completed event naming an unknown session is 200', code == 200, (code, d))
settle(2)
check('and credits nothing', len(ledger()) == len(before), (len(before), len(ledger())))

print('stripe: a live endpoint with no signing secret')
code, d = settings(stripe_key=None, stripe_webhook_secret=None, stripe_url=SSTUB,
                   public_url=HOST, mode='live')
check('live mode with no key and no secret saves', code == 200, (code, d))
settle()
code, d = hook('checkout.session.completed', 'cs_nope', sig='')
check('the webhook in live mode with no signing secret is 400',
      code == 400 and err_of(d) == 'signature: no signing secret configured', (code, d))
code, d = settings(stripe_key=STRIPE_KEY, stripe_webhook_secret=WHSEC, stripe_url=SSTUB,
                   public_url=HOST, mode='live')
check('the Stripe settings go back', code == 200, (code, d))
settle()

print('stripe: the return page')
code, text = page(RETURN + '?ship=' + SHIP + '&cancelled=1')
check('the return page with cancelled=1 is 200 and says cancelled',
      code == 200 and 'cancelled' in text.lower(), (code, text[:200]))
code, text = page(RETURN + '?ship=' + SHIP)
check('the return page without a sid says pending',
      code == 200 and 'pending' in text.lower(), (code, text[:200]))
# a sid the stub never issued: the page stays pending and the ring gets
# its stripe.return entry from this run, not from an earlier one
code, text = page(RETURN + '?sid=cs_stub_never_issued')
check('the return page with an unknown sid says pending',
      code == 200 and 'pending' in text.lower(), (code, text[:200]))
settings()
settle()

print('btcpay: the settings')
code, d = settings(stripe_key=STRIPE_KEY, stripe_webhook_secret=WHSEC, stripe_url=SSTUB,
                   public_url=HOST, mode='live', btcpay_url=BSTUB + '/',
                   btcpay_store=BTC_STORE, btcpay_key=BTC_KEY, btcpay_webhook_secret=WHSEC)
check('PUT /api/settings takes the two BTCPay secrets', code == 200, (code, d))
settle()
code, d = curl('GET', API + '/settings')
check('the btcpay key reads masked', dictish(d).get('btcpay_key', '').endswith('1234')
      and 'btcpay-gate' not in dictish(d).get('btcpay_key', ''), d)
check('the btcpay webhook secret reads masked',
      dictish(d).get('btcpay_webhook_secret', '').endswith('gate')
      and 'whsec_' not in dictish(d).get('btcpay_webhook_secret', ''), d)
check('the btcpay url is not masked and loses its trailing slash',
      dictish(d).get('btcpay_url') == BSTUB, d)
check('the store id is not masked', dictish(d).get('btcpay_store') == BTC_STORE, d)
code, d = settings(stripe_key='', stripe_webhook_secret='', stripe_url=SSTUB,
                   public_url=HOST, mode='live', btcpay_url=BSTUB,
                   btcpay_store=BTC_STORE, btcpay_key='', btcpay_webhook_secret='')
settle()
code, d = curl('GET', API + '/settings')
check('a blank BTCPay secret keeps the stored one',
      dictish(d).get('btcpay_key', '').endswith('1234')
      and dictish(d).get('btcpay_webhook_secret', '').endswith('gate'), d)

print('btcpay: the webhook')
code, d = btc_hook('InvoiceSettled', 'inv_nope', sig='sha256=deadbeef')
check('a bad BTCPay signature is 401', code == 401 and err_of(d) == 'signature', (code, d))
code, d = btc_hook('InvoiceSettled', 'inv_nope', sig='')
check('a missing BTCPay signature is 401 when the secret is set', code == 401, (code, d))
code, d = btc_hook('InvoicePaymentSettled', 'inv_1')
check('an unrelated BTCPay event is 200 and does nothing',
      code == 200 and dictish(d).get('ok') is True, (code, d))
before = ledger()
code, d = btc_hook('InvoiceSettled', 'inv_does_not_exist')
check('a settled event naming an unknown invoice is 200', code == 200, (code, d))
settle(2)
check('and credits nothing', len(ledger()) == len(before), (len(before), len(ledger())))

print('btcpay: the return page')
code, text = page(RETURN + '?ship=' + SHIP + '&nonce=not-a-row&rail=btcpay')
check('the btcpay return page with an unknown nonce is 200 and says pending',
      code == 200 and 'pending' in text.lower(), (code, text[:200]))
settings()
settle()

print('leases: the setting')
code, d = settings(lease_provider='stub')
check('PUT /api/settings takes a lease provider', code == 200, (code, d))
settle()
code, d = curl('GET', API + '/settings')
check('the lease provider round-trips unmasked',
      dictish(d).get('lease_provider') == 'stub', d)
check('the two checkout lifetimes round-trip',
      dictish(d).get('stripe_minutes') == 1440 and dictish(d).get('btcpay_minutes') == 60, d)
code, d = settings(lease_provider='stub', stripe_minutes=0)
settle()
code, d = curl('GET', API + '/settings')
check('a zero lifetime is kept, not defaulted away',
      dictish(d).get('stripe_minutes') == 0, d)
settings()
settle()

print('the tick')
code, d = curl('POST', API + '/tick', {})
check('POST /api/tick answers ok', code == 200 and dictish(d).get('ok') is True, (code, d))
code, d = curl('GET', API + '/tick')
check('GET /api/tick is not a route', code == 404, (code, d))

print('the audit ring')
code, log = curl('GET', API + '/log')
text = json.dumps(log)
ops = set(r.get('op') for r in (log if isinstance(log, list) else []))
check('GET /api/log answers the ring', code == 200 and isinstance(log, list) and len(log) > 0, (code, str(log)[:200]))
for op in ('set-provider', 'set-catalog', 'open-account', 'add-key', 'credit', 'debit', 'refund',
           'drop-key', 'close-account', 'set-plan', 'drop-plan',
           'stripe.webhook', 'stripe.return', 'btcpay.webhook'):
    check('the ring holds an entry for ' + op, op in ops, sorted(ops))
check('the ring never carries a secret', 'stub-key' not in text and 'prov-key' not in text and
      STRIPE_KEY not in text and WHSEC not in text and BTC_KEY not in text
      and (SEC1 or 'x') not in text, text[:300])
out = subprocess.run(['curl', '-s', '-m', '30', '-b', JAR, INSTANCE + '/tr/last?raw=1'],
                     capture_output=True, text=True).stdout
check('tr/last reads ok after the last op', '"ok"' in out and 'stub-key' not in out, out[:200])

broom()
print()
if fails:
    print('FAILED: ' + ', '.join(fails))
    sys.exit(1)
print('ALL OK (%d checks)' % count[0])
