::  armillary: the model, pure. See docs/superpowers/specs/2026-09-19-armillary-design.md.
::
::    Import-free on purpose: the same file builds in the clay desk's
::    /lib, where -test reaches it, and in the app's code namespace,
::    where the nexus wraps it. Nothing here touches a ship: no bowl,
::    no roads, no vases.
::
::    Every amount is an integer number of microdollars: one dollar is
::    1.000.000. A price is microdollars per million tokens. A charge
::    rounds up, so a request never costs less than its price.
::
|%
::  ==  caps, the spec's
::
++  max-name       200                          ::  a key name
++  max-id         64                           ::  a provider id or name
++  max-url        500                          ::  a base url
++  max-model-id   200                          ::  a catalog id
++  max-providers  200
++  max-catalog    2.000
++  max-keys       20
++  ring-cap       500
++  max-body       4.194.304
::  ==  time
::
::  +unix-secs: seconds since 1970, 0 before it
::
++  unix-secs
  |=  d=@da
  ^-  @ud
  ?:  (lth d ~1970.1.1)  0
  (div (sub d ~1970.1.1) ~s1)
::  +de-iso: "2026-09-19T22:05:00Z" (a fraction is allowed and dropped,
::  Z only) to a @da, or ~
::
::    A day the month does not have is refused rather than rolled over:
::    +year turns 2026-02-30 into March, so the date is re-encoded and
::    compared with the ten characters the caller sent.
::
++  de-iso
  |=  t=@t
  ^-  (unit @da)
  =/  two   (bass 10 (stun [2 2] dit))
  =/  four  (bass 10 (stun [4 4] dit))
  =/  rule
    ;~  plug
      four
      ;~(pfix hep two)
      ;~(pfix hep two)
      ;~(pfix (just 'T') two)
      ;~(pfix col two)
      ;~(pfix col two)
      (punt ;~(pfix dot (plus dit)))
      (cold ~ (just 'Z'))
    ==
  =/  got  (rush t rule)
  ?~  got  ~
  =/  [y=@ud mo=@ud d=@ud h=@ud mi=@ud s=@ud *]  u.got
  ?.  ?&  (gte mo 1)   (lte mo 12)
          (gte d 1)    (lte d 31)
          (lth h 24)   (lth mi 60)  (lth s 60)
      ==
    ~
  =/  when=@da  (year [[& y] mo d h mi s ~])
  ?.  =((end [3 10] (en-iso when)) (end [3 10] t))  ~
  `when
::  +en-iso: a @da to "2026-09-19T22:05:00Z", whole seconds
::
++  en-iso
  |=  when=@da
  ^-  @t
  =/  [[* y=@ud] mo=@ud [d=@ud h=@ud mi=@ud s=@ud *]]  (yore when)
  =/  yy=tape  ((d-co:co 4) y)
  =/  mm=tape  ((d-co:co 2) mo)
  =/  dd=tape  ((d-co:co 2) d)
  =/  hh=tape  ((d-co:co 2) h)
  =/  ii=tape  ((d-co:co 2) mi)
  =/  ss=tape  ((d-co:co 2) s)
  (crip "{yy}-{mm}-{dd}T{hh}:{ii}:{ss}Z")
::  ==  json, read without crashing
::
++  gj                                          ::  a key's value, or null
  |=  [jon=json k=@t]
  ^-  json
  ?.  ?=([%o *] jon)  ~
  (fall (~(get by p.jon) k) ~)
++  has-key
  |=  [jon=json k=@t]
  ^-  ?
  ?.  ?=([%o *] jon)  |
  (~(has by p.jon) k)
++  gs                                          ::  a string, or ''
  |=  [jon=json k=@t]
  ^-  @t
  =/  v=json  (gj jon k)
  ?:(?=([%s *] v) p.v '')
++  gn                                          ::  a whole number, 0 when absent
  |=  [jon=json k=@t]
  ^-  @ud
  =/  v=json  (gj jon k)
  ?.  ?=([%n *] v)  0
  (fall (rush p.v dem) 0)
++  gb                                          ::  a boolean, false when absent
  |=  [jon=json k=@t]
  ^-  ?
  =/  v=json  (gj jon k)
  ?:(?=([%b *] v) p.v |)
++  ga                                          ::  an array's items, or ~
  |=  [jon=json k=@t]
  ^-  (list json)
  =/  v=json  (gj jon k)
  ?:(?=([%a *] v) p.v ~)
++  gt                                          ::  an ISO time
  |=  [jon=json k=@t]
  ^-  (unit @da)
  =/  s=@t  (gs jon k)
  ?:(=('' s) ~ (de-iso s))
++  gsd                                         ::  a number that may be negative
  |=  [jon=json k=@t]
  ^-  @sd
  =/  v=json  (gj jon k)
  ?.  ?=([%n *] v)  --0
  (de-sd p.v)
::  +de-sd: "-20" or "20" to a @sd, 0 on anything else
::
++  de-sd
  |=  t=@t
  ^-  @sd
  =/  tap=tape  (trip t)
  ?~  tap  --0
  ?.  =('-' i.tap)  (sun:si (fall (rush t dem) 0))
  =/  rest=@t  (crip t.tap)
  (new:si | (fall (rush rest dem) 0))
::  +strings: the strings in an array
::
++  strings
  |=  l=(list json)
  ^-  (list @t)
  (murn l |=(j=json ?:(?=([%s *] j) `p.j ~)))
++  en-time        |=(d=@da ^-(json s+(en-iso d)))
++  en-maybe-time  |=(d=(unit @da) ^-(json ?~(d ~ (en-time u.d))))
++  en-num         |=(n=@ud ^-(json (numb:enjs:format n)))
::  +en-sd: a signed amount as a JSON number, "-1500" or "1500"
::
++  en-sd
  |=  n=@sd
  ^-  json
  =/  mag=tape  (a-co:co (abs:si n))
  =/  txt=tape  ?:((syn:si n) mag ['-' mag])
  [%n (crip txt)]
::  ==  decimals
::
::  +de-dec: a decimal string to an integer scaled by 10^scale
::
::    "0.000003" at scale 12 is 3.000.000; "12" is 12.000.000.000.000;
::    "0" is 0. Fraction digits past the scale are dropped rather than
::    rounded. Any other character, or a second dot, answers ~.
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
::  +per-million: OpenRouter's dollars per token to microdollars per
::  million tokens. Six decimal places of a dollar times a million
::  tokens is twelve places of scale.
::
++  per-million  |=(t=@t ^-((unit @ud) (de-dec t 12)))
::  +trim-zeros: a tape without its trailing zeros
::
++  trim-zeros
  |=  t=tape
  ^-  tape
  =/  r=tape  (flop t)
  |-  ^-  tape
  ?~  r  ~
  ?:  =('0' i.r)  $(r t.r)
  (flop r)
::  +en-dec: an integer scaled by 10^scale back to a decimal string,
::  trailing zeros trimmed. 3.000.000 at scale 12 is "0.000003".
::
++  en-dec
  |=  [n=@ud scale=@ud]
  ^-  @t
  =/  unit-of=@ud  (pow 10 scale)
  =/  whole=@ud    (div n unit-of)
  =/  frac=@ud     (mod n unit-of)
  =/  wt=tape      (a-co:co whole)
  ?:  =(0 frac)  (crip wt)
  =/  ft0=tape  (a-co:co frac)
  =/  ft=tape   (weld (reap (sub scale (lent ft0)) '0') ft0)
  =/  cut=tape  (trim-zeros ft)
  =/  out=tape  (weld wt (weld "." cut))
  (crip out)
::  +dollars-per-token: a price in microdollars per million tokens as
::  the string OpenRouter uses
::
++  dollars-per-token  |=(price=@ud ^-(@t (en-dec price 12)))
::  ==  money
::
::  +charge: what tokens at a price cost, rounded up
::
++  charge
  |=  [toks=@ud price=@ud]
  ^-  @ud
  =/  n=@ud  (mul toks price)
  ?:  =(0 n)  0
  (div (add n 999.999) 1.000.000)
::  +markup-of: a cost times an integer percent, rounded up
::
++  markup-of
  |=  [cost=@ud pct=@ud]
  ^-  @ud
  =/  n=@ud  (mul cost pct)
  ?:  =(0 n)  0
  (div (add n 99) 100)
::  ==  keys
::
::  +secret-of, +id-of: base-32 text from entropy, dots stripped and
::  zero-padded to a floor, since scot drops leading zero digits: a
::  secret is 20 to 24 characters, an id 6 to 8. Callers feed each a
::  disjoint slice of the entropy; neither derives from the other.
::
++  secret-of
  |=  eny=@
  ^-  @t
  (pad-left (skip (slag 2 (trip (scot %uv (end [3 15] eny)))) |=(c=@t =('.' c))) 20)
++  id-of
  |=  eny=@
  ^-  @t
  (pad-left (skip (slag 2 (trip (scot %uv (end [3 5] eny)))) |=(c=@t =('.' c))) 6)
::  +pad-left: zeros in front, up to a floor
::
++  pad-left
  |=  [t=tape n=@ud]
  ^-  @t
  =/  len=@ud  (lent t)
  ?:  (gte len n)  (crip t)
  (crip (weld (reap (sub n len) '0') t))
::  +hash-token: a salted sha-256 as text
::
++  hash-token
  |=  [salt=@t secret=@t]
  ^-  @t
  (scot %ux (shax (rap 3 salt ':' secret ~)))
::  +parse-bearer: "Bearer <id>.<secret>" to the pair, or ~. The scheme
::  is case-insensitive; the id ends at the first dot.
::
++  parse-bearer
  |=  h=@t
  ^-  (unit [id=@t secret=@t])
  =/  t=tape  (trip h)
  ?.  (gte (lent t) 8)  ~
  ?.  =("bearer " (cass (scag 7 t)))  ~
  =/  tok=tape
    =/  raw=tape  (slag 7 t)
    |-  ?:(?=([%' ' *] raw) $(raw t.raw) raw)
  =/  at=(unit @ud)  (find "." tok)
  ?~  at  ~
  =/  id=tape  (scag u.at tok)
  =/  secret=tape  (slag +(u.at) tok)
  ?:  |(=(0 (lent id)) =(0 (lent secret)))  ~
  `[(crip id) (crip secret)]
::  +$  key: one inference key on an account. The secret is never
::  stored: only the salt and the salted hash.
::
+$  key  [id=@t name=@t salt=@t hash=@t made=@da used=(unit @da)]
::  +key-ok: the presented secret against the stored salt and hash
::
++  key-ok
  |=  [k=key secret=@t]
  ^-  ?
  =(hash.k (hash-token salt.k secret))
::  +en-key-row: the stored shape, salt and hash inside
::
++  en-key-row
  |=  k=key
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.k]
      ['name' s+name.k]
      ['salt' s+salt.k]
      ['hash' s+hash.k]
      ['made' (en-time made.k)]
      ['used' (en-maybe-time used.k)]
  ==
::  +en-key-public: the key as the owner's page sees it: no salt, no
::  hash, so a read route can never leak either
::
++  en-key-public
  |=  k=key
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.k]
      ['name' s+name.k]
      ['made' (en-time made.k)]
      ['used' (en-maybe-time used.k)]
  ==
::  +de-key: a stored key row, or ~ when a field is missing
::
++  de-key
  |=  jon=json
  ^-  (unit key)
  ?.  ?=([%o *] jon)  ~
  =/  id=@t    (gs jon 'id')
  =/  salt=@t  (gs jon 'salt')
  =/  hash=@t  (gs jon 'hash')
  =/  made=(unit @da)  (gt jon 'made')
  ?:  |(=('' id) =('' salt) =('' hash) ?=(~ made))  ~
  `[id (gs jon 'name') salt hash u.made (gt jon 'used')]
::  ==  masking
::
::  +secret-key: a field name whose value is a secret. Phase 3 adds the
::  Stripe and BTCPay fields; each of those ends in _key or _secret, so
::  this arm already names them.
::
++  secret-key
  |=  k=@t
  ^-  ?
  ?:  =('secret' k)  &
  =/  tap=tape  (trip k)
  =/  n=@ud  (lent tap)
  ?:  &((gte n 4) =("_key" (slag (sub n 4) tap)))  &
  &((gte n 7) =("_secret" (slag (sub n 7) tap)))
::  +mask: a secret as the page may see it: empty stays empty, so the
::  page tells unset from set; anything else is the last four
::  characters behind four bullets
::
++  mask
  |=  t=@t
  ^-  @t
  ?:  =('' t)  ''
  =/  tap=tape  (trip t)
  =/  n=@ud  (lent tap)
  =/  tail=tape  ?:((gte n 4) (slag (sub n 4) tap) tap)
  (rap 3 '••••' (crip tail) ~)
::  +mask-doc: every secret string in a document, masked in place
::
++  mask-doc
  |=  jon=json
  ^-  json
  ?.  ?=([%o *] jon)  jon
  :-  %o
  %-  ~(urn by p.jon)
  |=  [k=@t v=json]
  ^-  json
  ?:  &((secret-key k) ?=([%s *] v))  s+(mask p.v)
  (mask-doc v)
::  ==  providers
::
+$  provider
  $:  id=@t
      name=@t
      kind=?(%openai-compatible %openrouter)
      base-url=@t
      api-key=@t
      provisioning-key=@t
  ==
::  +de-provider: one provider row from the page, or the field that
::  failed. A blank api_key or provisioning_key means keep whatever is
::  stored; the writer resolves that, since the lib holds no state.
::
++  de-provider
  |=  jon=json
  ^-  (each provider @t)
  ?.  ?=([%o *] jon)  [%| 'a JSON object is required']
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
  =/  kind=@t  (gs jon 'kind')
  ?.  |(=('openai-compatible' kind) =('openrouter' kind))
    [%| 'kind: openai-compatible or openrouter']
  =/  base=@t  (gs jon 'base_url')
  ?:  |(=('' base) (gth (met 3 base) max-url))  [%| 'base_url: 1 to 500 bytes']
  =/  name=@t  ?:(=('' (gs jon 'name')) id (gs jon 'name'))
  ?:  (gth (met 3 name) max-id)  [%| 'name: 1 to 64 bytes']
  =/  akind=?(%openai-compatible %openrouter)
    ?:(=('openrouter' kind) %openrouter %openai-compatible)
  [%& [id name akind base (gs jon 'api_key') (gs jon 'provisioning_key')]]
::  +en-provider-full: the stored shape, the secrets inside. This never
::  leaves the ship.
::
++  en-provider-full
  |=  p=provider
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.p]
      ['name' s+name.p]
      ['kind' s+`@t`kind.p]
      ['base_url' s+base-url.p]
      ['api_key' s+api-key.p]
      ['provisioning_key' s+provisioning-key.p]
  ==
::  +en-provider-masked: the same row as a read route answers it: every
::  field, both secrets masked
::
++  en-provider-masked
  |=  p=provider
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.p]
      ['name' s+name.p]
      ['kind' s+`@t`kind.p]
      ['base_url' s+base-url.p]
      ['api_key' s+(mask api-key.p)]
      ['provisioning_key' s+(mask provisioning-key.p)]
  ==
::  +de-provider-stored: a stored provider row back to its shape
::
++  de-provider-stored
  |=  jon=json
  ^-  (unit provider)
  =/  got  (de-provider jon)
  ?:(?=(%| -.got) ~ `p.got)
::  ==  the catalog
::
+$  model-row
  $:  id=@t
      provider=@t
      upstream=@t
      in=@ud
      out=@ud
      cost-in=@ud
      cost-out=@ud
      enabled=?
      tags=(list @t)
  ==
::  +de-catalog: the whole catalog from the page, or the first failing
::  field named with its row index. Duplicate ids are refused, since a
::  request looks a model up by id and two rows would race.
::
++  de-catalog
  |=  jon=json
  ^-  (each (list model-row) @t)
  ?.  ?=([%a *] jon)  [%| 'a JSON array is required']
  =/  items=(list json)  p.jon
  ?:  (gth (lent items) max-catalog)  [%| 'catalog: over 2000 rows']
  =/  seen=(set @t)  *(set @t)
  =/  out=(list model-row)  ~
  =/  i=@ud  0
  |-  ^-  (each (list model-row) @t)
  ?~  items  [%& (flop out)]
  =/  at=tape  (a-co:co i)
  =/  where=@t  (crip (weld "row " (weld at " ")))
  =/  j=json  i.items
  ?.  ?=([%o *] j)  [%| (cat 3 where 'a JSON object is required')]
  =/  id=@t  (gs j 'id')
  ?:  |(=('' id) (gth (met 3 id) max-model-id))
    [%| (cat 3 where 'id: 1 to 200 bytes')]
  ?:  (~(has in seen) id)  [%| (cat 3 where 'id: duplicate')]
  =/  prov=@t  (gs j 'provider')
  ?:  |(=('' prov) (gth (met 3 prov) max-id))
    [%| (cat 3 where 'provider: 1 to 64 bytes')]
  =/  up=@t  ?:(=('' (gs j 'upstream')) id (gs j 'upstream'))
  ?:  (gth (met 3 up) max-model-id)
    [%| (cat 3 where 'upstream: 1 to 200 bytes')]
  =/  row=model-row
    :*  id
        prov
        up
        (gn j 'in')
        (gn j 'out')
        (gn j 'cost_in')
        (gn j 'cost_out')
        (gb j 'enabled')
        (strings (ga j 'tags'))
    ==
  $(items t.items, i +(i), seen (~(put in seen) id), out [row out])
::  +en-model-row: one catalog row as the owner's page reads it
::
++  en-model-row
  |=  r=model-row
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.r]
      ['provider' s+provider.r]
      ['upstream' s+upstream.r]
      ['in' (en-num in.r)]
      ['out' (en-num out.r)]
      ['cost_in' (en-num cost-in.r)]
      ['cost_out' (en-num cost-out.r)]
      ['enabled' b+enabled.r]
      ['tags' a+(turn tags.r |=(t=@t ^-(json s+t)))]
  ==
++  en-catalog
  |=  cat=(list model-row)
  ^-  json
  [%a (turn cat en-model-row)]
::  +public-catalog: the enabled rows, prices and tags, no costs. This
::  is what every ship may read.
::
++  public-catalog
  |=  cat=(list model-row)
  ^-  json
  :-  %a
  %+  turn  (skim cat |=(r=model-row enabled.r))
  |=  r=model-row
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.r]
      ['provider' s+provider.r]
      ['in' (en-num in.r)]
      ['out' (en-num out.r)]
      ['tags' a+(turn tags.r |=(t=@t ^-(json s+t)))]
  ==
::  +en-models-list: the enabled rows in OpenAI's list shape, each with
::  OpenRouter's pricing strings, so one client reads both
::
++  en-models-list
  |=  cat=(list model-row)
  ^-  json
  =/  rows=(list model-row)  (skim cat |=(r=model-row enabled.r))
  %-  pairs:enjs:format
  :~  ['object' s+'list']
      :-  'data'
      :-  %a
      %+  turn  rows
      |=  r=model-row
      ^-  json
      %-  pairs:enjs:format
      :~  ['id' s+id.r]
          ['object' s+'model']
          ['owned_by' s+provider.r]
          :-  'pricing'
          %-  pairs:enjs:format
          :~  ['prompt' s+(dollars-per-token in.r)]
              ['completion' s+(dollars-per-token out.r)]
          ==
          ['tags' a+(turn tags.r |=(t=@t ^-(json s+t)))]
      ==
  ==
::  +find-model: the enabled row a customer's model id names, or ~
::
++  find-model
  |=  [cat=(list model-row) id=@t]
  ^-  (unit model-row)
  |-  ^-  (unit model-row)
  ?~  cat  ~
  ?:  &(=(id id.i.cat) enabled.i.cat)  `i.cat
  $(cat t.cat)
::  ==  import from a provider
::
::  +import-rows: a provider's GET /models body to catalog rows, every
::  one disabled. OpenRouter's pricing fills the costs and the marked
::  up prices; a provider without prices gives zeros for the owner to
::  type over.
::
++  import-rows
  |=  [provider=@t pct=@ud jon=json]
  ^-  (list model-row)
  %+  murn  (ga jon 'data')
  |=  j=json
  ^-  (unit model-row)
  ?.  ?=([%o *] j)  ~
  =/  id=@t  (gs j 'id')
  ?:  |(=('' id) (gth (met 3 id) max-model-id))  ~
  =/  pricing=json  (gj j 'pricing')
  =/  ci=(unit @ud)  (per-million (gs pricing 'prompt'))
  =/  co=(unit @ud)  (per-million (gs pricing 'completion'))
  ?:  |(?=(~ ci) ?=(~ co))
    `[id provider id 0 0 0 0 | ~]
  `[id provider id (markup-of u.ci pct) (markup-of u.co pct) u.ci u.co | ~]
::  +merge-import: fresh rows appended to the catalog, leaving every id
::  the owner already priced exactly as it is
::
++  merge-import
  |=  [cat=(list model-row) fresh=(list model-row)]
  ^-  (list model-row)
  =/  held=(set @t)  (sy (turn cat |=(r=model-row id.r)))
  (weld cat (skip fresh |=(r=model-row (~(has in held) id.r))))
::  ==  an upstream answer
::
::  +read-usage: the token counts an upstream reported, or ~ when it
::  reported none. completion_tokens is absent on an embedding.
::
++  read-usage
  |=  body=@t
  ^-  (unit [in=@ud out=@ud])
  =/  jon=json  (fall (de:json:html body) ~)
  =/  usage=json  (gj jon 'usage')
  ?.  ?=([%o *] usage)  ~
  ?.  (has-key usage 'prompt_tokens')  ~
  `[(gn usage 'prompt_tokens') (gn usage 'completion_tokens')]
::  +read-error: what an upstream said went wrong, or ''
::
++  read-error
  |=  body=@t
  ^-  @t
  =/  jon=json  (fall (de:json:html body) ~)
  =/  err=json  (gj jon 'error')
  =/  inner=@t  (gs err 'message')
  ?.  =('' inner)  inner
  (gs jon 'message')
::  +swap-model: the customer's body as it goes upstream: our catalog
::  id replaced by the provider's, and stream dropped, since iris
::  answers whole bodies. Everything else passes through untouched.
::
++  swap-model
  |=  [jon=json upstream=@t]
  ^-  json
  ?.  ?=([%o *] jon)  jon
  =/  m=(map @t json)  (~(del by p.jon) 'stream')
  [%o (~(put by m) 'model' s+upstream)]
::  +is-stream: did the customer ask for a stream
::
++  is-stream  |=(jon=json ^-(? (gb jon 'stream')))
::  ==  the ledger
::
+$  row
  $:  kind=?(%credit %debit %refund)
      amount=@ud
      cost=@ud
      model=@t
      in=@ud
      out=@ud
      mode=@t
      rail=@t
      ref=@t
      note=@t
      at=@da
  ==
::  what a ledger grub holds: a version head in front of the shape, so
::  a later shape is told apart by the reader instead of clamming by
::  luck
::
+$  stored-row  [%1 =row]
::  +read-row: a stored noun to a row, or ~
::
++  read-row
  |=  n=*
  ^-  (unit row)
  =/  r  (mule |.(;;(stored-row n)))
  ?:(?=(%& -.r) `row.p.r ~)
::  +en-row, +de-row: a ledger row as JSON
::
++  en-row
  |=  r=row
  ^-  json
  %-  pairs:enjs:format
  :~  ['kind' s+`@t`kind.r]
      ['amount' (en-num amount.r)]
      ['cost' (en-num cost.r)]
      ['model' s+model.r]
      ['in' (en-num in.r)]
      ['out' (en-num out.r)]
      ['mode' s+mode.r]
      ['rail' s+rail.r]
      ['ref' s+ref.r]
      ['note' s+note.r]
      ['at' (en-time at.r)]
  ==
++  de-row
  |=  jon=json
  ^-  (each row @t)
  ?.  ?=([%o *] jon)  [%| 'a JSON object is required']
  =/  kind=@t  (gs jon 'kind')
  ?.  ?|(=('credit' kind) =('debit' kind) =('refund' kind))
    [%| 'kind: credit, debit or refund']
  =/  akind=?(%credit %debit %refund)
    ?:(=('credit' kind) %credit ?:(=('debit' kind) %debit %refund))
  =/  at=(unit @da)  (gt jon 'at')
  ?~  at  [%| 'at: an ISO 8601 UTC time is required']
  :-  %&
  :*  akind
      (gn jon 'amount')
      (gn jon 'cost')
      (gs jon 'model')
      (gn jon 'in')
      (gn jon 'out')
      (gs jon 'mode')
      (gs jon 'rail')
      (gs jon 'ref')
      (gs jon 'note')
      u.at
  ==
::  +fold-balance: credits minus debits minus refunds. Signed, since a
::  request in flight may take the balance below zero.
::
++  fold-balance
  |=  rows=(list row)
  ^-  @sd
  =/  acc=@sd  --0
  |-  ^-  @sd
  ?~  rows  acc
  =/  amt=@sd  (sun:si amount.i.rows)
  =/  next=@sd  ?:(=(%credit kind.i.rows) (sum:si acc amt) (dif:si acc amt))
  $(rows t.rows, acc next)
::  +row-name: the grub name a ledger row lives under. The seconds sort
::  the directory; n is bumped by the writer while the name exists.
::
++  row-name
  |=  [at=@da n=@ud]
  ^-  @ta
  =/  secs=tape  (a-co:co (unix-secs at))
  =/  nth=tape   (a-co:co n)
  `@ta`(crip (weld secs (weld "-" nth)))
::  ==  accounts
::
::    The three Stripe fields are the account's half of a subscription:
::    the customer and the subscription ids Stripe gave us, and when the
::    period it is paid for runs out. A customer-facing view never shows
::    the ids; +en-subscription with with-id false is what it carries.
::
+$  account
  $:  ship=@p
      balance=@sd
      made=@da
      seen=(unit @da)
      closed=?
      plan=@t
      stripe-customer=@t
      stripe-subscription=@t
      renews=(unit @da)
  ==
++  en-account
  |=  a=account
  ^-  json
  %-  pairs:enjs:format
  :~  ['ship' s+(scot %p ship.a)]
      ['balance' (en-sd balance.a)]
      ['made' (en-time made.a)]
      ['seen' (en-maybe-time seen.a)]
      ['closed' b+closed.a]
      ['plan' s+plan.a]
      ['stripe_customer' s+stripe-customer.a]
      ['stripe_subscription' s+stripe-subscription.a]
      ['renews' (en-maybe-time renews.a)]
  ==
++  de-account
  |=  jon=json
  ^-  (unit account)
  ?.  ?=([%o *] jon)  ~
  =/  who=(unit @p)  (slaw %p (gs jon 'ship'))
  ?~  who  ~
  =/  made=(unit @da)  (gt jon 'made')
  ?~  made  ~
  :-  ~
  :*  u.who
      (gsd jon 'balance')
      u.made
      (gt jon 'seen')
      (gb jon 'closed')
      (gs jon 'plan')
      (gs jon 'stripe_customer')
      (gs jon 'stripe_subscription')
      (gt jon 'renews')
  ==
::  +en-subscription: an account's subscription as a read route answers
::  it. with-id is the owner's view; the customer's own view leaves the
::  Stripe ids out, since they are ours and not its business.
::
++  en-subscription
  |=  [sub=@t renews=(unit @da) with-id=?]
  ^-  json
  =/  rows=(list [@t json])
    :~  ['active' b+!=('' sub)]
        ['renews' (en-maybe-time renews)]
    ==
  (pairs:enjs:format ?.(with-id rows (snoc rows ['id' s+sub])))
::  +en-account-summary: one line of the accounts list
::
++  en-account-summary
  |=  [a=account keys=@ud]
  ^-  json
  %-  pairs:enjs:format
  :~  ['ship' s+(scot %p ship.a)]
      ['balance' (en-sd balance.a)]
      ['keys' (en-num keys)]
      ['made' (en-time made.a)]
      ['seen' (en-maybe-time seen.a)]
      ['closed' b+closed.a]
      ['plan' s+plan.a]
      ['subscription' (en-subscription stripe-subscription.a renews.a &)]
  ==
::  ==  settings
::
+$  settings
  $:  markup=@ud
      min-topup=@ud
      public-url=@t
      mode=?(%stub %live)
      refuse-comets=?
      stripe-key=@t
      stripe-webhook-secret=@t
      stripe-url=@t
  ==
::  +stripe-base: where Stripe's API lives. A blank stripe_url is the
::  real one; the gate points it at the stub instead.
::
++  stripe-base  'https://api.stripe.com'
::  +starter-settings: what a fresh install holds. Phase 4 adds the
::  BTCPay fields.
::
++  starter-settings
  ^-  json
  %-  pairs:enjs:format
  :~  ['markup_pct' (en-num 130)]
      ['min_topup' (en-num 5.000.000)]
      ['public_url' s+'']
      ['mode' s+'stub']
      ['refuse_comets' b+|]
      ['stripe_key' s+'']
      ['stripe_webhook_secret' s+'']
      ['stripe_url' s+stripe-base]
  ==
++  de-settings
  |=  jon=json
  ^-  (each settings @t)
  ?.  ?=([%o *] jon)  [%| 'a JSON object is required']
  =/  pct=@ud  (gn jon 'markup_pct')
  ?:  =(0 pct)  [%| 'markup_pct: a whole percent above zero']
  =/  mode=@t  (gs jon 'mode')
  ?.  |(=('stub' mode) =('live' mode))  [%| 'mode: stub or live']
  =/  url=@t  (gs jon 'public_url')
  ?:  (gth (met 3 url) max-url)  [%| 'public_url: at most 500 bytes']
  =/  sur=@t  (gs jon 'stripe_url')
  ?:  (gth (met 3 sur) max-url)  [%| 'stripe_url: at most 500 bytes']
  =/  amode=?(%stub %live)  ?:(=('live' mode) %live %stub)
  :-  %&
  :*  pct
      (gn jon 'min_topup')
      url
      amode
      (gb jon 'refuse_comets')
      (gs jon 'stripe_key')
      (gs jon 'stripe_webhook_secret')
      ?:(=('' sur) stripe-base sur)
  ==
++  en-settings
  |=  s=settings
  ^-  json
  %-  pairs:enjs:format
  :~  ['markup_pct' (en-num markup.s)]
      ['min_topup' (en-num min-topup.s)]
      ['public_url' s+public-url.s]
      ['mode' s+`@t`mode.s]
      ['refuse_comets' b+refuse-comets.s]
      ['stripe_key' s+stripe-key.s]
      ['stripe_webhook_secret' s+stripe-webhook-secret.s]
      ['stripe_url' s+stripe-url.s]
  ==
::  ==  plans
::
::  +$  plan: one thing a customer may buy. A topup plan credits its
::  credit once; a subscription credits it every time Stripe reports its
::  invoice paid. stripe-price is the Price id on Stripe, filled in by
::  the owner's Create on Stripe button or pasted; it is an identifier,
::  not a secret.
::
+$  plan
  $:  id=@t
      name=@t
      kind=?(%topup %subscription)
      price=@ud
      credit=@ud
      interval=@t
      stripe-price=@t
  ==
++  de-plan
  |=  jon=json
  ^-  (each plan @t)
  ?.  ?=([%o *] jon)  [%| 'a JSON object is required']
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
  =/  kind=@t  (gs jon 'kind')
  ?.  |(=('topup' kind) =('subscription' kind))
    [%| 'kind: topup or subscription']
  =/  price=@ud  (gn jon 'price')
  ?:  =(0 price)  [%| 'price: above zero']
  =/  credit=@ud  (gn jon 'credit')
  ?:  =(0 credit)  [%| 'credit: above zero']
  =/  interval=@t  (gs jon 'interval')
  =/  subs=?  =('subscription' kind)
  ?:  &(subs !|(=('month' interval) =('year' interval)))
    [%| 'interval: month or year']
  =/  name=@t  ?:(=('' (gs jon 'name')) id (gs jon 'name'))
  ?:  (gth (met 3 name) max-name)  [%| 'name: 1 to 200 bytes']
  =/  akind=?(%topup %subscription)  ?:(subs %subscription %topup)
  [%& [id name akind price credit ?:(subs interval '') (gs jon 'stripe_price')]]
++  en-plan
  |=  p=plan
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.p]
      ['name' s+name.p]
      ['kind' s+`@t`kind.p]
      ['price' (en-num price.p)]
      ['credit' (en-num credit.p)]
      ['interval' s+interval.p]
      ['stripe_price' s+stripe-price.p]
  ==
::  +de-plan-stored: a stored plan row back to its shape
::
++  de-plan-stored
  |=  jon=json
  ^-  (unit plan)
  =/  got  (de-plan jon)
  ?:(?=(%| -.got) ~ `p.got)
::  +en-plans-public: what a customer ship reads. Every field is here:
::  nothing on a plan is a secret, and the Price id is what a checkout
::  names out loud.
::
++  en-plans-public
  |=  plans=(list plan)
  ^-  json
  [%a (turn plans en-plan)]
::  +plans-sorted: the rows of plans.json by id, so a page and a gate
::  see the same order every time
::
++  plans-sorted
  |=  jon=json
  ^-  (list plan)
  =/  pm=(map @t json)  ?:(?=([%o *] jon) p.jon ~)
  %+  murn  (sort ~(tap by pm) |=([a=[k=@t *] b=[k=@t *]] (aor k.a k.b)))
  |=  [k=@t j=json]
  ^-  (unit plan)
  (de-plan-stored j)
::  +find-plan: the plan a customer named, or ~
::
++  find-plan
  |=  [plans=(list plan) id=@t]
  ^-  (unit plan)
  |-  ^-  (unit plan)
  ?~  plans  ~
  ?:  =(id id.i.plans)  `i.plans
  $(plans t.plans)
::  +plan-by-price: the plan a Stripe Price id names, or ~
::
++  plan-by-price
  |=  [plans=(list plan) price=@t]
  ^-  (unit plan)
  ?:  =('' price)  ~
  |-  ^-  (unit plan)
  ?~  plans  ~
  ?:  =(price stripe-price.i.plans)  `i.plans
  $(plans t.plans)
::  ==  the audit ring
::
::  +ring-push: newest first, trimmed to a cap
::
++  ring-push
  |=  [ring=json entry=json cap=@ud]
  ^-  json
  =/  cur=(list json)  ?:(?=([%a *] ring) p.ring ~)
  [%a (scag cap `(list json)`[entry cur])]
::  +trail-entry: one audit row. A secret never reaches here: the
::  writer passes the op, the ship and the amount and nothing else.
::
++  trail-entry
  |=  [op=@t ok=? why=@t ship=@t amount=@sd at=@da]
  ^-  json
  %-  pairs:enjs:format
  :~  ['op' s+op]
      ['ok' b+ok]
      ['why' s+why]
      ['ship' s+ship]
      ['amount' (en-sd amount)]
      ['at' (en-time at)]
  ==
::  ==  the writer's ops
::
::  +de-op: which op a poke carries
::
++  de-op  |=(jon=json ^-(@t (gs jon 'op')))
::  +ship-field: a ship named in an op, or the field that failed
::
++  ship-field
  |=  jon=json
  ^-  (each @p @t)
  =/  raw=@t  (gs jon 'ship')
  ?:  =('' raw)  [%| 'ship: not an @p']
  =/  who=(unit @p)  (slaw %p raw)
  ?~(who [%| 'ship: not an @p'] [%& u.who])
::  +de-op-provider: the set-provider payload
::
++  de-op-provider
  |=  jon=json
  ^-  (each provider @t)
  (de-provider (gj jon 'provider'))
::  +de-op-drop: the drop-provider payload, an id
::
++  de-op-drop
  |=  jon=json
  ^-  (each @t @t)
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
  [%& id]
::  +de-op-catalog: the set-catalog payload
::
++  de-op-catalog
  |=  jon=json
  ^-  (each (list model-row) @t)
  (de-catalog (gj jon 'catalog'))
::  +de-op-account: the open-account and close-account payload
::
++  de-op-account
  |=  jon=json
  ^-  (each @p @t)
  (ship-field jon)
::  +de-op-credit: a credit row. The amount must be above zero, and
::  rail and ref say where it came from, so a webhook delivered twice
::  credits once.
::
++  de-op-credit
  |=  jon=json
  ^-  (each [ship=@p amount=@ud rail=@t ref=@t note=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  amount=@ud  (gn jon 'amount')
  ?:  =(0 amount)  [%| 'amount: a whole number above zero']
  =/  rail=@t  (gs jon 'rail')
  ?:  =('' rail)  [%| 'rail: stripe, btcpay or owner']
  =/  ref=@t  (gs jon 'ref')
  ?:  |(=('' ref) (gth (met 3 ref) max-name))  [%| 'ref: 1 to 200 bytes']
  [%& [p.who amount rail ref (gs jon 'note')]]
::  +de-op-debit: a debit row. The proxy computed every number here
::  before it pokes, so the writer only stores them.
::
++  de-op-debit
  |=  jon=json
  ^-  (each [ship=@p amount=@ud cost=@ud model=@t in=@ud out=@ud mode=@t ref=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  model=@t  (gs jon 'model')
  ?:  |(=('' model) (gth (met 3 model) max-model-id))
    [%| 'model: 1 to 200 bytes']
  =/  mode=@t  (gs jon 'mode')
  ?.  |(=('proxy' mode) =('lease' mode))  [%| 'mode: proxy or lease']
  :-  %&
  :*  p.who
      (gn jon 'amount')
      (gn jon 'cost')
      model
      (gn jon 'in')
      (gn jon 'out')
      mode
      (gs jon 'ref')
  ==
::  +de-op-refund: a refund row
::
++  de-op-refund
  |=  jon=json
  ^-  (each [ship=@p amount=@ud ref=@t note=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  amount=@ud  (gn jon 'amount')
  ?:  =(0 amount)  [%| 'amount: a whole number above zero']
  =/  ref=@t  (gs jon 'ref')
  ?:  |(=('' ref) (gth (met 3 ref) max-name))  [%| 'ref: 1 to 200 bytes']
  [%& [p.who amount ref (gs jon 'note')]]
::  +de-op-key: the add-key payload, the row already hashed by the
::  request fiber that minted it
::
++  de-op-key
  |=  jon=json
  ^-  (each [ship=@p =key] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  k=(unit key)  (de-key (gj jon 'key'))
  ?~  k  [%| 'key: id, salt, hash and made are required']
  ?:  (gth (met 3 name.u.k) max-name)  [%| 'name: 1 to 200 bytes']
  [%& [p.who u.k]]
::  +de-op-drop-key, +de-op-touch-key: a key on an account by id
::
++  de-op-drop-key
  |=  jon=json
  ^-  (each [ship=@p id=@t] @t)
  (ship-and-id jon)
++  de-op-touch-key
  |=  jon=json
  ^-  (each [ship=@p id=@t] @t)
  (ship-and-id jon)
++  ship-and-id
  |=  jon=json
  ^-  (each [ship=@p id=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-name))  [%| 'id: 1 to 200 bytes']
  [%& [p.who id]]
::  +de-op-settings: the set-settings payload
::
++  de-op-settings
  |=  jon=json
  ^-  (each settings @t)
  (de-settings (gj jon 'settings'))
::  +de-op-plan, +de-op-drop-plan: one plan row, and a plan by id
::
++  de-op-plan
  |=  jon=json
  ^-  (each plan @t)
  (de-plan (gj jon 'plan'))
++  de-op-drop-plan
  |=  jon=json
  ^-  (each @t @t)
  (de-op-drop jon)
::  +de-op-subscription: what Stripe told us about a customer's
::  subscription. renews is absent until the first invoice says when the
::  period ends.
::
++  de-op-subscription
  |=  jon=json
  ^-  (each [ship=@p customer=@t subscription=@t plan=@t renews=(unit @da)] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  sub=@t  (gs jon 'subscription')
  ?:  |(=('' sub) (gth (met 3 sub) max-name))  [%| 'subscription: 1 to 200 bytes']
  =/  cus=@t  (gs jon 'customer')
  ?:  (gth (met 3 cus) max-name)  [%| 'customer: at most 200 bytes']
  =/  plan=@t  (gs jon 'plan')
  ?:  (gth (met 3 plan) max-id)  [%| 'plan: at most 64 bytes']
  [%& [p.who cus sub plan (gt jon 'renews')]]
::  +de-op-clear-subscription: the account keeps its ledger and loses
::  its subscription
::
++  de-op-clear-subscription
  |=  jon=json
  ^-  (each @p @t)
  (ship-field jon)
::  ==  the account channel over ames
::
::  +armillary-instance: where a desk install of this app sits on any
::  ship. One ship addresses another's inbox and account view through
::  this path, since a desk app cannot learn its own.
::
++  armillary-instance
  ^-  path
  /apps/'shell.shell'/desks/'armillary.desk'/desk/data/'armillary.armillary_app'
::  +group-name: the usergroup that lets one customer ship read its own
::  account view and nothing else. The ship's name without the sig, so
::  ~wex reads armillary-wex.
::
++  group-name
  |=  who=@p
  ^-  @t
  (rap 3 'armillary-' (rsh [3 1] (scot %p who)) ~)
::  +is-comet: a self-signed identity. On the groundwire network a comet
::  is paid for before ames will carry it, so the vendor takes them; a
::  vendor elsewhere turns refuse_comets on.
::
++  is-comet  |=(who=@p ^-(? ?=(%pawn (clan:title who))))
::  +$  inbox-op: everything a customer ship asks of its vendor. The
::  source ship of the poke is the account: no op names a ship.
::
+$  inbox-op
  $%  [%hello ~]
      [%refresh ~]
      [%checkout rail=@t plan=@t amount=@ud nonce=@t]
      [%mint-key name=@t nonce=@t]
      [%got-key id=@t]
      [%drop-key id=@t]
      [%lease ~]
      [%drop-lease ~]
      [%cancel-subscription ~]
  ==
::  +de-inbox: one op from a poke, or the field that failed. A stranger
::  sends this, so every branch is a clean refusal.
::
++  de-inbox
  |=  jon=json
  ^-  (each inbox-op @t)
  =/  op=@t  (gs jon 'op')
  ?:  =('hello' op)                (each-op [%hello ~])
  ?:  =('refresh' op)              (each-op [%refresh ~])
  ?:  =('lease' op)                (each-op [%lease ~])
  ?:  =('drop-lease' op)           (each-op [%drop-lease ~])
  ?:  =('cancel-subscription' op)  (each-op [%cancel-subscription ~])
  ?:  =('checkout' op)
    =/  rail=@t  (gs jon 'rail')
    ?.  |(=('stripe' rail) =('btcpay' rail))  [%| 'rail: stripe or btcpay']
    =/  nonce=@t  (gs jon 'nonce')
    ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
    =/  plan=@t  (gs jon 'plan')
    =/  amount=@ud  (gn jon 'amount')
    ?:  &(=('' plan) =(0 amount))  [%| 'plan or amount required']
    (each-op [%checkout rail plan amount nonce])
  ?:  =('mint-key' op)
    =/  name=@t  (gs jon 'name')
    ?:  |(=('' name) (gth (met 3 name) max-name))  [%| 'name: 1 to 200 bytes']
    =/  nonce=@t  (gs jon 'nonce')
    ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
    (each-op [%mint-key name nonce])
  ?:  =('got-key' op)
    =/  id=@t  (gs jon 'id')
    ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
    (each-op [%got-key id])
  ?:  =('drop-key' op)
    =/  id=@t  (gs jon 'id')
    ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
    (each-op [%drop-key id])
  [%| 'op: unknown']
::  +each-op: a taken op, cast once so every branch above reads alike
::
++  each-op  |=(o=inbox-op ^-((each inbox-op @t) [%& o]))
::  +en-inbox: the exact inverse of +de-inbox, so the customer side and
::  the vendor side never disagree about the wire
::
++  en-inbox
  |=  o=inbox-op
  ^-  json
  ?-    -.o
      %hello                 (pairs:enjs:format ~[['op' s+'hello']])
      %refresh               (pairs:enjs:format ~[['op' s+'refresh']])
      %lease                 (pairs:enjs:format ~[['op' s+'lease']])
      %drop-lease            (pairs:enjs:format ~[['op' s+'drop-lease']])
      %cancel-subscription   (pairs:enjs:format ~[['op' s+'cancel-subscription']])
      %checkout
    %-  pairs:enjs:format
    :~  ['op' s+'checkout']
        ['rail' s+rail.o]
        ['plan' s+plan.o]
        ['amount' (en-num amount.o)]
        ['nonce' s+nonce.o]
    ==
      %mint-key
    %-  pairs:enjs:format
    :~  ['op' s+'mint-key']
        ['name' s+name.o]
        ['nonce' s+nonce.o]
    ==
      %got-key   (pairs:enjs:format ~[['op' s+'got-key'] ['id' s+id.o]])
      %drop-key  (pairs:enjs:format ~[['op' s+'drop-key'] ['id' s+id.o]])
  ==
::  +$  view: the account as its own ship reads it. The vendor writes it
::  whole on every change and one usergroup lets that ship alone peek it.
::
::    keys_pending holds the secrets of keys minted and not yet fetched.
::    That is the one place a secret crosses the wire, and a got-key
::    clears it.
::
+$  view
  $:  ship=@p
      balance=@sd
      plan=@t
      subscription=json
      keys=(list json)
      keys-pending=(list [nonce=@t id=@t name=@t secret=@t])
      lease=json
      checkouts=json
      ledger=(list json)
      public-url=@t
      rev=@ud
      updated=@da
  ==
++  en-view
  |=  v=view
  ^-  json
  %-  pairs:enjs:format
  :~  ['ship' s+(scot %p ship.v)]
      ['balance' (en-sd balance.v)]
      ['plan' s+plan.v]
      ['subscription' subscription.v]
      ['keys' a+keys.v]
      :-  'keys_pending'
      :-  %a
      %+  turn  keys-pending.v
      |=  [nonce=@t id=@t name=@t secret=@t]
      ^-  json
      %-  pairs:enjs:format
      :~  ['nonce' s+nonce]
          ['id' s+id]
          ['name' s+name]
          ['secret' s+secret]
      ==
      ['lease' lease.v]
      ['checkouts' checkouts.v]
      ['ledger' a+ledger.v]
      ['public_url' s+public-url.v]
      ['rev' (en-num rev.v)]
      ['updated' (en-time updated.v)]
  ==
::  +de-view: a peeked view. A document without a ship or a rev is not a
::  view, so the customer side keeps whatever it held.
::
++  de-view
  |=  jon=json
  ^-  (unit view)
  ?.  ?=([%o *] jon)  ~
  =/  who=(unit @p)  (slaw %p (gs jon 'ship'))
  ?~  who  ~
  ?.  (has-key jon 'rev')  ~
  =/  pend=(list [nonce=@t id=@t name=@t secret=@t])
    %+  turn  (ga jon 'keys_pending')
    |=  j=json
    ^-  [@t @t @t @t]
    [(gs j 'nonce') (gs j 'id') (gs j 'name') (gs j 'secret')]
  :-  ~
  :*  u.who
      (gsd jon 'balance')
      (gs jon 'plan')
      (gj jon 'subscription')
      (ga jon 'keys')
      pend
      (gj jon 'lease')
      (gj jon 'checkouts')
      (ga jon 'ledger')
      (gs jon 'public_url')
      (gn jon 'rev')
      (fall (gt jon 'updated') *@da)
  ==
::  +view-nonces: every nonce the view accounts for, from keys_pending
::  and from checkouts. An op whose nonce is here landed on the vendor.
::
++  view-nonces
  |=  v=view
  ^-  (set @t)
  =/  out=(set @t)
    (~(gas in *(set @t)) (turn keys-pending.v |=([n=@t *] n)))
  ?.  ?=([%o *] checkouts.v)  out
  (~(gas in out) ~(tap in ~(key by p.checkouts.v)))
::  ==  the customer's own keys
::
::  +$  held-key: an inference key this ship fetched. The secret is here
::  because this ship is the customer: it is the bearer.
::
+$  held-key  [id=@t name=@t secret=@t made=@da]
++  en-held
  |=  k=held-key
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.k]
      ['name' s+name.k]
      ['secret' s+secret.k]
      ['made' (en-time made.k)]
  ==
++  de-held
  |=  jon=json
  ^-  (unit held-key)
  ?.  ?=([%o *] jon)  ~
  =/  id=@t  (gs jon 'id')
  =/  secret=@t  (gs jon 'secret')
  =/  made=(unit @da)  (gt jon 'made')
  ?:  |(=('' id) =('' secret) ?=(~ made))  ~
  `[id (gs jon 'name') secret u.made]
::  +en-held-public: the same key as a read route answers it, with no
::  secret, so only the mint ever shows one
::
++  en-held-public
  |=  k=held-key
  ^-  json
  %-  pairs:enjs:format
  :~  ['id' s+id.k]
      ['name' s+name.k]
      ['made' (en-time made.k)]
  ==
::  +inference-json: what a client needs to run, the whole of Talon's
::  integration
::
++  inference-json
  |=  [mode=@t base=@t key=@t models=(list @t)]
  ^-  json
  %-  pairs:enjs:format
  :~  ['mode' s+mode]
      ['base_url' s+base]
      ['key' s+key]
      ['models' a+(turn models |=(t=@t ^-(json s+t)))]
  ==
::  ==  the channel's writer ops, on the vendor
::
::  +de-op-view: the write-view payload
::
++  de-op-view
  |=  jon=json
  ^-  (each @p @t)
  (ship-field jon)
::  +de-op-pending: a minted key waiting to be fetched. This is the one
::  writer op that carries a secret, and it goes to pending.json alone.
::
++  de-op-pending
  |=  jon=json
  ^-  (each [ship=@p id=@t secret=@t nonce=@t name=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
  =/  secret=@t  (gs jon 'secret')
  ?:  =('' secret)  [%| 'secret: required']
  =/  nonce=@t  (gs jon 'nonce')
  ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
  =/  name=@t  (gs jon 'name')
  ?:  (gth (met 3 name) max-name)  [%| 'name: 1 to 200 bytes']
  [%& [p.who id secret nonce name]]
::  +de-op-drop-pending: the secret leaves the vendor once the customer
::  says it has it
::
++  de-op-drop-pending
  |=  jon=json
  ^-  (each [ship=@p id=@t] @t)
  (ship-and-id jon)
::  +de-op-checkout: one checkout row on an account, keyed by its nonce
::
++  de-op-checkout
  |=  jon=json
  ^-  (each [ship=@p nonce=@t rail=@t plan=@t amount=@ud url=@t expires=@da status=@t] @t)
  =/  who  (ship-field jon)
  ?:  ?=(%| -.who)  [%| p.who]
  =/  nonce=@t  (gs jon 'nonce')
  ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
  =/  status=@t  (gs jon 'status')
  ?:  =('' status)  [%| 'status: required']
  =/  url=@t  (gs jon 'url')
  ?:  (gth (met 3 url) max-url)  [%| 'url: at most 500 bytes']
  :-  %&
  :*  p.who
      nonce
      (gs jon 'rail')
      (gs jon 'plan')
      (gn jon 'amount')
      url
      (fall (gt jon 'expires') *@da)
      status
  ==
::  ==  the channel's writer ops, on the customer
::
::  +de-op-vendor: the vendor ship, or ~ to stop being anyone's customer
::
++  de-op-vendor
  |=  jon=json
  ^-  (each (unit @p) @t)
  =/  raw=@t  (gs jon 'ship')
  ?:  =('' raw)  [%& ~]
  =/  who=(unit @p)  (slaw %p raw)
  ?~(who [%| 'ship: not an @p'] [%& `u.who])
::  +de-op-store-key: an inference key fetched from the vendor's view
::
++  de-op-store-key
  |=  jon=json
  ^-  (each held-key @t)
  =/  k=(unit held-key)  (de-held (gj jon 'key'))
  ?~  k  [%| 'key: id, secret and made are required']
  ?:  (gth (met 3 name.u.k) max-name)  [%| 'name: 1 to 200 bytes']
  [%& u.k]
++  de-op-forget-key
  |=  jon=json
  ^-  (each @t @t)
  =/  id=@t  (gs jon 'id')
  ?:  |(=('' id) (gth (met 3 id) max-id))  [%| 'id: 1 to 64 bytes']
  [%& id]
::  +de-op-store-view: the peeked view, stored verbatim. The customer
::  keeps what the vendor said rather than a shape of its own.
::
++  de-op-store-view
  |=  jon=json
  ^-  (each json @t)
  =/  v=json  (gj jon 'view')
  ?.  ?=([%o *] v)  [%| 'view: a JSON object is required']
  [%& v]
::  +de-op-note-op: an op queued for the vendor, by nonce. The op itself
::  travels under payload, since op names the writer op.
::
++  de-op-note-op
  |=  jon=json
  ^-  (each [nonce=@t payload=json sent=?] @t)
  =/  nonce=@t  (gs jon 'nonce')
  ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
  =/  pay=json  (gj jon 'payload')
  ?.  ?=([%o *] pay)  [%| 'payload: a JSON object is required']
  [%& [nonce pay (gb jon 'sent')]]
++  de-op-drop-op
  |=  jon=json
  ^-  (each @t @t)
  =/  nonce=@t  (gs jon 'nonce')
  ?:  |(=('' nonce) (gth (met 3 nonce) max-id))  [%| 'nonce: 1 to 64 bytes']
  [%& nonce]
--
