::  armillary-stripe: Stripe's requests and its answers, pure.
::
::    Every arm here builds a request:http a fiber may send, or reads a
::    body a fiber received. Nothing does IO. The key is a sample, never
::    a constant: a secret lives in settings.json and passes through.
::
::    Import-free like the other two libs, so the encoders and the JSON
::    getters below are copied from /lib/armillary-http.hoon and
::    /lib/armillary.hoon rather than imported. A lib that imports a lib
::    cannot build in both the clay desk and the app's code namespace,
::    which is the rule the whole desk follows.
::
|%
::  ==  copied from /lib/armillary-http.hoon
::
++  url-encode
  |=  t=@t
  ^-  @t
  =/  out=tape
    %-  zing
    %+  turn  (trip t)
    |=  c=@t
    ^-  tape
    ?:  ?|  &((gte c 'a') (lte c 'z'))
            &((gte c 'A') (lte c 'Z'))
            &((gte c '0') (lte c '9'))
            =('-' c)
            =('.' c)
            =('_' c)
            =('~' c)
        ==
      [c ~]
    =/  hex=tape  ((x-co:co 2) c)
    ['%' (cuss hex)]
  (crip out)
++  join-amp
  |=  parts=(list @t)
  ^-  @t
  ?~  parts  ''
  ?~  t.parts  i.parts
  (rap 3 i.parts '&' (join-amp t.parts) ~)
::  +form-enc: key=value pairs whose values are already encoded. The
::  success url carries a placeholder Stripe fills in, so its value is
::  built by hand and must not be encoded twice.
::
++  form-enc
  |=  kvs=(list [@t @t])
  ^-  octs
  %-  as-octs:mimes:html
  %-  join-amp
  %+  turn  kvs
  |=  [k=@t v=@t]
  ^-  @t
  (rap 3 (url-encode k) '=' v ~)
++  bearer  |=(t=@t ^-(@t (rap 3 'Bearer ' t ~)))
++  hmac-sha256
  |=  [key=@t msg=@t]
  ^-  @ux
  ::  sha-256l reads a byts with its first byte most significant, and a
  ::  cord holds its first byte least significant, so both sides are
  ::  swapped on the way in. The digest comes back in standard order.
  (hmac-sha256l:hmac:crypto [(met 3 key) (swp 3 key)] [(met 3 msg) (swp 3 msg)])
++  hex-of
  |=  h=@ux
  ^-  @t
  =/  i=@ud  0
  =/  out=tape  ~
  |-  ^-  @t
  ?:  =(64 i)  (crip out)
  =/  nib=@  (cut 2 [i 1] h)
  =/  c=@t  ?:((lth nib 10) (add '0' nib) (add 87 nib))
  $(i +(i), out [c out])
++  same-hex
  |=  [a=@t b=@t]
  ^-  ?
  =/  x=tape  (trip a)
  =/  y=tape  (trip b)
  ?.  =((lent x) (lent y))  |
  =/  acc=@  0
  |-  ^-  ?
  ?~  x  =(0 acc)
  ?~  y  =(0 acc)
  $(x t.x, y t.y, acc (con acc (mix i.x i.y)))
++  chop
  |=  [sep=@t t=tape]
  ^-  (list tape)
  =/  cur=tape  ~
  =/  out=(list tape)  ~
  |-  ^-  (list tape)
  ?~  t  (flop [(flop cur) out])
  ?:  =(sep i.t)  $(t t.t, cur ~, out [(flop cur) out])
  $(t t.t, cur [i.t cur])
++  parse-stripe-sig
  |=  h=@t
  ^-  (unit [t=@ud v1=@t])
  =/  parts=(list tape)  (chop ',' (trip h))
  =/  ts=(unit @ud)  ~
  =/  v1=@t  ''
  |-  ^-  (unit [t=@ud v1=@t])
  ?~  parts
    ?~  ts  ~
    ?:  =('' v1)  ~
    `[u.ts v1]
  =/  kv=(list tape)  (chop '=' i.parts)
  ?~  kv  $(parts t.parts)
  ?~  t.kv  $(parts t.parts)
  =/  k=tape  i.kv
  =/  v=tape  i.t.kv
  =/  had-t=?  ?=(^ ts)
  ?:  &(=("t" k) !had-t)
    $(parts t.parts, ts (rush (crip v) dem))
  ?:  &(=("v1" k) =('' v1))
    $(parts t.parts, v1 (crip v))
  $(parts t.parts)
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
++  gn
  |=  [jon=json k=@t]
  ^-  @ud
  =/  v=json  (gj jon k)
  ?.  ?=([%n *] v)  0
  (fall (rush p.v dem) 0)
++  gb
  |=  [jon=json k=@t]
  ^-  ?
  =/  v=json  (gj jon k)
  ?:(?=([%b *] v) p.v |)
++  ga
  |=  [jon=json k=@t]
  ^-  (list json)
  =/  v=json  (gj jon k)
  ?:(?=([%a *] v) p.v ~)
::  +de-body: a response body as JSON, null when it is not JSON at all
::
++  de-body  |=(body=@t ^-(json (fall (de:json:html body) ~)))
::  +num: a whole number as the text a form body carries
::
++  num  |=(n=@ud ^-(@t (crip (a-co:co n))))
::  ==  the pieces every request shares
::
::  +heads: the two headers every Stripe call carries. The key is the
::  caller's; nothing here remembers it.
::
++  heads
  |=  key=@t
  ^-  (list [@t @t])
  :~  ['authorization' (bearer key)]
      ['content-type' 'application/x-www-form-urlencoded']
  ==
::  +auth-only: the same without a content type, for a GET
::
++  auth-only  |=(key=@t ^-((list [@t @t]) ~[['authorization' (bearer key)]]))
::  +at: a route under the API base, the base's trailing slash dropped
::
++  at
  |=  [base=@t leaf=@t]
  ^-  @t
  =/  b=tape  (trip base)
  =/  trimmed=tape  ?:(&(?=(^ b) =('/' (rear `tape`b))) (snip `tape`b) b)
  (crip (weld trimmed (trip leaf)))
::  ==  checkout sessions
::
::  +return-url: a success url with Stripe's session placeholder on the
::  end. The url itself is encoded, the ampersand that joins the
::  parameter is encoded too, and the placeholder is left literal: that
::  is the one string Stripe reads back out of the value it decodes.
::
++  return-url
  |=  success=@t
  ^-  @t
  (rap 3 (url-encode success) '%26sid={CHECKOUT_SESSION_ID}' ~)
::  +customer-request: the one Stripe Customer a ship ever has. Every
::  session that ship opens hangs off it, so Stripe shows one buyer with
::  a history rather than a new stranger per payment, and the Billing
::  Portal has something to open.
::
++  customer-request
  |=  [base=@t key=@t ship=@t]
  ^-  request:http
  =/  kvs=(list [@t @t])
    :~  ['metadata[ship]' (url-encode ship)]
        ['description' (url-encode (rap 3 'Armillary ' ship ~))]
    ==
  [%'POST' (at base '/v1/customers') (heads key) `(form-enc kvs)]
::  +topup-request: a one-off payment for a fixed number of cents. The
::  ship is in the metadata, which is what makes the payment an account.
::
::    A blank customer sends no customer at all, which is what a vendor
::    whose Customer create failed falls back to. With one, Checkout is
::    also allowed to write back the name it collects.
::
++  topup-request
  |=  $:  base=@t
          key=@t
          ship=@t
          customer=@t
          amount-cents=@ud
          label=@t
          success=@t
          cancel=@t
          expires=@ud
      ==
  ^-  request:http
  =/  extra=(list [@t @t])
    ?:  =('' customer)  ~
    ~[['customer' (url-encode customer)]]
  =/  kvs=(list [@t @t])
    ;:  weld
      :~  ['mode' (url-encode 'payment')]
          ['metadata[ship]' (url-encode ship)]
      ==
      extra
      :~  ['success_url' (return-url success)]
          ['cancel_url' (url-encode cancel)]
          ['expires_at' (num expires)]
          ['line_items[0][price_data][currency]' 'usd']
          ['line_items[0][price_data][product_data][name]' (url-encode label)]
          ['line_items[0][price_data][product_data][tax_code]' tax-code]
          ['line_items[0][price_data][unit_amount]' (num amount-cents)]
          ['line_items[0][quantity]' '1']
      ==
    ==
  [%'POST' (at base '/v1/checkout/sessions') (heads key) `(form-enc kvs)]
::  +subscription-request: a recurring charge on a price the owner made
::  on Stripe. The plan rides on the subscription's own metadata, so an
::  invoice months later still says which plan it renews.
::
++  subscription-request
  |=  $:  base=@t
          key=@t
          ship=@t
          customer=@t
          price=@t
          plan=@t
          success=@t
          cancel=@t
      ==
  ^-  request:http
  =/  extra=(list [@t @t])
    ?:(=('' customer) ~ ~[['customer' (url-encode customer)]])
  =/  kvs=(list [@t @t])
    ;:  weld
      :~  ['mode' (url-encode 'subscription')]
          ['line_items[0][price]' (url-encode price)]
          ['line_items[0][quantity]' '1']
          ['metadata[ship]' (url-encode ship)]
      ==
      extra
      :~  ['subscription_data[metadata][ship]' (url-encode ship)]
          ['subscription_data[metadata][plan]' (url-encode plan)]
          ['success_url' (return-url success)]
          ['cancel_url' (url-encode cancel)]
      ==
    ==
  [%'POST' (at base '/v1/checkout/sessions') (heads key) `(form-enc kvs)]
::  +session-request: read a session back. This is the verification: the
::  webhook body is never trusted for the amount or the ship.
::
++  session-request
  |=  [base=@t key=@t sid=@t]
  ^-  request:http
  =/  url=@t  (at base (rap 3 '/v1/checkout/sessions/' (url-encode sid) ~))
  [%'GET' url (auth-only key) ~]
::  +read-session: a checkout session as the vendor needs it. customer,
::  subscription and payment_intent are null on a session that has not
::  reached them yet, and read as ''.
::
::    subtotal is what the goods came to before tax. It is what a
::    credit is worth: tax collected on a sale is not the customer's
::    balance, it is the state's. total is kept for the record.
::
++  read-session
  |=  body=@t
  ^-  %-  unit
      $:  id=@t
          mode=@t
          paid=?
          total=@ud
          subtotal=@ud
          ship=@t
          customer=@t
          subscription=@t
          intent=@t
          url=@t
      ==
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  id=@t  (gs jon 'id')
  ?:  =('' id)  ~
  :-  ~
  :*  id
      (gs jon 'mode')
      =('paid' (gs jon 'payment_status'))
      (gn jon 'amount_total')
      (gn jon 'amount_subtotal')
      (gs (gj jon 'metadata') 'ship')
      (gs jon 'customer')
      (gs jon 'subscription')
      (gs jon 'payment_intent')
      (gs jon 'url')
  ==
::  ==  invoices
::
++  invoice-request
  |=  [base=@t key=@t iid=@t]
  ^-  request:http
  =/  url=@t  (at base (rap 3 '/v1/invoices/' (url-encode iid) ~))
  [%'GET' url (auth-only key) ~]
::  +read-invoice: one paid invoice on a subscription. The first line is
::  the plan's: a subscription made here holds exactly one.
::
++  read-invoice
  |=  body=@t
  ^-  (unit [id=@t paid=? customer=@t subscription=@t price=@t period-end=@ud])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  id=@t  (gs jon 'id')
  ?:  =('' id)  ~
  =/  lines=(list json)  (ga (gj jon 'lines') 'data')
  =/  first=json  ?~(lines ~ i.lines)
  :-  ~
  :*  id
      ?|(=('paid' (gs jon 'status')) (gb jon 'paid'))
      (gs jon 'customer')
      (gs jon 'subscription')
      (gs (gj first 'price') 'id')
      (gn (gj first 'period') 'end')
  ==
::  ==  disputes
::
::  +dispute-request: read a dispute back. The webhook body says only
::  which dispute; the amount, the PaymentIntent and the status come
::  from Stripe itself.
::
++  dispute-request
  |=  [base=@t key=@t id=@t]
  ^-  request:http
  =/  url=@t  (at base (rap 3 '/v1/disputes/' (url-encode id) ~))
  [%'GET' url (auth-only key) ~]
::  +read-dispute: one dispute as the vendor needs it. amount is in
::  cents, as everything on Stripe is, and status is Stripe's own word
::  for where the dispute stands.
::
++  read-dispute
  |=  body=@t
  ^-  (unit [id=@t intent=@t amount=@ud status=@t])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  id=@t  (gs jon 'id')
  ?:  =('' id)  ~
  `[id (gs jon 'payment_intent') (gn jon 'amount') (gs jon 'status')]
::  ==  events
::
::  +event-of: the only two things a webhook body is trusted for. The
::  object is read back from Stripe by its id; nothing else in the body
::  decides anything.
::
++  event-of
  |=  body=@t
  ^-  (unit [type=@t id=@t])
  =/  jon=json  (de-body body)
  ?.  ?=([%o *] jon)  ~
  =/  type=@t  (gs jon 'type')
  ?:  =('' type)  ~
  =/  id=@t  (gs (gj (gj jon 'data') 'object') 'id')
  ?:  =('' id)  ~
  `[type id]
::  +tax-code: Stripe's product tax code for what the vendor sells,
::  "Artificial Intelligence as a Service, cloud based, personal use"
::  (txcd_10105001), from Stripe's own list. Every line item carries
::  it: Managed Payments refuses a product without one, and Stripe Tax
::  needs it to tax a digital service right in the US.
::
++  tax-code  'txcd_10105001'
::  ==  products, prices and cancellation
::
++  product-request
  |=  [base=@t key=@t name=@t]
  ^-  request:http
  =/  kvs=(list [@t @t])  ~[['name' (url-encode name)] ['tax_code' tax-code]]
  [%'POST' (at base '/v1/products') (heads key) `(form-enc kvs)]
++  price-request
  |=  [base=@t key=@t product=@t cents=@ud interval=@t]
  ^-  request:http
  =/  kvs=(list [@t @t])
    :~  ['product' (url-encode product)]
        ['unit_amount' (num cents)]
        ['currency' 'usd']
        ['recurring[interval]' (url-encode interval)]
    ==
  [%'POST' (at base '/v1/prices') (heads key) `(form-enc kvs)]
::  +read-id: the id Stripe answers after a create
::
++  read-id
  |=  body=@t
  ^-  (unit @t)
  =/  id=@t  (gs (de-body body) 'id')
  ?:(=('' id) ~ `id)
::  +cancel-request: the subscription ends when the period it is paid
::  for ends, so the customer keeps what it bought
::
++  cancel-request
  |=  [base=@t key=@t sub=@t]
  ^-  request:http
  =/  url=@t  (at base (rap 3 '/v1/subscriptions/' (url-encode sub) ~))
  =/  kvs=(list [@t @t])  ~[['cancel_at_period_end' 'true']]
  [%'POST' url (heads key) `(form-enc kvs)]
::  ==  the webhook signature
::
::  +verify-signature: Stripe signs "<t>.<body>" with the endpoint's
::  signing secret. A header older or newer than five minutes is refused
::  whatever it says, so a captured request cannot be replayed later.
::
++  verify-signature
  |=  [secret=@t header=@t body=@t now=@ud]
  ^-  ?
  =/  got=(unit [t=@ud v1=@t])  (parse-stripe-sig header)
  ?~  got  |
  =/  gap=@ud  ?:((gth now t.u.got) (sub now t.u.got) (sub t.u.got now))
  ?:  (gth gap 300)  |
  =/  signed=@t  (rap 3 (num t.u.got) '.' body ~)
  (same-hex (hex-of (hmac-sha256 secret signed)) v1.u.got)
--
