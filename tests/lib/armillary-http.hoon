::  Unit tests for /lib/armillary-http: encoding, auth and the HMAC.
::
::    The HMAC case is RFC 4231's second vector, so the digest and its
::    byte order are checked against the standard rather than against
::    what this code happens to produce.
::
/+  *test, ah=armillary-http
|%
::  ==  urls and bodies
::
++  test-url-encode
  ;:  weld
    (expect-eq !>('a%20b') !>((url-encode:ah 'a b')))
    (expect-eq !>('%26') !>((url-encode:ah '&')))
    (expect-eq !>('%2F') !>((url-encode:ah '/')))
    (expect-eq !>('%C3%A9') !>((url-encode:ah 'é')))
    (expect-eq !>('~wex-1.2_3') !>((url-encode:ah '~wex-1.2_3')))
    (expect-eq !>('') !>((url-encode:ah '')))
  ==
++  test-form-body
  =/  want=octs  (as-octs:mimes:html 'a=1&b=x%20y')
  ;:  weld
    (expect-eq !>(want) !>((form-body:ah ~[['a' '1'] ['b' 'x y']])))
    (expect-eq !>('') !>((form-cord:ah ~)))
    (expect-eq !>('a=1') !>((form-cord:ah ~[['a' '1']])))
  ==
++  test-chop
  ;:  weld
    (expect-eq !>(`(list tape)`~["a" "b" "c"]) !>((chop:ah ',' "a,b,c")))
    (expect-eq !>(`(list tape)`~["a" ""]) !>((chop:ah ',' "a,")))
  ==
::  ==  auth headers
::
++  test-bearer
  (expect-eq !>('Bearer sk_test_1') !>((bearer:ah 'sk_test_1')))
++  test-basic-auth
  (expect-eq !>('Basic YTpi') !>((basic-auth:ah 'a' 'b')))
::  ==  hmac
::
::  RFC 4231 case 2: key "Jefe", data "what do ya want for nothing?"
::
++  test-hmac-sha256
  =/  want=@t  '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'
  =/  got=@ux  (hmac-sha256:ah 'Jefe' 'what do ya want for nothing?')
  (expect-eq !>(want) !>((hex-of:ah got)))
++  test-hex-of-pads
  =/  short=@t  (hex-of:ah 0x1)
  ;:  weld
    (expect-eq !>(`@ud`64) !>((met 3 short)))
    (expect-eq !>(`@t`'0000000000000000000000000000000000000000000000000000000000000001') !>(short))
  ==
++  test-same-hex
  ;:  weld
    (expect !>((same-hex:ah 'abcd' 'abcd')))
    (expect !>(!(same-hex:ah 'abcd' 'abce')))
    (expect !>(!(same-hex:ah 'abcd' 'abcde')))
    (expect !>(!(same-hex:ah 'abcd' '')))
  ==
::  ==  the stripe-signature header
::
++  test-parse-stripe-sig
  =/  head=@t
    %^  rap  3  't=1492774577,'
    :~  'v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd,'
        'v0=6ffbb59b2300aae63f272406069a9788598b792a944a07aba816edb039989a39'
    ==
  =/  want=(unit [t=@ud v1=@t])
    :-  ~
    :-  1.492.774.577
    '5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd'
  ;:  weld
    (expect-eq !>(want) !>((parse-stripe-sig:ah head)))
    (expect-eq !>(`(unit [t=@ud v1=@t])`~) !>((parse-stripe-sig:ah 'nonsense')))
    (expect-eq !>(`(unit [t=@ud v1=@t])`~) !>((parse-stripe-sig:ah 't=1')))
    (expect-eq !>(`(unit [t=@ud v1=@t])`~) !>((parse-stripe-sig:ah '')))
  ==
--
