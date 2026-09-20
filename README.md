# armillary

Armillary sells model inference from your own Urbit ship: you hold the provider keys, your customers hold prepaid balances, and every request is priced, forwarded and debited on the ship.

The name is the instrument: nested rings around one centre, each turning at its own rate, read together to say where everything stands.

## What it does

You connect the upstream providers you already pay for, import their model lists, mark up what they charge and enable the models you want to sell. A customer ship gets an account, a prepaid balance and an inference key. It points any OpenAI-compatible client at `https://<your ship>/apps/armillary/v1` and calls `/chat/completions` or `/embeddings` with that key. Your ship forwards the request to the right provider with your key, reads the token counts the provider reports, charges the customer's balance at your prices, and answers the provider's response unchanged.

Every amount on the ship is an integer number of microdollars, one dollar being 1,000,000, and a charge always rounds up. An account's ledger is append-only and the balance is the fold over it, so the cached number on the account row can always be rebuilt from the rows that are the truth.

This is phase 4: the vendor half, the proxy path, the account channel over ames, and both money rails, the card through Stripe and bitcoin through BTCPay Server. Direct provider leases are phase 5.

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
| `GET` and `PUT /api/settings` | markup, minimum top-up, public URL, mode, `refuse_comets`, the Stripe and BTCPay fields, `lease_provider` and how many minutes a checkout on each rail stays open; every secret masked on read, a blank field keeps the stored one and a JSON `null` clears it |
| `GET /api/providers` | every provider, both secrets masked |
| `POST /api/providers` | a new row; 409 when the id is taken |
| `PUT /api/providers/<id>` | an edit; 409 when the id is unknown. A blank secret keeps the stored one, a JSON `null` clears it |
| `DELETE /api/providers/<id>` | drop the connection. Its catalog rows stay and stop answering |
| `POST /api/providers/<id>/test` | one tiny chat completion; answers `{"status", "model", "text"}` |
| `POST /api/providers/<id>/import` | pull `GET <base_url>/models` and fold the new ids in as disabled rows; answers `{"added": <n>}` |
| `GET` and `PUT /api/catalog` | the whole catalog, replaced whole. A row on an unknown provider is 400 `row <i> provider: unknown` |
| `GET /api/plans` | every plan, by id. On a customer ship this is the vendor's list instead, read live |
| `POST /api/plans` | a new plan; 409 when the id is taken |
| `PUT /api/plans/<id>` | an edit; 409 when the id is unknown. A blank `stripe_price` keeps the stored one |
| `DELETE /api/plans/<id>` | drop it; 409 while an open subscription names it |
| `POST /api/plans/<id>/stripe` | make the Product and the Price on Stripe and store the Price id. 400 `stripe_key: not set`, 400 on a top-up plan, which needs none, 502 with Stripe's own message when it refuses |
| `GET /api/accounts?q=` | every account with its balance and key count; `q` is a substring of the ship |
| `GET /api/accounts/<ship>` | the account, its keys with no salt and no hash, and the newest 100 ledger rows |
| `POST /api/accounts/<ship>/keys` | `{"name"}`: mint. Opens the account when there is none. The secret is answered once |
| `DELETE /api/accounts/<ship>/keys/<kid>` | revoke |
| `POST /api/accounts/<ship>/credit` and `/refund` | `{"amount", "note"}`: owner rows in the ledger. A repeated `ref` is 409 `ref: already recorded` |
| `POST /api/accounts/<ship>/close` | revoke every key, delete the lease key upstream, keep the ledger |
| `POST /api/accounts/<ship>/reconcile` | read this account's lease from the provider, charge what it spent and move its cap; answers `{"ship", "ok", "why"}` |
| `DELETE /api/accounts/<ship>/lease` | delete the lease key upstream and drop the row |
| `POST /api/accounts/<ship>/clear-subscription` | forget a subscription Stripe says is gone; 409 when there is none |
| `DELETE /api/accounts/<ship>` | delete the account, its keys and its whole ledger. Owner only, and irreversible: this exists so the gate can leave the ship as it found it, and nothing on the page calls it |
| `GET /api/report?days=30` | what the vendor made over a window: credits by rail, charged, cost, margin, refunds, requests, tokens, lease spend, accounts and the top ten models |
| `POST /api/tick` | prod the housekeeping fiber: reconcile every lease, expire stale checkouts, fold old ledger rows. It runs itself every ten minutes; this is for when ten minutes is too long to wait |
| `GET /api/log` | the audit ring, the last 500 writer outcomes, newest first. No secret ever reaches it |

### Public, no cookie

| route | answers |
|---|---|
| `POST /hooks/stripe` | Stripe's webhook. The body is trusted for the event type and the object id and nothing else; the object is read back from Stripe before anything is credited. In live mode a bad, missing or uncheckable signature is 400; everything else answers 200, including a failed read. It handles the two completions, the async failure, the paid invoice, the deleted subscription and both dispute events |
| `POST /hooks/btcpay` | BTCPay's webhook. The body is trusted for the event type and the invoice id and nothing else; the invoice is read back from BTCPay before anything is credited. A bad or missing signature is 401 when the webhook secret is set; everything else answers 200, including a failed read |
| `GET /pay/return?ship&sid` | where Stripe sends the browser. It verifies the session itself, so a payment lands even when the webhook does not. `&cancelled=1` says so instead |
| `GET /pay/return?ship&nonce&rail=btcpay` | where BTCPay sends the browser. The nonce finds the checkout row, the row holds the invoice id, and the invoice is read back the same way |
| `GET` and `POST /pay/stub` | the stub rail's own page, in stub mode only |

### On a customer ship, owner cookie

These are what a client on the customer's own ship calls, over the cookie it already has. `docs/channel.md` is how the channel underneath them works.

| route | answers |
|---|---|
| `GET /api/account` | the last view this ship read from its vendor, plus `vendor`, `self` and `stale` (seconds since the read). `?fresh=1` peeks the vendor first and waits up to thirty seconds |
| `PUT /api/vendor` | `{"ship"}`: who this ship buys from, and a `hello` to open the account there. `{"ship": ""}` clears it |
| `GET /api/keys` | the inference keys this ship holds, never their secrets |
| `POST /api/keys` | `{"name"}`: ask the vendor for a key and wait for it. Answers `{"id", "name", "secret"}` once, or 202 `{"pending": true, "nonce"}` after thirty seconds, which is not a failure |
| `DELETE /api/keys/<id>` | tell the vendor to revoke it and forget it here at once |
| `POST /api/checkout` | `{"rail", "plan" or "amount"}`: `rail` is `stripe` for a card or `btcpay` for bitcoin. Opens a checkout and answers `{"url"}`, or 202 with the nonce. 502 with the vendor's reason when the vendor refused it. A subscription plan is card only |
| `POST /api/cancel-subscription` | ask the vendor to stop the subscription renewing; 202, and the view says when Stripe confirms |
| `GET /api/inference` | everything a client needs: `{"mode", "base_url", "key", "models"}`. `lease` mode with the provider's own key when this ship holds a lease that can still spend, `proxy` mode with the vendor's base URL and the newest inference key otherwise. 404 `no key yet` when this ship holds neither |
| `GET /api/catalog` | the vendor's public catalog with prices, read live; 502 `vendor unreachable` when the vendor does not answer. On a ship that is nobody's customer this is the owner's own catalog instead |
| `POST /api/lease` | ask the vendor for a lease and wait for it. Answers the lease, or 404 `no lease for this account` when the vendor offers none, 502 with the vendor's reason when the provider refused, 202 with the nonce after thirty seconds |
| `DELETE /api/lease` | give it back: this ship forgets the key at once and the vendor deletes it upstream. `docs/leases.md` is how a lease works |

### Being a customer

A customer is a ship, and its account id is its `@p`. Point it at a vendor and it opens the account itself:

```bash
curl -s -b jar -H 'content-type: application/json' -X PUT "$API/vendor" -d '{"ship": "~wex"}'
curl -s -b jar "$API/account?fresh=1"
curl -s -b jar -H 'content-type: application/json' -X POST "$API/keys" -d '{"name": "phone"}'
curl -s -b jar "$API/inference"
```

The ops go over ames from this ship's armillary desk into the vendor's inbox, signed by ames, so the source ship is the identity and no password or claim token exists. The answers come back in an account view on the vendor that this ship alone may peek, through a usergroup the vendor makes for it. A minted key's secret crosses that way once and is cleared as soon as this ship says it has it.

Topping up opens a checkout with the vendor and answers a URL to open in a browser. In stub mode that URL is the vendor's own page with one button and no money moves, which is how the whole loop is proved without a rail. In live mode it is a Stripe Checkout Session on the card rail or a BTCPay invoice on the bitcoin one, and `docs/payments.md` is how both halves work.

The Stripe key is a restricted key, `rk_`, with write on Checkout Sessions, Customers, Products, Prices, Subscriptions and the Billing Portal and read on Invoices and Disputes, and live mode will not save without the endpoint's signing secret beside it.

A ship can be its own customer: point `vendor.json` at itself and the page shows both halves with a note saying so. That is what `scripts/ship-matrix.py` runs against with two arguments.

Live updates come from the instance's change beacon, streamed through grubbery's keep-SSE at `/grubbery/api/keep/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/beacon/rev`. It moves once per write that changed something, and a client that sees it move refetches what it shows. A write answers before the writer applies it, so a read right after one may still be a moment behind.

### The repository

- `code/` is the desk: the nexus at `code/nex/armillary/app.hoon` with the page beside it, the model in `code/lib/armillary.hoon` (pure, import-free, unit-tested), the marcs under `code/mar`. `code/version.json` is what replicates.
- `code/lib/armillary-http.hoon`, `code/lib/armillary-stripe.hoon` and `code/lib/armillary-btcpay.hoon` are the two rails' pure half: percent encoding, form bodies, HMAC-SHA256, decimal dollars, and each rail's request builders and readers. Import-free like the model, so each one builds in both places, which is why the small encoders appear in all three.
- `tests/lib/armillary.hoon`, `tests/lib/armillary-http.hoon` and `tests/lib/armillary-stripe.hoon` are the unit suites, run with `-test` on a dev ship.
- `scripts/` holds the gates, all against a dev ship: `api-matrix.py` (the story above, over HTTP), `ship-matrix.py` (the account channel and both rails, one ship or two), `page-smoke.py`, `fake-provider.py` (the OpenAI-compatible stub), `fake-stripe.py` (the Stripe stub) and `fake-btcpay.py` (the BTCPay stub), `code-closure.py` and `weir-check.py`. `live-matrix.py` is run by hand against Stripe test mode and a real BTCPay store.
- `docs/`: the design at `docs/superpowers/specs/2026-09-19-armillary-design.md` and the plans under `docs/superpowers/plans`; `docs/channel.md` for the account channel over ames; `docs/payments.md` for both money rails; `docs/leases.md` for the lease path; `docs/releasing.md` for how a release reaches ricsul and its subscribers.
- Family: [lattice](https://github.com/nisfeb/lattice), [auspex](https://github.com/nisfeb/auspex), [calendar](https://github.com/nisfeb/calendar), [orrery](https://github.com/nisfeb/orrery), [register](https://github.com/nisfeb/register), installed from `~ricsul-bilwyt` the same way.

© nisfeb
