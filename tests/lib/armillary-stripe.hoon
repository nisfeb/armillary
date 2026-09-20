::  Unit tests for /lib/armillary-stripe: the requests and the readers.
::
::    A builder is checked by decoding the form body it made back into
::    pairs, so the assertion reads as the keys Stripe's API documents
::    rather than as one long encoded string.
::
/+  *test, ah=armillary-http, ast=armillary-stripe
|%
::  ==  reading a form body back
::
++  nib
  |=  c=@t
  ^-  @
  ?:  &((gte c '0') (lte c '9'))  (sub c '0')
  ?:  &((gte c 'a') (lte c 'f'))  (add 10 (sub c 'a'))
  ?:  &((gte c 'A') (lte c 'F'))  (add 10 (sub c 'A'))
  0
++  dec-pct
  |=  t=tape
  ^-  tape
  ?~  t  ~
  ?.  =('%' i.t)  [i.t (dec-pct t.t)]
  ?~  t.t  ~[i.t]
  ?~  t.t.t  [i.t (dec-pct t.t)]
  =/  hx=@  (add (mul 16 (nib i.t.t)) (nib i.t.t.t))
  [`@t`hx (dec-pct t.t.t.t)]
++  pairs-of
  |=  bod=(unit octs)
  ^-  (list [@t @t])
  ?~  bod  ~
  %+  turn  (chop:ah '&' (trip q.u.bod))
  |=  seg=tape
  ^-  [@t @t]
  =/  at=(unit @ud)  (find "=" seg)
  ?~  at  [(crip (dec-pct seg)) '']
  :-  (crip (dec-pct (scag u.at seg)))
  (crip (dec-pct (slag +(u.at) seg)))
++  base  'http://127.0.0.1:3399'
++  key   'sk_test_gate'
++  ok-url  'https://ex.com/apps/armillary/pay/return?ship=~feb'
++  no-url  'https://ex.com/apps/armillary/pay/return?ship=~feb&cancelled=1'
::  ==  the builders
::
++  test-customer-request
  =/  req=request:http  (customer-request:ast base key '~feb')
  =/  want=(list [@t @t])
    :~  ['metadata[ship]' '~feb']
        ['description' 'Armillary ~feb']
    ==
  ;:  weld
    (expect-eq !>(%'POST') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/customers') !>(url.req))
    (expect-eq !>(`(unit @t)`[~ 'Bearer sk_test_gate']) !>((get-header:http 'authorization' header-list.req)))
    (expect-eq !>(want) !>((pairs-of body.req)))
  ==
++  test-topup-request
  =/  req=request:http
    %-  topup-request:ast
    [base key '~feb' '' 1.000 'Armillary credit' ok-url no-url 1.789.855.500]
  =/  want=(list [@t @t])
    :~  ['mode' 'payment']
        ['metadata[ship]' '~feb']
        :-  'success_url'
        'https://ex.com/apps/armillary/pay/return?ship=~feb&sid={CHECKOUT_SESSION_ID}'
        ['cancel_url' no-url]
        ['expires_at' '1789855500']
        ['line_items[0][price_data][currency]' 'usd']
        ['line_items[0][price_data][product_data][name]' 'Armillary credit']
        ['line_items[0][price_data][unit_amount]' '1000']
        ['line_items[0][quantity]' '1']
    ==
  ;:  weld
    (expect-eq !>(%'POST') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/checkout/sessions') !>(url.req))
    (expect-eq !>(`(unit @t)`[~ 'Bearer sk_test_gate']) !>((get-header:http 'authorization' header-list.req)))
    %+  expect-eq
      !>(`(unit @t)`[~ 'application/x-www-form-urlencoded'])
    !>((get-header:http 'content-type' header-list.req))
    (expect-eq !>(want) !>((pairs-of body.req)))
  ==
::  +test-topup-request-customer: the same call for a ship that already
::  has a Customer. Checkout may then write back the name it collects.
::
++  test-topup-request-customer
  =/  req=request:http
    %-  topup-request:ast
    [base key '~feb' 'cus_9' 1.000 'Armillary credit' ok-url no-url 1.789.855.500]
  =/  want=(list [@t @t])
    :~  ['mode' 'payment']
        ['metadata[ship]' '~feb']
        ['customer' 'cus_9']
        ['customer_update[name]' 'auto']
        :-  'success_url'
        'https://ex.com/apps/armillary/pay/return?ship=~feb&sid={CHECKOUT_SESSION_ID}'
        ['cancel_url' no-url]
        ['expires_at' '1789855500']
        ['line_items[0][price_data][currency]' 'usd']
        ['line_items[0][price_data][product_data][name]' 'Armillary credit']
        ['line_items[0][price_data][unit_amount]' '1000']
        ['line_items[0][quantity]' '1']
    ==
  (expect-eq !>(want) !>((pairs-of body.req)))
++  test-subscription-request
  =/  req=request:http
    (subscription-request:ast base key '~feb' '' 'price_1' 'pro' ok-url no-url)
  =/  want=(list [@t @t])
    :~  ['mode' 'subscription']
        ['line_items[0][price]' 'price_1']
        ['line_items[0][quantity]' '1']
        ['metadata[ship]' '~feb']
        ['subscription_data[metadata][ship]' '~feb']
        ['subscription_data[metadata][plan]' 'pro']
        :-  'success_url'
        'https://ex.com/apps/armillary/pay/return?ship=~feb&sid={CHECKOUT_SESSION_ID}'
        ['cancel_url' no-url]
    ==
  ;:  weld
    (expect-eq !>(%'POST') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/checkout/sessions') !>(url.req))
    (expect-eq !>(want) !>((pairs-of body.req)))
  ==
++  test-subscription-request-customer
  =/  req=request:http
    (subscription-request:ast base key '~feb' 'cus_9' 'price_1' 'pro' ok-url no-url)
  =/  want=(list [@t @t])
    :~  ['mode' 'subscription']
        ['line_items[0][price]' 'price_1']
        ['line_items[0][quantity]' '1']
        ['metadata[ship]' '~feb']
        ['customer' 'cus_9']
        ['subscription_data[metadata][ship]' '~feb']
        ['subscription_data[metadata][plan]' 'pro']
        :-  'success_url'
        'https://ex.com/apps/armillary/pay/return?ship=~feb&sid={CHECKOUT_SESSION_ID}'
        ['cancel_url' no-url]
    ==
  (expect-eq !>(want) !>((pairs-of body.req)))
++  test-session-request
  =/  req=request:http  (session-request:ast base key 'cs_1')
  ;:  weld
    (expect-eq !>(%'GET') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/checkout/sessions/cs_1') !>(url.req))
    (expect-eq !>(`(unit @t)`[~ 'Bearer sk_test_gate']) !>((get-header:http 'authorization' header-list.req)))
    (expect-eq !>(`(unit octs)`~) !>(body.req))
  ==
++  test-invoice-request
  =/  req=request:http  (invoice-request:ast base key 'in_1')
  ;:  weld
    (expect-eq !>(%'GET') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/invoices/in_1') !>(url.req))
  ==
++  test-product-request
  =/  req=request:http  (product-request:ast base key 'Pro plan')
  ;:  weld
    (expect-eq !>('http://127.0.0.1:3399/v1/products') !>(url.req))
    (expect-eq !>(`(list [@t @t])`~[['name' 'Pro plan']]) !>((pairs-of body.req)))
  ==
++  test-price-request
  =/  req=request:http  (price-request:ast base key 'prod_1' 2.500 'month')
  =/  want=(list [@t @t])
    :~  ['product' 'prod_1']
        ['unit_amount' '2500']
        ['currency' 'usd']
        ['recurring[interval]' 'month']
    ==
  ;:  weld
    (expect-eq !>('http://127.0.0.1:3399/v1/prices') !>(url.req))
    (expect-eq !>(want) !>((pairs-of body.req)))
  ==
++  test-cancel-request
  =/  req=request:http  (cancel-request:ast base key 'sub_1')
  ;:  weld
    (expect-eq !>(%'POST') !>(method.req))
    (expect-eq !>('http://127.0.0.1:3399/v1/subscriptions/sub_1') !>(url.req))
    (expect-eq !>(`(list [@t @t])`~[['cancel_at_period_end' 'true']]) !>((pairs-of body.req)))
  ==
::  ==  the readers
::
++  paid-payment
  '''
  {"id":"cs_1","mode":"payment","payment_status":"paid","amount_total":1080,
   "amount_subtotal":1000,"payment_intent":"pi_1",
   "metadata":{"ship":"~feb"},"customer":null,"subscription":null,
   "url":"http://stub/pay/cs_1"}
  '''
++  paid-subscription
  '''
  {"id":"cs_2","mode":"subscription","payment_status":"paid","amount_total":2500,
   "metadata":{"ship":"~feb"},"customer":"cus_9","subscription":"sub_9",
   "url":"http://stub/pay/cs_2"}
  '''
++  unpaid-session
  '''
  {"id":"cs_3","mode":"payment","payment_status":"unpaid","amount_total":1000,
   "metadata":{"ship":"~feb"},"customer":null,"subscription":null,
   "url":"http://stub/pay/cs_3"}
  '''
++  test-read-session-payment
  =/  got  (read-session:ast paid-payment)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect-eq !>('cs_1') !>(id.u.got))
    (expect-eq !>('payment') !>(mode.u.got))
    (expect !>(paid.u.got))
    (expect-eq !>(`@ud`1.080) !>(total.u.got))
    ::  the credit follows the subtotal, so tax on the sale is not
    ::  credited to the customer
    (expect-eq !>(`@ud`1.000) !>(subtotal.u.got))
    (expect-eq !>('pi_1') !>(intent.u.got))
    (expect-eq !>('~feb') !>(ship.u.got))
    (expect-eq !>('') !>(customer.u.got))
    (expect-eq !>('') !>(subscription.u.got))
    (expect-eq !>('http://stub/pay/cs_1') !>(url.u.got))
  ==
++  test-read-session-subscription
  =/  got  (read-session:ast paid-subscription)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect-eq !>('subscription') !>(mode.u.got))
    (expect !>(paid.u.got))
    (expect-eq !>('cus_9') !>(customer.u.got))
    (expect-eq !>('sub_9') !>(subscription.u.got))
  ==
++  test-read-session-unpaid
  =/  got  (read-session:ast unpaid-session)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect !>(!paid.u.got))
    ::  a session that has not been paid has no PaymentIntent yet
    (expect-eq !>('') !>(intent.u.got))
    (expect-eq !>(`(unit @t)`~) !>((read-id:ast 'not json at all')))
  ==
++  paid-invoice
  '''
  {"id":"in_1","status":"paid","customer":"cus_9","subscription":"sub_9",
   "lines":{"data":[{"price":{"id":"price_1"},"period":{"end":1792447500}}]}}
  '''
++  test-read-invoice
  =/  got  (read-invoice:ast paid-invoice)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect-eq !>('in_1') !>(id.u.got))
    (expect !>(paid.u.got))
    (expect-eq !>('cus_9') !>(customer.u.got))
    (expect-eq !>('sub_9') !>(subscription.u.got))
    (expect-eq !>('price_1') !>(price.u.got))
    (expect-eq !>(`@ud`1.792.447.500) !>(period-end.u.got))
  ==
++  test-event-of
  =/  ev=@t
    '{"type":"checkout.session.completed","data":{"object":{"id":"cs_1"}}}'
  ;:  weld
    (expect-eq !>(`(unit [type=@t id=@t])`[~ 'checkout.session.completed' 'cs_1']) !>((event-of:ast ev)))
    (expect-eq !>(`(unit [type=@t id=@t])`~) !>((event-of:ast 'junk')))
    (expect-eq !>(`(unit [type=@t id=@t])`~) !>((event-of:ast '{"type":"x"}')))
  ==
++  test-read-id
  ;:  weld
    (expect-eq !>(`(unit @t)`[~ 'prod_1']) !>((read-id:ast '{"id":"prod_1"}')))
    (expect-eq !>(`(unit @t)`~) !>((read-id:ast '{}')))
  ==
::  ==  the signature
::
++  secret  'whsec_gate'
++  body-fixture  '{"type":"checkout.session.completed"}'
++  head-at
  |=  [when=@ud sig=@t]
  ^-  @t
  (rap 3 't=' (crip (a-co:co when)) ',v1=' sig ~)
++  good-sig
  |=  when=@ud
  ^-  @t
  =/  signed=@t  (rap 3 (crip (a-co:co when)) '.' body-fixture ~)
  (hex-of:ah (hmac-sha256:ah secret signed))
++  test-verify-signature
  =/  when=@ud  1.789.855.500
  =/  head=@t  (head-at when (good-sig when))
  ;:  weld
    (expect !>((verify-signature:ast secret head body-fixture when)))
    (expect !>((verify-signature:ast secret head body-fixture (add when 299))))
    (expect !>(!(verify-signature:ast secret head body-fixture (add when 301))))
    (expect !>(!(verify-signature:ast secret head body-fixture (sub when 301))))
    (expect !>(!(verify-signature:ast secret (head-at when 'deadbeef') body-fixture when)))
    (expect !>(!(verify-signature:ast secret 'nonsense' body-fixture when)))
    (expect !>(!(verify-signature:ast 'other' head body-fixture when)))
  ==
--
