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
  =/  a=account:arm  [~wex -20 t0 ~ |]
  (expect-eq !>(`(unit account:arm)`[~ a]) !>((de-account:arm (en-account:arm a))))
++  test-de-settings
  =/  got  (de-settings:arm starter-settings:arm)
  ;:  weld
    (expect !>(?=(%& -.got)))
    (expect-eq !>(`@ud`130) !>(?:(?=(%& -.got) markup.p.got 0)))
    (expect-eq !>(`@ud`5.000.000) !>(?:(?=(%& -.got) min-topup.p.got 0)))
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
--
