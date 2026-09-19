::  armillary-http: the bytes a provider's HTTP API wants, pure.
::
::    Import-free like /lib/armillary.hoon, for the same reason: this
::    file builds in the clay desk's /lib, where -test reaches it, and
::    in the app's code namespace, where the nexus wraps it.
::
::    Percent encoding, form bodies, the two auth headers, HMAC-SHA256
::    and the Stripe signature header. Nothing here does IO and nothing
::    here holds a secret: a caller passes one in and gets bytes back.
::
|%
::  ==  urls and bodies
::
::  +url-encode: a string as a URL component. Everything but RFC 3986's
::  unreserved set becomes a percent escape with uppercase hex, which is
::  what Stripe's examples show.
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
::  +join-amp: the pieces of a form body, one ampersand between each
::
++  join-amp
  |=  parts=(list @t)
  ^-  @t
  ?~  parts  ''
  ?~  t.parts  i.parts
  (rap 3 i.parts '&' (join-amp t.parts) ~)
::  +form-cord: key=value pairs, both sides encoded, as one string
::
++  form-cord
  |=  kvs=(list [@t @t])
  ^-  @t
  %-  join-amp
  %+  turn  kvs
  |=  [k=@t v=@t]
  ^-  @t
  (rap 3 (url-encode k) '=' (url-encode v) ~)
::  +form-body: the same as the bytes of a request body
::
++  form-body
  |=  kvs=(list [@t @t])
  ^-  octs
  (as-octs:mimes:html (form-cord kvs))
::  ==  auth headers
::
++  bearer  |=(t=@t ^-(@t (rap 3 'Bearer ' t ~)))
::  +basic-auth: user and password as HTTP basic auth
::
++  basic-auth
  |=  [user=@t pass=@t]
  ^-  @t
  =/  raw=@t  (rap 3 user ':' pass ~)
  (rap 3 'Basic ' (en:base64:mimes:html (as-octs:mimes:html raw)) ~)
::  ==  hmac
::
::  +hmac-sha256: the keyed hash Stripe signs a webhook with. zuse's own
::  arm takes byts and answers the digest in standard byte order, so
::  +hex-of renders it the way Stripe writes it.
::
++  hmac-sha256
  |=  [key=@t msg=@t]
  ^-  @ux
  ::  sha-256l reads a byts with its first byte most significant, and a
  ::  cord holds its first byte least significant, so both sides are
  ::  swapped on the way in. The digest comes back in standard order.
  (hmac-sha256l:hmac:crypto [(met 3 key) (swp 3 key)] [(met 3 msg) (swp 3 msg)])
::  +hex-of: a digest as 64 lowercase hex digits. An atom drops its
::  leading zero bytes, so the padding is done here rather than by scot.
::
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
::  +same-hex: two hex strings, compared without an early exit. Every
::  byte is folded in, so the time the answer takes says nothing about
::  where the first difference was.
::
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
::  +chop: a tape split on a separator, the empty pieces kept
::
++  chop
  |=  [sep=@t t=tape]
  ^-  (list tape)
  =/  cur=tape  ~
  =/  out=(list tape)  ~
  |-  ^-  (list tape)
  ?~  t  (flop [(flop cur) out])
  ?:  =(sep i.t)  $(t t.t, cur ~, out [(flop cur) out])
  $(t t.t, cur [i.t cur])
::  +parse-stripe-sig: the stripe-signature header, "t=<unix>,v1=<hex>"
::  and sometimes a v0 as well. The first v1 is the one to check.
::
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
  ::  the first t and the first v1 win; a second of either is ignored,
  ::  and the narrowing stays out of the recursion
  =/  had-t=?  ?=(^ ts)
  ?:  &(=("t" k) !had-t)
    $(parts t.parts, ts (rush (crip v) dem))
  ?:  &(=("v1" k) =('' v1))
    $(parts t.parts, v1 (crip v))
  $(parts t.parts)
--
