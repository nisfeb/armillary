::  Unit tests for /lib/armillary-openrouter: the provisioning requests
::  and the answers they read.
::
::    A built request is checked by decoding the JSON body it made back
::    into a document, so the assertion reads as the fields OpenRouter
::    documents rather than as one long string.
::
/+  *test, ao=armillary-openrouter
|%
++  base   'https://openrouter.ai/api/v1/keys'
++  key    'sk-or-prov-1'
::  +body-json: a built request's body, read back as a document
::
++  body-json
  |=  req=request:http
  ^-  json
  =/  bod=(unit octs)  body.req
  ?~  bod  ~
  (fall (de:json:html q.u.bod) ~)
::  ==  money
::
++  test-usd-of
  ;:  weld
    (expect-eq !>('1.500000') !>((usd-of:ao 1.500.000)))
    (expect-eq !>('0.000000') !>((usd-of:ao 0)))
    (expect-eq !>('0.000001') !>((usd-of:ao 1)))
  ==
++  test-micro-of
  ;:  weld
    (expect-eq !>(`(unit @ud)`[~ 12.300]) !>((micro-of:ao [%n '0.0123'])))
    (expect-eq !>(`(unit @ud)`[~ 1.000.000]) !>((micro-of:ao [%n '1'])))
    (expect-eq !>(`(unit @ud)`[~ 0]) !>((micro-of:ao [%n '0.00000049'])))
  ==
++  test-micro-of-junk
  ::  OpenRouter sends numbers; a string where a number belongs is not
  ::  read as money at all
  ;:  weld
    (expect-eq !>(`(unit @ud)`~) !>((micro-of:ao s+'0.75')))
    (expect-eq !>(`(unit @ud)`~) !>((micro-of:ao ~)))
    (expect-eq !>(`(unit @ud)`~) !>((micro-of:ao [%n 'x'])))
  ==
::  ==  where the keys live
::
++  test-keys-base
  ;:  weld
    %+  expect-eq
      !>('https://openrouter.ai/api/v1/keys')
    !>((keys-base:ao 'https://openrouter.ai/api/v1'))
    %+  expect-eq
      !>('http://127.0.0.1:3399/api/v1/keys')
    !>((keys-base:ao 'http://127.0.0.1:3399/v1'))
  ==
::  ==  the builders
::
++  test-create-request-head
  =/  req=request:http  (create-request:ao base key 'armillary/~feb' 1.500.000)
  ;:  weld
    (expect-eq !>(%'POST') !>(method.req))
    (expect-eq !>(base) !>(url.req))
    %+  expect-eq
      !>(`(unit @t)`[~ 'Bearer sk-or-prov-1'])
    !>((get-header:http 'authorization' header-list.req))
    %+  expect-eq
      !>(`(unit @t)`[~ 'application/json'])
    !>((get-header:http 'content-type' header-list.req))
  ==
++  test-create-request-body
  =/  req=request:http  (create-request:ao base key 'armillary/~feb' 1.500.000)
  =/  jon=json  (body-json req)
  ;:  weld
    (expect-eq !>('armillary/~feb') !>((gs:ao jon 'name')))
    (expect-eq !>(`(unit @ud)`[~ 1.500.000]) !>((micro-of:ao (gj:ao jon 'limit'))))
  ==
++  test-get-request
  =/  req=request:http  (get-request:ao base key 'h1')
  ;:  weld
    (expect-eq !>(%'GET') !>(method.req))
    (expect-eq !>('https://openrouter.ai/api/v1/keys/h1') !>(url.req))
    %+  expect-eq
      !>(`(unit @t)`[~ 'Bearer sk-or-prov-1'])
    !>((get-header:http 'authorization' header-list.req))
    (expect-eq !>(`(unit octs)`~) !>(body.req))
  ==
++  test-delete-request
  =/  req=request:http  (delete-request:ao base key 'h1')
  ;:  weld
    (expect-eq !>(%'DELETE') !>(method.req))
    (expect-eq !>('https://openrouter.ai/api/v1/keys/h1') !>(url.req))
    (expect-eq !>(`(unit octs)`~) !>(body.req))
  ==
::  +field-kinds: which of the two patch fields a body carries, so a
::  patch that names one is told from one that names both
::
++  field-kinds
  |=  jon=json
  ^-  [lim=@ud dis=@ud]
  :-  ?:(?=([%n *] (gj:ao jon 'limit')) 1 0)
  ?:(?=([%b *] (gj:ao jon 'disabled')) 1 0)
++  test-patch-disabled
  =/  req=request:http  (patch-request:ao base key 'h1' ~ `&)
  =/  jon=json  (body-json req)
  ;:  weld
    (expect-eq !>(%'PATCH') !>(method.req))
    (expect-eq !>('https://openrouter.ai/api/v1/keys/h1') !>(url.req))
    (expect-eq !>(`[@ud @ud]`[0 1]) !>((field-kinds jon)))
    (expect !>((gb:ao jon 'disabled')))
  ==
++  test-patch-limit
  =/  req=request:http  (patch-request:ao base key 'h1' `500.000 ~)
  =/  jon=json  (body-json req)
  ;:  weld
    (expect-eq !>(`[@ud @ud]`[1 0]) !>((field-kinds jon)))
    (expect-eq !>(`(unit @ud)`[~ 500.000]) !>((micro-of:ao (gj:ao jon 'limit'))))
  ==
++  test-patch-both
  =/  req=request:http  (patch-request:ao base key 'h1' `2.000.000 `|)
  =/  jon=json  (body-json req)
  ;:  weld
    (expect-eq !>(`[@ud @ud]`[1 1]) !>((field-kinds jon)))
    (expect-eq !>(`(unit @ud)`[~ 2.000.000]) !>((micro-of:ao (gj:ao jon 'limit'))))
    (expect !>(!(gb:ao jon 'disabled')))
  ==
::  ==  the readers
::
++  created-body
  '''
  {"key":"sk-or-v1-abc123","data":{"hash":"h7","name":"armillary/~feb",
   "label":"armillary/~feb","limit":1.5,"limit_remaining":1.5,
   "limit_reset":null,"disabled":false,"usage":0,"usage_daily":0,
   "created_at":"2026-09-20T00:00:00Z"}}
  '''
++  read-body
  '''
  {"data":{"hash":"h7","name":"armillary/~feb","limit":2,
   "disabled":false,"usage":0.75,"usage_daily":0.75}}
  '''
++  test-read-created
  =/  got  (read-created:ao created-body)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect-eq !>('sk-or-v1-abc123') !>(key.u.got))
    (expect-eq !>('h7') !>(hash.u.got))
    (expect-eq !>(`@ud`0) !>(usage.u.got))
    (expect-eq !>(`@ud`1.500.000) !>(limit.u.got))
    (expect !>(!disabled.u.got))
  ==
++  test-read-key
  =/  got  (read-key:ao read-body)
  ?~  got  (expect !>(|))
  ;:  weld
    (expect-eq !>('h7') !>(hash.u.got))
    (expect-eq !>(`@ud`750.000) !>(usage.u.got))
    (expect-eq !>(`@ud`2.000.000) !>(limit.u.got))
    (expect !>(!disabled.u.got))
  ==
++  test-read-junk
  =/  a=@ud  ?~((read-key:ao 'not json') 0 1)
  =/  b=@ud  ?~((read-key:ao '{"data":{"usage":1}}') 0 1)
  =/  c=@ud  ?~((read-created:ao '{"data":{"hash":"h7"}}') 0 1)
  ;:  weld
    (expect-eq !>(`@ud`0) !>(a))
    (expect-eq !>(`@ud`0) !>(b))
    (expect-eq !>(`@ud`0) !>(c))
  ==
::  ==  the two sums a lease turns on
::
++  test-debit-for
  ;:  weld
    (expect-eq !>(`@ud`130.000) !>((debit-for:ao 100.000 0 130)))
    (expect-eq !>(`@ud`65.000) !>((debit-for:ao 150.000 100.000 130)))
  ==
++  test-debit-for-still
  ::  usage that did not move owes nothing, and one microdollar of
  ::  movement rounds up rather than down
  ;:  weld
    (expect-eq !>(`@ud`0) !>((debit-for:ao 100.000 100.000 130)))
    (expect-eq !>(`@ud`0) !>((debit-for:ao 50 100 130)))
    (expect-eq !>(`@ud`2) !>((debit-for:ao 1 0 130)))
  ==
++  test-limit-for
  ;:  weld
    (expect-eq !>(`@ud`869.230) !>((limit-for:ao 100.000 --1.000.000 130)))
    (expect-eq !>(`@ud`100.000) !>((limit-for:ao 100.000 -5.000 130)))
    (expect-eq !>(`@ud`100.000) !>((limit-for:ao 100.000 --0 130)))
  ==
--
