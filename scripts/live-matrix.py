#!/usr/bin/env python3
"""live-matrix.py HOST JAR PEER PJAR
The one run this family cannot automate: a real Stripe test-mode key, a
real BTCPay store, real money, a real person clicking. HOST is the
vendor with its owner cookie jar, PEER the customer ship with its own;
the two may be the same ship, which makes it its own customer.

Every secret comes from the environment and from nowhere else: never a
file in this repo, and none of them is ever printed. The card half reads
STRIPE_TEST_KEY; the bitcoin half reads BTCPAY_URL, BTCPAY_STORE and
BTCPAY_KEY, and runs only when all three are set; the lease half reads
OPENROUTER_PROVISIONING_KEY and runs only when it is set. Run it by
hand:

    STRIPE_TEST_KEY=rk_test_... python3 scripts/live-matrix.py \\
        http://localhost:8080 wex.cookies http://localhost:8080 wex.cookies

    BTCPAY_URL=https://btcpay.example.com BTCPAY_STORE=... BTCPAY_KEY=... \\
        STRIPE_TEST_KEY=rk_test_... python3 scripts/live-matrix.py ...

It reports what it saw and asserts nothing about timing. A rail takes as
long as it takes, a chain confirmation takes longer still, and a webhook
that never arrives is still a pass for the return page, which is the
point of having both. It restores stub mode and clears every key on the
way out, however it ends.
"""
import json
import os
import subprocess
import sys
import time

if len(sys.argv) < 5:
    print(__doc__)
    sys.exit(2)
HOST, JAR, PEER, PJAR = sys.argv[1:5]
KEY = os.environ.get('STRIPE_TEST_KEY', '')
if not KEY:
    print('STRIPE_TEST_KEY is not set. Nothing ran.')
    sys.exit(2)
PLAN = {'id': 'live-pro', 'name': 'Live Pro', 'kind': 'subscription',
        'price': 2500000, 'credit': 3000000, 'interval': 'month'}
POLL_SECONDS = 600
BTC_URL = os.environ.get('BTCPAY_URL', '')
BTC_STORE = os.environ.get('BTCPAY_STORE', '')
BTC_KEY = os.environ.get('BTCPAY_KEY', '')
BTC_POLL_SECONDS = 1800
OR_KEY = os.environ.get('OPENROUTER_PROVISIONING_KEY', '')
OR_BASE = os.environ.get('OPENROUTER_BASE_URL', 'https://openrouter.ai/api/v1')
OR_MODEL = os.environ.get('OPENROUTER_MODEL', 'openrouter/auto')


def api(host):
    return host + '/apps/armillary/api'


def curl(method, url, body=None, jar=None, timeout=180):
    cmd = ['curl', '-s', '-m', str(timeout), '-X', method, '-w', '\n%{http_code}', url]
    if jar:
        cmd += ['-b', jar]
    if body is not None:
        cmd += ['-H', 'content-type: application/json', '-d', json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    text, _, code = out.rpartition('\n')
    try:
        data = json.loads(text) if text else None
    except json.JSONDecodeError:
        data = text
    return int(code or 0), data


def dictish(d):
    return d if isinstance(d, dict) else {}


def settings(**over):
    doc = {'markup_pct': 130, 'min_topup': 5000000, 'public_url': '',
           'mode': 'stub', 'refuse_comets': False, 'stripe_key': '',
           'stripe_webhook_secret': '', 'stripe_url': 'https://api.stripe.com',
           'btcpay_url': '', 'btcpay_store': '', 'btcpay_key': '',
           'btcpay_webhook_secret': '', 'lease_provider': '',
           'stripe_minutes': 1440, 'btcpay_minutes': 60}
    doc.update(over)
    return curl('PUT', api(HOST) + '/settings', doc, jar=JAR)


def account():
    code, d = curl('GET', api(PEER) + '/account?fresh=1', jar=PJAR, timeout=120)
    return dictish(d)


def wait_for(label, ok, seconds=POLL_SECONDS):
    """poll the customer's own account until ok, for up to seconds"""
    started = time.time()
    while time.time() - started < seconds:
        a = account()
        if ok(a):
            print('  %s after %ds' % (label, int(time.time() - started)))
            return a
        time.sleep(10)
        print('  waiting on %s, %ds so far' % (label, int(time.time() - started)))
    print('  gave up on %s after %ds' % (label, seconds))
    return account()


def restore():
    curl('DELETE', api(HOST) + '/plans/' + PLAN['id'], jar=JAR)
    curl('PUT', api(PEER) + '/vendor', {'ship': ''}, jar=PJAR)
    settings(stripe_key=None, stripe_webhook_secret=None,
             btcpay_key=None, btcpay_webhook_secret=None, lease_provider='')
    curl('DELETE', api(PEER) + '/lease', jar=PJAR)
    curl('DELETE', api(HOST) + '/providers/live-openrouter', jar=JAR)
    print('restored: stub mode, no rail keys, no lease')


PUBLIC = os.environ.get('ARMILLARY_PUBLIC_URL', HOST)
print('vendor %s, customer %s, public url %s' % (HOST, PEER, PUBLIC))
try:
    code, d = settings(stripe_key=KEY, public_url=PUBLIC, mode='live')
    print('live mode: %s' % code)
    time.sleep(2)
    code, d = curl('PUT', api(PEER) + '/vendor', {'ship': dictish(account()).get('self')
                                                  or ''}, jar=PJAR)
    code, d = curl('GET', api(PEER) + '/account', jar=PJAR)
    vendor = dictish(d).get('vendor', '')
    if not vendor:
        print('the customer has no vendor set. Set it and run again.')
        raise SystemExit(2)
    before = dictish(account()).get('balance', 0)
    print('balance now %d microdollars' % before)

    print('\na ten dollar top-up')
    code, co = curl('POST', api(PEER) + '/checkout',
                    {'rail': 'stripe', 'amount': 10000000}, jar=PJAR, timeout=180)
    url = dictish(co).get('url', '')
    if not url:
        print('no checkout url: %s %s' % (code, co))
        raise SystemExit(1)
    print('  pay here with 4242 4242 4242 4242, any future date, any CVC:')
    print('  %s' % url)
    after = wait_for('the top-up credit', lambda a: a.get('balance', 0) > before)
    rows = [r for r in after.get('ledger', []) if r.get('rail') == 'stripe']
    print('  balance %d, newest stripe row %s' % (after.get('balance', 0),
                                                  json.dumps(rows[0]) if rows else 'none'))

    print('\na subscription')
    curl('POST', api(HOST) + '/plans', PLAN, jar=JAR)
    time.sleep(1)
    code, p = curl('POST', api(HOST) + '/plans/' + PLAN['id'] + '/stripe', {}, jar=JAR)
    print('  plan on Stripe: %s %s' % (code, dictish(p).get('stripe_price', p)))
    time.sleep(2)
    base = dictish(account()).get('balance', 0)
    code, co = curl('POST', api(PEER) + '/checkout',
                    {'rail': 'stripe', 'plan': PLAN['id']}, jar=PJAR, timeout=180)
    url = dictish(co).get('url', '')
    if not url:
        print('no subscription url: %s %s' % (code, co))
        raise SystemExit(1)
    print('  subscribe here with the same card:')
    print('  %s' % url)
    after = wait_for('the subscription credit', lambda a: a.get('balance', 0) > base)
    print('  balance %d, subscription %s, plan %s' %
          (after.get('balance', 0), json.dumps(after.get('subscription')), after.get('plan')))
    code, acct = curl('GET', api(HOST) + '/accounts/' + (after.get('ship') or ''), jar=JAR)
    print('  the owner sees %s' % json.dumps(dictish(acct).get('subscription')))
    print('\nwhat is left: cancel the subscription in the Stripe dashboard, or')
    print('POST /api/cancel-subscription on the customer, and watch the webhook.')

    if not (BTC_URL and BTC_STORE and BTC_KEY):
        print('\nno BTCPay environment set, so the bitcoin half is skipped.')
    else:
        print('\na bitcoin top-up')
        code, d = settings(stripe_key='', public_url=PUBLIC, mode='live',
                           btcpay_url=BTC_URL, btcpay_store=BTC_STORE, btcpay_key=BTC_KEY)
        print('  btcpay settings: %s' % code)
        time.sleep(2)
        base = dictish(account()).get('balance', 0)
        code, co = curl('POST', api(PEER) + '/checkout',
                        {'rail': 'btcpay', 'amount': 10000000}, jar=PJAR, timeout=180)
        url = dictish(co).get('url', '')
        if not url:
            print('  no invoice url: %s %s' % (code, co))
        else:
            print('  pay this invoice from a testnet wallet, on chain or over Lightning:')
            print('  %s' % url)
            after = wait_for('the bitcoin credit', lambda a: a.get('balance', 0) > base,
                             seconds=BTC_POLL_SECONDS)
            rows = [r for r in after.get('ledger', []) if r.get('rail') == 'btcpay']
            print('  balance %d, newest btcpay row %s' %
                  (after.get('balance', 0), json.dumps(rows[0]) if rows else 'none'))
            nonce = dictish(co).get('nonce', '')
            row = dictish(dictish(after.get('checkouts')).get(nonce))
            print('  the checkout row is %s' % json.dumps(row))
    if not OR_KEY:
        print('\nno OPENROUTER_PROVISIONING_KEY set, so the lease half is skipped.')
    else:
        print('\na real lease')
        # the provisioning key rides on a provider row and is never
        # printed: the ship masks it on every read route
        code, d = curl('POST', api(HOST) + '/providers',
                       {'id': 'live-openrouter', 'name': 'OpenRouter',
                        'kind': 'openrouter', 'base_url': OR_BASE,
                        'api_key': '', 'provisioning_key': OR_KEY}, jar=JAR)
        if code == 409:
            code, d = curl('PUT', api(HOST) + '/providers/live-openrouter',
                           {'name': 'OpenRouter', 'kind': 'openrouter',
                            'base_url': OR_BASE, 'api_key': '',
                            'provisioning_key': OR_KEY}, jar=JAR)
        print('  the provider row: %s' % code)
        time.sleep(1)
        code, d = settings(stripe_key='', public_url=PUBLIC, mode='live',
                           lease_provider='live-openrouter')
        print('  lease provider set: %s' % code)
        time.sleep(2)
        base = dictish(account()).get('balance', 0)
        print('  balance before the lease: %d microdollars' % base)
        code, lease = curl('POST', api(PEER) + '/lease', {}, jar=PJAR, timeout=180)
        key = dictish(lease).get('key', '')
        if not key:
            print('  no lease: %s %s' % (code, lease))
        else:
            # the key itself is never printed, only its hash and figures
            print('  lease hash %s, cap %s microdollars' %
                  (dictish(lease).get('hash'), dictish(lease).get('limit')))
            out = subprocess.run(
                ['curl', '-s', '-m', '180', '-X', 'POST',
                 '-H', 'content-type: application/json',
                 '-H', 'authorization: Bearer ' + key,
                 '-d', json.dumps({'model': OR_MODEL,
                                   'messages': [{'role': 'user', 'content': 'Say ok.'}],
                                   'max_tokens': 5}),
                 dictish(lease).get('base_url', OR_BASE) + '/chat/completions'],
                capture_output=True, text=True).stdout
            try:
                answer = json.loads(out)
            except ValueError:
                answer = {}
            said = ''
            if dictish(answer).get('choices'):
                said = dictish(dictish(answer['choices'][0]).get('message')).get('content', '')
            print('  OpenRouter answered: %s' % (said or str(out)[:200]))
            code, d = curl('POST', api(HOST) + '/tick', {}, jar=JAR, timeout=180)
            print('  tick: %s' % code)
            after = wait_for('the lease debit',
                             lambda a: any(r.get('mode') == 'lease' for r in a.get('ledger', [])),
                             seconds=120)
            rows = [r for r in after.get('ledger', []) if r.get('mode') == 'lease']
            print('  newest lease row %s' % (json.dumps(rows[0]) if rows else 'none'))
            print('  lease now %s' % json.dumps(after.get('lease')))
            code, d = curl('DELETE', api(PEER) + '/lease', jar=PJAR, timeout=180)
            print('  dropped the lease: %s' % code)
finally:
    restore()
