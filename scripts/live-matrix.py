#!/usr/bin/env python3
"""live-matrix.py HOST JAR PEER PJAR
The one run this family cannot automate: a real Stripe test-mode key, a
real card, a real person clicking. HOST is the vendor with its owner
cookie jar, PEER the customer ship with its own; the two may be the same
ship, which makes it its own customer.

The key comes from the environment variable STRIPE_TEST_KEY and from
nowhere else: never a file in this repo, and it is never printed. Run it
by hand:

    STRIPE_TEST_KEY=rk_test_... python3 scripts/live-matrix.py \\
        http://localhost:8080 wex.cookies http://localhost:8080 wex.cookies

It reports what it saw and asserts nothing about timing. Stripe takes as
long as it takes, and a webhook that never arrives is still a pass for
the return page, which is the point of having both. It restores stub
mode and clears the key on the way out, however it ends.
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
           'stripe_webhook_secret': '', 'stripe_url': 'https://api.stripe.com'}
    doc.update(over)
    return curl('PUT', api(HOST) + '/settings', doc, jar=JAR)


def account():
    code, d = curl('GET', api(PEER) + '/account?fresh=1', jar=PJAR, timeout=120)
    return dictish(d)


def wait_for(label, ok):
    """poll the customer's own account until ok, for up to ten minutes"""
    started = time.time()
    while time.time() - started < POLL_SECONDS:
        a = account()
        if ok(a):
            print('  %s after %ds' % (label, int(time.time() - started)))
            return a
        time.sleep(10)
        print('  waiting on %s, %ds so far' % (label, int(time.time() - started)))
    print('  gave up on %s after %ds' % (label, POLL_SECONDS))
    return account()


def restore():
    curl('DELETE', api(HOST) + '/plans/' + PLAN['id'], jar=JAR)
    curl('PUT', api(PEER) + '/vendor', {'ship': ''}, jar=PJAR)
    settings(stripe_key=None, stripe_webhook_secret=None)
    print('restored: stub mode, no Stripe key')


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
finally:
    restore()
