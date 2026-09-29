#!/usr/bin/env python3
"""Put code/ on a DEV ship as the armillary desk, the way a user adds one.

  dev-deploy.py <base-url> <cookie-jar> [--add]

Mirrors code/ into the ship's ball at /armillary-dev/code through the
explorer (creating what is missing, rewriting the rest), then stamps that
copy's version.json so the desk pulls it: a desk follows its source's
version file, and any change to it is a release. --add makes the desk the
first time (POST /desks/add, following /armillary-dev/code), approves the
whole ask, culls the fibers that parked while the desk was jailed and
reloads the instance; --approve does the same without the add. The jar
comes from
scripts/hoon-test-kit/ship-cookie.sh. Read the instance's ?info=1 after: a
bang is a compile error.

Never point this at a real ship: releases go through the forge.
"""
import json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

url, jar = sys.argv[1].rstrip('/'), sys.argv[2]
code = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'code')
dest = 'armillary-dev/code'
INSTANCE = 'apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app'
cookie = next(f'{p[5]}={p[6]}' for p in (l.rstrip('\n').split('\t') for l in open(jar))
              if len(p) == 7 and p[5].startswith('urbauth-'))

def call(method, path, form=None, body=None):
    head = {'cookie': cookie, 'accept': 'application/json'}
    data = urllib.parse.urlencode(form).encode() if form else None
    if body is not None:
        data, head['content-type'] = json.dumps(body).encode(), 'application/json'
    req = urllib.request.Request(f'{url}/{path}', data=data, method=method, headers=head)
    #  the explorer answers a create with a 303 back to the page; don't follow it
    class Stay(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a): return None
    try:
        with urllib.request.build_opener(Stay).open(req) as r: return r.status, r.read()
    except urllib.error.HTTPError as e: return e.code, e.read()

def exists(path):
    return call('GET', f'grubbery/ball/{path}?info=1')[0] == 200

def ensure_dir(path):
    if exists(path): return
    parent, name = path.rsplit('/', 1) if '/' in path else ('', path)
    if parent: ensure_dir(parent)
    s, b = call('POST', f'grubbery/ball/{parent}', {'action': 'create-folder', 'foldername': name})
    if s not in (200, 303): sys.exit(f'create-folder {path}: {s} {b[:200]}')

def blot(path):
    s, b = call('GET', f'grubbery/ball/{path}?info=1')
    return json.loads(b).get('blot') if s == 200 else None

#  a .hoon or .json file is kept under its own mark; any other (the icon)
#  as mime, which is what a /< import of it finds, as the forge lays it
def put(rel, text):
    path = f'{dest}/{rel}'
    d, name = path.rsplit('/', 1)
    ensure_dir(d)
    form = {'action': 'create-file', 'filename': name}
    if not name.endswith(('.hoon', '.json')):
        form['blot'] = '/mime'
        if blot(path) not in (None, '/mime'):
            s, b = call('POST', f'grubbery/ball/{d}', {'action': 'delete-grub', 'filename': name})
            if s not in (200, 303): sys.exit(f'delete-grub {path}: {s} {b[:200]}')
    if not exists(path):
        s, b = call('POST', f'grubbery/ball/{d}', form)
        if s not in (200, 303): sys.exit(f'create-file {path}: {s} {b[:200]}')
    s, b = call('POST', f'grubbery/ball/{path}', {'action': 'write-text', 'content': text})
    if s != 200: sys.exit(f'write-text {path}: {s} {b.decode(errors="replace")[:400]}')

files = sorted(os.path.relpath(os.path.join(dp, f), code)
               for dp, _, fs in os.walk(code) for f in fs)
for rel in files:
    if rel == 'version.json': continue
    put(rel, open(os.path.join(code, rel), encoding='utf-8').read())
    print('  ' + rel)
#  last, so the desk pulls a whole tree: the repo's version, stamped
ver = json.load(open(os.path.join(code, 'version.json')))
ver['dev'] = time.strftime('%Y-%m-%dT%H:%M:%S')
put('version.json', json.dumps(ver))
print(f'  version.json {json.dumps(ver)}')

if '--add' in sys.argv:
    s, b = call('POST', 'apps/grubbery/desks/add', body={'name': 'armillary', 'code': '/' + dest})
    print(f'desks/add: {s} {b.decode(errors="replace")}')
    time.sleep(20)
if '--add' in sys.argv or '--approve' in sys.argv:
    #  the ten-road ask, granted whole: without `granted` the shell records
    #  an empty grant, and a customer-only ship has no use for a smaller one
    #  in a test
    grant = {'poke': ['/sys/bowl.sig', '/sys/eyre/', '/sys/iris/', '/sys/behn/',
                      '/sys/gall/', '/sys/ames/registry'],
             'peek': ['/sys/link/', '/sys/ames/ships/', '/sys/ames/usergroups/'],
             'make': ['/sys/ames/usergroups/']}
    s, b = call('POST', 'apps/grubbery/permits',
                body={'action': 'approve-weir', 'app': '/' + INSTANCE, 'granted': grant})
    print(f'permits: {s} {b.decode(errors="replace")[:200]}')
    time.sleep(5)
    #  the fibers rose jailed and parked on a vetoed dart, and a reload
    #  never revives a parked fiber: its stale veto is still queued. A
    #  parked sig file is culled instead, and the reload lays it fresh
    for sig in ('main.sig', 'web.sig', 'inbox.sig', 'client.sig', 'tick.sig'):
        s, b = call('GET', f'grubbery/ball/{INSTANCE}/{sig}?info=1')
        if s == 200 and json.loads(b).get('bang'):
            s, b = call('POST', f'grubbery/ball/{INSTANCE}', {'action': 'delete-grub', 'filename': sig})
            print(f'  culled parked {sig}: {s}')
    s, b = call('POST', 'apps/grubbery/permits/reload', body={'app': '/' + INSTANCE})
    print(f'reload: {s} {b.decode(errors="replace")[:200]}')
for _ in range(12):
    time.sleep(10)
    s, b = call('GET', f'grubbery/ball/{INSTANCE}?info=1')
    bang = json.loads(b).get('bang') if s == 200 else f'({s})'
    if s == 200:
        break
print(f'bang: {bang}')
for sig in ('main.sig', 'web.sig', 'inbox.sig', 'client.sig', 'tick.sig'):
    s, b = call('GET', f'grubbery/ball/{INSTANCE}/{sig}?info=1')
    fb = json.loads(b).get('bang') if s == 200 else f'({s})'
    if fb:
        print(f'  {sig} bang: {str(fb).strip()}')
