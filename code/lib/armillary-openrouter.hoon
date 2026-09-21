::  armillary-openrouter: the key provisioning API, pure.
::
::    A lease is an OpenRouter runtime key with a spending cap. Every
::    arm here builds a request:http a fiber may send, or reads a body
::    a fiber received. Nothing does IO. The provisioning key is a
::    sample, never a constant: it lives on a provider row and passes
::    through.
::
::    Import-free like the other provider libs, so the JSON getters and
::    the decimal reader below are copied from /lib/armillary.hoon
::    rather than imported. A lib that imports a lib cannot build in
::    both the clay desk and the app's code namespace, which is the
::    rule the whole desk follows.
::
|%
::  ==  copied from /lib/armillary.hoon: json, read without crashing
::
++  gj
  |=  [jon=json k=@t]
  ^-  json
  ?.  ?=([%o *] jon)  ~
  (fall (~(get by p.jon) k) ~)
++  gs
  |=  [jon=json k=@t]
  ^-  @t
  =/  v=json  (gj jon k)
  ?:(?=([%s *] v) p.v '')
++  gb
  |=  [jon=json k=@t]
  ^-  ?
  =/  v=json  (gj jon k)
  ?:(?=([%b *] v) p.v |)
::  +de-body: a response body as JSON, null when it is not JSON at all
::
++  de-body  |=(body=@t ^-(json (fall (de:json:html body) ~)))
::  +de-dec: a decimal string to an integer scaled by 10^scale. Copied
::  from /lib/armillary.hoon for the same import-free reason.
::
++  de-dec
  |=  [t=@t scale=@ud]
  ^-  (unit @ud)
  =/  tap=tape   (trip t)
  =/  whole=@ud  0
  =/  frac=@ud   0
  =/  digits=@ud  0
  =/  dotted=?   |
  =/  any=?      |
  |-  ^-  (unit @ud)
  ?~  tap
    ?.  any  ~
    `(add (mul whole (pow 10 scale)) (mul frac (pow 10 (sub scale digits))))
  =/  c=@t  i.tap
  ?:  =('.' c)
    ?:  dotted  ~
    $(tap t.tap, dotted &)
  ?.  &((gte c '0') (lte c '9'))  ~
  =/  d=@ud  (sub c '0')
  ?.  dotted
    $(tap t.tap, whole (add (mul whole 10) d), any &)
  ?:  (lth digits scale)
    $(tap t.tap, frac (add (mul frac 10) d), digits +(digits), any &)
  $(tap t.tap, any &)
::  ==  money, as OpenRouter writes it
::
::  +usd-of: microdollars as the decimal number a limit carries. Six
::  places, so one microdollar survives the trip out and back.
::
++  usd-of
  |=  micro=@ud
  ^-  @t
  =/  whole=tape  (a-co:co (div micro 1.000.000))
  =/  rest=@ud  (mod micro 1.000.000)
  =/  digits=tape  (a-co:co rest)
  =/  pad=@ud  (sub 6 (lent digits))
  =/  zeros=tape  (reap pad '0')
  (crip :(weld whole "." zeros digits))
::  +micro-of: a JSON number to microdollars. OpenRouter sends numbers,
::  not strings, and a json %n carries its digits as text, so the same
::  decimal reader serves. Anything past six places is truncated: a
::  fraction of a microdollar is not money we can write down.
::
++  micro-of
  |=  j=json
  ^-  (unit @ud)
  ?.  ?=([%n *] j)  ~
  (de-dec `@t`p.j 6)
::  ==  where the keys live
::
::  +keys-base: the provisioning collection under a provider's base
::  url. A base url names the inference API (.../api/v1 on OpenRouter,
::  .../v1 on the stub) and the keys live beside it at /api/v1/keys, so
::  the inference suffix comes off and the management one goes on.
::
++  keys-base
  |=  base-url=@t
  ^-  @t
  =/  b=tape  (trip base-url)
  =/  cut=tape
    ?:  =("/api/v1" (slag (sub (lent b) (min 7 (lent b))) b))
      (scag (sub (lent b) 7) b)
    ?:  =("/v1" (slag (sub (lent b) (min 3 (lent b))) b))
      (scag (sub (lent b) 3) b)
    b
  =/  trimmed=tape
    ?:(&(?=(^ cut) =('/' (rear `tape`cut))) (snip `tape`cut) cut)
  (crip (weld trimmed "/api/v1/keys"))
::  ==  the pieces every request shares
::
::  +heads: the two headers a write call carries. OpenRouter's
::  management API takes the provisioning key as a bearer.
::
++  heads
  |=  key=@t
  ^-  (list [@t @t])
  :~  ['authorization' (rap 3 'Bearer ' key ~)]
      ['content-type' 'application/json']
  ==
::  +auth-only: the same without a content type, for a GET or a DELETE
::
++  auth-only
  |=  key=@t
  ^-  (list [@t @t])
  ~[['authorization' (rap 3 'Bearer ' key ~)]]
::  +key-at: one key's own route, by its hash
::
++  key-at
  |=  [base=@t hash=@t]
  ^-  @t
  (rap 3 base '/' hash ~)
::  ==  the four calls
::
::  +create-request: a fresh runtime key with a cap. The plaintext key
::  comes back here and nowhere else, which is why the vendor stores
::  it.
::
++  create-request
  |=  [base=@t key=@t name=@t limit-micro=@ud]
  ^-  request:http
  =/  doc=json
    %-  pairs:enjs:format
    :~  ['name' s+name]
        ['limit' [%n `@ta`(usd-of limit-micro)]]
    ==
  =/  body=octs  (as-octs:mimes:html (en:json:html doc))
  [%'POST' base (heads key) `body]
::  +get-request: one key's figures, which is what a reconcile reads
::
++  get-request
  |=  [base=@t key=@t hash=@t]
  ^-  request:http
  [%'GET' (key-at base hash) (auth-only key) ~]
::  +patch-request: the cap and the switch, only the fields given. A
::  patch that names nothing is a patch of an empty document, which
::  OpenRouter takes as a no-op.
::
++  patch-request
  |=  [base=@t key=@t hash=@t limit=(unit @ud) disabled=(unit ?)]
  ^-  request:http
  =/  rows=(list [@t json])  ~
  =.  rows
    ?~(limit rows (snoc rows ['limit' [%n `@ta`(usd-of u.limit)]]))
  =.  rows
    ?~(disabled rows (snoc rows ['disabled' b+u.disabled]))
  =/  body=octs
    (as-octs:mimes:html (en:json:html (pairs:enjs:format rows)))
  [%'PATCH' (key-at base hash) (heads key) `body]
::  +delete-request: the key goes upstream, which is what a dropped
::  lease and a closed account both need
::
++  delete-request
  |=  [base=@t key=@t hash=@t]
  ^-  request:http
  [%'DELETE' (key-at base hash) (auth-only key) ~]
::  ==  the readers
::
::  +read-created: what a create answered. The plaintext key is at the
::  top level and the figures are under data.
::
++  read-created
  |=  body=@t
  ^-  (unit [key=@t hash=@t usage=@ud limit=@ud disabled=?])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  key=@t  (gs jon 'key')
  ?:  =('' key)  ~
  =/  d=json  (gj jon 'data')
  =/  hash=@t  (gs d 'hash')
  ?:  =('' hash)  ~
  :-  ~
  :*  key
      hash
      (fall (micro-of (gj d 'usage')) 0)
      (fall (micro-of (gj d 'limit')) 0)
      (gb d 'disabled')
  ==
::  +read-key: the same figures on a read. usage is credits spent in
::  USD, which is what the reconcile turns into a debit.
::
::  +read-key-full: everything OpenRouter says about a key, for the
::  owner's live view: the running usage windows and what the provider
::  itself thinks remains, beside the figures the ship keeps.
::
++  read-key-full
  |=  body=@t
  ^-  (unit [hash=@t name=@t usage=@ud daily=@ud weekly=@ud monthly=@ud limit=@ud remaining=(unit @ud) disabled=? created=@t updated=@t])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  d=json  (gj jon 'data')
  =/  hash=@t  (gs d 'hash')
  ?:  =('' hash)  ~
  :-  ~
  :*  hash
      (gs d 'name')
      (fall (micro-of (gj d 'usage')) 0)
      (fall (micro-of (gj d 'usage_daily')) 0)
      (fall (micro-of (gj d 'usage_weekly')) 0)
      (fall (micro-of (gj d 'usage_monthly')) 0)
      (fall (micro-of (gj d 'limit')) 0)
      (micro-of (gj d 'limit_remaining'))
      (gb d 'disabled')
      (gs d 'created_at')
      (gs d 'updated_at')
  ==
++  read-key
  |=  body=@t
  ^-  (unit [hash=@t usage=@ud limit=@ud disabled=?])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  d=json  (gj jon 'data')
  =/  hash=@t  (gs d 'hash')
  ?:  =('' hash)  ~
  :-  ~
  :*  hash
      (fall (micro-of (gj d 'usage')) 0)
      (fall (micro-of (gj d 'limit')) 0)
      (gb d 'disabled')
  ==
::  ==  the two sums a lease turns on
::
::  +debit-for: what the customer owes for spending we have not
::  charged for yet. Rounded up, so the vendor never loses a
::  microdollar to division.
::
++  debit-for
  |=  [usage=@ud seen=@ud pct=@ud]
  ^-  @ud
  ?.  (gth usage seen)  0
  =/  moved=@ud  (sub usage seen)
  (div (add (mul moved pct) 99) 100)
::  +limit-for: where the cap belongs. OpenRouter counts a key's limit
::  from zero, so the cap is everything spent so far plus what the
::  balance still buys at our markup. A balance at or below zero caps
::  the key at what it already spent, which stops it as surely as
::  disabled does; the reconcile sets disabled too.
::
++  limit-for
  |=  [usage=@ud balance=@sd pct=@ud]
  ^-  @ud
  ?.  (syn:si balance)  usage
  =/  left=@ud  (abs:si balance)
  ?:  =(0 left)  usage
  (add usage (div (mul left 100) pct))
--
