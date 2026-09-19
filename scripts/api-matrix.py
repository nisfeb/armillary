#!/usr/bin/env python3
"""api-matrix.py HOST JAR PROVIDER_PORT
The HTTP gate for armillary: spec sections 4, 5 and 8 against a stub
provider. HOST like http://localhost:8080; JAR a curl cookie jar from
POST /~/login; PROVIDER_PORT the port fake-provider.py listens on with
the key "stub-key". It starts nothing: the runner starts the stub first.
Exits 1 on any failure. Safe to rerun: it deletes the account and the
provider it made, both before it starts and after it finishes."""
import json, subprocess, sys, time

HOST, JAR, PORT = sys.argv[1], sys.argv[2], sys.argv[3]
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


def message(text):
    return [{'role': 'user', 'content': text}]


def dictish(d):
    return d if isinstance(d, dict) else {}


def err_of(d):
    return dictish(dictish(d).get('error')).get('message', '')


def ledger():
    code, d = curl('GET', API + '/accounts/' + SHIP)
    return dictish(d).get('ledger', []) if code == 200 else []


def broom():
    curl('DELETE', API + '/accounts/' + SHIP)
    curl('DELETE', API + '/providers/stub')
    # the catalog outlives a dropped provider on purpose, so the gate
    # clears it by hand or a rerun imports nothing
    curl('PUT', API + '/catalog', [])
    settle()


broom()
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
code, k1 = curl('POST', API + '/accounts/' + SHIP + '/keys', {'name': 'one'})
check('a mint opens the account and answers a secret', code == 200 and '.' in dictish(k1).get('secret', ''), (code, k1))
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

print('the audit ring')
code, log = curl('GET', API + '/log')
text = json.dumps(log)
ops = set(r.get('op') for r in (log if isinstance(log, list) else []))
check('GET /api/log answers the ring', code == 200 and isinstance(log, list) and len(log) > 0, (code, str(log)[:200]))
for op in ('set-provider', 'set-catalog', 'open-account', 'add-key', 'credit', 'debit', 'refund',
           'drop-key', 'close-account'):
    check('the ring holds an entry for ' + op, op in ops, sorted(ops))
check('the ring never carries a secret', 'stub-key' not in text and 'prov-key' not in text and
      (SEC1 or 'x') not in text, text[:300])
out = subprocess.run(['curl', '-s', '-m', '30', '-b', JAR, INSTANCE + '/tr/last?raw=1'],
                     capture_output=True, text=True).stdout
check('tr/last reads ok after the last op', '"ok"' in out and 'stub-key' not in out, out[:200])

broom()
print()
if fails:
    print('FAILED: ' + ', '.join(fails))
    sys.exit(1)
print('ALL OK (%d checks)' % count[0])
