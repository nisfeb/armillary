# Payments

A customer buys credit with a card or with bitcoin. On the card rail the vendor makes a Stripe Checkout Session; on the bitcoin rail it makes one BTCPay Server invoice, whose checkout page offers both on chain and Lightning. Either way the person pays on the rail's own page, and the vendor credits the ship's account once it has read the payment back from the rail. Subscriptions are card only.

## The checkout flow

1. The customer ship pokes a `checkout` op into the vendor's inbox with a rail, a nonce, and either a plan id or an amount in microdollars. That is the account channel, `docs/channel.md`.
2. The vendor's inbox fiber reads settings. In stub mode it answers its own `/pay/stub` page and nothing else happens. In live mode it builds a Stripe Checkout Session for the `stripe` rail and a BTCPay invoice for the `btcpay` rail, and sends it.
3. Every refusal is a checkout row with status `refused` and a `note` saying which field was wrong: `stripe_key: not set` or `btcpay: not set`, `plan: unknown`, `amount: below the minimum`, `plan and amount: choose one`, `plan: not on Stripe yet`, `plan: subscriptions are card only`. The customer only ever sees the view, so a refusal has to live there.
4. On a 2xx, the row is written with the rail's url, status `pending` and the rail's own id for it: the session id on Stripe, the invoice id on BTCPay. The customer's `POST /api/checkout` answers that url, or 502 with the note when the row was refused.
5. The person pays. Stripe sends them to `<public_url>/apps/armillary/pay/return?ship=<ship>&sid=<session>`; BTCPay sends them to the same page with `?ship=<ship>&nonce=<nonce>&rail=btcpay`. Both also send the vendor a webhook.

A top-up is `mode=payment` with one inline line item at the amount. Every line item, inline or on a plan's Product, carries Stripe's product tax code `txcd_10105001`, Artificial Intelligence as a Service, cloud based, personal use. Stripe needs it for two reasons: a Stripe account with Managed Payments on (the default on new accounts, Stripe as merchant of record for tax, fraud and disputes) refuses a line item without an eligible code, and Stripe Tax needs it to tax a digital service correctly in the US. A subscription is `mode=subscription` on the plan's Stripe Price, with the ship and the plan id in the subscription's own metadata, so an invoice months later still says which plan it renews.

The rail's call runs inside the inbox fiber. That serializes every customer's ops behind one slow call, for up to two minutes. It is marked in the code with a `ponytail:` comment; a spawned fiber per op is the upgrade when a vendor has enough customers to feel it.

## The two verification paths

Both end in the same two arms, `+credit-session` and `+credit-invoice`, and both are safe to run twice: a credit whose `ref` is already in the ledger writes nothing and answers `already recorded`.

- **The webhook**, `POST /hooks/stripe`, public and without a cookie. Stripe calls it when it can.
- **The return page**, `GET /pay/return`, which the person's own browser loads on the way back. It verifies the same session, so a payment is credited even when the webhook is late or the public URL was never reachable from the internet. That is the register rule: the browser round trip is the path that always exists.

Whichever arrives first credits; the second finds the ref recorded and does nothing.

## The webhook's trust rule

The body of a webhook is read for exactly two things: the event `type` and `data.object.id`. Everything else, the amount, the ship, whether it was paid, comes from reading that object back from Stripe with the vendor's own key. A forged body can at worst name a real session, which then reads back as whatever it really is.

In live mode the `stripe-signature` header is checked always: HMAC-SHA256 over `<t>.<raw body>` with the signing secret, compared against the `v1` element, with a five minute tolerance and a byte comparison that does not stop at the first difference. A bad or missing signature is 400 and nothing else happens. A live endpoint with no signing secret configured is 400 as well, with `signature: no signing secret configured`, and the settings route refuses to go live with a key and no secret in the first place. Reading the object back is defense in depth on top of that, not the only trust.

Stub mode is the one place a blank signing secret is allowed, because the stub runs on the same machine and nothing else can reach the endpoint.

Seven event types do anything:

| event | what happens |
|---|---|
| `checkout.session.completed` | read the session, credit `amount_subtotal` cents times 10.000, keep its PaymentIntent on the checkout row, mark the row paid, and on a subscription session store the Stripe customer and subscription ids |
| `checkout.session.async_payment_succeeded` | the same, for a payment method that settles later |
| `checkout.session.async_payment_failed` | mark the checkout row `failed`. Nothing was credited, so nothing comes off |
| `invoice.paid` | read the invoice, find the account by its Stripe customer id, credit the plan's `credit`, and set `renews` from the invoice's period end |
| `customer.subscription.deleted` | find the account holding that subscription id and clear its subscription |
| `charge.dispute.created` | read the dispute, find the ship by its PaymentIntent, and take the money back off the ledger |
| `charge.dispute.closed` | note the dispute's final status in the ring and change nothing |

The credit follows `amount_subtotal`, not `amount_total`. Tax collected on a sale is the state's money, not the customer's balance, so a session that one day carries tax credits the goods and nothing else.

Everything else answers 200 and does nothing. So does a failed read: Stripe retries a non-2xx, and a retry storm against an upstream that is already unhappy helps nobody. The outcome goes into the audit ring as `stripe.webhook`, and the Payments view shows the last ten.

A session with no checkout row on the named ship is refused `unknown session`. The row is written before the url is ever answered, so a session this ship never made cannot credit it.

## Disputes

A customer can tell its bank the charge was not its own. The money leaves us whatever we do next, so `charge.dispute.created` takes the credit back at once: the dispute is read from Stripe, its PaymentIntent finds the checkout row that kept it, and a `refund` row of the dispute's amount goes on that ship's ledger with `rail` `stripe`, `ref` `dispute-<id>` and `note` `dispute <status>`. The refund op dedupes on its ref, so a second delivery of the same event writes nothing. A dispute that names a payment no row here holds is `unknown payment`.

The account is then reconciled: a lease is recapped to the balance that is left, and disabled when there is none. The balance may go below zero, and it stays there until a top-up covers it. That is the point. The credit was already spent, the money has been taken back, and the proxy and the lease both refuse with a 402 saying the balance is empty.

`charge.dispute.closed` only writes its status into the audit ring as `stripe.dispute`. A dispute won is credited back by the owner, by hand, because only the owner can see that the money really came back.

## Only a ship that spoke over ames can pay

Every payment credits an @p, and an @p is only ever taken from an ames poke. The inbox fiber stamps `seen` on the account on every op it takes, and the writer sets it from nothing else. Each credit path checks the stamp before it writes: a Stripe session or invoice, a BTCPay invoice, or the owner attaching a subscription for a ship that never poked the inbox is refused with `ship: never spoke to us over ames`, whatever the object says. The owner cannot open an account either: a mint for a ship with no account answers 404 until that ship says hello. The reasoning is fraud: a card session's metadata can name any ship, but only the ship itself can produce a signed ames packet, so the balance can only ever land with the @p that asked for it.

## Managed Payments

A Stripe account made after 2026 has Managed Payments on by default: Stripe is the merchant of record for digital goods, and handles sales tax and VAT in some eighty countries, fraud, disputes and transaction-level customer support, for a higher fee per transaction. Prepaid inference credit is a fully automated digital product sold direct, which is what Managed Payments accepts. Two things follow in the code: every line item carries the product tax code, and a session never sends `customer_update`, since Managed Payments collects the name and billing address itself. With it on, the tax and dispute items in the release checklist are Stripe's. It is one Dashboard toggle to turn off, in which case the ship's own dispute handling and Stripe Tax apply.

## Verified against the sandbox

On 2026-09-20 the card rail ran against the Nisfeb sandbox for the first time: a ten dollar top-up through hosted Checkout, credited from the return page; a Talon Pro subscription whose first invoice was delivered as a signed `invoice.paid` and credited twelve dollars; a renewal a month later on a Stripe test clock, credited again with the new invoice id and the renewal date set; and a replay of the same event, verified and refused as already recorded. Three defects the local stub could not show were found and fixed: the tax code, a 500 byte cap on the checkout url (a real one is about 600), and the 2025-03 invoice shape, where the subscription and the price moved under `parent` and `pricing`.

On 2026-09-21 the bitcoin rail ran against a real BTCPay Server (testnet3, on asimov, `docs/superpowers/plans/2026-09-20-armillary-phase-7-release.md` names it): a five dollar checkout made a real invoice in eleven seconds, sneagan paid it from a testnet wallet, it settled after one block, the return page read the invoice back and credited five dollars with the invoice id as the ref, and a replay answered already recorded. The store wallet was watch-only from an xpub, which is what production should use; a hot wallet is refused for a non-admin key by the server policy. Two things stay unproven until a public ship exists: the webhook delivery and Lightning, which needs the store's LND funded with a channel.

## The settings

| field | what it is |
|---|---|
| `stripe_key` | a restricted key, `rk_live_...` or `rk_test_...`, with write on Checkout Sessions, Customers, Products, Prices, Subscriptions and the Billing Portal, and read on Invoices and Disputes. A full secret key works and is a bigger blast radius. Masked on every read; a blank field on save keeps what is stored, an explicit `null` clears it |
| `stripe_webhook_secret` | the endpoint's signing secret, the same rules. Live mode refuses to save without it once a key is set |
| `stripe_url` | the API base, `https://api.stripe.com` unless the gate points it at `scripts/fake-stripe.py` |
| `public_url` | where a customer's browser reaches this ship, which is what the return url and the webhook url are built from |
| `min_topup` | the smallest custom amount, five dollars by default |
| `mode` | `stub` or `live`. Stub mode never calls Stripe at all |

Neither secret ever appears unmasked on a read route, in `/tr/log`, in `/tr/inbox`, or in the account view.

## Plans

`plans.json` is a map by id. A plan is `id`, `name`, `kind` (`topup` or `subscription`), `price` and `credit` in microdollars, `interval` (`month` or `year`, subscriptions only) and `stripe_price`, which is the Stripe Price id. The Price id is an identifier, not a secret, and the customer's `GET /api/plans` carries it.

A top-up plan needs nothing on Stripe: its checkout carries the amount inline. A subscription plan needs a Price, which the owner makes with the Create on Stripe button on the Payments view, or pastes in by hand. A plan an open subscription names cannot be deleted: the next invoice would credit nothing.

## What Stripe needs from the owner

1. A restricted key, `rk_`, with exactly these permissions and nothing else:

| resource | access |
|---|---|
| Checkout Sessions | write |
| Customers | write |
| Products | write |
| Prices | write |
| Subscriptions | write |
| Invoices | read |
| Disputes | read |
| Billing Portal | write |

   A full secret key works too; a restricted one is the smaller blast radius. Billing Portal is there for the self-serve portal that is still to come, and costs nothing to grant now.

2. A webhook endpoint on the public URL, pointing at `<public_url>/apps/armillary/hooks/stripe`, subscribed to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `invoice.paid`, `customer.subscription.deleted`, `charge.dispute.created` and `charge.dispute.closed`.
3. That endpoint's signing secret, pasted into the Payments view. Live mode will not save without it.

Without a public URL the return page still proves the whole flow: it verifies the session from the browser's own visit. The webhook is proven on the production ship, which is the register rule.

## Proving it

`scripts/fake-stripe.py PORT SECRET SHIP_URL` stands in for Stripe: Checkout Sessions, Customers, Invoices, Products, Prices, Subscriptions, Disputes, and the pages that pretend to be a person paying. `POST /stub/pay/<session>` pays one, `POST /stub/fail/<session>` fails a late settlement, `POST /stub/dispute/<session>` opens one dispute on its payment and redelivers the event on every later call, `POST /stub/renew/<sub>` invents the next invoice, `POST /stub/delete/<sub>` reports the subscription gone, and `GET /stub/state` dumps the store. It signs its webhooks with SECRET, or posts them unsigned when SECRET is `-`.

`api-matrix.py` and `ship-matrix.py` both run against it. `live-matrix.py` is the one run by hand, against Stripe test mode with a key from `STRIPE_TEST_KEY`; it prints the checkout url for a person to pay with `4242 4242 4242 4242` and then polls the customer's balance.

## BTCPay Server

BTCPay gives both bitcoin rails from one invoice. Its checkout page offers an on-chain address and a Lightning invoice, it watches the chain, it counts confirmations, and it settles Lightning at once. Nothing in this codebase watches addresses, so BTCPay is the whole of the bitcoin side.

### The flow

A checkout is `POST <btcpay_url>/api/v1/stores/<btcpay_store>/invoices` with `Authorization: token <btcpay_key>` and a JSON body: `amount` as decimal dollars rounded up to the cent, `currency` `USD`, `metadata` carrying the ship and the nonce, and `checkout` carrying `redirectURL`, `redirectAutomatically` and `expirationMinutes` 60. The answer's `checkoutLink` is the url the customer opens, and its `id` is the invoice id the row keeps. The row expires in an hour, which is what the invoice was asked for.

A `checkout` op on the `btcpay` rail with a subscription plan is refused `plan: subscriptions are card only`. A bitcoin customer tops up.

### The two verification paths

Both end in one arm, `+credit-btc-invoice`, which reads the invoice back from BTCPay and does what its `status` says:

| status | what happens |
|---|---|
| `Processing` | the row becomes `processing`, nothing is credited. On chain this is the wait for the store's confirmation count |
| `Settled` | the invoice's `amount` is credited as microdollars with `ref` the invoice id and `rail` `btcpay`, and the row becomes `paid` |
| `Expired` | the row becomes `expired` |
| `Invalid` | the row becomes `invalid` |

The credit is deduped by its ref, so running it twice answers `already recorded` and writes nothing.

- **The webhook**, `POST /hooks/btcpay`, public and without a cookie. `InvoiceSettled`, `InvoiceProcessing`, `InvoiceExpired` and `InvoiceInvalid` each run the arm; every other type answers 200 and does nothing. The outcome goes into the audit ring as `btcpay.webhook`.
- **The return page**, `GET /pay/return?ship&nonce&rail=btcpay`. BTCPay's redirect carries no invoice id, so the nonce finds the checkout row and the row holds the id. This is the one place the ship in the query is used, and only to find the row: the invoice's own metadata is what says whose account this is. A settled invoice says the payment was received; a processing one says the payment was seen and the balance updates once it settles.

### The webhook's trust rule

The body is read for exactly two things: `type` and `invoiceId`. The amount, the ship and the status all come from reading the invoice back with the vendor's own api key.

When `btcpay_webhook_secret` is set, the `BTCPay-Sig` header is checked first: the header must read `sha256=` followed by the lowercase hex HMAC-SHA256 of the raw body with the secret, compared with a fold that does not stop at the first difference. A bad or missing signature is 401 and nothing else happens. Everything past a good signature answers 200, even a failed read, because BTCPay retries a failed delivery six times.

An invoice with no checkout row on the named ship is refused `unknown invoice`. The row is written before the url is ever answered.

### The settings

| field | what it is |
|---|---|
| `btcpay_url` | the instance, such as `https://btcpay.example.com`. A trailing slash is stripped when it is read |
| `btcpay_store` | the store id the invoices belong to |
| `btcpay_key` | the api key. Masked on every read; a blank field on save keeps what is stored, an explicit `null` clears it |
| `btcpay_webhook_secret` | the store webhook's secret, the same rules |

Neither secret ever appears unmasked on a read route, in `/tr/log`, in `/tr/inbox`, or in the account view.

### What BTCPay needs from the owner

1. A BTCPay Server store, self-hosted or hosted, with a wallet on it.
2. An api key on that store with `btcpay.store.cancreateinvoice` and `btcpay.store.canviewinvoices`, and nothing else.
3. A webhook on the store pointing at `<public_url>/apps/armillary/hooks/btcpay`, with a secret, subscribed to `InvoiceSettled`, `InvoiceProcessing`, `InvoiceExpired` and `InvoiceInvalid`.
4. The store id, the instance url, the api key and the webhook secret, pasted into the Payments view.

Subscriptions are card only, so a store with no Stripe key beside it sells top-ups and nothing else.

Without a public URL the return page still proves the whole flow: it verifies the invoice from the browser's own visit. The webhook is proven on the production ship, which is the register rule.

### Proving it

`scripts/fake-btcpay.py PORT SECRET SHIP_URL` stands in for BTCPay: the two Greenfield invoice routes and a checkout page with three buttons. `POST /stub/pay/<id>` settles an invoice the way Lightning does, `POST /stub/processing/<id>` marks it seen the way a chain payment does, `POST /stub/expire/<id>` expires it, and `GET /stub/state` dumps the store. It signs its webhooks with SECRET, or posts them unsigned when SECRET is `-`.

`api-matrix.py` and `ship-matrix.py` both run against it. `live-matrix.py` is the run by hand, against a real store, with `BTCPAY_URL`, `BTCPAY_STORE` and `BTCPAY_KEY` in the environment; it prints the invoice url for a person to pay from a testnet wallet and then polls the customer's balance for half an hour.
