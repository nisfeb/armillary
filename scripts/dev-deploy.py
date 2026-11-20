#!/usr/bin/env python3
"""Put code/ on a DEV ship as the armillary desk, the way a user adds one.

  dev-deploy.py <base-url> <cookie-jar> [--add [--replace] | --approve]

Mirrors code/ into the ship's ball at /armillary-dev/code (creating what
is missing, rewriting the rest), then stamps that copy's version.json so
the desk pulls it: a desk follows its source's version file, and any
change to it is a release. --add makes the desk the first time (POST
/desks/add, following /armillary-dev/code), approves the whole ask and
reloads the instance; --approve does the same without the add. A desk
that already follows another source, like the stock desk that follows
the forge, is culled first only with --replace. The jar comes from
scripts/hoon-test-kit/ship-cookie.sh. It ends with what did not build
and what is banged under the desk, and exits 1 if anything is.

It speaks both kernels. It asks /grubbery/api/peek/apps/ first. The
current kernel answers with the shell at /apps/shell, and the writes go
through /grubbery/api/make and /grubbery/api/cull. An older kernel does
not answer, so the shell is at /apps/shell.shell and the writes go
through the explorer at /grubbery/ball.

Never point this at a real ship: releases go through the forge.
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

url, jar = sys.argv[1].rstrip('/'), sys.argv[2]
code = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'code')
dest = 'armillary-dev/code'
SIGS = ('main.sig', 'web.sig', 'inbox.sig', 'client.sig', 'tick.sig', 'push.sig')
cookie = next(f'{p[5]}={p[6]}' for p in (l.rstrip('\n').split('\t') for l in open(jar))
              if len(p) == 7 and p[5].startswith('urbauth-'))

#  the explorer answers a create with a 303 back to the page; don't follow it
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a): return None

def call(method, path, form=None, body=None, raw=None, ctype=None, follow=False):
    head = {'cookie': cookie, 'accept': 'application/json'}
    data = urllib.parse.urlencode(form).encode() if form else None
    if body is not None:
        data, head['content-type'] = json.dumps(body).encode(), 'application/json'
    if raw is not None:
        data, head['content-type'] = raw, ctype or 'application/octet-stream'
    req = urllib.request.Request(f'{url}/{path}', data=data, method=method, headers=head)
    opener = urllib.request.build_opener(*([] if follow else [Stay]))
    try:
        with opener.open(req) as r: return r.status, r.read()
    except urllib.error.HTTPError as e: return e.code, e.read()

def jload(b):
    try: return json.loads(b)
    except ValueError: return None

s, b = call('GET', 'grubbery/api/peek/apps/')
CURRENT = s == 200 and isinstance(jload(b), dict)
SHELL = 'shell' if CURRENT and 'shell' in jload(b).get('dirs', []) else 'shell.shell'
DESK = f'apps/{SHELL}/desks/armillary.desk'
INSTANCE = f'{DESK}/desk/data/armillary.armillary_app'
print(f'kernel: {"current" if CURRENT else "older"}, shell at /apps/{SHELL}')

#  a .hoon or .json file is kept under its own mark; any other (the icon,
#  the page) as mime, which is what a /< import of it finds, as the
#  forge lays it
MIME = {'.svg': 'image/svg+xml', '.css': 'text/css', '.html': 'text/html',
        '.js': 'text/javascript'}

def blot_of(name):
    ext = os.path.splitext(name)[1]
    return '/' + ext[1:] if ext in ('.hoon', '.json') else None

if CURRENT:
    listed = {}
    def kids(path):
        """a directory's files, or None when there is no directory"""
        if path not in listed:
            s, b = call('GET', f'grubbery/api/peek/{path}/')
            listed[path] = set(jload(b).get('files', [])) if s == 200 else None
        return listed[path]

    def exists(path):
        return call('GET', f'grubbery/api/peek/{path}/')[0] == 200

    def ensure_dir(path):
        if kids(path) is not None: return
        parent = path.rsplit('/', 1)[0] if '/' in path else ''
        if parent: ensure_dir(parent)
        s, b = call('PUT', f'grubbery/api/make/{path}/')
        if s not in (201, 409): sys.exit(f'make {path}/: {s} {b[:200]}')
        listed[path] = set()

    def put(rel, data):
        path = f'{dest}/{rel}'
        d, name = path.rsplit('/', 1)
        ensure_dir(d)
        blot = blot_of(name)
        ctype = 'text/plain' if blot else MIME.get(os.path.splitext(name)[1])
        mark = f'blot={blot}' if blot else ''
        if name in kids(d):
            s, b = call('PUT', f'grubbery/api/make/{path}?force=1&{mark}', raw=data, ctype=ctype)
            if s == 200: return
            #  it would not take the overwrite: cull it and make it again
            call('DELETE', f'grubbery/api/cull/{path}')
        s, b = call('PUT', f'grubbery/api/make/{path}?{mark}', raw=data, ctype=ctype)
        if s != 201: sys.exit(f'make {path}: {s} {b.decode(errors="replace")[:400]}')
        kids(d).add(name)

    def cull(path):
        return call('DELETE', f'grubbery/api/cull/{path}')

    def read_json(path):
        s, b = call('GET', f'grubbery/api/peek/{path}')
        return jload(b) if s == 200 else None

    def bangs():
        """what did not build and what is banged, as lines"""
        out = []
        s, b = call('GET', f'grubbery/api/build/{DESK}/desk/code')
        for f in (jload(b) or {}).get('files', []) if s == 200 else []:
            out.append(f'build {f["source"]}: ' + ' '.join(f.get('error') or []))
        s, b = call('GET', f'grubbery/api/bang/{DESK}/')
        for h in (jload(b) or {}).get('hits', []) if s == 200 else []:
            out.append(f'bang {h["where"]}: ' + ' '.join(h.get('error') or []))
        return out
else:
    def exists(path):
        return call('GET', f'grubbery/ball/{path}?info=1')[0] == 200

    def ensure_dir(path):
        if exists(path): return
        parent, name = path.rsplit('/', 1) if '/' in path else ('', path)
        if parent: ensure_dir(parent)
        s, b = call('POST', f'grubbery/ball/{parent}', {'action': 'create-folder', 'foldername': name})
        if s not in (200, 303): sys.exit(f'create-folder {path}: {s} {b[:200]}')

    def info(path):
        s, b = call('GET', f'grubbery/ball/{path}?info=1')
        return (jload(b) or {}) if s == 200 else None

    def put(rel, data):
        path = f'{dest}/{rel}'
        d, name = path.rsplit('/', 1)
        ensure_dir(d)
        form = {'action': 'create-file', 'filename': name}
        if not blot_of(name):
            form['blot'] = '/mime'
            if (info(path) or {}).get('blot') not in (None, '/mime'):
                s, b = call('POST', f'grubbery/ball/{d}', {'action': 'delete-grub', 'filename': name})
                if s not in (200, 303): sys.exit(f'delete-grub {path}: {s} {b[:200]}')
        if not exists(path):
            s, b = call('POST', f'grubbery/ball/{d}', form)
            if s not in (200, 303): sys.exit(f'create-file {path}: {s} {b[:200]}')
        s, b = call('POST', f'grubbery/ball/{path}',
                    {'action': 'write-text', 'content': data.decode('utf-8')})
        if s != 200: sys.exit(f'write-text {path}: {s} {b.decode(errors="replace")[:400]}')

    def cull(path):
        parent, name = path.rstrip('/').rsplit('/', 1)
        return call('POST', f'grubbery/ball/{parent}', {'action': 'delete-grub', 'filename': name})

    def read_json(path):
        #  a raw read answers 307 on this kernel: follow it
        s, b = call('GET', f'grubbery/ball/{path}?raw=1', follow=True)
        return jload(b) if s == 200 else None

    def bangs():
        out = []
        for p in [INSTANCE] + [f'{INSTANCE}/{sig}' for sig in SIGS]:
            bang = (info(p) or {}).get('bang')
            if bang: out.append(f'bang /{p}: {str(bang).strip()}')
        return out

files = sorted(os.path.relpath(os.path.join(dp, f), code)
               for dp, _, fs in os.walk(code) for f in fs)
for rel in files:
    if rel == 'version.json': continue
    put(rel, open(os.path.join(code, rel), 'rb').read())
    print('  ' + rel)
#  last, so the desk pulls a whole tree: the repo's version, stamped
ver = json.load(open(os.path.join(code, 'version.json')))
ver['dev'] = time.strftime('%Y-%m-%dT%H:%M:%S')
put('version.json', json.dumps(ver).encode())
print(f'  version.json {json.dumps(ver)}')

def wait_for(path, tries=18):
    for _ in range(tries):
        if exists(path): return True
        time.sleep(10)
    return False

if '--add' in sys.argv:
    if exists(DESK):
        src = (read_json(f'{DESK}/source.json') or {}).get('code')
        if src != '/' + dest:
            if '--replace' not in sys.argv:
                sys.exit(f'/{DESK} follows {src}; --replace culls it first')
            s, b = cull(DESK + '/')
            print(f'culled the desk that followed {src}: {s}')
            time.sleep(5)
    s, b = call('POST', 'apps/grubbery/desks/add', body={'name': 'armillary', 'code': '/' + dest})
    print(f'desks/add: {s} {b.decode(errors="replace")}')
    if not wait_for(INSTANCE): sys.exit(f'no instance at /{INSTANCE} after three minutes')
    time.sleep(5)
if '--add' in sys.argv or '--approve' in sys.argv:
    #  the whole ask, from the instance's own weir.json, and both groups
    #  keys: without `granted` the shell records an empty grant, and a
    #  customer-only ship has no use for a smaller one in a test
    ask = read_json(f'{INSTANCE}/weir.json') or {}
    grant = {k: [r['road'] for r in ask.get(k, [])] for k in ('poke', 'peek', 'make')}
    grant['groups'] = ['/public', '/armillary/']
    if not grant['poke']: sys.exit(f'no ask at /{INSTANCE}/weir.json')
    s, b = call('POST', 'apps/grubbery/permits',
                body={'action': 'approve-weir', 'app': '/' + INSTANCE, 'granted': grant})
    print(f'permits: {s} {b.decode(errors="replace")[:200]}')
    time.sleep(5)
    #  the fibers rose jailed and parked on a vetoed dart. A kernel
    #  before 785d015 never revives one on reload, its stale veto still
    #  queued, so a banged sig file is culled and the reload lays it
    #  fresh. On a newer kernel nothing is parked and nothing is culled.
    for line in bangs():
        sig = next((g for g in SIGS if line.startswith(f'bang /{INSTANCE}/{g}')), None)
        if sig:
            s, b = cull(f'{INSTANCE}/{sig}')
            print(f'  culled parked {sig}: {s}')
    s, b = call('POST', 'apps/grubbery/permits/reload', body={'app': '/' + INSTANCE})
    print(f'reload: {s} {b.decode(errors="replace")[:200]}')
time.sleep(10)
if not wait_for(INSTANCE, 12): print(f'no instance at /{INSTANCE}')
bad = bangs()
print(f'bang: {"null" if not bad else len(bad)}')
for line in bad: print('  ' + line.strip()[:600])
sys.exit(1 if bad else 0)
