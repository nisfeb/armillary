# Armillary: a token reseller on a ship

Status: draft, revised 2026-09-19 after sneagan's corrections: an account is a ship, every account action outside inference goes over ames, and groundwire comets are customers. Nothing is built. Section 14 lists what is still assumed without asking.

## 1. What this is

Armillary sells model inference. The owner connects upstream providers (OpenRouter, Bedrock, any OpenAI-compatible endpoint), picks the models to offer and the prices, and takes money by card through Stripe and by bitcoin on chain and over Lightning through BTCPay Server. Customers are ships. A customer's balance, keys, plan and lease are managed from its own ship over ames, so every request that is not inference travels the signed channel, and only the inference hot path is HTTP: a standard OpenAI-shaped API on the vendor ship under a bearer key minted over ames, or, for a client we own, a capped provider key the vendor hands out so the client calls the provider directly and the vendor ship carries no tokens.

It is one grubbery desk app in the nisfeb family, installed on both sides: the vendor ship runs it as the service, every customer ship runs it as the client. That is orrery's sharing shape, one desk, two roles, and it is what lets Talon work without a single new credential: Talon already holds the cookie for the user's ship, so Talon talks to the armillary desk on that ship, and that desk talks to the vendor over ames as the ship it is.

The name is the instrument: nested rings that model the sky, each turning on its own axis around one centre.

## 2. Who talks to it

- The **vendor owner** holds the cookie on the vendor ship. The owner sets up providers, the catalog, prices, plans and payment rails, and sees every account, every key and the whole ledger. The owner's console is the page on the vendor ship over its own cookie: there is no other signed channel from a ship to itself.
- A **customer** is a ship. Its account id is its @p. It acts through the armillary desk on its own ship, which pokes the vendor's inbox over ames (the source ship is the identity, signed by ames) and reads its own account view by a remote peek the vendor grants to that ship alone. On the customer ship, the page and the API are the ship owner's, over that ship's cookie, which is how Talon reaches them.
- An **inference key** is a bearer token, `Authorization: Bearer <id>.<secret>`, orrery's client-key shape. It names one account and exists only for the HTTP hot path. It is minted over ames, delivered through the account view the customer ship alone can peek, and stored on the customer ship. The vendor keeps a salted hash. Keys are checked in the app, not by eyre.
- The **public** holds nothing and reaches only the two payment webhooks and the browser return page. There is no public checkout, no signup, no claim token.

An account exists from a ship's first poke. An unfunded account costs the vendor one small grub and nothing else. Comets are accepted: the vendor runs on the groundwire network, where a comet is spawned by a bitcoin transaction and its attestation is verified by gw-btc before ames will carry its packets, so a comet whose poke lands is already a paid-for identity and the customers this service is for are groundwire comets. The vendor does nothing extra. A settings switch `refuse_comets`, off by default, refuses them for a vendor on a network without that guarantee. Moons hold their own accounts.

## 3. Money

### Units

Every amount on the ship is an integer number of microdollars: one dollar is 1,000,000. Prices are microdollars per million tokens. A charge is `ceil(tokens * price / 1,000,000)`, rounded up so a request never costs less than its price. The page shows dollars to four places.

Bitcoin payments are priced in dollars by BTCPay at invoice time and credited in dollars. The ship never holds a sat amount as a balance.

### The ledger

An account's ledger is append-only. A row is one of:

| kind | fields | written by |
|---|---|---|
| `credit` | `amount`, `rail` (`stripe`, `btcpay`, `owner`), `ref` (the Stripe session or invoice id, the BTCPay invoice id, or the owner's note), `at` | a verified payment, or the owner |
| `debit` | `amount` (what the customer was charged), `cost` (what the upstream charged us, when known), `model`, `in`, `out` (tokens), `mode` (`proxy` or `lease`), `ref` (the upstream request id, or the lease reconciliation stamp), `at` | the proxy after a completed request, or the lease reconciler |
| `refund` | `amount`, `ref`, `note`, `at` | the owner |

A `credit` or `refund` with a `ref` already in the ledger is a no-op, so a webhook delivered twice credits once.

Balance is the fold: credits minus debits minus refunds. The writer caches it on the account row on every write and a `rebuild` op refolds it, so reads are one grub and the ledger stays the truth. Ledger rows older than 90 days are compacted into one summary row per month per kind, keeping the totals and dropping the detail.

A request is allowed when the balance is above zero when the request starts. Two requests in flight at once can both pass that check, so a balance can go a little below zero, by at most the in-flight requests. A negative balance blocks the next request. This is the ceiling; a per-account reservation is the upgrade if it matters.

### Plans

A plan is a row in `plans.json`: `id`, `name`, `kind` (`topup` or `subscription`), `price` (microdollars), `credit` (microdollars added to the balance when paid), `interval` (`month` or `year`, subscriptions only), `stripe_price` (the Stripe Price id, filled in when the owner creates the plan on Stripe from the page, or pasted). A top-up plan is a fixed amount; a custom top-up is any amount at or above the minimum in settings (default five dollars) and credits exactly what was paid. A subscription credits `credit` every time Stripe reports its invoice paid.

The Talon subscription is one subscription plan. Nothing in armillary knows what Talon is; Talon knows which plan id to offer.

## 4. Providers and the catalog

### Providers

`providers.json` holds the owner's upstream connections. A provider is `id`, `name`, `kind`, `base_url`, `api_key`, and for OpenRouter a `provisioning_key`. Secrets never leave the ship: the page reads masked rows and saves with a blank field meaning keep, null meaning clear, the way orrery's generator settings work.

Two kinds, and the second is the first plus one thing:

- `openai-compatible`: any endpoint that answers `POST <base_url>/chat/completions` and, usually, `GET <base_url>/models` with a bearer key. This covers OpenAI, Anthropic's compatibility endpoint, Venice, a self-hosted vLLM, and Bedrock. Bedrock's `bedrock-mantle` endpoint (`https://bedrock-mantle.<region>.api.aws/v1`) is OpenAI-compatible, takes an Amazon Bedrock API key as the bearer token, and lists models; its `bedrock-runtime` endpoint has no models listing. So Bedrock is a row with that base URL and that key, not a kind of its own.
- `openrouter`: the same, `base_url` `https://openrouter.ai/api/v1`, plus a provisioning key that lets the ship mint capped runtime keys for leases (section 5). Its models listing carries prices, so import fills the catalog prices.

The page's Test button on a provider sends one tiny chat completion and reports the status and the model that answered.

### The catalog

`catalog.json` is the list of models customers may use. A row is `id` (the model id customers send, such as `anthropic/claude-sonnet-4.5`), `provider`, `upstream` (the id sent upstream, when it differs), `in`, `out` (microdollars per million tokens, what the customer pays), `cost_in`, `cost_out` (what the upstream charges, when known, for margin), `enabled`, and free `tags` (the page shows `zdr` as a badge, since Talon's provider screen shows ZDR badges).

Import from provider pulls `GET /models`, adds the rows that are new as disabled, and for OpenRouter fills `cost_in` and `cost_out` from its pricing and `in` and `out` as cost times the markup in settings (default 1.3). For a provider without prices the owner types them. The owner enables what to sell.

The enabled catalog with prices is published as `/catalog-public.json`, readable by every ship through the `/public` usergroup, so a customer ship shows prices before it has an account. `GET /v1/models` answers the same rows in OpenAI's list shape, each with a `pricing` object (`prompt`, `completion`, dollars per token as strings, the OpenRouter convention) and the tags.

## 5. Inference

Two paths, both HTTP, both under an inference key or a lease. This is the one place the design leaves ames: a chat completion is large, latency-bound and often streamed, and ames is none of those things.

### Proxy: the standard endpoints

`POST /v1/chat/completions` and `POST /v1/embeddings` on the vendor ship under `/apps/armillary`, inference key required. The base URL a client configures is `https://<vendor host>/apps/armillary/v1`.

1. Identify the key. 403 when it is missing, wrong or revoked.
2. Read the catalog row for `model`. 404 `model: not offered` when it is missing or disabled.
3. Read the balance. 402 `balance: empty` when it is not above zero.
4. `stream: true` is refused 400 `stream: not supported on the proxy; take a lease`. Iris returns a whole response, so the ship cannot stream, and Talon does not stream today.
5. Forward the body upstream with `model` replaced by `upstream` and the provider's key, with a two minute deadline (calendar's `+fetch-hdr` shape, orrery's `+ask-model` shape).
6. On a 2xx, read `usage.prompt_tokens` and `usage.completion_tokens`, compute the charge from the catalog row, poke the writer with a `debit` row, and answer the upstream body as it came, with its status. The debit is written after the answer is known but before the response is sent, so a crash between the two costs the customer nothing and the owner one request.
7. On an upstream error, answer its status and its body when it is JSON, else `{"error": {"message": "<provider> answered <status>"}}`. No debit. On no answer by the deadline, 504.

Embeddings charge `prompt_tokens` at the row's `in` price.

The request body is passed through untouched apart from `model`, so tools, JSON mode, images and every other field the upstream supports work without the ship knowing about them. Bodies over 4 MB are refused 413.

There is no per-key rate limit in v1. The balance is the cap. Add a per-account requests-per-minute counter on the account row when a key misbehaves.

### Lease: direct to the provider

This is the path for clients we own. The vendor hands the customer a real provider key with a spending cap equal to the customer's balance, the client calls the provider directly, and the vendor reconciles what was spent. No tokens cross either ship. Streaming, tools, every provider feature, and the provider's latency, all for free.

In v1 a lease is an OpenRouter runtime key made through the provisioning API. OpenRouter keys carry a `limit` in dollars, report `usage` in dollars, and can be `disabled`, which is exactly the shape a prepaid balance needs.

A customer asks for a lease over ames (section 6, the `lease` op). The answer lands in its account view: `{"provider": "openrouter", "base_url": "https://openrouter.ai/api/v1", "key": "<sk-or-...>", "models": [<the catalog ids on this provider>]}`.

- The first lease on an account creates the OpenRouter key: `POST /api/v1/keys` with the provisioning key, `name` `armillary/<ship>`, `limit` equal to the balance divided by the lease markup, in dollars. The vendor stores the key's `hash`, the key itself and `usage_seen: 0` on the account's `lease.json`. The key must be stored, since OpenRouter returns it once. It is written into the account view for that ship to peek and nowhere else, and never logged.
- A later `lease` op answers the stored key, after a reconcile.
- **Reconcile** runs on a behn tick every ten minutes for every account with a lease, and before every `lease` and `refresh` op: `GET /api/v1/keys/<hash>` answers `usage` in dollars; the vendor writes one `debit` row for `(usage - usage_seen) * markup` when it moved, sets `usage_seen`, and then makes the OpenRouter `limit` equal `usage + balance / markup` so the cap always tracks the balance. When the balance is at or below zero the key is set `disabled`; a credit re-enables it and raises the limit. Revoking the lease, or the owner closing the account, deletes the OpenRouter key.
- The `lease_markup` in settings (default 1.3) is the one number for this path: OpenRouter's `usage` is at its prices, and the customer pays that times the markup. The same number is what import uses to fill proxy prices from cost, so the two paths charge alike for the same model.

What a lease does not do: it cannot limit the key to the catalog's models. An OpenRouter key can spend on any model at the owner's cost times the markup, capped by the balance. The `models` list is advice to the client. Bedrock and the other providers have no per-customer capped key, so they are proxy only in v1; a Bedrock lease would need short-term credentials signed on the ship and is a later phase if wanted.

Talon takes a lease when one is offered and falls back to the proxy otherwise. The client-facing rule is one line: read the inference config from your own ship; it says lease or proxy, a base URL and a key.

## 6. The account channel over ames

Everything a customer does that is not inference is a JSON op poked from the customer's armillary desk into the vendor's `/inbox.sig`, and every answer is a grub in the customer's account view on the vendor ship, which that ship alone may peek. This is orrery's sharing mechanism (`shares.sig`, `remote-poke-wait`, `peek-remote-wait`, one usergroup per shared grub) with the roles fixed: the vendor is always the host, the customer always the guest.

### The inbox

`/inbox.sig` on the vendor is registered on the `/public` usergroup through `/sys/ames/registry`, so any ship may poke it. The source ship of the poke is the account. An op is `{"op": <name>, ...}`:

| op | fields | what the vendor does |
|---|---|---|
| `hello` | | opens the account if the ship has none (refused silently for a comet when `refuse_comets` is on), makes the ship's usergroup and its view, records the time |
| `refresh` | | reconciles the lease if any and rewrites the view |
| `checkout` | `rail`, `plan` or `amount`, `nonce` | makes the Stripe session or the BTCPay invoice with `metadata[ship]`, writes `{nonce, url, expires}` into the view's `checkouts` |
| `mint-key` | `name`, `nonce` | mints an inference key, writes `{nonce, id, name, secret}` into the view's `keys_pending` once; the customer ship stores it and sends `got-key` |
| `got-key` | `id` | clears the secret from the view |
| `drop-key` | `id` | revokes it |
| `lease` | | creates or refreshes the lease and writes it into the view |
| `drop-lease` | | deletes the OpenRouter key and clears the view's lease |
| `cancel-subscription` | | cancels the Stripe subscription at period end |

Every op is idempotent under its `nonce` where it has one: a `checkout` with a nonce already in the view answers the same URL. Remote acks are unobservable (trap 22 in `/project/lattice/grubbery-fiber-deploy-traps`), so the customer side never treats a timeout as failure. It pokes, then peeks the view until the nonce appears, up to thirty seconds, and reports pending after that.

### The account view

`/accounts/<ship>/view.json` on the vendor: `ship`, `balance`, `plan`, `subscription` (`active`, `renews`), `keys` (id, name, made, last used), `keys_pending` (the secrets not yet fetched), `lease` (or null), `checkouts` (nonce, url, expires, status), `ledger` (the last 50 rows), `rev`, `updated`. The vendor rewrites it whole on every change to that account. The grant is a usergroup named for the ship, `<ship>.grp` under `/sys/ames/usergroups`, holding that one ship with peek on that one file, made on `hello` and rewritten never. Nothing about one account is readable by another ship.

The customer ship peeks the view on demand, after every op it sends, and on a five minute tick while it holds a lease, so the balance Talon shows is at most five minutes old and exact right after an action.

### The customer side

On a customer ship the same desk holds `/vendor.json` (the vendor ship, default the production ship), `/keys.json` (the inference keys it has fetched, secrets included, since this ship is the customer), `/lease.json` (the current lease), `/view.json` (the last view it peeked) and `/client.sig` (the fiber that pokes, peeks and ticks). Its page is the customer's own console: balance, plan, top up, subscribe, keys, lease, the ledger, and the vendor's public catalog with prices. Its HTTP API is what Talon calls, over the cookie Talon already has (section 8).

The vendor ship's own desk has `/vendor.json` pointing at itself and is its own customer for testing.

## 7. Payments

### Checkout

A customer's `checkout` op names a rail and a plan or an amount. The vendor makes the session or invoice and writes its URL into the view. The customer ship answers Talon the URL, Talon opens it in a browser, and the person pays. When the payment is verified the vendor credits the ship's account, rewrites the view, and the customer ship's next peek shows the balance. No claim token is needed: the ship on the poke is the account, and the ship is in the metadata of the session or invoice.

`GET /pay/return?ship=<ship>`, public, is where Stripe and BTCPay send the browser after a payment. It is a plain page that says the payment was received and the app can be returned to, or that it is still pending. For Stripe it also carries `sid` and verifies the session, so a payment is credited even when the webhook is late or the public URL was not reachable, the register rule.

### Stripe

Settings: the secret key, the webhook signing secret, the public URL. All in `settings.json`, masked on read.

- A top-up checkout is a Checkout Session in `mode=payment` with one line at the plan's price, or a custom amount, `metadata[ship]`, `success_url` the return route with the session id placeholder appended after encoding, `cancel_url` the return route with `cancelled=1`, `expires_at` now plus 24 hours.
- A subscription checkout is a Checkout Session in `mode=subscription` with the plan's `stripe_price`, the same metadata, and `subscription_data[metadata][plan]`.
- `POST /hooks/stripe`, public: the body is read only for the event type and the object id, never trusted for anything else. `checkout.session.completed`: GET the session; when `payment_status` is `paid`, credit `amount_total` (in cents, times 10,000) with `ref` the session id to the ship in metadata. For a subscription session, also store the Stripe `customer` and `subscription` ids on the account. `invoice.paid`: GET the invoice; find the account by `customer`; credit the plan's `credit` with `ref` the invoice id. `customer.subscription.deleted`: clear the subscription from the account. Everything else answers 200 and does nothing. Answer 200 even on a failed GET, noting it in the ring, since Stripe retries non-2xx. The signature header is verified when the signing secret is set (HMAC-SHA256 over `<t>.<body>`, the `v1` element, five minute tolerance); with no secret the GET verification is the only trust, which is register's stance.
- Plans are created on Stripe from the page: the owner fills name, price and interval, and the ship creates the Product and the Price and stores the ids. Or the owner pastes a Price id.

### BTCPay Server

BTCPay gives both bitcoin rails from one invoice: the checkout page offers on-chain and Lightning, watches the chain, counts confirmations, and settles Lightning at once. Nothing in this codebase watches on-chain addresses, so BTCPay is the whole of the bitcoin side. The owner runs it (or uses a hosted instance) and supplies its URL, the store id, an API key with `btcpay.store.cancreateinvoice` and `btcpay.store.canviewinvoices`, and the webhook secret.

- A checkout is `POST <url>/api/v1/stores/<store>/invoices` with `amount` in dollars, `currency` `USD`, `metadata` `{ship}`, `checkout.redirectURL` the return route, `checkout.expirationMinutes` 60. The answer's `checkoutLink` is the URL.
- `POST /hooks/btcpay`, public: verify `BTCPay-Sig` (`sha256=` HMAC-SHA256 of the raw body with the webhook secret; refuse 401 when it does not match). Then, for `InvoiceSettled`, GET the invoice and credit its `amount` (dollars, times 1,000,000) with `ref` the invoice id when its `status` is `Settled`. `InvoiceExpired` and `InvoiceInvalid` mark the view's checkout row expired. Every other event answers 200.
- On-chain payments settle after the store's confirmation count, so the checkout row stays pending for ten minutes or more. The return page and the view both say so.

Subscriptions are card only. A bitcoin customer tops up.

### What is not here

Metronome is skipped. The prepaid ledger on the ship is the meter and Stripe Billing carries the subscriptions; Metronome adds nothing until there is post-paid usage-based invoicing to send, and the earlier analysis (`/project/brave/metronome-inference-billing`) found it fits prepaid poorly. LNbits and LND direct are skipped: ecash's five `ln-*` arms would give Lightning without BTCPay, but not on-chain, and BTCPay gives both. Add either when the owner has a node and no BTCPay.

## 8. The API

Three surfaces. JSON in and out, `content-type: application/json` required on any body, the orrery rules. Errors are `{"error": {"message": "<text>"}}`, the OpenAI shape, so one client error path covers everything.

### On the vendor ship, inference key

| route | answers |
|---|---|
| `GET /v1/models` | the enabled catalog in OpenAI list shape with `pricing` and `tags` |
| `POST /v1/chat/completions` | the proxy, section 5 |
| `POST /v1/embeddings` | the proxy, section 5 |

### On the vendor ship, public

| route | answers |
|---|---|
| `POST /hooks/stripe`, `POST /hooks/btcpay` | the webhooks |
| `GET /pay/return` | the browser return page |

### On the vendor ship, owner cookie

| route | answers |
|---|---|
| `GET` and `PUT /api/settings` | markup, minimum top-up, public URL, `refuse_comets`, the Stripe and BTCPay fields (masked on read) |
| `GET`, `POST`, `PUT /api/providers[/<id>]`, `DELETE`, `POST /api/providers/<id>/test`, `POST /api/providers/<id>/import` | section 4 |
| `GET` and `PUT /api/catalog` | the whole catalog, replaced whole; the PUT republishes `catalog-public.json` |
| `GET`, `POST`, `PUT /api/plans[/<id>]`, `DELETE` | section 3; `POST /api/plans/<id>/stripe` creates the Product and Price |
| `GET /api/accounts?q&limit` | accounts with balance, plan, keys, last use |
| `GET /api/accounts/<ship>` | the account, its keys, its lease state, its last 100 ledger rows |
| `POST /api/accounts/<ship>/credit` `{"amount", "note"}` and `/refund` | owner rows in the ledger |
| `DELETE /api/accounts/<ship>/keys/<kid>` | revoke for a customer |
| `POST /api/accounts/<ship>/close` | revokes every key, deletes the lease key upstream, keeps the ledger, drops the usergroup |
| `GET /api/report?days=30` | credits by rail, charged, cost, margin, requests, tokens, the top models |
| `GET /api/log` | the audit ring |

### On the customer ship, owner cookie (what Talon calls)

| route | answers |
|---|---|
| `GET /api/account` | the last peeked view plus `vendor`, `stale` (seconds since the peek); `?fresh=1` peeks first |
| `GET /api/catalog` | the vendor's public catalog with prices |
| `GET /api/plans` | the vendor's plans |
| `POST /api/checkout` `{"rail", "plan" or "amount"}` | pokes `checkout`, waits for the nonce in the view, answers `{"url"}` or 202 `{"pending": true}` |
| `POST /api/keys` `{"name"}` | pokes `mint-key`, waits, stores the secret, answers `{"id", "name", "secret"}` once |
| `GET /api/keys`, `DELETE /api/keys/<id>` | the stored keys, never the secret after the mint; revoke |
| `POST /api/lease`, `DELETE /api/lease` | pokes `lease` or `drop-lease`, answers the lease from the view |
| `GET /api/inference` | what a client needs to run: `{"mode": "lease" or "proxy", "base_url", "key", "models"}`, the lease when held, else the proxy base URL and the first inference key |
| `PUT /api/vendor` `{"ship"}` | changes the vendor and sends `hello` |
| `POST /api/cancel-subscription` | pokes it |

Talon's whole integration is `GET /api/inference` plus the checkout and account routes, all on the ship it is already logged into.

## 9. The page

One HTML file, one CSS, one JS, no framework, views switched by the hash, the orrery pattern. Every action is optimistic with a fallback read, the register rule. The page shows the vendor views when `/vendor.json` names our own ship, the customer views otherwise; both are in the one file.

Vendor views:

- **Providers**: rows with kind, base URL, masked key, a Test button with its last result, Import. An add form.
- **Catalog**: a table of models, provider, customer prices, cost, margin, enabled switch, tags. Inline edit of prices. A filter box.
- **Accounts**: the list with ship, balance, plan, keys, last use; a detail with the ledger, the keys with revoke, credit, refund, close, and the lease state (key hash, usage seen, limit, disabled).
- **Payments**: the Stripe and BTCPay settings, the plans with create-on-Stripe, the public URL, the two webhook URLs to paste into Stripe and BTCPay, and the last ten webhook outcomes from the ring.
- **Report**: the last 30 days: revenue by rail, charged versus cost, requests and tokens, the top ten models. Numbers in a table, no charts in v1.

Customer views:

- **Account**: vendor, balance, plan and renewal, top up (plan buttons and a custom amount, card or bitcoin), subscribe, cancel, the ledger.
- **Keys and lease**: mint a key (secret shown once), revoke, take or drop a lease, the inference config as Talon sees it.
- **Catalog**: the vendor's models and prices.

## 10. The tree and the writer

The nexus owns this tree. Every persistent path has a `%fall` row in `on-load`; every blot has a noun-passthrough marc; the writer never crashes. Vendor paths sit empty on a customer ship and the other way round.

```
/main.sig                 the writer: every mutation is a JSON op through it
/web.sig                  binds /apps/armillary
/inbox.sig                vendor: the inbox other ships poke, on the /public group
/tick.sig                 vendor: reconcile leases, compact ledgers, every ten minutes
/client.sig               customer: poke, peek and the five minute tick
/requests/<id>            ephemeral request fibers
/settings.json            vendor: markup, minimum, public URL, refuse_comets, Stripe, BTCPay
/providers.json           vendor: the upstream connections, secrets inside
/catalog.json             vendor: the models offered
/catalog-public.json      vendor: the enabled rows with prices, peekable by /public
/plans.json               vendor: the plans, peekable by /public
/accounts/<ship>/account.json   vendor: ship, balance (cached), plan, stripe ids, made, last seen
/accounts/<ship>/keys.json      vendor: salted hashes, one row per key
/accounts/<ship>/lease.json     vendor: the OpenRouter key, its hash, usage seen, limit, disabled
/accounts/<ship>/view.json      vendor: the account as the ship reads it, peekable by <ship>.grp
/accounts/<ship>/ledger/<at>-<n>   vendor: one row per credit, debit or refund
/vendor.json              both: the vendor ship; our own on the vendor
/keys.json                customer: the inference keys fetched, secrets included
/lease.json               customer: the current lease
/view.json                customer: the last peeked view and when
/tr/last  /tr/log         the last writer outcome and the audit ring of 500
/tr/inbox                 vendor: ship traffic, its own ring of 500
/beacon/rev               the change beacon the page streams
```

Writer ops, one per mutation: `set-settings`, `set-provider`, `drop-provider`, `set-catalog`, `set-plan`, `drop-plan`, `open-account`, `credit`, `debit`, `refund`, `add-key`, `drop-key`, `touch-key`, `set-lease`, `drop-lease`, `set-checkout`, `set-subscription`, `write-view`, `close-account`, `compact`, `rebuild`; on the customer side `set-vendor`, `store-key`, `forget-key`, `store-lease`, `store-view`. Secrets never appear in `/tr/log`; a row names the op, the ship and the amount.

Roads are nexus-relative (`rf`, `rv`, the orrery helpers). The weir asks for `/sys/bowl.sig`, `/sys/eyre/` (bind and answer), `/sys/iris/` (talk to providers, Stripe and BTCPay; refuse this and nothing can be bought or answered), `/sys/behn/` (the ticks and the two minute provider deadline), `/sys/link/` (find our own writer), `/sys/gall/` (poke the vendor's inbox; refuse this and this ship cannot be a customer), `/sys/ames/registry` (let customer ships poke the inbox; refuse this and this ship cannot be a vendor), `/sys/ames/ships/` peek (read your account on the vendor), and `/sys/ames/usergroups/` make and peek (one group per account, so each ship reads its own account and nothing else). Every `why` says what breaks when refused.

## 11. Files

```
code/
  bill.json  tile.json  version.json  icon.svg
  nex/armillary/app.hoon         the nexus, both roles
  nex/armillary/armillary.{html,css,js}   the page, both roles
  nex/armillary/return.html      the payment return page
  lib/armillary.hoon             types, codecs, ledger fold, pricing, keys, ops, the view. Import-free
  lib/armillary-http.hoon        url-encode, form-body, bearer, hmac helpers. Import-free
  lib/armillary-stripe.hoon      request builders and readers. Import-free
  lib/armillary-btcpay.hoon      request builders and readers. Import-free
  lib/armillary-openrouter.hoon  provisioning requests and readers, models import. Import-free
  mar/                           the noun passthroughs: json, mime, sig, weir, http-response, timer-*, gall-poke, poke-ack, ships, usergroups/registry-action
tests/lib/armillary*.hoon        one test file per lib
scripts/
  api-matrix.py                  the vendor gate on ~wex, stub providers and stub payments
  ship-matrix.py                 the ames gate: ~feb as the customer of ~wex
  fake-provider.py               an OpenAI-compatible stub with usage in its answers, and a stub provisioning route
  live-matrix.py                 Stripe test mode and BTCPay testnet, by hand
  page-smoke.py
  code-closure.py  weir-check.py   copied from auspex; both clean before every release
README.md                        the family shape: what it is, Try it, the API table, the repository
docs/
  releasing.md                   copied from orrery; the mechanism is the same
  superpowers/specs/  superpowers/plans/
```

Stub mode: `providers.mode` in settings is `stub` or `live`. In stub mode the proxy and the provisioning calls go to whatever `base_url` the provider row names (the gate points it at `fake-provider.py`), and checkouts answer a local URL whose page marks the checkout paid, so the whole flow runs on `~wex` and `~feb` with no key. Live mode is the real thing.

## 12. Testing

- Unit tests on `~wex` with the revision pinned, one file per lib: the ledger fold and the cached balance agree; charge rounding rounds up; a duplicate `ref` is a no-op; key hashing and parsing; every inbox op decodes and a broken one answers the field that failed; the view encodes and decodes; comet detection; every request builder's method, URL, headers and body keys; every reader on a fixture, paid and unpaid, settled and expired; the Stripe and BTCPay signature checks on a good and a bad signature.
- `api-matrix.py` against `~wex` as the vendor in stub mode: providers CRUD with masking; import from the fake provider; catalog and its public copy; an owner-minted key completes a chat and the ledger shows the debit with the right amount; an empty balance is 402; `stream` is 400; an unknown model 404; embeddings charge input only; both webhooks with an unrelated event answer 200 and change nothing; a replayed webhook credits once; owner credit, refund, close; the report adds up; `/tr/log` never contains a secret.
- `ship-matrix.py` with `~feb` as the customer of `~wex`: `hello` opens the account and `~feb` can peek its view while `~wex`'s own view of another ship is refused; a checkout round-trips a URL; the stub pays it and the balance shows on `~feb` within one peek; a key minted from `~feb` completes a chat on `~wex`; the secret leaves the view after `got-key`; a lease against the stub provisioning route creates, reconciles, disables at zero and re-enables on credit; `GET /api/inference` on `~feb` answers the lease, then the proxy after `drop-lease`; a comet's `hello` opens an account, and is refused once `refuse_comets` is on.
- `page-smoke.py`: every view renders on both ships and one edit round-trips.
- `live-matrix.py`, by hand, once keys exist: Stripe test mode with 4242 4242 4242 4242 for a top-up and a subscription; a BTCPay testnet Lightning payment; a real OpenRouter lease with a one dollar cap. Ames paths are verified on real ships too, since a fake ship derives its keys from its name.

## 13. Phases

Each phase is one compact plan written as the implementer's brief, one implementer, one review at the end, one fix pass (`/feedback/register-speed-over-ceremony`). Estimates are for one implementer with the ship recipes already working.

1. **The vendor, proxy only.** Skeleton, providers, catalog with import and the public copy, accounts, keys minted by the owner, the ledger, `GET /v1/models`, the two proxy routes, the vendor page's Providers, Catalog and Accounts views, stub provider, `api-matrix.py`. Talon can use it the same day through its OpenAI-compatible provider entry with a hand-delivered key. About two days.
2. **The account channel.** The inbox, the ops, the per-ship usergroup and view, the customer role (`client.sig`, the customer routes, the customer views), `hello`, keys and `got-key` over ames, `ship-matrix.py` on `~wex` and `~feb`. Checkout is stubbed. About two days.
3. **Stripe.** Plans, the `checkout` op for card, the return page, the webhook, subscriptions, the Payments view. About one day.
4. **BTCPay.** Invoices, the webhook, the bitcoin half of checkout and of the Payments view. About half a day.
5. **Leases and the report.** OpenRouter provisioning, reconcile on the tick, disable and re-enable, the `lease` ops, `GET /api/inference`, the Report view. About one day.
6. **Talon and release.** In the talon repo, its own spec: an `Armillary` provider entry that reads `GET /api/inference` from the user's ship, offers the plans, opens checkout, shows the balance, and uses the lease or the proxy. The store copy that promises no backend is rewritten. Then the production vendor ship, the domain, the webhook URLs, `live-matrix.py`, and the ricsul steps that are sneagan's (the desk is installed on customer ships from ricsul like the rest of the family). About two days.

## 14. Assumed without asking

Decided by sneagan on 2026-09-19: an account is a ship, an @p is required, and every account action outside inference goes over ames.

Still assumed, each cheap to change now:

1. The name is armillary, from the directory.
2. One desk, two roles, the vendor is its own customer for testing. Not two desks.
3. Comets are accepted because the groundwire network has already verified them on chain; `refuse_comets` exists for a vendor elsewhere. Moons hold their own accounts. Unverified: that on a groundwire vere no poke from an unattested comet can reach the nexus at all, which is what makes an app-level check unnecessary.
4. One vendor per customer ship.
5. The vendor owner's console is the page over the vendor ship's own cookie. Vendor administration from another ship is not in v1.
6. Inference itself stays HTTP under a key minted over ames, or a lease. It does not go over ames.
7. Prepaid only. A subscription is a periodic credit. No post-paid usage invoicing and no Metronome.
8. Bitcoin, both rails, through BTCPay Server, not through LNbits or LND directly.
9. A lease is an OpenRouter runtime key capped at the balance, and it is not limited to the catalog's models. Bedrock and every other provider are proxy only in v1. Streaming exists only on a lease.
10. No free trial credit. It runs on its own production ship, not on `~ricsul-bilwyt`. Amounts in microdollars, prices per million tokens, rounding up.

## 15. Out of scope for v1

Per-key rate limits, request reservations against the balance, Bedrock leases, a public web page (Talon and the customer ship's page are the customer's pages), invoices and receipts by email, tax, multiple currencies, an affiliate or referral scheme, MCP tools (the family's tool discovery gap is open, `/reference/grubbery-mcp-desk-tool-discovery-gap`), an Anthropic-shaped `/v1/messages` route, and several vendors per customer ship.
