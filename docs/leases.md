# Leases

A lease is the path for clients the vendor owns. Instead of proxying every request through two ships, the vendor hands the customer a real provider key with a spending cap equal to what its balance buys, the client calls the provider directly, and the vendor reconciles what was spent every ten minutes.

No tokens cross either ship on this path. Streaming works, tools work, images work, and the latency is the provider's own.

In v1 a lease is an OpenRouter runtime key made through the key provisioning API. OpenRouter keys carry a `limit` in dollars, report `usage` in dollars, and can be `disabled`, which is exactly the shape a prepaid balance needs.

## What the owner sees

The Accounts list carries a Lease column: `none`, `active`, `disabled`, or `stale` when the tick has not read the key in over twenty minutes. The account detail's Lease card shows the key's hash and provider, when it was made, the state, and a table of spent, cap and left-under-the-cap in both the provider's dollars and the customer's at the markup, plus when it was last reconciled. "Read from the provider now" fetches the key as the provider sees it this second, through the provisioning key, and shows usage today, this week and this month, the cap, what the provider itself says remains, whether it is disabled there, and any usage not yet billed with what it will bill at the next reconcile. The lease's own charges are listed below, newest first. "Reconcile now" moves the ship's figures; the live read moves nothing.

## What the owner supplies

One thing: an OpenRouter provisioning key on the OpenRouter provider row, under Providers. Then, on the Payments view, pick that provider under Leases. A blank lease provider means this vendor offers no leases, and every customer asking for one is told so.

The provisioning key is a secret. It is stored on the provider row, masked on every read route, and never written into the audit ring.

## The cap rule

The one number is the markup in settings, the same percent the catalog's import uses to fill proxy prices from cost, so the two paths charge alike for the same model.

- A fresh lease is capped at `balance / markup`, in dollars.
- On every reconcile the cap moves to `usage + balance / markup`, where `usage` is what OpenRouter says the key has spent so far. OpenRouter counts a key's limit from zero, so the cap has to carry what is already spent.
- A balance at or below zero caps the key at what it has already spent, and sets `disabled` as well. Either one stops it; both is belt and braces.
- A credit raises the cap and clears `disabled` on the next reconcile.

## The reconcile

`+reconcile` is the one arm every lease path uses. It runs on the ten minute tick for every account whose lease was last read more than nine minutes ago, and at once on every `lease` op from a customer, on the owner's Reconcile now button, and on the owner's Drop lease button by way of the delete.

Each pass does this:

1. Read the key from OpenRouter by its hash. A non-2xx answer leaves the row alone and reports what the provider said.
2. When `usage` is above `usage_seen`, write one `debit` row for `(usage - usage_seen) * markup`, rounded up, with `cost` the raw difference, `model` `openrouter`, `mode` `lease` and `ref` `lease-<unix seconds>`.
3. Work out the balance after that debit here rather than reading it back: the writer applies the poke after the fiber has moved on, so a read would see the balance as it was.
4. When the cap or the switch differ from what is stored, PATCH them upstream. On a 2xx the row takes the new figures; on a failure the row keeps the cap it has and records only what was learned, so it never claims a cap upstream never took.

A closed account's reconcile deletes the key upstream and drops the row. So does the owner's Close account button, the owner's hard delete of an account, and the customer's own Drop.

## What the client does

Exactly what it does for the proxy: read `GET /api/inference` on its own ship.

    {"mode": "lease", "base_url": "https://openrouter.ai/api/v1", "key": "sk-or-v1-...", "models": [...]}

When the ship holds a lease that is not disabled, that route answers lease mode with the provider's own base URL and the leased key. Otherwise it answers proxy mode with the vendor's base URL and the newest inference key, as before.

That is the whole fallback. A lease that has run out of money is `disabled`, so the route answers proxy mode, and the proxy answers 402 with a line a person can read. The client keeps its one code path either way.

`POST /api/lease` takes a lease and answers it. `DELETE /api/lease` gives it back: the ship forgets the key at once, so a key that is gone here is gone here even if the vendor is down, and the vendor deletes it upstream when the op lands.

## Where the key lives

The plaintext key is written in three places and nowhere else: the vendor's `/accounts/<ship>/lease.json`, that one ship's own account view, which its own usergroup alone may peek, and the customer's `/lease.json`.

No owner read route answers it. `GET /api/accounts/<ship>` shows the hash, the provider, the usage, the cap and the switch. No audit row carries it: the ring names the op, the ship and the hash.

## The two things a lease cannot do

**It cannot limit the key to the catalog's models.** An OpenRouter key can spend on any model OpenRouter sells, at the owner's cost times the markup, capped by the balance. The `models` list in the lease is advice to the client, not a rule.

**It cannot stream through the ship.** That is the point: the client talks to the provider, so the ship is not in the path at all. Anything that needs the ship in the path, per-model pricing or per-request rules, is the proxy's job.

Bedrock and the other providers have no per-customer capped key, so they are proxy only. A Bedrock lease would need short-term credentials signed on the ship, which is a later phase if it is ever wanted.
