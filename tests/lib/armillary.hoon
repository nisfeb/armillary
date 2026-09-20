::  Unit tests for /lib/armillary: decimals, money, keys and the decoders.
::
::    Every case a client can send, plus the cases only a broken client
::    sends. A decoder never crashes: "answers the field that failed"
::    is the behaviour under test.
::
/+  *test, arm=armillary
|%
++  jo  |=(t=@t ^-(json (need (de:json:html t))))
::  +refused, +taken: a decoder's verdict, so a test may ask it of a
::  call rather than of a face
++  refused  |=(e=(each * @t) ^-(? ?=(%| -.e)))
++  taken    |=(e=(each * @t) ^-(? ?=(%& -.e)))
++  t0  ~2026.9.19..22.05.00
::  ==  time
::
++  test-iso-roundtrip
  =/  s=@t  '2026-09-19T22:05:00Z'
  ;:  weld
    (expect-eq !>(`(unit @da)`[~ t0]) !>((de-iso:arm s)))
    (expect-eq !>(s) !>((en-iso:arm t0)))
    (expect-eq !>(`(unit @da)`~) !>((de-iso:arm '2026-13-01T00:00:00Z')))
  ==
++  test-unix-secs
  ;:  weld
    (expect-eq !>(`@ud`1.789.855.500) !>((unix-secs:arm t0)))
    (expect-eq !>(`@ud`0) !>((unix-secs:arm ~1969.12.31)))
  ==
::  ==  decimals
::
++  test-de-dec
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 3.000.000]) !>((de-dec:arm '0.000003' 12)))
    (expect-eq !>(`(unit @ud)`[~ 12.000.000.000.000]) !>((de-dec:arm '12' 12)))
    (expect-eq !>(`(unit @ud)`[~ 0]) !>((de-dec:arm '0' 12)))
    (expect-eq !>(`(unit @ud)`~) !>((de-dec:arm '1.2.3' 12)))
    (expect-eq !>(`(unit @ud)`~) !>((de-dec:arm 'abc' 12)))
    (expect-eq !>(`(unit @ud)`~) !>((de-dec:arm '' 12)))
  ==
++  test-de-dec-truncates
  (expect-eq !>(`(unit @ud)`[~ 0]) !>((de-dec:arm '0.0000000000005' 12)))
++  test-per-million
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 3.000.000]) !>((per-million:arm '0.000003')))
    (expect-eq !>(`(unit @ud)`[~ 1.500.000]) !>((per-million:arm '0.0000015')))
    (expect-eq !>(`(unit @ud)`~) !>((per-million:arm '')))
  ==
++  test-en-dec
  ;:  weld
    (expect-eq !>('0.000003') !>((en-dec:arm 3.000.000 12)))
    (expect-eq !>('0.0000015') !>((en-dec:arm 1.500.000 12)))
    (expect-eq !>('0') !>((en-dec:arm 0 12)))
    (expect-eq !>('12') !>((en-dec:arm 12.000.000.000.000 12)))
  ==
::  ==  money
::
++  test-charge
  ;:  weld
    (expect-eq !>(`@ud`3.000) !>((charge:arm 1.000 3.000.000)))
    (expect-eq !>(`@ud`1) !>((charge:arm 1 1)))
    (expect-eq !>(`@ud`98) !>((charge:arm 5 19.500.000)))
    (expect-eq !>(`@ud`39) !>((charge:arm 10 3.900.000)))
    (expect-eq !>(`@ud`0) !>((charge:arm 0 3.900.000)))
  ==
++  test-markup-of
  ;:  weld
    (expect-eq !>(`@ud`1.300) !>((markup-of:arm 1.000 130)))
    (expect-eq !>(`@ud`3.900.000) !>((markup-of:arm 3.000.000 130)))
    (expect-eq !>(`@ud`0) !>((markup-of:arm 0 130)))
  ==
::  ==  the ledger
::
++  r-credit  ^-(row:arm [%credit 100 0 '' 0 0 '' 'owner' 'a' '' t0])
++  r-debit   ^-(row:arm [%debit 30 20 'stub/alpha' 10 5 'proxy' '' 'b' '' t0])
++  r-refund  ^-(row:arm [%refund 90 0 '' 0 0 '' '' 'c' '' t0])
++  test-fold-balance
  ;:  weld
    (expect-eq !>(`@sd`-20) !>((fold-balance:arm ~[r-credit r-debit r-refund])))
    (expect-eq !>(`@sd`--0) !>((fold-balance:arm ~)))
    (expect-eq !>(`@sd`--100) !>((fold-balance:arm ~[r-credit])))
  ==
++  test-en-sd
  ;:  weld
    (expect-eq !>(`json`n+'-20') !>((en-sd:arm -20)))
    (expect-eq !>(`json`n+'1500') !>((en-sd:arm --1.500)))
    (expect-eq !>(`json`n+'0') !>((en-sd:arm --0)))
  ==
++  test-row-name
  (expect-eq !>(`@ta`'1789855500-0') !>((row-name:arm t0 0)))
++  test-read-row
  ;:  weld
    (expect-eq !>(`(unit row:arm)`[~ r-debit]) !>((read-row:arm [%1 r-debit])))
    (expect-eq !>(`(unit row:arm)`~) !>((read-row:arm 0)))
  ==
++  test-de-row
  =/  got  (de-row:arm (en-row:arm r-debit))
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`row:arm`r-debit) !>(?:(?=(%& -.got) p.got r-debit)))
  ==
::  ==  keys
::
++  test-parse-bearer
  ;:  weld
    (expect-eq !>(`(unit [@t @t])`[~ 'ab' 'cd']) !>((parse-bearer:arm 'Bearer ab.cd')))
    (expect-eq !>(`(unit [@t @t])`[~ 'ab' 'cd']) !>((parse-bearer:arm 'bearer ab.cd')))
    (expect-eq !>(`(unit [@t @t])`~) !>((parse-bearer:arm 'Bearer abcd')))
    (expect-eq !>(`(unit [@t @t])`~) !>((parse-bearer:arm 'Basic x')))
  ==
++  k1
  ^-  key:arm
  ['abc123' 'test' '0vsalt' (hash-token:arm '0vsalt' 'sekret') t0 ~]
++  test-key-ok
  ;:  weld
    (expect !>((key-ok:arm k1 'sekret')))
    (expect !>(!(key-ok:arm k1 'other')))
  ==
++  test-de-key
  ;:  weld
    (expect-eq !>(`(unit key:arm)`[~ k1]) !>((de-key:arm (en-key-row:arm k1))))
    (expect-eq !>(`(unit key:arm)`~) !>((de-key:arm (jo '{"id":"abc123"}'))))
  ==
++  test-en-key-public
  =/  txt=tape  (trip (en:json:html (en-key-public:arm k1)))
  ;:  weld
    (expect-eq !>(`(unit @ud)`~) !>((find "salt" txt)))
    (expect-eq !>(`(unit @ud)`~) !>((find "hash" txt)))
  ==
::  ==  masking
::
++  test-mask
  ;:  weld
    (expect-eq !>('') !>((mask:arm '')))
    (expect-eq !>(`(unit @ud)`~) !>((find "stub" (trip (mask:arm 'stub-key')))))
    (expect-eq !>(`(unit @ud)`[~ 12]) !>((find "-key" (trip (mask:arm 'stub-key')))))
  ==
::  ==  providers
::
++  test-de-provider-names-kind
  =/  got  (de-provider:arm (jo '{"id":"a","kind":"x"}'))
  ;:  weld
    (expect !>(?=(%| -.got)))
    (expect-eq !>('kind: openai-compatible or openrouter') !>(?:(?=(%| -.got) p.got '')))
  ==
++  test-de-provider-names-id
  =/  got  (de-provider:arm (jo '{"kind":"openrouter"}'))
  (expect-eq !>('id: 1 to 64 bytes') !>(?:(?=(%| -.got) p.got '')))
++  p-blank
  (jo '{"id":"stub","name":"Stub","kind":"openrouter","base_url":"http://x/v1","api_key":""}')
++  test-de-provider-blank-key
  =/  got  (de-provider:arm p-blank)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>('') !>(?:(?=(%& -.got) api-key.p.got 'no')))
  ==
++  p-full
  ^-  provider:arm
  ['stub' 'Stub' %openrouter 'http://127.0.0.1:3399/v1' 'stub-key' 'prov-key']
++  test-en-provider-masked
  =/  txt=tape  (trip (en:json:html (en-provider-masked:arm p-full)))
  ;:  weld
    (expect-eq !>(`(unit @ud)`~) !>((find "stub-key" txt)))
    (expect-eq !>(`(unit @ud)`~) !>((find "prov-key" txt)))
    (expect-eq !>(`(unit @ud)`~) !>((find "prov-" txt)))
  ==
::  ==  the catalog
::
++  cat-json
  %-  jo
  '[{"id":"stub/alpha","provider":"stub","in":3900000,"enabled":true},{"id":"stub/beta","provider":"stub","in":1500000,"enabled":false}]'
++  test-de-catalog
  =/  got  (de-catalog:arm cat-json)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`@ud`2) !>(?:(?=(%& -.got) (lent p.got) 0)))
  ==
++  test-de-catalog-duplicate
  =/  bad  (jo '[{"id":"a","provider":"stub"},{"id":"b","provider":"stub"},{"id":"a","provider":"stub"}]')
  =/  got  (de-catalog:arm bad)
  (expect-eq !>('row 2 id: duplicate') !>(?:(?=(%| -.got) p.got '')))
++  test-de-catalog-bad-row
  =/  bad  (jo '[{"id":"a","provider":"stub"},{"provider":"stub"}]')
  =/  got  (de-catalog:arm bad)
  (expect-eq !>('row 1 id: 1 to 200 bytes') !>(?:(?=(%| -.got) p.got '')))
++  cat-rows
  ^-  (list model-row:arm)
  :~  ['stub/alpha' 'stub' 'stub/alpha' 3.900.000 19.500.000 3.000.000 15.000.000 & ~]
      ['stub/beta' 'stub' 'stub/beta' 1.500.000 6.000.000 0 0 | ~]
  ==
++  test-find-model
  =/  alpha  (find-model:arm cat-rows 'stub/alpha')
  =/  beta   (find-model:arm cat-rows 'stub/beta')
  =/  nope   (find-model:arm cat-rows 'stub/nope')
  ;:  weld
    (expect !>(?=(^ alpha)))
    (expect !>(?=(~ beta)))
    (expect !>(?=(~ nope)))
  ==
++  test-public-catalog
  =/  got=json  (public-catalog:arm cat-rows)
  (expect-eq !>(`@ud`1) !>(?:(?=([%a *] got) (lent p.got) 0)))
++  test-en-models-list
  =/  rows=(list model-row:arm)
    :~  ['a' 'stub' 'a' 3.000.000 1.500.000 0 0 & ~]
    ==
  =/  got=json  (en-models-list:arm rows)
  =/  data=(list json)  (ga:arm got 'data')
  =/  first=json  ?~(data ~ i.data)
  =/  pricing=json  (gj:arm first 'pricing')
  ;:  weld
    (expect-eq !>('0.000003') !>((gs:arm pricing 'prompt')))
    (expect-eq !>('0.0000015') !>((gs:arm pricing 'completion')))
    (expect-eq !>('stub') !>((gs:arm first 'owned_by')))
    (expect-eq !>('list') !>((gs:arm got 'object')))
  ==
::  ==  import
::
++  models-body
  %-  jo
  '{"data":[{"id":"stub/alpha","pricing":{"prompt":"0.000003","completion":"0.000015"}},{"id":"stub/beta","pricing":{"prompt":"0.0000015","completion":"0.000006"}}]}'
++  test-import-rows
  =/  got=(list model-row:arm)  (import-rows:arm 'stub' 130 models-body)
  =/  want=(list model-row:arm)
    :~  ['stub/alpha' 'stub' 'stub/alpha' 3.900.000 19.500.000 3.000.000 15.000.000 | ~]
        ['stub/beta' 'stub' 'stub/beta' 1.950.000 7.800.000 1.500.000 6.000.000 | ~]
    ==
  (expect-eq !>(want) !>(got))
++  test-import-rows-no-pricing
  =/  got=(list model-row:arm)  (import-rows:arm 'stub' 130 (jo '{"data":[{"id":"stub/free"}]}'))
  =/  want=(list model-row:arm)  ~[['stub/free' 'stub' 'stub/free' 0 0 0 0 | ~]]
  (expect-eq !>(want) !>(got))
++  test-merge-import
  =/  held=(list model-row:arm)
    ~[['stub/alpha' 'stub' 'stub/alpha' 1 2 0 0 & ~]]
  =/  fresh=(list model-row:arm)  (import-rows:arm 'stub' 130 models-body)
  =/  got=(list model-row:arm)  (merge-import:arm held fresh)
  =/  head=model-row:arm  ?~(got *model-row:arm i.got)
  ;:  weld
    (expect-eq !>(`@ud`2) !>((lent got)))
    (expect-eq !>(`@ud`1) !>(in.head))
    (expect !>(enabled.head))
  ==
::  ==  an upstream answer
::
++  test-read-usage
  =/  body=@t  '{"id":"stub-1","usage":{"prompt_tokens":10,"completion_tokens":5}}'
  ;:  weld
    (expect-eq !>(`(unit [@ud @ud])`[~ 10 5]) !>((read-usage:arm body)))
    (expect-eq !>(`(unit [@ud @ud])`[~ 9 0]) !>((read-usage:arm '{"usage":{"prompt_tokens":9}}')))
    (expect-eq !>(`(unit [@ud @ud])`~) !>((read-usage:arm '{"choices":[]}')))
  ==
++  test-read-error
  ;:  weld
    (expect-eq !>('bad key') !>((read-error:arm '{"error":{"message":"bad key"}}')))
    (expect-eq !>('plain') !>((read-error:arm '{"message":"plain"}')))
    (expect-eq !>('') !>((read-error:arm '{"ok":true}')))
  ==
++  test-swap-model
  =/  body=json  (jo '{"model":"stub/alpha","stream":true,"messages":[]}')
  =/  got=json  (swap-model:arm body 'up/x')
  ;:  weld
    (expect-eq !>('up/x') !>((gs:arm got 'model')))
    (expect !>(!(has-key:arm got 'stream')))
    (expect !>((has-key:arm got 'messages')))
  ==
++  test-is-stream
  ;:  weld
    (expect !>((is-stream:arm (jo '{"stream":true}'))))
    (expect !>(!(is-stream:arm (jo '{"stream":false}'))))
    (expect !>(!(is-stream:arm (jo '{}'))))
  ==
::  ==  accounts and settings
::
++  test-account-roundtrip
  =/  bare=account:arm  [~wex -20 t0 ~ | '' '' '' ~]
  =/  subbed=account:arm  [~wex -20 t0 `t0 | 'pro' 'cus_9' 'sub_9' `t0]
  ;:  weld
    (expect-eq !>(`(unit account:arm)`[~ bare]) !>((de-account:arm (en-account:arm bare))))
    (expect-eq !>(`(unit account:arm)`[~ subbed]) !>((de-account:arm (en-account:arm subbed))))
  ==
::  the customer's own view never carries the Stripe ids; the owner's
::  read of the same account does
::
++  test-en-subscription
  =/  mine=json  (en-subscription:arm 'sub_9' `t0 |)
  =/  theirs=json  (en-subscription:arm 'sub_9' `t0 &)
  =/  none=json  (en-subscription:arm '' ~ |)
  ;:  weld
    (expect !>((gb:arm mine 'active')))
    (expect-eq !>('') !>((gs:arm mine 'id')))
    (expect-eq !>('sub_9') !>((gs:arm theirs 'id')))
    (expect !>(!(gb:arm none 'active')))
    (expect-eq !>(`json`~) !>((gj:arm none 'renews')))
  ==
++  test-de-settings
  =/  got  (de-settings:arm starter-settings:arm)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`@ud`130) !>(?:(?=(%& -.got) markup.p.got 0)))
    (expect-eq !>(`@ud`5.000.000) !>(?:(?=(%& -.got) min-topup.p.got 0)))
    (expect-eq !>('https://api.stripe.com') !>(?:(?=(%& -.got) stripe-url.p.got '')))
    (expect-eq !>('') !>(?:(?=(%& -.got) stripe-key.p.got 'x')))
    (expect-eq !>('') !>(?:(?=(%& -.got) lease-provider.p.got 'x')))
  ==
::  the provider whose provisioning key mints leases is a plain id, so
::  it round-trips unmasked while the keys beside it do not
::
++  test-de-settings-lease-provider
  =/  doc=@t  '{"markup_pct":130,"mode":"stub","lease_provider":"open"}'
  =/  got  (de-settings:arm (jo doc))
  =/  back=json  ?:(?=(%& -.got) (en-settings:arm p.got) ~)
  (expect-eq !>('open') !>((gs:arm back 'lease_provider')))
::  a blank stripe_url is the real Stripe, so a settings document written
::  before phase 3 still points somewhere
::
++  test-de-settings-stripe-url
  =/  got  (de-settings:arm (jo '{"markup_pct":130,"mode":"live","stripe_url":""}'))
  (expect-eq !>('https://api.stripe.com') !>(?:(?=(%& -.got) stripe-url.p.got '')))
::  the two Stripe secrets are masked by the same arm the provider keys
::  use, so nothing had to be added for them
::
++  test-mask-doc-stripe
  =/  doc=json  (jo '{"stripe_key":"sk_test_abcd","stripe_webhook_secret":"whsec_wxyz","stripe_url":"https://api.stripe.com"}')
  =/  masked=json  (mask-doc:arm doc)
  ;:  weld
    (expect-eq !>('••••abcd') !>((gs:arm masked 'stripe_key')))
    (expect-eq !>('••••wxyz') !>((gs:arm masked 'stripe_webhook_secret')))
    (expect-eq !>('https://api.stripe.com') !>((gs:arm masked 'stripe_url')))
  ==
::  ==  plans
::
++  test-de-plan
  =/  good=@t
    '{"id":"pro","name":"Pro","kind":"subscription","price":2500000,"credit":3000000,"interval":"month"}'
  =/  got  (de-plan:arm (jo good))
  ;:  weld
    (expect !>((taken (de-plan:arm (jo good)))))
    (expect-eq !>('pro') !>(?:(?=(%& -.got) id.p.got '')))
    (expect-eq !>('month') !>(?:(?=(%& -.got) interval.p.got '')))
    (expect-eq !>('') !>(?:(?=(%& -.got) stripe-price.p.got 'x')))
    %+  expect-eq  !>('id: 1 to 64 bytes')
    !>((why (de-plan:arm (jo '{"kind":"topup","price":1,"credit":1}'))))
    %+  expect-eq  !>('kind: topup or subscription')
    !>((why (de-plan:arm (jo '{"id":"a","kind":"x","price":1,"credit":1}'))))
    %+  expect-eq  !>('price: above zero')
    !>((why (de-plan:arm (jo '{"id":"a","kind":"topup","price":0,"credit":1}'))))
    %+  expect-eq  !>('credit: above zero')
    !>((why (de-plan:arm (jo '{"id":"a","kind":"topup","price":1,"credit":0}'))))
    %+  expect-eq  !>('interval: month or year')
    !>((why (de-plan:arm (jo '{"id":"a","kind":"subscription","price":1,"credit":1}'))))
    ::  a top-up plan needs no interval
    (expect !>((taken (de-plan:arm (jo '{"id":"a","kind":"topup","price":1,"credit":1}')))))
  ==
++  test-en-plans-public
  =/  doc=@t
    '{"pro":{"id":"pro","name":"Pro","kind":"subscription","price":2500000,"credit":3000000,"interval":"month","stripe_price":"price_1"},"ten":{"id":"ten","name":"Ten","kind":"topup","price":10000000,"credit":10000000,"interval":"","stripe_price":""}}'
  =/  plans=(list plan:arm)  (plans-sorted:arm (jo doc))
  =/  out=json  (en-plans-public:arm plans)
  =/  rows=(list json)  ?:(?=([%a *] out) p.out ~)
  =/  first=json  ?~(rows ~ i.rows)
  =/  ten=(unit plan:arm)  (find-plan:arm plans 'ten')
  =/  pro=(unit plan:arm)  (plan-by-price:arm plans 'price_1')
  ;:  weld
    (expect-eq !>(`@ud`2) !>((lent plans)))
    ::  by id, so a page and a gate see one order
    (expect-eq !>('pro') !>((gs:arm first 'id')))
    (expect-eq !>('price_1') !>((gs:arm first 'stripe_price')))
    (expect-eq !>(`(unit plan:arm)`~) !>((find-plan:arm plans 'nope')))
    (expect-eq !>('ten') !>(?~(ten '' id.u.ten)))
    (expect-eq !>('pro') !>(?~(pro '' id.u.pro)))
    (expect-eq !>(`(unit plan:arm)`~) !>((plan-by-price:arm plans '')))
  ==
++  test-de-op-plan
  =/  good=@t  '{"plan":{"id":"a","kind":"topup","price":1,"credit":1}}'
  ;:  weld
    (expect !>((taken (de-op-plan:arm (jo good)))))
    (expect !>((refused (de-op-plan:arm (jo '{"plan":{}}')))))
    (expect !>((taken (de-op-drop-plan:arm (jo '{"id":"a"}')))))
    (expect !>((refused (de-op-drop-plan:arm (jo '{}')))))
  ==
++  test-de-op-subscription
  =/  good=@t
    '{"ship":"~feb","customer":"cus_9","subscription":"sub_9","plan":"pro","renews":"2026-09-19T22:05:00Z"}'
  =/  got  (de-op-subscription:arm (jo good))
  ;:  weld
    (expect !>((taken (de-op-subscription:arm (jo good)))))
    (expect-eq !>('sub_9') !>(?:(?=(%& -.got) subscription.p.got '')))
    (expect-eq !>(`(unit @da)`[~ t0]) !>(?:(?=(%& -.got) renews.p.got ~)))
    (expect !>((refused (de-op-subscription:arm (jo '{"ship":"~feb"}')))))
    (expect !>((refused (de-op-subscription:arm (jo '{"subscription":"sub_9"}')))))
    (expect !>((taken (de-op-clear-subscription:arm (jo '{"ship":"~feb"}')))))
  ==
++  test-de-settings-bad-mode
  =/  got  (de-settings:arm (jo '{"markup_pct":130,"mode":"nope"}'))
  (expect-eq !>('mode: stub or live') !>(?:(?=(%| -.got) p.got '')))
::  ==  the writer's ops
::
++  test-de-op-account
  ;:  weld
    (expect !>((refused (de-op-account:arm (jo '{"ship":"~not-a-ship"}')))))
    (expect !>((taken (de-op-account:arm (jo '{"ship":"~wex"}')))))
    (expect !>((refused (de-op-account:arm (jo '{}')))))
  ==
++  test-de-op-credit
  =/  good  (jo '{"ship":"~wex","amount":100,"rail":"owner","ref":"owner-1","note":"hi"}')
  =/  got  (de-op-credit:arm good)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`@ud`100) !>(?:(?=(%& -.got) amount.p.got 0)))
    (expect !>((refused (de-op-credit:arm (jo '{"ship":"~wex","amount":0,"rail":"owner","ref":"x"}')))))
    (expect !>((refused (de-op-credit:arm (jo '{"ship":"~wex","amount":5,"rail":"owner"}')))))
  ==
++  test-de-op-debit
  =/  good  (jo '{"ship":"~wex","amount":137,"cost":105,"model":"stub/alpha","in":10,"out":5,"mode":"proxy","ref":"stub-1"}')
  =/  got  (de-op-debit:arm good)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`@ud`137) !>(?:(?=(%& -.got) amount.p.got 0)))
    (expect !>((refused (de-op-debit:arm (jo '{"ship":"~wex","model":"a","mode":"x"}')))))
  ==
++  test-de-op-drop
  ;:  weld
    (expect !>((taken (de-op-drop:arm (jo '{"id":"stub"}')))))
    (expect !>((refused (de-op-drop:arm (jo '{}')))))
  ==
++  test-de-op
  (expect-eq !>('credit') !>((de-op:arm (jo '{"op":"credit"}'))))
::  ==  the ring
::
++  test-ring-push
  =/  e1=json  (jo '{"n":1}')
  =/  e2=json  (jo '{"n":2}')
  =/  e3=json  (jo '{"n":3}')
  =/  one=json  (ring-push:arm [%a ~] e1 2)
  =/  two=json  (ring-push:arm one e2 2)
  =/  three=json  (ring-push:arm two e3 2)
  =/  rows=(list json)  ?:(?=([%a *] three) p.three ~)
  =/  head=json  ?~(rows ~ i.rows)
  ;:  weld
    (expect-eq !>(`@ud`2) !>((lent rows)))
    (expect-eq !>(`@ud`3) !>((gn:arm head 'n')))
  ==
++  test-trail-entry
  =/  e=json  (trail-entry:arm 'credit' & '' '~wex' --100 t0)
  ;:  weld
    (expect-eq !>('credit') !>((gs:arm e 'op')))
    (expect-eq !>('~wex') !>((gs:arm e 'ship')))
    (expect-eq !>(`@sd`--100) !>((gsd:arm e 'amount')))
  ==
::  ==  the account channel
::
++  test-group-name
  ;:  weld
    (expect-eq !>('armillary-wex') !>((group-name:arm ~wex)))
    (expect-eq !>('armillary-sampel-palnet') !>((group-name:arm ~sampel-palnet)))
  ==
::  a comet is any identity past 64 bits; the literal name is sixteen
::  syllables, so the test names one by its value instead
++  test-is-comet
  ;:  weld
    (expect-eq !>(|) !>((is-comet:arm ~wex)))
    (expect-eq !>(|) !>((is-comet:arm ~sampel-palnet-sampel-palnet)))
    (expect-eq !>(&) !>((is-comet:arm `@p`(bex 100))))
  ==
++  test-de-inbox-plain
  ;:  weld
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%hello ~]]) !>((de-inbox:arm (jo '{"op":"hello"}'))))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%refresh ~]]) !>((de-inbox:arm (jo '{"op":"refresh"}'))))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%lease ~]]) !>((de-inbox:arm (jo '{"op":"lease"}'))))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%drop-lease ~]]) !>((de-inbox:arm (jo '{"op":"drop-lease"}'))))
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%cancel-subscription ~]])
    !>((de-inbox:arm (jo '{"op":"cancel-subscription"}')))
  ==
++  test-de-inbox-keys
  ;:  weld
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%mint-key 'phone' 'n1']])
    !>((de-inbox:arm (jo '{"op":"mint-key","name":"phone","nonce":"n1"}')))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%got-key 'abc']]) !>((de-inbox:arm (jo '{"op":"got-key","id":"abc"}'))))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%drop-key 'abc']]) !>((de-inbox:arm (jo '{"op":"drop-key","id":"abc"}'))))
  ==
++  test-de-inbox-checkout
  ;:  weld
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%checkout 'stripe' '' 1.000.000 'n2']])
    !>((de-inbox:arm (jo '{"op":"checkout","rail":"stripe","amount":1000000,"nonce":"n2"}')))
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%checkout 'btcpay' 'pro' 0 'n3']])
    !>((de-inbox:arm (jo '{"op":"checkout","rail":"btcpay","plan":"pro","nonce":"n3"}')))
  ==
++  test-de-inbox-refusals
  ;:  weld
    (expect-eq !>('op: unknown') !>((why (de-inbox:arm (jo '{"op":"x"}')))))
    (expect-eq !>('op: unknown') !>((why (de-inbox:arm (jo '{}')))))
    %-  expect-eq
    :-  !>('nonce: 1 to 64 bytes')
    !>((why (de-inbox:arm (jo '{"op":"mint-key","name":"phone"}'))))
    %-  expect-eq
    :-  !>('name: 1 to 200 bytes')
    !>((why (de-inbox:arm (jo '{"op":"mint-key","nonce":"n1"}'))))
    %-  expect-eq
    :-  !>('plan or amount required')
    !>((why (de-inbox:arm (jo '{"op":"checkout","rail":"stripe","nonce":"n2"}'))))
    %-  expect-eq
    :-  !>('rail: stripe or btcpay')
    !>((why (de-inbox:arm (jo '{"op":"checkout","rail":"cash","nonce":"n2","amount":10}'))))
  ==
::  +why: a refusal's text, so a test asks for the message by name
++  why  |=(e=(each * @t) ^-(@t ?:(?=(%| -.e) p.e '')))
::  +round: an op through en-inbox and back
++  round  |=(o=inbox-op:arm ^-((each inbox-op:arm @t) (de-inbox:arm (en-inbox:arm o))))
++  test-en-inbox-roundtrip
  ;:  weld
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%hello ~]]) !>((round [%hello ~])))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%refresh ~]]) !>((round [%refresh ~])))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%lease ~]]) !>((round [%lease ~])))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%drop-lease ~]]) !>((round [%drop-lease ~])))
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%cancel-subscription ~]])
    !>((round [%cancel-subscription ~]))
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%checkout 'stripe' '' 1.000.000 'n2']])
    !>((round [%checkout 'stripe' '' 1.000.000 'n2']))
    %-  expect-eq
    :-  !>(`(each inbox-op:arm @t)`[%& [%mint-key 'phone' 'n1']])
    !>((round [%mint-key 'phone' 'n1']))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%got-key 'abc']]) !>((round [%got-key 'abc'])))
    (expect-eq !>(`(each inbox-op:arm @t)`[%& [%drop-key 'abc']]) !>((round [%drop-key 'abc'])))
  ==
::  ==  the account view
::
++  a-view
  ^-  view:arm
  :*  ~wex
      --1.000.000
      'pro'
      [%o ~]
      ~[(jo '{"id":"abc","name":"phone"}')]
      ~[['n1' 'abc' 'phone' 'sss']]
      ~
      'not offered'
      (jo '{"n2":{"url":"http://x/pay","status":"pending"}}')
      ~[(jo '{"kind":"credit","amount":1000000}')]
      'https://vendor.example'
      7
      t0
  ==
++  test-view-roundtrip
  =/  back=(unit view:arm)  (de-view:arm (en-view:arm a-view))
  ;:  weld
    (expect-eq !>(`(unit view:arm)`[~ a-view]) !>(back))
    (expect-eq !>(`(unit view:arm)`~) !>((de-view:arm (jo '{"rev":1}'))))
    (expect-eq !>(`(unit view:arm)`~) !>((de-view:arm (jo '{"ship":"~wex"}'))))
  ==
++  test-view-nonces
  =/  ns=(set @t)  (view-nonces:arm a-view)
  ;:  weld
    (expect-eq !>(&) !>((~(has in ns) 'n1')))
    (expect-eq !>(&) !>((~(has in ns) 'n2')))
    (expect-eq !>(|) !>((~(has in ns) 'n9')))
    (expect-eq !>(`@ud`2) !>(~(wyt in ns)))
  ==
::  ==  the customer's own keys
::
++  test-held-key
  =/  k=held-key:arm  ['abc' 'phone' 'sss' t0]
  =/  back=(unit held-key:arm)  (de-held:arm (en-held:arm k))
  =/  pub=json  (en-held-public:arm k)
  ;:  weld
    (expect-eq !>(`(unit held-key:arm)`[~ k]) !>(back))
    (expect-eq !>('') !>((gs:arm pub 'secret')))
    (expect-eq !>('abc') !>((gs:arm pub 'id')))
    (expect-eq !>(`(unit held-key:arm)`~) !>((de-held:arm (jo '{"id":"abc"}'))))
  ==
++  test-inference-json
  =/  j=json  (inference-json:arm 'proxy' 'http://x/v1' 'abc.sss' ~['stub/alpha' 'stub/beta'])
  ;:  weld
    (expect-eq !>('proxy') !>((gs:arm j 'mode')))
    (expect-eq !>('http://x/v1') !>((gs:arm j 'base_url')))
    (expect-eq !>('abc.sss') !>((gs:arm j 'key')))
    (expect-eq !>(`@ud`2) !>((lent (ga:arm j 'models'))))
  ==
::  ==  the channel's writer ops
::
++  test-de-op-pending
  =/  full=@t  '{"ship":"~wex","id":"abc","secret":"s","nonce":"n1","name":"phone"}'
  ;:  weld
    (expect !>((taken (de-op-pending:arm (jo full)))))
    %-  expect-eq
    :-  !>('secret: required')
    !>((why (de-op-pending:arm (jo '{"ship":"~wex","id":"abc","nonce":"n1"}'))))
    (expect !>((refused (de-op-pending:arm (jo '{"id":"abc"}')))))
  ==
++  test-de-op-checkout
  =/  full=@t
    '{"ship":"~wex","nonce":"n2","rail":"stripe","amount":10,"url":"u","status":"pending"}'
  ;:  weld
    (expect !>((taken (de-op-checkout:arm (jo full)))))
    %-  expect-eq
    :-  !>('status: required')
    !>((why (de-op-checkout:arm (jo '{"ship":"~wex","nonce":"n2"}'))))
  ==
++  test-de-op-vendor
  ;:  weld
    (expect-eq !>(`(each (unit @p) @t)`[%& `~wex]) !>((de-op-vendor:arm (jo '{"ship":"~wex"}'))))
    (expect-eq !>(`(each (unit @p) @t)`[%& ~]) !>((de-op-vendor:arm (jo '{"ship":""}'))))
    (expect !>((refused (de-op-vendor:arm (jo '{"ship":"~not-a-ship"}')))))
  ==
++  test-de-op-client
  =/  kj=@t
    '{"key":{"id":"abc","name":"phone","secret":"s","made":"2026-09-19T22:05:00Z"}}'
  ;:  weld
    (expect !>((taken (de-op-store-key:arm (jo kj)))))
    (expect !>((refused (de-op-store-key:arm (jo '{"key":{"id":"abc"}}')))))
    (expect !>((taken (de-op-forget-key:arm (jo '{"id":"abc"}')))))
    (expect !>((refused (de-op-forget-key:arm (jo '{}')))))
    (expect !>((taken (de-op-store-view:arm (jo '{"view":{"ship":"~wex","rev":1}}')))))
    (expect !>((refused (de-op-store-view:arm (jo '{}')))))
    (expect !>((taken (de-op-note-op:arm (jo '{"nonce":"n1","payload":{"op":"hello"}}')))))
    (expect !>((refused (de-op-note-op:arm (jo '{"nonce":"n1"}')))))
    (expect !>((taken (de-op-drop-op:arm (jo '{"nonce":"n1"}')))))
  ==
::  ==  the lease
::
++  a-lease
  ^-  lease:arm
  ['open' 'h7' 'sk-or-v1-abc' 750.000 2.000.000 | t0 t0]
++  test-lease-roundtrip
  =/  back=(unit lease:arm)  (de-lease:arm (en-lease:arm a-lease))
  ;:  weld
    (expect-eq !>(`(unit lease:arm)`[~ a-lease]) !>(back))
    (expect-eq !>(`(unit lease:arm)`~) !>((de-lease:arm (jo '{"key":"x"}'))))
    (expect-eq !>(`(unit lease:arm)`~) !>((de-lease:arm (jo '{}'))))
  ==
++  test-lease-owner-hides-the-key
  =/  owner=json  (en-lease-owner:arm a-lease)
  =/  text=@t    (en:json:html owner)
  ;:  weld
    (expect-eq !>('h7') !>((gs:arm owner 'hash')))
    (expect-eq !>(`@ud`750.000) !>((gn:arm owner 'usage_seen')))
    (expect !>(=(~ (find "sk-or-v1-abc" (trip text)))))
  ==
++  test-lease-view
  =/  v=json  (en-lease-view:arm a-lease 'https://openrouter.ai/api/v1' ~['a/b'])
  ;:  weld
    (expect-eq !>('openrouter') !>((gs:arm v 'provider')))
    (expect-eq !>('https://openrouter.ai/api/v1') !>((gs:arm v 'base_url')))
    (expect-eq !>('sk-or-v1-abc') !>((gs:arm v 'key')))
    (expect-eq !>(`@ud`750.000) !>((gn:arm v 'usage')))
    (expect-eq !>(`(list @t)`~['a/b']) !>((strings:arm (ga:arm v 'models'))))
  ==
++  test-de-op-lease
  =/  full=@t
    '{"ship":"~wex","lease":{"hash":"h7","key":"k","provider":"open","checked":"2026-09-19T22:05:00Z"}}'
  ;:  weld
    (expect !>((taken (de-op-lease:arm (jo full)))))
    (expect !>((refused (de-op-lease:arm (jo '{"ship":"~wex","lease":{}}')))))
    (expect !>((taken (de-op-drop-lease:arm (jo '{"ship":"~wex"}')))))
    (expect !>((refused (de-op-drop-lease:arm (jo '{}')))))
  ==
++  test-de-op-touch-lease
  =/  both=@t
    '{"ship":"~wex","usage_seen":10,"limit":20,"disabled":true,"checked":"2026-09-19T22:05:00Z"}'
  =/  bare=@t  '{"ship":"~wex","usage_seen":10,"checked":"2026-09-19T22:05:00Z"}'
  =/  got  (de-op-touch-lease:arm (jo both))
  =/  thin  (de-op-touch-lease:arm (jo bare))
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 20]) !>(?:(?=(%& -.got) limit.p.got ~)))
    (expect-eq !>(`(unit ?)`[~ &]) !>(?:(?=(%& -.got) disabled.p.got ~)))
    (expect-eq !>(`(unit @ud)`~) !>(?:(?=(%& -.thin) limit.p.thin `99)))
    (expect-eq !>(`(unit ?)`~) !>(?:(?=(%& -.thin) disabled.p.thin `&)))
    (expect !>((refused (de-op-touch-lease:arm (jo '{"ship":"~wex"}')))))
  ==
++  test-de-op-lease-error
  ;:  weld
    (expect !>((taken (de-op-lease-error:arm (jo '{"ship":"~wex","why":"not offered"}')))))
    (expect !>((taken (de-op-lease-error:arm (jo '{"ship":"~wex","why":""}')))))
    (expect !>((refused (de-op-lease-error:arm (jo '{"why":"x"}')))))
  ==
::  ==  compaction
::
::  three months of rows, two kinds, plus one row inside the window and
::  one summary already written. Only the first four fold.
::
++  old-rows
  ^-  (list [name=@ta =row:arm])
  :~  ['a' [%credit 100 0 '' 0 0 '' 'stub' 'r1' '' ~2026.1.5]]
      ['b' [%credit 50 0 '' 0 0 '' 'stub' 'r2' '' ~2026.1.20]]
      ['c' [%debit 30 20 'x' 1 2 'proxy' '' 'r3' '' ~2026.2.3]]
      ['d' [%debit 7 5 'y' 1 1 'proxy' '' 'r4' '' ~2026.3.9]]
      ['e' [%credit 9 0 '' 0 0 '' 'stub' 'compact-2025-12-credit' '' ~2025.12.1]]
      ['f' [%debit 1 1 'z' 0 0 'proxy' '' 'r5' '' ~2026.9.18]]
  ==
++  test-month-start
  ;:  weld
    (expect-eq !>(`@da`~2026.2.1) !>((month-start:arm ~2026.2.3..11.30.00)))
    (expect-eq !>('2026-02') !>((month-of:arm ~2026.2.3..11.30.00)))
    (expect-eq !>('2026-11') !>((month-of:arm ~2026.11.30)))
  ==
++  test-is-summary
  ;:  weld
    (expect !>((is-summary:arm 'compact-2026-01-credit')))
    (expect !>(!(is-summary:arm 'stub-n1')))
    (expect !>(!(is-summary:arm '')))
  ==
++  test-compact-fold
  =/  got  (compact-fold:arm old-rows ~2026.6.1)
  =/  refs=(list @t)  (turn fresh.got |=(r=row:arm ref.r))
  ;:  weld
    (expect-eq !>(`@ud`3) !>((lent fresh.got)))
    (expect-eq !>(`@ud`4) !>((lent stale.got)))
    %+  expect-eq
      !>(`(list @t)`~['compact-2026-01-credit' 'compact-2026-02-debit' 'compact-2026-03-debit'])
    !>(refs)
    (expect-eq !>(`@ud`150) !>(amount:(snag 0 fresh.got)))
    (expect-eq !>('2 rows') !>(note:(snag 0 fresh.got)))
    (expect-eq !>(`@ud`30) !>(amount:(snag 1 fresh.got)))
    (expect-eq !>(`@ud`20) !>(cost:(snag 1 fresh.got)))
    (expect-eq !>(`@da`~2026.2.1) !>(at:(snag 1 fresh.got)))
  ==
++  test-compact-fold-keeps-the-balance
  ::  a fold moves nothing: the sum over the summaries plus the rows it
  ::  left alone is the sum over everything
  =/  got  (compact-fold:arm old-rows ~2026.6.1)
  =/  all=(list row:arm)  (turn old-rows |=([n=@ta r=row:arm] r))
  =/  kept=(list row:arm)
    %+  murn  old-rows
    |=([n=@ta r=row:arm] ^-((unit row:arm) ?:((lien stale.got |=(x=@ta =(x n))) ~ `r)))
  %+  expect-eq
    !>((fold-balance:arm all))
  !>((fold-balance:arm (weld fresh.got kept)))
++  test-compact-fold-nothing-old
  =/  got  (compact-fold:arm old-rows ~2025.1.1)
  ;:  weld
    (expect-eq !>(`@ud`0) !>((lent fresh.got)))
    (expect-eq !>(`@ud`0) !>((lent stale.got)))
  ==
++  test-de-op-store-lease
  ;:  weld
    (expect !>((taken (de-op-store-lease:arm (jo '{"lease":{"key":"k"}}')))))
    (expect !>((taken (de-op-store-lease:arm (jo '{"lease":null}')))))
    (expect !>((taken (de-op-store-lease:arm (jo '{}')))))
    (expect !>((refused (de-op-store-lease:arm (jo '{"lease":"k"}')))))
  ==
--
