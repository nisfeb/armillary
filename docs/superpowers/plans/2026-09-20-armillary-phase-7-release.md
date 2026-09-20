# Armillary Phase 7: release

**Goal:** a production vendor ship selling real inference for real money to Talon users, with the desk reaching customer ships from `~ricsul-bilwyt` like the rest of the family. This is a checklist, not a build: everything below is configuration, live verification and publishing. The steps marked **sneagan** are his and never an agent's (`/feedback/never-publish-grubbery-on-ricsul`, `/feedback/deploy-only-to-tyr`). Written 2026-09-20 ahead of phase 5's completion; the lease and report steps assume version 6.

## 1. The vendor ship

- **sneagan** chooses and runs the production vendor ship: a groundwire comet on asimov like `~hadmyn` and `~foppel` (`/project/groundwire/asimov-comet`), or a planet. It needs grubbery at the release the family runs, a public HTTPS domain (nginx and certbot on asimov, the `ponlen.nisfeb.com` idiom), and a loom that will not hit the wall under real traffic: `--loom 33` at least, since `~wex` at `--loom 31` melded twice this week.
- Install the desk on it from GitHub through its forge, the phase 1 recipe: `POST /grubbery/forge/api/add {"name":"armillary","repo":"nisfeb/armillary","ref":"main"}`, wait for the pull, `POST /apps/grubbery/desks/add {"name":"armillary","code":"/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code"}`, approve the ten-road ask on `/apps/grubbery/permits`, reload, bang null.
- On the page: `mode` `live`, `public_url` the domain, `markup_pct`, `min_topup`, `refuse_comets` off, `lease_provider` the OpenRouter row.

## 2. Providers and the catalog

- Add the OpenRouter provider with a runtime key and a provisioning key (both minted at openrouter.ai with credit on the account; the provisioning key is what mints customer leases and must never be a key Talon holds).
- Add Bedrock as an `openai-compatible` row: base `https://bedrock-mantle.<region>.api.aws/v1`, an Amazon Bedrock API key from an IAM user with `bedrock:InvokeModel` on the models to sell. Any other OpenAI-compatible vendor the same way.
- Import each provider's models, set the prices where import gave none, enable the rows to sell, and Test each provider from the page. Save the catalog; `catalog-public.json` republishes.

## 3. Money

- **Stripe.** A restricted key with Checkout Sessions, Products, Prices, Subscriptions and Invoices read and write; a webhook endpoint at `<public_url>/apps/armillary/hooks/stripe` with `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `invoice.paid`, `customer.subscription.deleted`; the signing secret into settings. Create the plans on the page: the Talon subscription (`kind` `subscription`, monthly, its `credit`), one or two top-ups. `POST /api/plans/<id>/stripe` makes the Product and Price. Then `live-matrix.py`'s Stripe half by hand with `STRIPE_TEST_KEY` first, then the live key.
- **BTCPay Server.** An instance (self-hosted on asimov or hosted), a store, an API key with `btcpay.store.cancreateinvoice` and `btcpay.store.canviewinvoices`, a webhook on the store to `<public_url>/apps/armillary/hooks/btcpay` with a secret and `InvoiceSettled`, `InvoiceProcessing`, `InvoiceExpired`, `InvoiceInvalid`; a Lightning node behind the store for the second rail. `live-matrix.py`'s BTCPay half by hand on testnet first (`BTCPAY_URL`, `BTCPAY_STORE`, `BTCPAY_KEY`).
- **Leases.** `live-matrix.py`'s lease half by hand with `OPENROUTER_PROVISIONING_KEY`: one real lease, one real completion, a tick, the debit, then drop.
- **Books.** Decide with whoever does the taxes how prepaid credit is recognised (deferred until spent) and how bitcoin receipts are valued (BTCPay's dollar amount at invoice time, which is what the ledger records). The report view gives credits by rail, charged, cost and margin over any window.

## 4. Customers get the desk

- A customer ship runs grubbery and installs `%armillary` from `~ricsul-bilwyt` the way it installs orrery or calendar. **sneagan** does the ricsul steps in `docs/releasing.md` sections 6 and 9: the forge repo on ricsul, the desk following it, the ask granted, then either a beta usergroup and `POST /grubbery/desk/armillary/share {"add":"/<group>"}`, or the stock desk line in `gub/nex/shell.hoon` and `|public`.
- On the customer ship the desk's `vendor.json` is empty until the page or Talon sets it. Talon's card sets it to the vendor ship on Add; decide the default vendor ship Talon offers (`ArmillaryRepo` takes it from the card; a constant in Talon for the production vendor is a one-line change in the talon repo).
- First customers: sneagan's own ships, then the beta group, then Talon's release notes.

## 5. Talon

- **sneagan** merges `feat/armillary` into the release branch and cuts the release: `talonVersionCode` and `talonVersionName`, the release commit, the tag, the push over port 443 (`/project/talon-repo-topology`). The in-app changelog is the commit body; say what Armillary is in one paragraph.
- Store listings: the rewritten `store/description.md`, `store/privacy-policy.md`, `store/data-safety.md` and `PRIVACY.md` go up with the release; Google Play's data safety form must be re-answered to match (a third party receives data when the provider is added).
- A device run on Android and on iOS of the card, the top-up through a real Stripe test session, and one completion in lease mode, before the release is public.

## 6. Watch the first week

- The vendor's Report view daily: credits by rail against Stripe's and BTCPay's own dashboards, charged against cost, and OpenRouter's key usage against the ledger's lease debits.
- `/tr/log` for `stripe.webhook` and `btcpay.webhook` rows that are not ok, and `/tr/inbox` for refused ops.
- The tick: every account with a lease has `checked` within the last ten minutes; a lease whose `disabled` flipped without a zero balance means a reconcile failed.
- Loom on the vendor ship: `|meld` at the first `meme`, and a bigger loom at the next restart.

## What phase 5 leaves for this checklist

Nothing in the code. Every item above is a key, a domain, a decision or a publish, and the publish steps are sneagan's.
