# Installing Armillary on your ship

Armillary is the paid inference tier for Talon. It runs on your own Urbit ship, keeps your account there, and talks to the vendor ship over ames, which is how the vendor knows every purchase comes from a real @p. You need the Grubbery shell on your ship already, the same one Lattice, Auspex and the Calendar run in.

## 1. Install the desk

1. Open your ship's Grubbery home page and press **Get Apps** at the top.
2. In the search box type `~ricsul-bilwyt` and press **search**.
3. Ricsul's published apps appear. Press **Install** on **Armillary**, keep the name `armillary`, and confirm.
4. Within a minute or two the bell at the top of the home page shows one item. Press **Review**, read the roads Armillary asks for, and approve them all. Each one says why it is there; the two that matter most are ames (your account on the vendor) and gall (the pokes that open it and buy credit).

That is the whole install. Your ship now serves `/apps/armillary`, and Talon can find it.

## 2. Turn it on in Talon

1. In Talon go to Settings, AI, and add the **Armillary** provider.
2. Talon sets the vendor to `~nisfeb` and your ship introduces itself over ames. The card fills with a balance of $0.00 within a minute; if it says your ship is still introducing itself, give it a moment and press Refresh.
3. Press **Top up**, pick $5, $10, $50 or another amount, choose Card or Bitcoin, and Continue. Card opens Stripe Checkout in your browser; Bitcoin opens a BTCPay invoice. Tax may be added at checkout. The card shows "Waiting for your payment" and then the credit landing.
4. Pick a model. Every request is charged against your balance at the vendor's posted price, and Talon warns you when the balance is low.

## 3. What you can see on your ship

`/apps/armillary` on your ship, with your ship's own login, shows your account: the vendor, the balance, top-ups, a Usage card for the last thirty days by model, and the full ledger. This is your receipt inside the ship; Stripe and BTCPay also mail one. The **Provider mode** switch in the header reveals the views that run a service. You do not need them to be a customer; they exist for ships that sell inference themselves.

## If something is off

- **Get Apps shows nothing for ~ricsul-bilwyt.** Your ship cannot reach ricsul over ames yet. Wait a minute and search again; a fresh ship sometimes needs a moment to find a new peer.
- **The card says "Not on this ship".** The desk is installed but its permissions are not approved yet. Open the bell on the Grubbery home page, or go to Sandbox Settings, and approve Armillary.
- **The balance stays empty after a payment.** A card payment lands within a minute of Stripe confirming it; a bitcoin payment needs one confirmation, usually ten to twenty minutes. Press Refresh on the card. If it still has not landed after that, tell the vendor with the time you paid and the last four digits of the card, or the invoice id.
- **A request answers "balance is empty".** Top up from the card. Your balance is charged by the vendor's ten-minute reconcile, so a run of requests can overshoot slightly before the warning shows.
