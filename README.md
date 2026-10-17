# armillary

Armillary sells model inference from your own Urbit ship: you hold the provider keys, your customers hold prepaid balances, and every request is priced, forwarded and debited on the ship.

The name is the instrument: nested rings around one centre, each turning at its own rate, read together to say where everything stands.

## What it does

You connect the upstream providers you already pay for, import their model lists, mark up what they charge and enable the models you want to sell. A customer ship gets an account, a prepaid balance and an inference key. It points any OpenAI-compatible client at `https://<your ship>/apps/armillary/v1` and calls `/chat/completions` or `/embeddings` with that key. Your ship forwards the request to the right provider with your key, reads the token counts the provider reports, charges the customer's balance at your prices, and answers the provider's response unchanged.

Every amount on the ship is an integer number of microdollars, one dollar being 1,000,000, and a charge always rounds up. An account's ledger is append-only and the balance is the fold over it, so the cached number on the account row can always be rebuilt from the rows that are the truth.

It has the vendor half, the proxy, direct provider leases, the account channel over ames, and both money rails: the card through Stripe and bitcoin through BTCPay Server.

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
| `POST /v1/chat/completions` | the proxy. A key is required: the owner cookie is refused, so the vendor's own page cannot be turned into a free client. On an OpenRouter provider the request asks for `usage.include`, and the charge is the `usage.cost` OpenRouter reports times the markup, which counts what token prices miss (cache writes, reasoning, a price changed since the import); token counts times the catalog's prices only when no cost comes back |
| `POST /v1/embeddings` | the same, charged on input tokens only |
| `POST /v1/audio/transcriptions` | speech to text, OpenRouter's JSON shape: `{"model", "input_audio": {"data": <base64 audio>, "format": "wav" or "mp3", "flac", "m4a", "ogg", "webm", "aac"}}`, with `language` and the rest passed through. Only a model tagged `transcription`, on an OpenRouter provider. Charged at the cost OpenRouter reports in `usage.cost` times the markup, since a transcription model may be priced per second or per token; the ledger keeps its token counts. The body may be up to 16 MB, since the audio rides in base64. On a free call (`own_free`, version 34) the provider may be `openai-compatible` too: the ship decodes the audio and sends OpenAI's multipart form (`model`, `file`, `response_format=json`, and `language` or `prompt` when given), which OpenAI, Groq, whisper.cpp's server and speaches all read; audio that is not base64 is 400 |
| `POST /alpha/decisions` | OpenRouter's decisions route (version 34): `{"model", "state", "questions", "provider"}`. The model must be the vendor's suggested `decision` tier, else 404 naming it, and 404 `decisions: not offered` when that tier is empty or nothing can run it. When the tier names a chat model the catalog sells, on any provider, the ship asks that model through its own provider in one chat completion for the answers as JSON and answers in the decisions shape, `{"id", "answers", "usage": {"input_tokens", "output_tokens"}}` (version 35). That is how a ship running its own open model has a decision model. The ship waits ten minutes for a chat model's answer and two for a decisions model's. A decision tier that names neither a chat model the catalog sells nor anything an OpenRouter provider could run is refused when it is saved. A reply that does not answer every question in the right shape (a probability from 0 to 1 for a noul question, one of the options for a choice) is 502 and charges nothing, and the charge is the proxy's: OpenRouter's cost at the markup, else tokens at the catalog's prices. The answers are the model's own stated probabilities, less calibrated than Jev's, and a chat model takes longer than Jev's half second. Any other name is a decisions model and is passed through to the lease provider, else an OpenRouter provider. Charged the `usage.cost` OpenRouter reports times the markup; an answer with no cost is 502 and charges nothing. An app finds it from its base URL by turning a trailing `/v1` into `/alpha/decisions`, which gives OpenRouter's own route under a lease and this one under the proxy |

Refusals on the proxy: 403 with no valid key, 404 `model: not offered`, 402 `balance: empty`, 402 `balance: in use by calls in flight` or `balance: held by your lease; call through it` (version 36, below), 400 `stream: not supported on the proxy; take a lease`, 400 for a transcription model on the chat or embeddings route and for any other model on the transcription route, 400 for a transcription model on a provider that is not OpenRouter (except on a free call, below), 413 over 4 MB (16 MB on the transcription route), 504 when the provider does not answer within ten minutes. An upstream error passes through with its own status and body.

### Owner cookie

| route | answers |
|---|---|
| `GET` and `PUT /api/settings` | markup, minimum top-up, public URL, mode, `refuse_comets`, the Stripe and BTCPay fields, `lease_provider`, how many minutes a checkout on each rail stays open, `own_free` (version 33: this ship's own keys are not charged when it is its own customer), and `stub_open` (version 33: stub mode credits other ships too, for a test rig only); every secret masked on read, a blank field keeps the stored one and a JSON `null` clears it |
| `GET /api/providers` | every provider, both secrets masked |
| `POST /api/providers` | a new row; 409 when the id is taken |
| `PUT /api/providers/<id>` | an edit; 409 when the id is unknown. A blank secret keeps the stored one, a JSON `null` clears it |
| `DELETE /api/providers/<id>` | drop the connection. Its catalog rows stay and stop answering |
| `POST /api/providers/<id>/test` | one tiny chat completion; answers `{"status", "model", "text"}` |
| `POST /api/providers/<id>/import` | pull `GET <base_url>/models` and fold the new ids in as disabled rows, a model id another provider's row already holds coming in as `<provider id>/<model id>` (version 33); on an OpenRouter provider also pull `<base_url>/models?output_modalities=transcription`, which its default listing leaves out, and tag those rows `transcription` (their prices are OpenRouter's own units, per second for some and per token for others, and are shown, not charged); on any provider, a model whose id says `whisper` or `transcribe` is tagged `transcription` too (version 35), since a provider that is not OpenRouter lists its speech models with its chat models and marks nothing, and any other speech model can be tagged by hand in the catalog's Tags field; answers `{"added", "zdr", "transcription"}` |
| `GET` and `PUT /api/catalog` | the whole catalog, replaced whole. A row on an unknown provider is 400 `row <i> provider: unknown` |
| `GET` and `PUT /api/suggested` | the AI this vendor drives for its customers: `{"rev", "tiers", "features", "models"}`. `tiers` names a model for `frontier`, `decision`, `zdr`, `private` and `transcription`, the last a speech to text model the catalog sells, which rides in `models` under `transcription` and onto which no feature may map; `features` names a tier for each feature (`catch_up`, `assistant`, `decision`, `dictation`, `orrery_generator`, `orrery_mail`, `orrery_chat`, `orrery_telegram`, `orrery_read`, `orrery_decider`, `orrery_browsing`, or a client's own name); `models` is the result an app reads, feature to model through its tier, with `default` the frontier model, which is what an app runs a feature left unmapped on. Two features are exceptions. `orrery_browsing` reads pages the owner never chose to send anywhere, so it may only be on the `zdr` tier (any other is 400), and left unmapped it takes the zdr model rather than `default`. `dictation` left unmapped is not in `models`, and Talon then runs it on the customer's own assistant model rather than on `default`. PUT `{"tiers", "features"}` replaces both; a blank drops an entry, and only the features naming a tier count toward the limit of 32; a tier model the catalog does not sell is 400, except the decision tier, which names a model for the decisions API; a feature on a tier with no model is 400. The revision moves only on a change, and every account's view is written again, so each customer ship has it within five minutes |
| `GET` and `PUT /api/brave` | the vendor's Brave Search key, which never leaves this ship: GET answers `key_set`, an optional `url` (blank is Brave's own), `cost`, what one search costs this vendor in microdollars (Brave's list price of 5000, $5 a thousand, until set), and `searches`, each account's searches by month. PUT `{"key"}` sets it, a JSON null removes it; `{"cost"}` sets the cost, and each field left out is kept |
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
| `DELETE /api/accounts/<ship>/lease` | reconcile the lease, so what the key spent since the last tick is charged, then delete the key upstream and drop the row |
| `POST /api/accounts/<ship>/clear-subscription` | forget a subscription Stripe says is gone; 409 when there is none |
| `DELETE /api/accounts/<ship>` | delete the account whole: its Stripe Customer, open sessions and invoices, lease key, directory, key-index entries, usergroup and ring rows. Owner only, and irreversible: the gate's broom, and nothing on the page calls it. `docs/payments.md` |
| `GET /api/refunds-due` | bitcoin payments that landed on accounts being deleted, for the owner to refund by hand |
| `POST /api/refunds-due/done` | `{"id"}`: one of them is refunded |
| `GET /api/report?days=30` | what the vendor made over a window: credits by rail, charged, cost, margin, refunds, requests, tokens, lease spend, accounts and the top ten models |
| `POST /api/tick` | prod the housekeeping fiber: give every paying account without a lease one (version 19, when a lease provider is set), reconcile every lease, expire stale checkouts, fold old ledger rows. It runs itself every ten minutes; this is for when ten minutes is too long to wait, and it also retries a mint that failed |
| `GET /api/log` | the audit ring, the last 500 writer outcomes, newest first. No secret ever reaches it |

### Public, no cookie

`GET /brave/res/v1/web/search` and `GET /brave/res/v1/local/place_search`, with the query Brave takes, forward a customer's search to Brave on the vendor's key and answer Brave's own body. The customer sends its armillary inference key as `Authorization: Bearer` or as Brave's own `X-Subscription-Token`, so Talon's web search and Orrery's place lookups only change their address. No other Brave path passes. A customer needs credit (402 `balance: empty` otherwise), and each search Brave answers is charged at the vendor's `cost` times the markup, as a debit on the ledger with model `brave/search` or `brave/place`, and counted on the account. The owner's cookie searches free.

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
| `GET /api/account` | the last view this ship read from its vendor, plus `vendor`, `self`, `stale` (seconds since the read) and `fetch_ms` (how long that read took). `?fresh=1` peeks the vendor first and waits up to thirty seconds |
| `PUT /api/vendor` | `{"ship"}`: who this ship buys from, and a `hello` to open the account there. `{"ship": ""}` clears it |
| `GET /api/keys` | the inference keys this ship holds, never their secrets |
| `POST /api/keys` | `{"name"}`: ask the vendor for a key and wait for it. Answers `{"id", "name", "secret"}` once, or 202 `{"pending": true, "nonce"}` after thirty seconds, which is not a failure |
| `DELETE /api/keys/<id>` | tell the vendor to revoke it and forget it here at once |
| `POST /api/checkout` | `{"rail", "plan" or "amount"}`: `rail` is `stripe` for a card or `btcpay` for bitcoin. Opens a checkout and answers `{"url"}`, or 202 with the nonce. 502 with the vendor's reason when the vendor refused it. A subscription plan is card only. `"wait": false` answers 202 `{"pending": true, "nonce"}` at once, for a client that follows the phase route below instead |
| `GET /api/checkout/<nonce>` | how far that checkout has got: `{"phase"}`, one of `placing` (not queued yet), `queued` (on this ship, not sent), `sent` (sent to the vendor, or its send timed out) and `answered`, which adds the vendor's `status`, `url` and `note`. `?nudge=1` wakes the client fiber, which the page asks every third second |
| `POST /api/checkout/<nonce>/cancel` | ask the vendor to cancel a `pending` checkout: its Stripe session expires or its BTCPay invoice goes Invalid, and the row turns `cancelled` with no url. Waits up to thirty seconds and answers `{"status", "note"}`; a payment that landed first keeps the row with a `not cancelled: ...` note. 404 for an unknown checkout, 409 for one not pending. `"wait": false` answers 202 at once. `docs/payments.md` |
| `POST /api/cancel-subscription` | ask the vendor to stop the subscription renewing; 202, and the view says when Stripe confirms |
| `POST /api/delete-account` | delete this ship's account on the vendor, record and data both, and forget the vendor here. 200 `deleted`, 202 `queued` with the nonce after thirty seconds, 409 `vendor: not set`, 502 with the vendor's reason and nothing deleted, such as `balance: below zero; top up to settle it, then delete`. A queued delete that the vendor later refuses puts the vendor back here; one queued for a vendor that is named again is dropped; one unanswered for a day is given up. `docs/channel.md` |
| `GET /api/inference` | everything a client needs: `{"mode", "base_url", "key", "models", "suggested", "search", "free"}`, where `free` (version 34) is true when this ship is its own vendor with `own_free` on, so its calls cost nothing and an app should not wait on a balance; where `suggested` is the vendor's `{"rev", "tiers", "features", "models"}` (rev 0 and nothing before any arrive) and `search` is `{"url", "key"}`, the vendor's Brave search and this ship's newest inference key, or `{}` while it holds none or the vendor has no Brave key (each view says which, as `search_offered`, version 20). `lease` mode with the provider's own key when this ship holds a lease that can still spend, `proxy` mode with the vendor's base URL and the newest inference key otherwise. 404 `no key yet` when this ship holds neither |
| `GET /api/catalog` | the vendor's public catalog with prices, read live; 502 `vendor unreachable` when the vendor does not answer. On a ship that is nobody's customer this is the owner's own catalog instead |
| `POST /api/lease` | ask the vendor for a lease and wait for it. Answers the lease, or 404 `no lease for this account` when the vendor offers none, 502 with the vendor's reason when the provider refused, 202 with the nonce after thirty seconds |
| `DELETE /api/lease` | give it back: this ship forgets the key at once and the vendor deletes it upstream, and gives no other until this ship asks with `POST /api/lease`. `docs/leases.md` is how a lease works |

### Being a customer

A customer is a ship, and its account id is its `@p`. Point it at a vendor and it opens the account itself:

```bash
curl -s -b jar -H 'content-type: application/json' -X PUT "$API/vendor" -d '{"ship": "~wex"}'
curl -s -b jar "$API/account?fresh=1"
curl -s -b jar -H 'content-type: application/json' -X POST "$API/keys" -d '{"name": "phone"}'
curl -s -b jar "$API/inference"
```

The ops go over ames from this ship's armillary desk into the vendor's inbox, signed by ames, so the source ship is the identity and no password or claim token exists. The answers come back in an account view on the vendor that this ship alone may peek, through a usergroup the vendor makes for it. A minted key's secret crosses that way once and is cleared as soon as this ship says it has it.

Topping up opens a checkout with the vendor and answers a URL to open in a browser. In stub mode that URL is the vendor's own page with one button and no money moves, which is how the whole loop is proved without a rail. Since version 33 stub mode serves the vendor's own ship alone: another ship's checkout is refused with `this vendor takes no payments yet`, and the page will not credit it, so a ship that never set up payments cannot be topped up for free and spent from. `stub_open` in settings lifts that for the two-ship test rig. In live mode it is a Stripe Checkout Session on the card rail or a BTCPay invoice on the bitcoin one, and `docs/payments.md` is how both halves work.

The Stripe key is a restricted key, `rk_`, with write on Checkout Sessions, Customers, Products, Prices, Subscriptions and the Billing Portal and read on Invoices, Charges and Disputes, and live mode will not save without the endpoint's signing secret beside it.

The page opens as a customer's: Account (the vendor, the balance, top-ups, a usage card of the last thirty days by model, and the ledger; on a free ship, which is its own vendor with `own_free` on, no balance and no top-up), Keys, Catalog and Data. Everything that runs a service, Providers, Accounts, Payments, Report and the vendor's Catalog with its tiers and Brave cards, sits behind the Provider mode toggle in the header, marked as such, and is what a vendor's owner uses; a customer never needs it. A browser that has never chosen opens in provider mode only when the ship has a provider configured. The choice is kept per browser. `node scripts/render-check.js` checks the page's pure render functions with no ship.

The vendor's suggested models (`GET` and `PUT /api/suggested` above) arrive in the account view and in `GET /api/inference` as `suggested`. The customer also keeps them alone in `vendor-suggested.json` in the instance, `{"rev", "models"}`, written only when they change and holding nothing secret, so another app on the ship can be granted that one file. `app-inference.json` beside it holds what such an app needs to call the vendor itself, `{"mode", "base_url", "key", "suggested", "search", "free"}`, the same choice `GET /api/inference` makes (`mode` is `none` while the ship holds no key). It holds a key, so the owner grants it to an app knowingly; Orrery asks for it to run its generator on the vendor's suggested model. Both are written only when they change.

A ship can be its own customer: point `vendor.json` at itself and both halves work against the same ship. That is what `scripts/ship-matrix.py` runs against with two arguments.

That is also how an owner runs their own inference for Talon and Orrery instead of buying it: add each provider they use, self-hosted or cloud, import and enable the models, point the vendor at the ship itself, and turn on `own_free` (Payments, Your own use). The ship's own keys then need no balance and write no debit, on the proxy and the Brave proxy alike, and transcription may go to a provider that is not OpenRouter. Apps still get one base URL and one key; the catalog sends each model to its provider, and the provider keys never leave the ship. Set `public_url` to an address the owner's phone can reach, since an unset one answers `http://localhost:8080`. Leave `own_free` off to test the payment rails on yourself.

Live updates come from the instance's change beacon, streamed through grubbery's keep-SSE at `/grubbery/api/keep/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/beacon/rev`. It moves once per write that changed something, and a client that sees it move refetches what it shows. A write answers before the writer applies it, so a read right after one may still be a moment behind.

### Version 36: what the 2026-10-17 review fixed

- **A payment is credited once, however old.** Compaction folds only charges; a credit or refund row, and its ref, is kept for ever, and a checkout already marked paid is never credited again. Compaction also converges: a month's charges end as one summary row. A finished checkout row goes a month after its window.
- **Calls in flight.** A paid call holds its worst case (the body at four bytes a token in, and `max_tokens` or 8192 out, at the row's prices; a cent a megabyte for a transcription; a cent for a decision) while it runs, and the balance a call may start on is the balance less every hold and less what a live lease may still spend. A second call while the first holds the balance is 402. Calls that land inside the writer's lag can still pass together. Holds older than twelve minutes are swept by the tick.
- **A debt is not deleted.** A delete with the balance below zero is refused.
- **Late upstream answers.** grubbery matches an HTTP answer to its request by order alone, so a lease read checks that the answer names the lease's key, and a Stripe session, customer or BTCPay invoice that names another ship is refused rather than stored. Two lease reads at once charge one difference once: the writer charges what a key spent past what it last recorded (`lease-spend`), and recorded usage never goes backwards. Two lease mints at once keep the first, and the second key is deleted upstream.
- **A queued delete is idempotent.** The vendor answers a tombstone it already wrote rather than deleting again, and a tombstone names no ship.
- **Usage that is not reported is still charged**, on the size of the request and the answer at four bytes a token, and `input_tokens` and `output_tokens` are read where a server reports those.
- **Money edge cases.** A dispute takes back at most what its payment credited; a refund made on Stripe (`charge.refunded`) takes back the credit it undoes; a subscription's first period is credited once, by its invoice; any matching Stripe `v1` signature is accepted while a secret is rolled; a BTCPay invoice lives `btcpay_minutes`; a cost below a microdollar rounds up and an exponent is read; a lease provider's base URL may end in a slash; a rail id with a character outside letters, digits, `_` and `-` is refused before any call.
- **The writer and the inbox** take pokes only from inside this nexus or from this ship by name, so another grub on the ship cannot write a credit or pose as the ship's own customer.
- **The public return page** asks Stripe nothing unless the named ship's own checkout holds the session, and notes only a credit; a bad webhook signature is refused without a note. Neither can be used to flush the audit ring.
- **The customer channel.** A view read that answers after its thirty seconds is taken by the next read of the same file instead of piling up in the client fiber. Keys belong to the vendor that minted them, so switching vendors never hands one vendor's key to another; a lease and a drop's mark are cleared on a switch. Queued ops go in the order they were queued, an op sent two minutes ago and still unseen goes again, and one queued a day ago is dropped. `got-key` goes again while the vendor still shows a key this ship holds.
- **The vendor's housekeeping.** The tick writes any view whose balance, suggested revision, search flag or days are behind, and a save of the suggested models or the Brave key prods it, so the change reaches customers one view at a time without holding calls up. A late HTTP answer or a stray wake is nothing to the tick or the inbox.
- **The page.** Deleting a provider deletes its catalog rows. Unsaved edits hold off every automatic redraw. A vendor's checkout url is followed only when it is a web address. Test on a fresh provider lists its models. The import line says how many arrived, all switched off. The Brave card shows and sets Brave's price. The own use card shows each step to running your own inference, with a Use this ship button that sets the vendor and mints a key. Phone tables keep their labels, the status line is said once, and the model picker names the option the arrow keys reach.
- **Upgrading a live vendor.** Add `charge.refunded` to the Stripe webhook endpoint's events and read on Charges to the restricted key. Without them a refund made on Stripe is not taken off the balance.

### The repository

- `code/` is the desk: the nexus at `code/nex/armillary/app.hoon` with the page beside it, the model in `code/lib/armillary.hoon` (pure, import-free, unit-tested), the marcs under `code/mar`. `code/version.json` is what replicates.
- `code/lib/armillary-http.hoon`, `code/lib/armillary-stripe.hoon` and `code/lib/armillary-btcpay.hoon` are the two rails' pure half: percent encoding, form bodies, HMAC-SHA256, decimal dollars, and each rail's request builders and readers. Import-free like the model, so each one builds in both places, which is why the small encoders appear in all three.
- `tests/lib/armillary.hoon`, `tests/lib/armillary-http.hoon` and `tests/lib/armillary-stripe.hoon` are the unit suites, run with `-test` on a dev ship.
- `scripts/` holds the gates, all against a dev ship: `api-matrix.py` (the story above, over HTTP), `ship-matrix.py` (the account channel and both rails, one ship or two), `page-smoke.py`, `fake-provider.py` (the OpenAI-compatible stub), `fake-stripe.py` (the Stripe stub) and `fake-btcpay.py` (the BTCPay stub), `code-closure.py` and `weir-check.py`. `live-matrix.py` is run by hand against Stripe test mode and a real BTCPay store.
- `docs/`: the design at `docs/superpowers/specs/2026-09-19-armillary-design.md` and the plans under `docs/superpowers/plans`; `docs/channel.md` for the account channel over ames; `docs/payments.md` for both money rails; `docs/leases.md` for the lease path; `docs/releasing.md` for how a release reaches ricsul and its subscribers.
- The console is silent. A ship within its parameters prints nothing, and every outcome a person might want is state instead: `/tr/last` is the writer's last outcome, `/tr/log` and `/tr/inbox` the two rings, and `/tr/crashes` one row per fiber that crashed since the last load, with the count, the time, the error's first line and what clears it. A crash is the one thing that reaches the console, once, at `>>>`, with the remedy. The trace prints only with `+dbg` on, which no release ships. `docs/releasing.md` has the quiet gate every release passes.
- Family: [lattice](https://github.com/nisfeb/lattice), [auspex](https://github.com/nisfeb/auspex), [calendar](https://github.com/nisfeb/calendar), [orrery](https://github.com/nisfeb/orrery), [register](https://github.com/nisfeb/register), installed from `~ricsul-bilwyt` the same way.

© nisfeb
