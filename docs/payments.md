# Payments

A customer buys credit with a card. The vendor makes a Stripe Checkout Session, the person pays on Stripe's own page, and the vendor credits the ship's account once it has read the payment back from Stripe. Bitcoin is phase 4 and answers `unavailable` until then.

## The checkout flow

1. The customer ship pokes a `checkout` op into the vendor's inbox with a rail, a nonce, and either a plan id or an amount in microdollars. That is the account channel, `docs/channel.md`.
2. The vendor's inbox fiber reads settings. In stub mode it answers its own `/pay/stub` page and nothing else happens. In live mode, for the `stripe` rail, it builds a Checkout Session and sends it.
3. Every refusal is a checkout row with status `refused` and a `note` saying which field was wrong: `stripe_key: not set`, `plan: unknown`, `amount: below the minimum`, `plan and amount: choose one`, `plan: not on Stripe yet`. The customer only ever sees the view, so a refusal has to live there.
4. On a 2xx, the row is written with the session url, status `pending` and the session id. The customer's `POST /api/checkout` answers that url, or 502 with the note when the row was refused.
5. The person pays. Stripe sends them to `<public_url>/apps/armillary/pay/return?ship=<ship>&sid=<session>`, and sends the vendor a webhook.

A top-up is `mode=payment` with one inline line item at the amount. A subscription is `mode=subscription` on the plan's Stripe Price, with the ship and the plan id in the subscription's own metadata, so an invoice months later still says which plan it renews.

The Stripe call runs inside the inbox fiber. That serializes every customer's ops behind one slow call, for up to two minutes. It is marked in the code with a `ponytail:` comment; a spawned fiber per op is the upgrade when a vendor has enough customers to feel it.

## The two verification paths

Both end in the same two arms, `+credit-session` and `+credit-invoice`, and both are safe to run twice: a credit whose `ref` is already in the ledger writes nothing and answers `already recorded`.

- **The webhook**, `POST /hooks/stripe`, public and without a cookie. Stripe calls it when it can.
- **The return page**, `GET /pay/return`, which the person's own browser loads on the way back. It verifies the same session, so a payment is credited even when the webhook is late or the public URL was never reachable from the internet. That is the register rule: the browser round trip is the path that always exists.

Whichever arrives first credits; the second finds the ref recorded and does nothing.

## The webhook's trust rule

The body of a webhook is read for exactly two things: the event `type` and `data.object.id`. Everything else, the amount, the ship, whether it was paid, comes from reading that object back from Stripe with the vendor's own key. A forged body can at worst name a real session, which then reads back as whatever it really is.

When `stripe_webhook_secret` is set, the `stripe-signature` header is checked first: HMAC-SHA256 over `<t>.<raw body>` with the signing secret, compared against the `v1` element, with a five minute tolerance and a byte comparison that does not stop at the first difference. A bad or missing signature is 400 and nothing else happens. With no signing secret set, reading the object back is the only trust, which is register's stance.

Four event types do anything:

| event | what happens |
|---|---|
| `checkout.session.completed` | read the session, credit `amount_total` cents times 10.000, mark the checkout row paid, and on a subscription session store the Stripe customer and subscription ids |
| `checkout.session.async_payment_succeeded` | the same, for a payment method that settles later |
| `invoice.paid` | read the invoice, find the account by its Stripe customer id, credit the plan's `credit`, and set `renews` from the invoice's period end |
| `customer.subscription.deleted` | find the account holding that subscription id and clear its subscription |

Everything else answers 200 and does nothing. So does a failed read: Stripe retries a non-2xx, and a retry storm against an upstream that is already unhappy helps nobody. The outcome goes into the audit ring as `stripe.webhook`, and the Payments view shows the last ten.

A session with no checkout row on the named ship is refused `unknown session`. The row is written before the url is ever answered, so a session this ship never made cannot credit it.

## The settings

| field | what it is |
|---|---|
| `stripe_key` | the secret key. Masked on every read; a blank field on save keeps what is stored, an explicit `null` clears it |
| `stripe_webhook_secret` | the endpoint's signing secret, the same rules |
| `stripe_url` | the API base, `https://api.stripe.com` unless the gate points it at `scripts/fake-stripe.py` |
| `public_url` | where a customer's browser reaches this ship, which is what the return url and the webhook url are built from |
| `min_topup` | the smallest custom amount, five dollars by default |
| `mode` | `stub` or `live`. Stub mode never calls Stripe at all |

Neither secret ever appears unmasked on a read route, in `/tr/log`, in `/tr/inbox`, or in the account view.

## Plans

`plans.json` is a map by id. A plan is `id`, `name`, `kind` (`topup` or `subscription`), `price` and `credit` in microdollars, `interval` (`month` or `year`, subscriptions only) and `stripe_price`, which is the Stripe Price id. The Price id is an identifier, not a secret, and the customer's `GET /api/plans` carries it.

A top-up plan needs nothing on Stripe: its checkout carries the amount inline. A subscription plan needs a Price, which the owner makes with the Create on Stripe button on the Payments view, or pastes in by hand. A plan an open subscription names cannot be deleted: the next invoice would credit nothing.

## What Stripe needs from the owner

1. A restricted key with write on Checkout Sessions, Products, Prices and Subscriptions, and read on Invoices. A full secret key works too; a restricted one is the smaller blast radius.
2. A webhook endpoint on the public URL, pointing at `<public_url>/apps/armillary/hooks/stripe`, subscribed to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `invoice.paid` and `customer.subscription.deleted`.
3. That endpoint's signing secret, pasted into the Payments view.

Without a public URL the return page still proves the whole flow: it verifies the session from the browser's own visit. The webhook is proven on the production ship, which is the register rule.

## Proving it

`scripts/fake-stripe.py PORT SECRET SHIP_URL` stands in for Stripe: Checkout Sessions, Invoices, Products, Prices, Subscriptions, and the pages that pretend to be a person paying. `POST /stub/pay/<session>` pays one, `POST /stub/renew/<sub>` invents the next invoice, `POST /stub/delete/<sub>` reports the subscription gone, and `GET /stub/state` dumps the store. It signs its webhooks with SECRET, or posts them unsigned when SECRET is `-`.

`api-matrix.py` and `ship-matrix.py` both run against it. `live-matrix.py` is the one run by hand, against Stripe test mode with a key from `STRIPE_TEST_KEY`; it prints the checkout url for a person to pay with `4242 4242 4242 4242` and then polls the customer's balance.
