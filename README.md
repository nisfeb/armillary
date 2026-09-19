# armillary

Armillary sells model inference from your own Urbit ship: you hold the provider keys, your customers hold prepaid balances, and every request is priced, forwarded and debited on the ship.

The name is the instrument: nested rings around one centre, each turning at its own rate, read together to say where everything stands.

## What it does

You connect the upstream providers you already pay for, import their model lists, mark up what they charge and enable the models you want to sell. A customer ship gets an account, a prepaid balance and an inference key. It points any OpenAI-compatible client at `https://<your ship>/apps/armillary/v1` and calls `/chat/completions` or `/embeddings` with that key. Your ship forwards the request to the right provider with your key, reads the token counts the provider reports, charges the customer's balance at your prices, and answers the provider's response unchanged.

Every amount on the ship is an integer number of microdollars, one dollar being 1,000,000, and a charge always rounds up. An account's ledger is append-only and the balance is the fold over it, so the cached number on the account row can always be rebuilt from the rows that are the truth.

This is phase 1: the vendor half, the proxy path, and a stub provider to prove it against. Accounts over ames, Stripe and BTCPay payments, and direct provider leases are phases 2 to 5.

## Try it

Everything below talks to the HTTP API with the ship's owner cookie. Log in once and keep the cookie jar.

```bash
SHIP=http://localhost:8080          # your ship's web address
curl -s -c jar -X POST -d "password=$CODE" $SHIP/~/login    # $CODE is what +code prints in the dojo
API=$SHIP/apps/armillary/api
post() { curl -s -b jar -H 'content-type: application/json' -X POST "$API/$1" -d "$2"; echo; }
```

Start the stub provider in another terminal, so there is something to sell:

```bash
python3 scripts/fake-provider.py 3399 stub-key
```

### Connect a provider

```bash
post providers '{"id": "stub", "name": "Stub", "kind": "openrouter",
                 "base_url": "http://127.0.0.1:3399/v1", "api_key": "stub-key"}'
```

The key never comes back out. Every read route answers it masked, and it never reaches the audit ring.

### Import its models and price them

```bash
post providers/stub/import ''          # answers {"added": 3}
```

Import fills `cost_in` and `cost_out` from the provider's own pricing and sets `in` and `out` to those times the markup in settings, 130 percent by default. Every imported row lands disabled. Enable what you want to sell by putting the whole catalog back:

```bash
curl -s -b jar -H 'content-type: application/json' -X PUT "$API/catalog" -d '[
  {"id": "stub/alpha", "provider": "stub", "in": 3900000, "out": 19500000,
   "cost_in": 3000000, "cost_out": 15000000, "enabled": true, "tags": ["zdr"]}
]'
```

### Open an account and mint a key

```bash
post 'accounts/~feb/keys' '{"name": "test"}'      # answers {"secret": "<id>.<secret>"} once
post 'accounts/~feb/credit' '{"amount": 1000000, "note": "first dollar"}'
```

The secret is answered once and stored only as a salted hash. Minting the first key opens the account.

### Spend it

```bash
curl -s -H 'content-type: application/json' \
     -H "authorization: Bearer $SECRET" \
     -X POST "$SHIP/apps/armillary/v1/chat/completions" \
     -d '{"model": "stub/alpha", "messages": [{"role": "user", "content": "hello there world"}]}'
```

The answer is the provider's body, verbatim, with its own status. Read the account back and the ledger holds one debit:

```bash
curl -s -b jar "$API/accounts/~feb"
```

Ten prompt tokens at 3.90 dollars per million and five completion tokens at 19.50 give 39 plus 98, so 137 microdollars, against a cost of 105. The balance is 999,863.

## The HTTP API

Errors are always `{"error": {"message": "<text>"}}`, OpenAI's shape, and a 4xx names the field that failed the way the library names it.

### Inference key

| route | answers |
|---|---|
| `GET /v1/models` | the enabled catalog in OpenAI list shape, each row with `pricing` as dollars per token and its `tags`. The owner cookie may read it too |
| `POST /v1/chat/completions` | the proxy. A key is required: the owner cookie is refused, so the vendor's own page cannot be turned into a free client |
| `POST /v1/embeddings` | the same, charged on input tokens only |

Refusals on the proxy: 403 with no valid key, 404 `model: not offered`, 402 `balance: empty`, 400 `stream: not supported on the proxy; take a lease`, 413 over 4 MB, 504 when the provider does not answer within two minutes. An upstream error passes through with its own status and body.

### Owner cookie

| route | answers |
|---|---|
| `GET` and `PUT /api/settings` | markup, minimum top-up, public URL, mode, `refuse_comets`; secrets masked on read |
| `GET /api/providers` | every provider, both secrets masked |
| `POST /api/providers` | a new row; 409 when the id is taken |
| `PUT /api/providers/<id>` | an edit; 409 when the id is unknown. A blank secret keeps the stored one, a JSON `null` clears it |
| `DELETE /api/providers/<id>` | drop the connection. Its catalog rows stay and stop answering |
| `POST /api/providers/<id>/test` | one tiny chat completion; answers `{"status", "model", "text"}` |
| `POST /api/providers/<id>/import` | pull `GET <base_url>/models` and fold the new ids in as disabled rows; answers `{"added": <n>}` |
| `GET` and `PUT /api/catalog` | the whole catalog, replaced whole. A row on an unknown provider is 400 `row <i> provider: unknown` |
| `GET /api/accounts?q=` | every account with its balance and key count; `q` is a substring of the ship |
| `GET /api/accounts/<ship>` | the account, its keys with no salt and no hash, and the newest 100 ledger rows |
| `POST /api/accounts/<ship>/keys` | `{"name"}`: mint. Opens the account when there is none. The secret is answered once |
| `DELETE /api/accounts/<ship>/keys/<kid>` | revoke |
| `POST /api/accounts/<ship>/credit` and `/refund` | `{"amount", "note"}`: owner rows in the ledger. A repeated `ref` is 409 `ref: already recorded` |
| `POST /api/accounts/<ship>/close` | revoke every key, keep the ledger |
| `DELETE /api/accounts/<ship>` | delete the account, its keys and its whole ledger. Owner only, and irreversible: this exists so the gate can leave the ship as it found it, and nothing on the page calls it |
| `GET /api/log` | the audit ring, the last 500 writer outcomes, newest first. No secret ever reaches it |

Live updates come from the instance's change beacon, streamed through grubbery's keep-SSE at `/grubbery/api/keep/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/beacon/rev`. It moves once per write that changed something, and a client that sees it move refetches what it shows. A write answers before the writer applies it, so a read right after one may still be a moment behind.

### The repository

- `code/` is the desk: the nexus at `code/nex/armillary/app.hoon` with the page beside it, the model in `code/lib/armillary.hoon` (pure, import-free, unit-tested), the marcs under `code/mar`. `code/version.json` is what replicates.
- `tests/lib/armillary.hoon` is the unit suite for the model, run with `-test` on a dev ship.
- `scripts/` holds the gates, all against a dev ship: `api-matrix.py` (the story above, over HTTP), `page-smoke.py`, `fake-provider.py` (the OpenAI-compatible stub they run against), `code-closure.py` and `weir-check.py`.
- `docs/`: the design at `docs/superpowers/specs/2026-09-19-armillary-design.md` and the plans under `docs/superpowers/plans`; `docs/releasing.md` for how a release reaches ricsul and its subscribers.
- Family: [lattice](https://github.com/nisfeb/lattice), [auspex](https://github.com/nisfeb/auspex), [calendar](https://github.com/nisfeb/calendar), [orrery](https://github.com/nisfeb/orrery), [register](https://github.com/nisfeb/register), installed from `~ricsul-bilwyt` the same way.

© nisfeb
