# The account channel over ames

Everything a customer ship does that is not inference is a JSON op poked from its armillary desk into the vendor's `/inbox.sig`, and every answer is a grub in that ship's account view on the vendor, which that ship alone may peek. This is orrery's sharing mechanism with the roles fixed: the vendor is always the host, the customer always the guest. Inference itself is plain HTTP with a bearer token and does not come through here.

## How it works

- `PUT /apps/armillary/api/vendor` with `{"ship": "~wex"}` on the customer ship records the vendor in `vendor.json` and queues a `hello`. `{"ship": ""}` clears it and the client fiber goes back to sleep.
- The client fiber at `/client.sig` sends every op in `client.json` that is not yet sent, waits two seconds, peeks the view, and stores it. It does that again every five minutes and whenever a request fiber prods it.
- On the vendor, `/inbox.sig` is registered on the `/public` usergroup, so any ship may poke it. The source ship of the poke is the account: no op names a ship, and the inbox never trusts one that did. A ship with no account gets one on its first op.
- The vendor's writer rewrites `/accounts/<ship>/view.json` whole at the end of every op that touches that account, so the view is never stale. The grant is a usergroup named for the ship, `armillary-<name>.grp` under `/sys/ames/usergroups`, holding that one ship with peek on that one file. Nothing about one account is readable by another ship.
- `catalog-public.json` and `plans.json` are granted to `/public`, so a customer can read what the vendor sells before it has an account.

## The ops

| op | fields | what the vendor does |
|---|---|---|
| `hello` | | opens the account, makes the ship's usergroup, writes the view |
| `refresh` | | rewrites the view |
| `checkout` | `rail`, `plan` or `amount`, `nonce` | writes a checkout row into the view. In stub mode the url is the vendor's own `/pay/stub` page; in live mode it is a Stripe Checkout Session, and a refusal is a row with status `refused` and a `note` saying which field was wrong. `docs/payments.md` |
| `mint-key` | `name`, `nonce` | mints an inference key, stores the salted hash, and writes `{nonce, id, name, secret}` into the view's `keys_pending` |
| `got-key` | `id` | clears that secret from `pending.json` and from the view |
| `drop-key` | `id` | revokes the key on the poking ship's account |
| `cancel-subscription` | | asks Stripe to stop the subscription renewing. The row on the account stays until `customer.subscription.deleted` arrives |
| `lease`, `drop-lease` | | noted as `not yet` in `/tr/inbox` and dropped. Phase 5 |

## The view

`/accounts/<ship>/view.json` on the vendor holds `ship`, `balance`, `plan`, `subscription`, `keys`, `keys_pending`, `lease`, `checkouts`, `ledger` (the last 50 rows), `public_url`, `rev` and `updated`. The view's `subscription` is `{active, renews}` and never the Stripe ids: those are the vendor's, and only the owner's own read of the account carries them. A checkout row is `{nonce, rail, plan, amount, url, sid, expires, status, note}`. The customer stores what it read verbatim in its own `/view.json` with a `fetched` stamp, and `GET /api/account` answers that plus `vendor`, `self` and `stale`.

`keys_pending` is the one place a secret crosses the wire. It is there because the ship it belongs to is the only ship that may peek the file, and it goes as soon as that ship says `got-key`. A key revoked or an account closed before the fetch clears the row too, so nothing is left waiting for nobody.

## The nonce rule

Every op that can be repeated carries a nonce the customer chose, and the vendor is idempotent under it: a `mint-key` whose nonce is already in `pending.json` mints nothing, and a `checkout` whose nonce is already in `checkouts.json` answers the row that is there. The customer keeps the op in `client.json` until its nonce shows in the view, and then drops it. An op with no nonce of its own (`hello`, `refresh`, `got-key`, `drop-key`) is dropped as soon as the send is taken, since it can never be seen in the view.

## The timeout rule

A remote poke's ack is unobservable in grubbery, so a timeout is unknown, not failure. `remote-poke-wait` gives up after thirty seconds and answers yes: the poke usually landed, and the view is what settles it. A peek gives up after thirty seconds and answers nothing, which leaves whatever the customer already knew in place. Nothing in the client fiber treats silence as an error.

The routes that wait do so for thirty seconds and then answer 202 with the nonce rather than an error: `POST /api/keys` and `POST /api/checkout`. The op is still queued and the next pass will land it.

## What to know

- A vendor and its customer can be the same ship. `vendor.json` naming our own ship makes a local poke instead of an ames one and a local read instead of a peek, and the page's customer views and provider mode both work against the one ship. That is what the single-ship gate runs on.
- Comets are accepted. On the groundwire network a comet is paid for before ames will carry its packets, so a comet whose poke lands is already a paid-for identity. A vendor elsewhere sets `refuse_comets` and their ops are noted `comet refused` and dropped.
- Ship traffic is logged in `/tr/inbox`, a ring of 500 of its own, so nothing a stranger sends can push the owner's audit log out of `/tr/log`. Read it at `GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/tr/inbox?raw=1`.
- No secret reaches either ring. The vendor's audit row for a mint names the op and the ship; the customer's names the key id.
- Deleting an account with `DELETE /api/accounts/<ship>` empties its group as well as its directory, so the ship loses the peek with the account.
- The ask grows by poke on `/sys/gall/` and `/sys/ames/registry`, peek on `/sys/ames/ships/` and `/sys/ames/usergroups/`, and make on `/sys/ames/usergroups/`. Refuse the two vendor roads and this ship cannot sell; refuse the two customer roads and it cannot buy. Everything else keeps working either way.
