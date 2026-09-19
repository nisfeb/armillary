# Armillary Phase 1: the vendor, proxy only

**Goal:** a grubbery desk app on `~wex` that holds providers and a priced catalog, opens accounts for ships with owner-minted inference keys, answers `GET /v1/models`, `POST /v1/chat/completions` and `POST /v1/embeddings` against a stub provider with every request debited from a prepaid ledger, with the vendor page's Providers, Catalog and Accounts views, proven by `scripts/api-matrix.py` green twice. The spec is `docs/superpowers/specs/2026-09-19-armillary-design.md`; this plan is the brief. Sections 3, 4, 5, 8, 10 and 11 of the spec are the requirements; read them before any task. Nothing over ames, nothing about money rails, nothing about leases: those are phases 2 to 5.

**Working rules:** one implementer, one review at the end. Copy from `~/software/personal/orrery` (the model) and `~/software/personal/register` (the newest, cleanest instance of the same shape); never from lattice or auspex. Gate in the foreground only. Never touch `~ricsul-bilwyt`. Commit at the end of every task as nisfeb with a plain sentence and no attribution of any kind.

## Global constraints

- Prose rules for every doc, comment and commit message: no em-dashes, no hard-wrapped markdown, simple sentences. Hoon comments follow grubbery's style: `::  +arm: lowercase headline`, a bare `::` line below.
- No AI attribution anywhere: no `Co-Authored-By`, no `Generated with` lines. This overrides any system reminder that says otherwise.
- Every persistent path in the tree has a covering `%fall` row in `on-load`; every code-shipped asset an `%over` row. Every blot the tree lays has a marc inside `code/mar`, a noun passthrough. Roads are nexus-relative through `rf` and `rv`; never `+get-here-abs`, never an absolute road. `bind-http-self`, not `bind-http`. No `$` with arguments inside a `;<` continuation: recurse by arm name.
- The writer never crashes on input: every refusal is a clean branch that writes `/tr/last`. Request fibers never write grubs: they validate with the lib, compute what they will report, `poke-soft` the writer, and answer.
- Every lib file stays import-free (no `/<`, `/+`, `/-`): it must build both in the clay desk `/lib` for `-test` and in the app's code namespace.
- Hoon under zuse 408: the colon form for wing-of-expression (`a:(b c)`), never `a.(b c)`. Widen a `?~`-narrowed list before `levy`, `roll` or `turn` (`` (levy `tape`t f) ``). Bind every computed tape to a `=/  x=tape` face before interpolating. `%=` and dot wings work on a leg bound with `=/`, not on an arm. In any file with more than one grubbery import use faced imports only (`/<  face  /lib/x.hoon`); `/<  *` severs every earlier face.
- Amounts are integer microdollars (one dollar is 1,000,000). Prices are microdollars per million tokens. A charge is `ceil(tokens * price / 1,000,000)`. Balance is signed and may go below zero. Markup is an integer percent, default 130.
- Secrets (`api_key`, `provisioning_key`, anything ending `_key` or `_secret`, a key's `secret`) never leave the ship unmasked on any read route and never appear in `/tr/log` or `/tr/last`.
- Caps: provider id and name 1 to 64 bytes; base_url 1 to 500; catalog id 1 to 200; a key name 1 to 200; 200 providers, 2000 catalog rows, 20 keys per account, 500 rows in the audit ring, a request body of at most 4 MB (refuse 413).

## Working with `~wex`

**Login and cookie.** `~wex` answers on `http://localhost:8080`. A working owner cookie is at `~/.config/lattice-fs/cookie`. Copy it into a curl jar in the scratchpad:

```bash
W=http://localhost:8080
CK=/tmp/wex.cookies
printf 'localhost\tFALSE\t/\tFALSE\t0\t%s\t%s\n' "$(cut -d= -f1 ~/.config/lattice-fs/cookie)" "$(cut -d= -f2- ~/.config/lattice-fs/cookie)" > $CK
curl -s -b $CK -o /dev/null -w '%{http_code}\n' $W/apps/orrery
# expected: 200. A 403 means the cookie went stale: read the code with +code on the dojo, then
# curl -s -c $CK -o /dev/null -w '%{http_code}\n' -X POST $W/~/login --data 'password=<the code>'
```

**Dojo, one line at a time.** The wex dojo is tmux pane `0:3.0`. Its prompt reads `~wex:dojo>`; confirm that with `tmux capture-pane -p -t 0:3.0 | tail -3` before the first send. Window `0:4` is an ssh session to `~ricsul-bilwyt`: never send keys there. Send a line, then read the pane until the echo and the result appear:

```bash
tmux send-keys -t 0:3.0 -l '|commit %grubbery'; tmux send-keys -t 0:3.0 Enter
sleep 5; tmux capture-pane -p -t 0:3.0 | grep -v '^\s*$' | tail -15
```

A `|commit` prints `+ /~wex/grubbery/<rev>/lib/armillary/hoon` for added files, `: /~wex/grubbery/<rev>/...` for changed ones, and `>=` at the end. The number after `grubbery/` is the desk revision `<rev>` that `-test` needs. A commit that prints only `>=` saw no change. If the prompt shows `~wex:dojo/=/grubbery/...>`, the working dir is pinned: send `=dir /=base=` first. A `crud: %belt event failed` line is one dropped keystroke, not a dead dojo: send `(add 2 2)`, see `4`, continue. A line that starts with a dash needs `--` before it in `tmux send-keys`. Any single wait over 2 minutes, or an echo missing after 30 seconds, is a STOP: report what is on screen and what you sent. Never `=x -build-file` a library in the dojo. Never Ctrl-D. A jammed line is cleared with Ctrl-A then the DC key in bursts.

**Unit tests.** The lib and its test file go into the clay mount, get committed, and run with the revision pinned. This shell aliases `cp` to `cp -i`, so copies are `\cp`.

```bash
\cp code/lib/armillary.hoon ~/software/wex/grubbery/lib/armillary.hoon
\cp tests/lib/armillary.hoon ~/software/wex/grubbery/tests/lib/armillary.hoon
tmux send-keys -t 0:3.0 -l '|commit %grubbery'; tmux send-keys -t 0:3.0 Enter
sleep 8; tmux capture-pane -p -t 0:3.0 | grep -v '^\s*$' | tail -6      # read <rev>
tmux send-keys -t 0:3.0 -l -- '-test /~wex/grubbery/<rev>/tests/lib/armillary ~'; tmux send-keys -t 0:3.0 Enter
sleep 20; tmux capture-pane -p -t 0:3.0 | grep -v '^\s*$' | tail -40
```

Count only the `OK`, `FAILED` and `CRASHED` lines between your own command echo and its `ok=` verdict. A commit that touches a library takes 70 to 95 seconds to print; a pane that keeps changing is working. A compile error prints `dep failed` or a trace with the file and line instead of a verdict.

**The fast loop for nexus code, once the desk exists (Task 2 step 4 onward).** Writing a file into the desk's code tree recompiles at once. Then reload the instance and read `bang`:

```bash
D=$W/grubbery/ball/apps/shell.shell/desks/armillary.desk/desk
I=$D/data/armillary.armillary_app
curl -s -b $CK -X POST --data-urlencode action=write-text --data-urlencode content@code/nex/armillary/app.hoon "$D/code/nex/armillary/app.hoon"
# answers: saved
curl -s -b $CK -X POST --data-urlencode action=reload-nexus "$I" -o /dev/null
sleep 20; curl -s -b $CK "$I?info=1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["bang"])'
# expected: None. Otherwise the bang carries the compile error with line and column.
```

A file not yet in the code tree is created first with `action=create-file&filename=<name>` POSTed to its directory URL, then written with `write-text`. The git repo is the source of truth: edit the repo file, then write it to the ship. The same loop writes `code/lib/*.hoon` to `$D/code/lib/<file>` and the page files to `$D/code/nex/armillary/<file>`.

**Reading the tree.** `GET $W/grubbery/ball/<path>?info=1` describes a node (children, `bang`, `weir`); `?raw=1` returns a JSON grub's text. The audit ring is `$I/tr/log?raw=1` and the last outcome `$I/tr/last?raw=1`: read `tr/last` whenever a write did not do what you expected.

**The stub provider.** `scripts/fake-provider.py PORT KEY` (Task 4 writes it; write it first if you need it earlier) listens on `127.0.0.1:PORT` and requires `Authorization: Bearer KEY`. The ship reaches it as `http://127.0.0.1:PORT/v1`.

## File structure

| file | responsibility |
|---|---|
| `code/bill.json`, `code/version.json`, `code/tile.json`, `code/icon.svg` | the desk manifest, the replicating version, the launcher tile |
| `code/mar/json.hoon`, `sig.hoon`, `mime.hoon`, `weir.hoon`, `http-response.hoon`, `timer-set.hoon`, `timer-rest.hoon`, `timer-wake.hoon` | kernel marcs the tree lays or the roads need, vendored verbatim from orrery's `code/mar/` |
| `code/mar/armillary/row.hoon` | the noun passthrough marc for a ledger row `[/armillary %row]` |
| `code/lib/armillary.hoon` | types, caps, JSON getters, ISO time, decimal parsing, the charge, the ledger fold, keys, providers, the catalog, accounts, settings, masking, the ring, the writer op decoders. Pure, import-free |
| `tests/lib/armillary.hoon` | unit tests for the lib, run on `~wex` |
| `code/nex/armillary/app.hoon` | the nexus: `on-load`, the writer, the binder, the request handler, the proxy |
| `code/nex/armillary/armillary.html`, `.css`, `.js` | the vendor page: Providers, Catalog, Accounts |
| `scripts/fake-provider.py` | the OpenAI-compatible stub with usage and OpenRouter-shaped pricing |
| `scripts/api-matrix.py`, `scripts/page-smoke.py` | the gates |
| `scripts/code-closure.py`, `scripts/weir-check.py` | copied from `~/software/personal/auspex/scripts/` |
| `docs/releasing.md`, `README.md`, `.gitignore` | the family docs |

## Task 1: the skeleton, the marcs, the lib and its tests

`code/bill.json` is `{"armillary.armillary_app": "/armillary/app"}`. `code/version.json` is `{"version": 1}`. `code/tile.json` has title `Armillary`, info `Sell model inference from your ship`, color `#1b2a4a`, image `/grubbery/tiles/icon/armillary`, href `/apps/armillary`. `code/icon.svg`: three concentric rings on a dark disc, hand-written, under 2 KB. `.gitignore`: `.claude/`, `.superpowers/`, `.DS_Store`, `__pycache__/`.

Marcs: copy the eight kernel marcs named in the file structure from `~/software/personal/orrery/code/mar/` unchanged. `code/mar/armillary/row.hoon` is orrery's `mar/orrery/obs.hoon` with the comment changed to name a ledger row stored as `[%1 row]`.

`code/lib/armillary.hoon`, one `|%` core, these arms with these names. Later tasks use them by name.

- Caps as constants: `max-name` 200, `max-id` 64, `max-url` 500, `max-model-id` 200, `max-providers` 200, `max-catalog` 2000, `max-keys` 20, `ring-cap` 500, `max-body` 4.194.304.
- JSON getters copied from orrery's lib: `gj` (a key of an object, or `~`), `gs` (a string, `''` when absent), `gn` (a number as `@ud`, 0 when absent or not a whole number), `gb` (a boolean, `|` when absent), `ga` (an array as a list, `~` when absent), `gsd` (a JSON number that may be negative, as `@sd`). Time: `de-iso` and `en-iso` copied from orrery (`YYYY-MM-DDTHH:MM:SSZ`); `en-time` as orrery's.
- `+en-sd |=(n=@sd json)`: a `%n` whose text is the signed decimal (`-1500` or `1500`). `+de-dec |=([t=@t scale=@ud] (unit @ud))`: a decimal string such as `0.000003` or `12` or `0` to an integer scaled by `10^scale`, truncating fraction digits beyond `scale`, `~` on any other character or a second dot. `+per-million |=(t=@t (unit @ud))` is `(de-dec t 12)`: dollars per token, OpenRouter's string, to microdollars per million tokens.
- `+charge |=([toks=@ud price=@ud] @ud)`: `ceil(toks * price / 1.000.000)`, so `(charge 1.000 3.000.000)` is 3.000 and `(charge 1 1)` is 1. `+markup-of |=([cost=@ud pct=@ud] @ud)`: `ceil(cost * pct / 100)`.
- Keys, copied from orrery's lib lines 1083 to 1133 and renamed: `secret-of`, `id-of`, `pad-left`, `hash-token`, `parse-bearer`, `key-ok`. `+$ key` is `[id=@t name=@t salt=@t hash=@t made=@da used=(unit @da)]`; `en-key-row`, `de-key` (`~` on a missing field), `en-key-public` (no salt, no hash).
- Providers: `+$ provider` is `[id=@t name=@t kind=?(%openai-compatible %openrouter) base-url=@t api-key=@t provisioning-key=@t]`. `+de-provider |=(jon=json (each provider @t))`: `%|` names the first failing field (`id: 1 to 64 bytes`, `kind: openai-compatible or openrouter`, `base_url: 1 to 500 bytes`); a blank `api_key` or `provisioning_key` is allowed (it means keep, resolved by the writer). `+en-provider-masked`: every field, the two secrets as `mask` (`''` when empty, else the last four characters behind `••••`). `+mask |=(t=@t @t)`. `+en-provider-full` for the writer's own storage.
- Catalog: `+$ model-row` is `[id=@t provider=@t upstream=@t in=@ud out=@ud cost-in=@ud cost-out=@ud enabled=? tags=(list @t)]`. `+de-catalog |=(jon=json (each (list model-row) @t))` reads an array, names the first failing field with its index (`row 3 id: 1 to 200 bytes`), refuses duplicate ids (`row 3 id: duplicate`) and over 2000 rows. `+en-catalog`. `+public-catalog |=((list model-row) json)`: the enabled rows as `[{id, provider, in, out, tags}]`. `+en-models-list |=((list model-row) json)`: OpenAI's shape, `{"object": "list", "data": [{"id", "object": "model", "owned_by": <provider>, "pricing": {"prompt": <dollars per token as a string>, "completion": ...}, "tags": [...]}]}`; the string is the microdollars-per-million figure rendered as dollars per token with twelve decimals and trailing zeros trimmed (`3.000.000` renders `0.000003`). `+find-model |=([cat=(list model-row) id=@t] (unit model-row))`, enabled rows only.
- Import: `+import-rows |=([provider=@t pct=@ud jon=json] (list model-row))`: from a `GET /models` body, every `data[].id` as a disabled row on this provider with `upstream` equal to the id, and when `pricing.prompt` and `pricing.completion` parse through `per-million`, `cost-in` and `cost-out` from them and `in` and `out` as `markup-of`; when absent, zeros. `+merge-import |=([cat=(list model-row) fresh=(list model-row)] (list model-row))`: rows whose id is already in `cat` are kept as they are, the rest appended.
- Usage: `+read-usage |=(body=@t (unit [in=@ud out=@ud]))`: `usage.prompt_tokens` and `usage.completion_tokens` (`completion_tokens` may be absent, then 0). `+read-error |=(body=@t @t)`: `error.message`, else `message`, else `''`. `+swap-model |=([jon=json upstream=@t] json)`: the object with `model` replaced and `stream` removed. `+is-stream |=(jon=json ?)`.
- Ledger: `+$ row` is `[kind=?(%credit %debit %refund) amount=@ud cost=@ud model=@t in=@ud out=@ud mode=@t rail=@t ref=@t note=@t at=@da]` (unused fields zero or blank). `+$ stored-row` is `[%1 row]`; `+read-row |=(n=* (unit row))` with the mule ladder as orrery's `read-body`. `+en-row`, `+de-row |=(jon=json (each row @t))`. `+fold-balance |=((list row) @sd)`: credits minus debits minus refunds. `+row-name |=([at=@da n=@ud] @ta)`: `<unix seconds>-<n>` as a knot.
- Accounts: `+$ account` is `[ship=@p balance=@sd made=@da seen=(unit @da) closed=?]`; `en-account`, `de-account`. `+en-account-summary |=([a=account keys=@ud] json)` for the list.
- Settings: `+starter-settings` is `{"markup_pct": 130, "min_topup": 5000000, "public_url": "", "mode": "stub", "refuse_comets": false}`; `+de-settings |=(jon=json (each settings @t))` with `+$ settings` `[markup=@ud min-topup=@ud public-url=@t mode=?(%stub %live) refuse-comets=?]`; `+en-settings`. Phase 3 adds the Stripe fields.
- The ring: `+ring-push |=([ring=json entry=json cap=@ud] json)`, newest first, trimmed to `cap`, copied from register's lib. `+trail-entry |=([op=@t ok=? why=@t ship=@t amount=@sd at=@da] json)`.
- Ops: `+de-op |=(jon=json @t)` answers `op`. Each writer op's decoder lives here and answers `(each <payload> @t)` naming the failing field: `de-op-provider` (the provider), `de-op-drop` (an `id`), `de-op-catalog` (the list), `de-op-account` (a `ship` as `@p`, parsed with `slaw %p`, refused when not a valid @p), `de-op-credit` (`ship`, `amount` above zero, `rail`, `ref`, `note`), `de-op-debit` (`ship`, `amount`, `cost`, `model`, `in`, `out`, `mode`, `ref`), `de-op-refund` (`ship`, `amount`, `ref`, `note`), `de-op-key` (`ship`, the key row from `de-key`), `de-op-drop-key` (`ship`, `id`), `de-op-touch-key` (`ship`, `id`), `de-op-settings`.

`tests/lib/armillary.hoon`, header as orrery's (`/+  *test, arm=armillary`), one arm per behaviour: `de-dec` on `0.000003` scale 12 is 3.000.000, on `12` is 12.000.000.000.000, on `0` is 0, on `1.2.3` and `abc` is `~`, on `0.0000000000005` truncates to 0; `charge` rounds up on three cases and answers 0 for 0 tokens; `markup-of 1000 130` is 1300; `fold-balance` on a credit of 100, a debit of 30 and a refund of 90 is `-20`; `en-sd` of `-20` renders `-20`; `parse-bearer` on `Bearer ab.cd`, `bearer ab.cd`, `Bearer abcd` (`~`), `Basic x` (`~`); `key-ok` true for the right secret and false for another; `de-provider` names `kind` on `{"id":"a","kind":"x"}` and accepts a row with a blank key; `en-provider-masked` never contains the key's first characters; `de-catalog` names a duplicate id and the failing row's index; `find-model` skips a disabled row; `en-models-list` renders `3.000.000` as `0.000003` and `1.500.000` as `0.0000015`; `import-rows` on a two-model OpenRouter fixture gives two disabled rows with costs and marked-up prices, and on a row without pricing gives zeros; `merge-import` keeps an existing row's prices; `read-usage` on a chat fixture and on a body with no usage (`~`); `swap-model` replaces `model` and drops `stream`; `read-row` lifts `[%1 row]` and answers `~` on a bare noun; `de-op-account` refuses `~not-a-ship` and accepts `~wex`; `ring-push` caps at the given size newest first. About 30 arms.

Run them on `~wex` with the revision pinned until every arm is OK. Then `git init`, `git add`, commit: `The desk skeleton, the marcs, the library and its tests`.

## Task 2: the nexus, the desk on `~wex`

`code/nex/armillary/app.hoon`, orrery's skeleton (`~/software/personal/orrery/code/nex/orrery/app.hoon` lines 1 to 200 for the header, `on-load`, `on-file`, `rf`, `rv`, `srv`; 487 to 550 for `read-json`, `send-json`, `send-err`; 574 to 648 for `handle-request`; 1770 for `poke-writer`; 2417 to 2510 for `identify`, `serve-mint`, `serve-clients`, `serve-drop-client`; 2561 for `serve-file`). Imports: `/<  arm  /lib/armillary.hoon`, `/&` for `icon.svg` and the three page files.

**The tree** (`on-load`), every row from spec section 10 that phase 1 uses: `%over` for `tile.json`, `link.json` (`{"name": "armillary", "description": "Sell model inference from your ship"}`), `weir.json`, `icon.svg`, the three page files; `%fall` for `main.sig`, `web.sig`, the dirs `requests`, `accounts`, `tr`, `beacon`, and the files `settings.json` (`starter-settings`), `providers.json` (`{}`), `catalog.json` (`[]`), `catalog-public.json` (`[]`), `plans.json` (`[]`), `vendor.json` (`{"ship": ""}`, phase 2 fills it), `beacon/rev` (0), `tr/last` (`{}`), `tr/log` (`[]`). Accounts live under `/accounts/<ship>/` with `account.json`, `keys.json` (`{}` keyed by id) and `ledger/<row-name>` grubs of blot `[/armillary %row]`; `lease.json` and `view.json` are phases 2 and 5.

**The weir**: poke `/sys/bowl.sig` (`read the current time and our ship`), `/sys/eyre/` (`bind /apps/armillary and answer requests, including the inference API`), `/sys/iris/` (`talk to your model providers over HTTPS. Refuse this and no request can be answered`), `/sys/behn/` (`give up on a provider that does not answer within two minutes`); peek `/sys/link/` (`find where this app is installed, so the page can address its own writer`). Every `why` says what refusing costs.

**The writer** at `/main.sig`, orrery's loop. `+apply` dispatches on `de-op` and writes `/tr/last` and a ring entry for every op, ok or refused; secrets never in the entry. Ops:

- `set-settings`: replace the whole document from `de-op-settings`.
- `set-provider`: from `de-op-provider`; when the incoming `api_key` or `provisioning_key` is blank and a row with that id exists, keep the stored one; a JSON `null` clears it (read that before decoding). Refuse over 200 providers.
- `drop-provider`: remove the row. Catalog rows on it stay, disabled by the reader (`find-model` also requires the provider to exist; do that check in the request fiber, not the lib).
- `set-catalog`: replace `catalog.json` whole and rewrite `catalog-public.json` from `public-catalog`.
- `open-account`: `/accounts/<ship>/account.json` with balance 0 and `keys.json` `{}` when absent; a no-op that answers ok when present. `<ship>` in the path is `(scot %p ship)`.
- `credit`, `debit`, `refund`: refuse when the account is missing or closed; for `credit` and `refund`, refuse `ref: already recorded` when any existing row on that account has the same `ref` (walk the ledger dir); write the row grub with `row-name` (bump `n` while the name exists) and rewrite `account.json` with the new balance (`+fold-balance` over all rows; cache it on the account row). `debit` never dedupes.
- `add-key`: refuse over 20; store the row under `keys.json[id]` with the hash, never a secret. `drop-key`: remove. `touch-key`: set `used`.
- `close-account`: `closed` true, `keys.json` emptied.
- `rebuild`: refold every account's balance from its ledger.

Beacon bump on every change, as orrery.

**The binder** at `/web.sig`, `bind-http-self` on `/apps/armillary`, one fiber per request under `/requests/<id>`.

**Identify**: the owner cookie (`authenticated` and `src` equal to `our`) is `[owner=& ship=our key=~]`; else a bearer token parsed with `parse-bearer`, whose id is looked up by walking `/accounts/*/keys.json` for a row with that id (keep a `/key-index.json` `{id: ship}` maintained by `add-key` and `drop-key` instead of the walk; add it to the tree with a `%fall` row), checked with `key-ok`, refused when the account is closed; stamp `used` through `touch-key` at most hourly as orrery does. Else 403.

**Routes**, in the order of spec section 8 and only these:

- `GET /`, the page and its two assets, owner only, `serve-file`, no-cache.
- `GET /v1/models`: key or owner; `en-models-list` over the catalog with rows whose provider exists.
- `POST /v1/chat/completions` and `POST /v1/embeddings`: key required (the owner cookie is refused 403 `an inference key is required`, so the owner's page cannot be turned into a free client). Steps 1 to 7 of spec section 5 exactly, with the messages given there. `+fetch |=(request:http (fiber ,[status=@ud body=@t]))` is calendar's `+fetch-hdr` (`~/software/personal/calendar/code/nex/calendar/app.hoon` line 1845) with the timer wire from `(nonce:io /fetch)` so two request fibers never share a wire, and `[~ %veto *]` answering status 0 with the body `the iris road is refused`. Status 0 answers 504 `{"error": {"message": "no answer from <provider name> within two minutes"}}`. The body sent upstream is `swap-model`; the headers `content-type: application/json` and `authorization: Bearer <api_key>`. The debit op carries `amount` from `charge` on both token counts, `cost` from the row's `cost_in` and `cost_out` the same way, `model` the catalog id, `mode` `proxy`, `ref` the upstream `id` field when present. Embeddings use only `in` at the row's `in` price. The answer is the upstream body verbatim with its status and `content-type: application/json`.
- Owner routes: `GET` and `PUT /api/settings` (masked on read; phase 1 has no secrets in settings yet, mask anyway through one arm so phase 3 inherits it), `GET /api/providers` (masked list), `POST /api/providers` (a new row; 409 when the id exists), `PUT /api/providers/<id>` (409 when it does not), `DELETE /api/providers/<id>`, `POST /api/providers/<id>/test` (one chat completion of `{"model": <the first enabled catalog row on it, else the body's "model">, "messages": [{"role": "user", "content": "Say ok."}], "max_tokens": 5}`; answers `{"status", "model", "text"}` where text is `choices[0].message.content` or the error), `POST /api/providers/<id>/import` (fetch `<base_url>/models`, `import-rows`, `merge-import`, `set-catalog`; answers `{"added": <n>}`), `GET` and `PUT /api/catalog` (`de-catalog`; a row whose provider does not exist is refused 400 `row <i> provider: unknown`), `GET /api/accounts?q=` (every account with its key count and balance, `q` a substring of the ship), `GET /api/accounts/<ship>` (the account, `en-key-public` for each key, the newest 100 ledger rows), `POST /api/accounts/<ship>/keys {"name"}` (opens the account when absent, mints as orrery's `serve-mint`, answers the secret once as `"secret": "<id>.<secret>"`), `DELETE /api/accounts/<ship>/keys/<kid>`, `POST /api/accounts/<ship>/credit {"amount", "note"}` (rail `owner`, `ref` `owner-<unix seconds>`), `POST /api/accounts/<ship>/refund {"amount", "note"}`, `POST /api/accounts/<ship>/close`, `GET /api/log`. `<ship>` in a route is parsed with `slaw %p` after the `~`; a bad one is 400 `ship: not an @p`. `GET /api/report` and `/api/plans` are later phases: answer 404 like any unknown route.

Every route that writes pokes the writer and answers from its own computation; every 4xx names the field as the lib does.

**Steps.** Write the file. Create the GitHub repo and push, the forge needs it: `gh repo create nisfeb/armillary --public --source=. --remote=origin --push` (if the repo exists: add the remote and push). Mirror and install on `~wex`:

```bash
curl -s -b $CK -X POST -H 'content-type: application/json' -d '{"name":"armillary","repo":"nisfeb/armillary","ref":"main"}' $W/grubbery/forge/api/add
# expected: created (409 means a previous attempt; continue)
# then every 10 s for at most 3 minutes:
curl -s -b $CK "$W/grubbery/ball/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code/version.json?raw=1"
# expected once pulled: {"version": 1}
curl -s -b $CK -X POST -H 'content-type: application/json' -d '{"name":"armillary","code":"/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code"}' $W/apps/grubbery/desks/add
# expected: created
# then every 15 s for at most 3 minutes:
curl -s -b $CK "$I?info=1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("bang:", d.get("bang")); print([c["name"] for c in d.get("children",[])])'
```

Expected `bang: None` and children including `main.sig`, `web.sig`, `accounts`, `settings.json`, `providers.json`, `catalog.json`, `beacon`, `tr`. A bang string is the compile error: fix in the repo, fast loop, until None. Then approve the ask and reload:

```bash
APP=/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app
curl -s -b $CK -X POST -H 'content-type: application/json' -d "{\"action\":\"approve-weir\",\"app\":\"$APP\",\"granted\":{\"poke\":[\"/sys/bowl.sig\",\"/sys/eyre/\",\"/sys/iris/\",\"/sys/behn/\"],\"peek\":[\"/sys/link/\"],\"make\":[]}}" $W/apps/grubbery/permits
curl -s -b $CK -X POST -H 'content-type: application/json' -d "{\"app\":\"$APP\"}" $W/apps/grubbery/permits/reload
sleep 15; curl -s -b $CK "$I?info=1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["weir"])'
```

Smoke by hand: start `scripts/fake-provider.py 3399 stub-key` (write it now from Task 4 if needed), `POST /api/providers {"id":"stub","name":"Stub","kind":"openrouter","base_url":"http://127.0.0.1:3399/v1","api_key":"stub-key"}`, `POST /api/providers/stub/import` answers `{"added": 3}`, enable one row through `PUT /api/catalog`, `POST /api/accounts/~feb/keys {"name":"test"}` answers a secret, `POST /api/accounts/~feb/credit {"amount": 1000000}`, then a chat completion with that bearer answers 200 with the stub's text and `GET /api/accounts/~feb` shows one debit. Commit: `The nexus: the tree, the writer, the owner routes and the proxy`. Push.

## Task 3: the page

`armillary.html`, `armillary.css`, `armillary.js`, orrery's shape (`~/software/personal/orrery/code/nex/orrery/orrery.{html,css,js}`: the hash router, the beacon stream through `/grubbery/api/keep/...beacon/rev`, `esc()` on every string, the fetch helpers, the settings-card save pattern). Three views, the spec's section 9 vendor half minus Payments and Report:

- **Providers** (`#providers`, the default): a table with name, kind, base URL, the masked key, a Test button that shows its last answer inline (`status · model · text`), an Import button that shows `added N`, Edit and Delete. An add form: id, name, kind (two radios), base URL, API key, provisioning key (shown when kind is openrouter). Editing shows the masked keys with the placeholder `leave blank to keep`.
- **Catalog** (`#catalog`): a table of every row: id, provider, in and out prices in dollars per million to four places (edit inline as dollars, saved as microdollars), cost in and out, margin as a percent when cost is known, enabled checkbox, tags as a comma list. A filter box over id and provider. One Save button posts the whole catalog; the page keeps the rows it received and edits in place, optimistic with a reload on error.
- **Accounts** (`#accounts`): the list (ship, balance in dollars, keys, last seen, closed) with a search box; clicking a ship opens the detail: balance, credit and refund forms (dollars, note), the keys with a revoke button and a mint form whose secret is shown once until dismissed, Close account behind a confirm, and the ledger table (at, kind, amount, model, tokens, ref).

Every amount input is dollars; the page converts. Every action is optimistic with a fallback read, and every error from the ship is shown in a status line, never an alert. Fast loop the three files, open `http://localhost:8080/apps/armillary` with the owner cookie in a browser or `page-smoke.py`, and click through: add the stub provider, import, enable a row, mint a key, credit, see the debit after a curl completion. Commit: `The vendor page: providers, catalog, accounts`.

## Task 4: the stub, the gates, the docs, version 2

`scripts/fake-provider.py PORT KEY`: `http.server`, no dependencies. `GET /v1/models` answers `{"data": [{"id": "stub/alpha", "pricing": {"prompt": "0.000003", "completion": "0.000015"}}, {"id": "stub/beta", "pricing": {"prompt": "0.0000015", "completion": "0.000006"}}, {"id": "stub/free"}]}`. `POST /v1/chat/completions` requires the bearer (else 401 `{"error": {"message": "bad key"}}`), refuses `stream` true with 400, answers `{"id": "stub-<n>", "model": <model>, "choices": [{"message": {"role": "assistant", "content": "ok: <the last user message>"}}], "usage": {"prompt_tokens": <7 + the word count of the last user message>, "completion_tokens": 5}}`; the model `stub/error` answers 500 `{"error": {"message": "stub failure"}}`; the model `stub/slow` sleeps 130 seconds (used once, to see the 504). `POST /v1/embeddings` answers `{"data": [{"embedding": [0.1, 0.2]}], "usage": {"prompt_tokens": 9}}`. `GET /stub/requests` answers the count and the last body seen, so the gate can assert the upstream saw `model` swapped and `stream` absent.

`scripts/api-matrix.py HOST JAR PROVIDER_PORT`, orrery's skeleton. Starts nothing: the runner starts the stub first. Safe to rerun: it deletes the accounts and providers it made (add `DELETE /api/accounts/<ship>` for the owner, a hard delete of the account dir, used by the gate only; document it in the API table as owner only). Checks: settings round-trip; providers: add, masked read never contains `stub-key`, edit with a blank key keeps it (a later test call still works), 409 on a duplicate, unknown id on PUT is 409; import adds 3 and a second import adds 0; catalog: PUT with a row on an unknown provider is 400 naming the row, a duplicate id is 400, enabling `stub/alpha` and `stub/beta`; `GET /v1/models` without a key is 403, with the owner cookie lists two rows with pricing `0.000003` and `0.000015` on alpha; accounts: mint for `~feb` opens the account, a second key, the 21st is 409, `GET /api/accounts` lists it with 2 keys; a completion with no credit is 402; credit 1.000.000 (`$1`), a completion with `stream: true` is 400, with `stub/free` is 404 (disabled), with `stub/nope` is 404, with `stub/error` passes the 500 and its message through and writes no debit, with `stub/alpha` and the message `hello there world` is 200 with content `ok: hello there world` and the ledger shows one debit of `charge(10, in) + charge(5, out)` microdollars with `cost` computed from the costs (the markup is 130, so amount is `ceil(10 * 3900000 / 1e6) + ceil(5 * 19500000 / 1e6)` = 39 + 98 = 137), the stub saw `model` equal to `stub/alpha` and no `stream`; the owner cookie on the completion route is 403; embeddings charge 9 tokens at `in` only; a revoked key is 403 and the other still works; refund with a repeated ref is 409 `ref: already recorded`; balance after everything equals the fold; close makes the key 403 and a mint 409; `GET /api/log` holds an entry per op and no `stub-key` anywhere in it; `tr/last` reads ok after the last op. Prints `ALL OK`.

`scripts/page-smoke.py HOST JAR`: orrery's, with the three asset names and the view ids changed; no node render tests.

Copy `code-closure.py` and `weir-check.py` from `~/software/personal/auspex/scripts/`; both clean. `docs/releasing.md`: orrery's with `orrery` replaced by `armillary` throughout and section 8 rewritten as this desk's checklist (version bump, closure, weir-check, unit tests, api-matrix twice, page-smoke, push, forge pull, bang null). `README.md`, the family shape: what it is in one line, Try it (the curl sequence from the Task 2 smoke, against `~wex`), the HTTP API as a table, The repository, the family links, `© nisfeb`. Bump `code/version.json` to 2, commit `The stub, the gates, the docs, version 2`, push, then on `~wex` `POST $W/grubbery/forge/api/run {"repo":"armillary.git_repo","command":"pull"}`; within a minute the desk's root `version.json` reads 2 and the bang is null; run the gate once more against the code the forge delivered.

## Done when

Unit tests green with the revision pinned (report the OK count from the run), `api-matrix.py` green twice, `page-smoke.py` green, the page clicked through, the desk at version 2 synced through the forge with a null bang, `main` pushed. Report those facts with the numbers you saw and the wex desk revision. Do not touch `~ricsul-bilwyt` or any ship but `~wex`. Any wait over 2 minutes is a STOP with a report of what is on screen. Commit before any verification step.
