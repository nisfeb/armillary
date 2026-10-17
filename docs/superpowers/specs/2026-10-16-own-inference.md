# Armillary as the inference provider for Talon and Orrery

Date: 2026-10-16. Talon's own AI settings are going away, and Armillary becomes the one place Talon and Orrery get inference. By default a ship pays `~nisfeb`. An owner who wants to run their own inference points their ship at itself and adds whatever providers they like: self-hosted servers, cloud APIs, or both at once.

## What stays as it is

Keys stay on the ship. An app gets one base URL and one armillary key from `GET /api/inference` (or `app-inference.json`), and the ship's catalog sends each model to its own provider. That catalog is already a router across providers, so a mix of Ollama, vLLM, llama.cpp, LM Studio, OpenAI, Groq, Together, Mistral, OpenRouter, and Gemini's or Anthropic's OpenAI-compatible endpoints all sit behind the one address. A self-hosted server on the owner's LAN is reachable from a phone anywhere, because the ship reaches it and the phone reaches the ship.

We do not hand provider keys to apps. The app's header says secrets never leave, and a phone holding an uncapped OpenAI key is a worse place to be than a phone holding an armillary key. A lease stays the one exception, since its key is capped.

## Version 33: an owner's own inference is free

- `settings.json` gains `own_free`, a boolean. Absent or false is today's behaviour, so `~nisfeb`, which buys from itself to test the live rails, is unchanged. When it is true and the key on a call belongs to this ship's own account, the call is not charged. The proxy skips the balance gate and writes no debit, and so does the Brave proxy. Searches are still counted.
- The proxy's refusal of transcription on a provider that is not OpenRouter exists because other providers report no cost. A free call needs no cost, so the refusal is lifted for it. The request shape is still OpenRouter's JSON until version 34.
- The proxy waits ten minutes for an upstream instead of two. A local model on modest hardware, and Orrery's generator, which itself allows ten, need the time.
- An import that finds a model id another provider's row already holds adds it as `<provider id>/<model id>` instead of dropping it. Two servers offering `llama3.1:8b` are both in the catalog.
- The page's Payments view has a "Your own use" card for the switch.

A ship with no `public_url` answers `http://localhost:8080` as its base, which a phone cannot reach. An owner running their own inference sets `public_url`. Talon can also rewrite that origin to the ship address it already uses when the vendor is the ship itself.

## Version 34: decisions and transcription everywhere

- `POST /apps/armillary/alpha/decisions` forwards to OpenRouter's decisions route. The model must be the vendor's suggested decision tier, since an open model field would make the route a gateway to anything. It goes to the lease provider when one is set, else the only OpenRouter provider. The charge is the `usage.cost` OpenRouter reports, at the markup. An answer without a cost is answered 502 and charged nothing. An app finds the route from its base URL: a trailing `/v1` becomes `/alpha/decisions`. That turns OpenRouter's `https://openrouter.ai/api/v1` into its own decisions URL and the proxy's base into this route, so one rule serves a lease and the proxy. Orrery's `decider-url` and Talon's `Decider` take that rule.
- Transcription on an `openai-compatible` provider: the ship takes the same JSON body, decodes the base64 audio and sends the upstream the multipart form OpenAI's API, Groq, whisper.cpp's server and speaches all read. Only a free call may take it. A paying customer stays refused there until a catalog row can carry a price per second, since such a provider reports no cost. Decoding on the ship is slow: a 3.6 MB clip took 11.4 s on a dev ship, so the 16 MB cap is near a minute.
- `GET /api/inference` and `app-inference.json` gain `free`, true when the ship is its own vendor with `own_free` on. Talon turns a cloud feature on only once there is a balance, and a free ship's balance stays at zero, so this is what tells it the features may run.

## Version 35: any provider's models for speech and decisions

- An import tags a model whose id says `whisper` or `transcribe` as speech to text on any provider, Talon's own rule, so an owner's whisper server can be the Transcription tier.
- Jev is offered for the decision tier only where there is an OpenRouter provider.
- A decision tier may name any chat model the catalog sells. The route then asks that model through its own provider in one chat completion for the answers as JSON, read back into the decisions shape, every question checked against its type; a reply that fails is 502 and charges nothing. The answers are the model's stated probabilities, rougher than Jev's.

## Version 36: the review

The fixes a full review found on 2026-10-17 are listed in the README under "Version 36". Two bear on this spec: a free ship's account view has no balance or top-up, and the Payments view's "Your own use" card shows each step with a Use this ship button, which is most of the one step below.

## Next: one step to your own key

v33 makes an owner's own inference free, but setting it up still means Provider mode, a provider, an import, enabling rows, tiers, and pointing the vendor at the ship. A page route, `#own`, does it in one form: the provider and its key, then the existing routes in order (add the provider, import, enable the rows the vendor currently suggests where the import has them, copy the vendor's tiers and features, turn on `own_free`, point the vendor at the ship, and mint a key so `GET /api/inference` answers one that works on the ship's own proxy). Talon's "Manage models in Armillary" button links there. Not built yet.

## Not built

- A `device` tier, a feature that runs on the customer's device and calls nobody. sneagan decided on 2026-10-16, for Talon, that paying is the opt-in for cloud reading, and Talon resolves every feature to the vendor's suggested model, so nothing would map to it. It is built and tested on the branch `feat/device-tier`, unreleased.
- Streaming. Only Brave Leo streams, and Talon already tells a Leo user to take a lease. Real streaming through the ship needs vere to pass a response on in parts, and `cttp.c` buffers the whole response ("XX inject partial responses as separate events"). A buffered imitation would answer Leo but stream nothing, so it waits until a client needs it.
- A native Anthropic kind. Anthropic and Gemini both serve an OpenAI-compatible endpoint, which the `openai-compatible` kind already reaches.
- A routes map from model to provider for apps to call directly. See "What stays as it is".
