::  armillary: sell model inference from your ship.
::  docs/superpowers/specs/2026-09-19-armillary-design.md
::
::  The tree this nexus owns (every persistent path has a row in +on-load):
::    /main.sig                          the writer: every mutation goes through it
::    /web.sig                           binds /apps/armillary; one fiber per request
::    /requests/<id>                     the ephemeral request fibers
::    /settings.json                     markup, minimum top-up, public url, mode
::    /providers.json                    the upstream connections, secrets inside
::    /catalog.json                      the models offered
::    /catalog-public.json               the enabled rows with prices
::    /plans.json                        the plans a customer may buy, by id
::    /vendor.json                       the vendor ship; ours on the vendor
::    /key-index.json                    a key id to the ship that holds it
::    /accounts/<ship>/account.json      ship, cached balance, made, seen, closed
::    /accounts/<ship>/keys.json         one salted hash per key, by id
::    /accounts/<ship>/ledger/<name>     [/armillary %row], one per money move
::    /beacon/rev                        the change beacon the page streams
::    /tr/last                           the last writer outcome, as json
::    /tr/log                            the audit ring, the last 500 ops
::    the page and the manifests         laid fresh on every load, not %fall
::
::  ROADS ARE NEXUS-RELATIVE. A desk-installed app cannot learn its own
::  absolute path, so every road is [%| up lane], where up is the number
::  of steps from the calling fiber to the nexus root: 0 for the writer
::  and the binder, 1 for a request fiber at /requests/<id>.
::
::  THE WRITER MUST NOT CRASH. +rise-wait restarts a failed process by
::  consuming the next poke without processing it, so every refusal is a
::  branch that returns cleanly and writes /tr/last.
::
::  SECRETS NEVER LEAVE. A provider key and a key's secret are stored
::  and sent upstream and nowhere else: no read route answers one, and
::  no audit row carries one.
::
/<  arm     /lib/armillary.hoon
/<  ahttp   /lib/armillary-http.hoon
/<  astripe  /lib/armillary-stripe.hoon
/&  icon  icon.svg
/&  page-html  armillary.html
/&  page-css   armillary.css
/&  page-js    armillary.js
=<  ^-  nexus:nexus
    |%
    ++  on-load
      |=  =ball:tarball
      ^-  bole:tarball
      =/  tile=json
        %-  pairs:enjs:format
        :~  title+s+'Armillary'
            info+s+'Sell model inference from your ship'
            color+s+'#1b2a4a'
            image+s+'/grubbery/tiles/icon/armillary'
            href+s+'/apps/armillary'
        ==
      =/  link=json
        %-  pairs:enjs:format
        :~  ['name' s+'armillary']
            ['description' s+'Sell model inference from your ship']
        ==
      %+  spin:loader  ball
      :~  (manifest:loader 0)
          [%over %& [/ %'tile.json'] [[/ %json] tile]]
          [%over %& [/ %'link.json'] [[/ %json] link]]
          [%over %& [/ %'weir.json'] [[/ %json] weir-json]]
          [%over %& [/ %'icon.svg'] [[/ %mime] icon]]
          [%over %& [/ %'armillary.html'] [[/ %mime] page-html]]
          [%over %& [/ %'armillary.css'] [[/ %mime] page-css]]
          [%over %& [/ %'armillary.js'] [[/ %mime] page-js]]
          [%fall %& [/ %'main.sig'] [[/ %sig] ~]]
          [%fall %& [/ %'web.sig'] [[/ %sig] ~]]
          [%fall %& [/ %'inbox.sig'] [[/ %sig] ~]]
          [%fall %& [/ %'client.sig'] [[/ %sig] ~]]
          [%fall %| /requests empty-dir:loader]
          [%fall %| /accounts empty-dir:loader]
          [%fall %| /tr empty-dir:loader]
          [%fall %| /beacon empty-dir:loader]
          [%fall %& [/ %'settings.json'] [[/ %json] starter-settings:arm]]
          [%fall %& [/ %'providers.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'catalog.json'] [[/ %json] [%a ~]]]
          [%fall %& [/ %'catalog-public.json'] [[/ %json] [%a ~]]]
          [%fall %& [/ %'plans.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'vendor.json'] [[/ %json] vendor-starter]]
          [%fall %& [/ %'key-index.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'keys.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'lease.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'view.json'] [[/ %json] [%o ~]]]
          [%fall %& [/ %'client.json'] [[/ %json] client-starter]]
          [%fall %& [/beacon %rev] [[/ %json] (numb:enjs:format 0)]]
          [%fall %& [/tr %last] [[/ %json] [%o ~]]]
          [%fall %& [/tr %log] [[/ %json] [%a ~]]]
          [%fall %& [/tr %inbox] [[/ %json] [%a ~]]]
      ==
    ::
    ++  on-file
      |=  [=rail:tarball =blot:tarball]
      ^-  spool:fiber:nexus
      |=  =prod:fiber:nexus
      =/  m  (fiber:fiber:nexus ,~)
      ^-  process:fiber:nexus
      ?+    rail  stay:m
          ::  the writer. It reaches nothing at rise: a jailed install
          ::  (weir not yet approved) would have every bowl poke vetoed,
          ::  and a crashed writer waits for the next poke before it
          ::  runs again.
          [~ %'main.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%armillary writer: failed")
        |-
        ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
        ;<  changed=?  bind:m  (apply from sage)
        ;<  ~  bind:m  ?.(changed (pure:m ~) bump-beacon)
        $
          ::  the HTTP binder. bind-http-self is veto-tolerant: jailed,
          ::  it logs and waits; the approval reload binds for real.
          [~ %'web.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%armillary web: failed")
        ;<  ~  bind:m  (bind-http-self:io [~ /apps/armillary])
        (http-dispatch:io %armillary)
          ::  the vendor's inbox: any ship may poke an account op here,
          ::  through the /public group's weir. The source ship of the
          ::  poke is the account; nothing in the payload names a ship.
          ::  A local poke is this ship acting as its own customer.
          [~ %'inbox.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%armillary inbox: failed")
        ::  the road a stranger pokes is laid from here: the registry
        ::  keys a grant to the poking fiber's own rail, so only a fiber
        ::  at the root can grant a road at the root
        ;<  ~  bind:m  lay-inbox-road
        |-
        ;<  [=from:fiber:nexus =sage:tarball]  bind:m  take-poke-from:io
        ;<  our=@p  bind:m  get-our:io
        ;<  ~  bind:m  (take-inbox (fall (get-poke-src:io from) our) sage)
        $
          ::  the customer's client: send what is queued, peek the view,
          ::  and do it again every five minutes or whenever prodded
          [~ %'client.sig']
        ;<  ~  bind:m  (rise-wait:io prod "%armillary client: failed")
        client-loop
          ::  one ephemeral fiber per in-flight request
          [[%requests ~] @]
        ;<  ~  bind:m  (rise-wait:io prod "%armillary request: failed")
        (handle-request name.rail)
      ==
    --
|%
::  ==  roads
::
++  rf  |=([up=@ud p=path n=@ta] ^-(road:tarball [%| up [%& p n]]))
++  rv  |=([up=@ud p=path] ^-(road:tarball [%| up [%| p]]))
++  acct-dir  |=(who=@p ^-(path /accounts/[(scot %p who)]))
++  ledger-dir  |=(who=@p ^-(path /accounts/[(scot %p who)]/ledger))
++  srv  ~(. http-res:io [%| 1 %& ~ %'web.sig'])
::  +vendor-starter: the vendor ship. Empty means this ship is nobody's
::  customer; PUT /api/vendor is the only thing that fills it.
::
++  vendor-starter  ^-(json (pairs:enjs:format ~[['ship' s+'']]))
::  +client-starter: the ops sent and not yet seen in the view, by nonce
::
++  client-starter  ^-(json (pairs:enjs:format ~[['ops' [%o ~]]]))
::  +ug-base: where this ship keeps its usergroups
::
++  ug-base     `path`/sys/ames/usergroups
::  +public-grp: the group every ship is in, whose weir carries the road
::  to our inbox
::
++  public-grp  `path`/sys/ames/usergroups/'public.grp'
::  +group-dir: one customer's group directory
::
++  group-dir
  |=  who=@p
  ^-  path
  (snoc ug-base (crip (weld (trip (group-name:arm who)) ".grp")))
::  ==  the ask
::
::  every why says what refusing it costs, so consent is informed
::
++  weir-json
  ^-  json
  =/  line  |=([r=@t w=@t] `json`(pairs:enjs:format ~[['road' s+r] ['why' s+w]]))
  %-  pairs:enjs:format
  :~  :-  'poke'
      :-  %a
      :~  (line '/sys/bowl.sig' 'read the current time and our ship')
          (line '/sys/eyre/' 'bind /apps/armillary and answer requests, including the inference API')
          (line '/sys/iris/' 'talk to your model providers over HTTPS. Refuse this and no request can be answered')
          (line '/sys/behn/' 'give up on a provider that does not answer within two minutes')
          (line '/sys/gall/' 'poke the vendor\'s inbox: open your account, mint keys, ask for a lease, buy credit. Refuse this and this ship cannot be a customer')
          (line '/sys/ames/registry' 'let customer ships poke this ship\'s inbox. Refuse this and this ship cannot be a vendor')
      ==
      :-  'peek'
      :-  %a
      :~  (line '/sys/link/' 'find where this app is installed, so the page can address its own writer')
          (line '/sys/ames/ships/' 'read your account on the vendor ship. Refuse this and this ship cannot be a customer')
          (line '/sys/ames/usergroups/' 'one group per customer, so each ship reads its own account and nothing else. Refuse this and this ship cannot be a vendor')
      ==
      :-  'make'
      :-  %a
      :~  (line '/sys/ames/usergroups/' 'one group per customer, so each ship reads its own account and nothing else. Refuse this and this ship cannot be a vendor')
      ==
  ==
::  ==  the writer
::
::  +apply: one op from a poke. Answers whether the tree changed.
::
++  apply
  |=  [=from:fiber:nexus =sage:tarball]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ?.  =([/ %json] p.sage)  (pure:m |)
  ;<  our=@p  bind:m  get-our:io
  ::  +get-poke-src reads the ship off the transport. ~ is a fiber
  ::  inside this nexus; our own ship arrives named through the
  ::  agent-facing surface. Anything else is refused.
  =/  src=(unit @p)  (get-poke-src:io from)
  ?.  ?|(?=(~ src) =(our u.src))
    (refuse 'poke' 'a foreign ship may not write here' '')
  =/  jon=json  (fall (mole |.(!<(json q.sage))) ~)
  =/  op=@t  (de-op:arm jon)
  ?:  =('set-settings' op)   (do-set-settings jon)
  ?:  =('set-provider' op)   (do-set-provider jon)
  ?:  =('drop-provider' op)  (do-drop-provider jon)
  ?:  =('set-catalog' op)    (do-set-catalog jon)
  ?:  =('set-plan' op)       (do-set-plan jon)
  ?:  =('drop-plan' op)      (do-drop-plan jon)
  ?:  =('set-subscription' op)    (do-set-subscription jon)
  ?:  =('clear-subscription' op)  (do-clear-subscription jon)
  ?:  =('open-account' op)   (do-open-account jon)
  ?:  =('credit' op)         (do-credit jon)
  ?:  =('debit' op)          (do-debit jon)
  ?:  =('refund' op)         (do-refund jon)
  ?:  =('add-key' op)        (do-add-key jon)
  ?:  =('drop-key' op)       (do-drop-key jon)
  ?:  =('touch-key' op)      (do-touch-key jon)
  ?:  =('close-account' op)  (do-close-account jon)
  ?:  =('drop-account' op)   (do-drop-account jon)
  ?:  =('rebuild' op)        do-rebuild
  ?:  =('write-view' op)     (do-op-write-view jon)
  ?:  =('set-pending' op)    (do-set-pending jon)
  ?:  =('drop-pending' op)   (do-drop-pending jon)
  ?:  =('set-checkout' op)   (do-set-checkout jon)
  ?:  =('set-vendor' op)     (do-set-vendor jon)
  ?:  =('store-key' op)      (do-store-key jon)
  ?:  =('forget-key' op)     (do-forget-key jon)
  ?:  =('store-view' op)     (do-store-view jon)
  ?:  =('note-op' op)        (do-note-op jon)
  ?:  =('drop-op' op)        (do-drop-op jon)
  (refuse op 'unknown op' '')
::  +refuse: a refusal that leaves the writer standing
::
++  refuse
  |=  [op=@t why=@t who=@t]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (note op | why who --0)
  (pure:m |)
::  +note-then-no: a no-op that still leaves its reason in /tr/last
::
++  note-then-no
  |=  [op=@t why=@t who=@t]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ~  bind:m  (note op & why who --0)
  (pure:m |)
::  +note: the last writer outcome at /tr/last, and the audit ring at
::  /tr/log (the last 500, newest first). The caller passes the op, the
::  ship and the amount: never a key, never a secret.
::
++  note
  |=  [op=@t ok=? why=@t who=@t amount=@sd]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  =/  entry=json  (trail-entry:arm op ok why who amount now)
  ;<  ~  bind:m  (over:io (rf 0 /tr %last) [[/ %json] entry])
  ;<  log=json  bind:m  (read-json (rf 0 /tr %log))
  (over:io (rf 0 /tr %log) [[/ %json] (ring-push:arm log entry ring-cap:arm)])
::  +note-inbox: an outcome of ship traffic, in its own ring of 500, so
::  a stranger's pokes never push the owner's audit log out of /tr/log.
::  A secret never reaches here: the mint notes the op and nothing else.
::
++  note-inbox
  |=  [op=@t ok=? why=@t by=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (note-inbox-at 0 op ok why by)
::  +note-inbox-at: the same ring from a fiber below the nexus root,
::  which a request fiber is
::
++  note-inbox-at
  |=  [up=@ud op=@t ok=? why=@t by=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  =/  entry=json  (trail-entry:arm op ok why by --0 now)
  ;<  log=json  bind:m  (read-json (rf up /tr %inbox))
  (over:io (rf up /tr %inbox) [[/ %json] (ring-push:arm log entry ring-cap:arm)])
::  +bump-beacon: the change beacon moves once per op that changed the
::  tree, never on a refusal or a no-op. Milliseconds since 1970, so a
::  browser keeps it exact.
::
++  bump-beacon
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  =/  ms=@ud  ?:((lth now ~1970.1.1) 0 (div (sub now ~1970.1.1) (div ~s1 1.000)))
  (over:io (rf 0 /beacon %rev) [[/ %json] (numb:enjs:format ms)])
::  +ensure-dirs: make each directory along base/segs, in order
::
++  ensure-dirs
  |=  [up=@ud base=path segs=(list @ta)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  segs  (pure:m ~)
  =/  dir=path  (weld base /[i.segs])
  ;<  ex=?  bind:m  (peek-exists:io (rv up dir))
  ;<  ~  bind:m
    ?:  ex  (pure:(fiber:fiber:nexus ,~) ~)
    ;<  *  bind:(fiber:fiber:nexus ,~)  (make-soft:io (rv up dir) &+empty-dir:loader)
    (pure:(fiber:fiber:nexus ,~) ~)
  (ensure-dirs up dir t.segs)
::  ==  ames: where we are, who may read what, and talking to a peer
::
::  +self-base: where this instance lives, from the shell's link registry
::  (/sys/link/armillary/dest.lanes: every instance claiming the name,
::  ours among them). ~ when the road is refused or the registry is
::  empty. A usergroup's own roads are absolute, so they need this;
::  everything else on this ship is nexus-relative.
::
++  self-base
  =/  m  (fiber:fiber:nexus ,(unit path))
  ^-  form:m
  ;<  vw=(unit view:nexus)  bind:m
    (peek-soft:io [%& %& /sys/link/armillary %'dest.lanes'] ~)
  ?.  ?=([~ %file *] vw)  (pure:m ~)
  =/  ls=(unit (set lane:tarball))
    (mole |.(!<((set lane:tarball) (need-vase:tarball sang.u.vw))))
  ?~  ls  (pure:m ~)
  =/  dirs=(list path)
    (murn ~(tap in u.ls) |=(=lane:tarball ?:(?=(%| -.lane) `p.lane ~)))
  ?~  dirs  (pure:m ~)
  ::  an arbitrary lane: a desk app cannot learn its own path, so two
  ::  instances claiming the name leave nothing here to tell them apart
  (pure:m `i.dirs)
::  +ug-read-weir: a usergroup's how, read whole
::
++  ug-read-weir
  |=  gdir=path
  =/  m  (fiber:fiber:nexus ,weir:nexus)
  ^-  form:m
  ;<  hv=(unit view:nexus)  bind:m  (peek-soft:io [%& %& gdir %'how.weir'] ~)
  ?~  hv  (pure:m *weir:nexus)
  ?.  ?=([%file *] u.hv)  (pure:m *weir:nexus)
  (pure:m (fall (mole |.(;;(weir:nexus (sang-noun:tarball sang.u.hv)))) *weir:nexus))
::  +ug-set: a usergroup's who and how, written whole: the ships in it
::  and the roads they reach through it
::
++  ug-set
  |=  [gname=@t ships=(set @p) pk=(set road:tarball) pok=(set road:tarball)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  gdir=path  (snoc ug-base (crip (weld (trip gname) ".grp")))
  ;<  old=weir:nexus  bind:m  (ug-read-weir gdir)
  =/  =weir:nexus  [make.old pok pk]
  ;<  ~  bind:m  (over:io [%& %& gdir %'who.ships'] [[/ %ships] ships])
  ;<  ~  bind:m  (over:io [%& %& gdir %'how.weir'] [[/ %weir] weir])
  (pure:m ~)
::  +ensure-group: the one customer ship may peek its own account view
::  and nothing else. One group per account, named for the ship.
::
++  ensure-group
  |=  who=@p
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  base=(unit path)  bind:m  self-base
  ?~  base  (pure:m ~)
  =/  road=road:tarball  [%& %& (weld u.base (acct-dir who)) %'view.json']
  (ug-set (group-name:arm who) (sy who ~) (sy road ~) ~)
::  +group-exists: has this account's group been laid yet
::
++  group-exists
  |=  who=@p
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  vw=(unit view:nexus)  bind:m
    (peek-soft:io [%& %& (group-dir who) %'who.ships'] ~)
  (pure:m ?=([~ %file *] vw))
::  +lay-inbox-road: any ship may poke our inbox, and any ship may read
::  the two public documents, both through the /public group's weir.
::  Quiet when the roads are refused: a ship that will not be a vendor
::  still works as a customer.
::
++  lay-inbox-road
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  base=(unit path)  bind:m  self-base
  ?~  base  (pure:m ~)
  ;<  old=weir:nexus  bind:m  (ug-read-weir public-grp)
  =/  road=road:tarball  [%& %& u.base %'inbox.sig']
  =/  cat=road:tarball   [%& %& u.base %'catalog-public.json']
  =/  plans=road:tarball  [%& %& u.base %'plans.json']
  ?:  ?&  (~(has in poke.old) road)
          (~(has in peek.old) cat)
          (~(has in peek.old) plans)
      ==
    (pure:m ~)
  ;<  reg=(unit tang)  bind:m  (reg-register-at-soft:io [u.base %'inbox.sig'])
  ?^  reg  (pure:m ~)
  ;<  err=(unit tang)  bind:m
    (reg-how-soft:io /public [~ (sy road ~) (sy cat plans ~)])
  (pure:m ~)
::  +remote-poke-wait: a poke to another ship's grubbery, answered or
::  timed out. A timer wake answers yes: grubbery's remote acks are
::  unobservable and a poke that timed out usually landed. A veto or a
::  nack answers no.
::
++  remote-poke-wait
  |=  [target=@p =lane:tarball jon=json]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  ;<  tw=wire  bind:m  (nonce:io /remote)
  =/  req=load:remo:nexus  [[/inbox-poke lane] %poke [[/ %json] jon]]
  ;<  w=wire  bind:m  (nonce:io /inbox-poke)
  ;<  ~  bind:m
    %-  send-dart:io
    [%node w &+&+[/sys/gall %'main.sig'] %poke [[/ %gall-poke] [[target %grubbery] grubbery-load+req]]]
  ;<  ~  bind:m  (set-timer:io tw (add now ~s30))
  ;<  ok=?  bind:m
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %veto %node * * *]
      ?.(=(w wire.dart.u.in) [%skip ~] [%done %.n])
        [~ %pack * *]
      ?.  =(w wire.u.in)  [%skip ~]
      ?~(err.u.in [%wait ~] [%done %.n])
        [~ %poke * *]
      ?:  =([/ %timer-wake] p.sage.u.in)
        ?.(=(tw !<(path q.sage.u.in)) [%skip ~] [%done %.y])
      ?.  =([/ %poke-ack] p.sage.u.in)  [%skip ~]
      =/  [aw=wire err=(unit tang)]  !<([wire (unit tang)] q.sage.u.in)
      ?.  =(w aw)  [%skip ~]
      [%done ?=(~ err)]
    ==
  ;<  ~  bind:m  (cancel-timer:io tw)
  (pure:m ok)
::  +peek-remote-wait: a deep peek of another ship's file, ~ on veto, a
::  miss or a timeout. A ship that is down must not park the fiber.
::
++  peek-remote-wait
  |=  [target=@p road=road:tarball]
  =/  m  (fiber:fiber:nexus ,(unit view:nexus))
  ^-  form:m
  ;<  now=@da  bind:m  get-time:io
  =/  until=@da  (add now ~s30)
  ;<  tw=wire  bind:m  (nonce:io /remote)
  ;<  pw=wire  bind:m  (nonce:io /peek)
  =/  rr=road:tarball
    ?-  -.road
      %|  road
      %&
        =/  prefix=path  /sys/ames/ships/[(scot %p target)]/root
        ?-  -.p.road
          %&  [%& %& (weld prefix path.p.p.road) name.p.p.road]
          %|  [%& %| (weld prefix p.p.road)]
        ==
    ==
  ;<  ~  bind:m  (send-dart:io %node pw rr %peek ~ ~ %.y)
  ;<  ~  bind:m  (set-timer:io tw until)
  ;<  got=(unit view:nexus)  bind:m
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %veto %node * * *]
      ?.(=(pw wire.dart.u.in) [%skip ~] [%done ~])
        [~ %peek * *]
      ?.(=(pw wire.u.in) [%skip ~] [%done `view.u.in])
        [~ %poke * *]
      ?.  =([/ %timer-wake] p.sage.u.in)  [%skip ~]
      ?.(=(tw !<(path q.sage.u.in)) [%skip ~] [%done ~])
    ==
  ;<  ~  bind:m  (cancel-timer:io tw)
  (pure:m got)
::  ==  the writer's ops
::
::  +do-set-settings: replace the document whole
::
++  do-set-settings
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-settings:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-settings' p.got '')
  ;<  cur=json  bind:m  (read-json (rf 0 / %'settings.json'))
  ::  the two Stripe secrets follow the provider rule: a blank field
  ::  keeps what is stored, an explicit null clears it. The page reads
  ::  them masked, so a save that sent the mask back would otherwise
  ::  store the mask.
  =/  doc=json  (en-settings:arm (kept-secrets p.got (gj:arm jon 'settings') cur))
  ?:  =(cur doc)  (note-then-no 'set-settings' 'unchanged' '')
  ;<  ~  bind:m  (over:io (rf 0 / %'settings.json') [[/ %json] doc])
  ;<  ~  bind:m  (note 'set-settings' & '' '' --0)
  (pure:m &)
::  +kept-secrets: a settings row with its two Stripe secrets resolved
::  against what is stored. Both the writer and the route that answers
::  the save use it, so the answer says what was kept.
::
++  kept-secrets
  |=  [s=settings:arm incoming=json stored=json]
  ^-  settings:arm
  =/  key=@t  (keep-secret incoming `stored 'stripe_key' stripe-key.s)
  =/  hook=@t
    (keep-secret incoming `stored 'stripe_webhook_secret' stripe-webhook-secret.s)
  s(stripe-key key, stripe-webhook-secret hook)
::  +keep-secret: a blank incoming secret keeps the stored one, an
::  explicit null clears it, anything else replaces it
::
++  keep-secret
  |=  [incoming=json old=(unit json) k=@t fresh=@t]
  ^-  @t
  =/  present=?  (has-key:arm incoming k)
  =/  v=json  (gj:arm incoming k)
  ?:  &(present ?=(~ v))  ''
  ?.  =('' fresh)  fresh
  ?~  old  ''
  (gs:arm u.old k)
::  +do-set-provider: one upstream connection, laid or replaced
::
++  do-set-provider
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-provider:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-provider' p.got '')
  =/  p=provider:arm  p.got
  ;<  provs=json  bind:m  (read-json (rf 0 / %'providers.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] provs) p.provs ~)
  =/  old=(unit json)  (~(get by pm) id.p)
  ?:  &(?=(~ old) (gte ~(wyt by pm) max-providers:arm))
    (refuse 'set-provider' 'providers: over 200' '')
  =/  incoming=json  (gj:arm jon 'provider')
  =/  api=@t   (keep-secret incoming old 'api_key' api-key.p)
  =/  prov=@t  (keep-secret incoming old 'provisioning_key' provisioning-key.p)
  =/  row=provider:arm  p(api-key api, provisioning-key prov)
  =/  next=json  [%o (~(put by pm) id.p (en-provider-full:arm row))]
  ;<  ~  bind:m  (over:io (rf 0 / %'providers.json') [[/ %json] next])
  ;<  ~  bind:m  (note 'set-provider' & id.p '' --0)
  (pure:m &)
::  +do-drop-provider: the connection goes. Catalog rows on it stay
::  where they are and stop answering, since a request checks that the
::  row's provider still exists.
::
++  do-drop-provider
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-drop:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-provider' p.got '')
  ;<  provs=json  bind:m  (read-json (rf 0 / %'providers.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] provs) p.provs ~)
  ?.  (~(has by pm) p.got)  (refuse 'drop-provider' 'no such provider' '')
  =/  next=json  [%o (~(del by pm) p.got)]
  ;<  ~  bind:m  (over:io (rf 0 / %'providers.json') [[/ %json] next])
  ;<  ~  bind:m  (note 'drop-provider' & p.got '' --0)
  (pure:m &)
::  +do-set-catalog: the catalog replaced whole, and the public copy
::  rewritten from it in the same op, so the two never disagree
::
++  do-set-catalog
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-catalog:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-catalog' p.got '')
  =/  cat=(list model-row:arm)  p.got
  ;<  ~  bind:m  (over:io (rf 0 / %'catalog.json') [[/ %json] (en-catalog:arm cat)])
  ;<  ~  bind:m
    (over:io (rf 0 / %'catalog-public.json') [[/ %json] (public-catalog:arm cat)])
  ;<  ~  bind:m  (note 'set-catalog' & '' '' --0)
  (pure:m &)
::  ==  plans
::
::  +plans-of: the rows of plans.json, by id. A document laid before
::  plans existed reads as no plans rather than crashing a request.
::
++  plans-of
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(list plan:arm))
  ^-  form:m
  ;<  jon=json  bind:m  (read-json (rf up / %'plans.json'))
  (pure:m (plans-sorted:arm jon))
::  +do-set-plan: one plan laid or replaced. The map is keyed by id, so
::  a repeat is an edit rather than a second row.
::
++  do-set-plan
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-plan:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-plan' p.got '')
  =/  p=plan:arm  p.got
  ;<  cur=json  bind:m  (read-json (rf 0 / %'plans.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] cur) p.cur ~)
  =/  next=json  [%o (~(put by pm) id.p (en-plan:arm p))]
  ?:  =(cur next)  (note-then-no 'set-plan' 'unchanged' '')
  ;<  ~  bind:m  (over:io (rf 0 / %'plans.json') [[/ %json] next])
  ;<  ~  bind:m  (note 'set-plan' & id.p '' --0)
  (pure:m &)
++  do-drop-plan
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-drop-plan:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-plan' p.got '')
  ;<  cur=json  bind:m  (read-json (rf 0 / %'plans.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] cur) p.cur ~)
  ?.  (~(has by pm) p.got)  (refuse 'drop-plan' 'no such plan' '')
  ;<  ~  bind:m  (over:io (rf 0 / %'plans.json') [[/ %json] [%o (~(del by pm) p.got)]])
  ;<  ~  bind:m  (note 'drop-plan' & p.got '' --0)
  (pure:m &)
::  ==  a customer's subscription
::
::  +do-set-subscription: the Stripe ids and the plan a paid session or
::  a paid invoice reported. The ids live on the account row and are
::  never written into the customer's own view.
::
++  do-set-subscription
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-subscription:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-subscription' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir ship.c) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (refuse 'set-subscription' 'ship: no such account' who)
  ::  a blank customer or plan keeps what is there: an invoice says the
  ::  customer and the period, a session says the plan
  =/  cus=@t  ?:(=('' customer.c) stripe-customer.u.a customer.c)
  =/  plan=@t  ?:(=('' plan.c) plan.u.a plan.c)
  =/  renews=(unit @da)  ?~(renews.c renews.u.a renews.c)
  =/  row=account:arm
    u.a(plan plan, stripe-customer cus, stripe-subscription subscription.c, renews renews)
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir ship.c) %'account.json') [[/ %json] (en-account:arm row)])
  ;<  ~  bind:m  (do-write-view ship.c)
  ;<  ~  bind:m  (note 'set-subscription' & plan who --0)
  (pure:m &)
::  +do-clear-subscription: Stripe says the subscription is gone, or the
::  owner says so. The ledger and the balance are untouched.
::
++  do-clear-subscription
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-clear-subscription:arm jon)
  ?:  ?=(%| -.got)  (refuse 'clear-subscription' p.got '')
  =/  who=@p  p.got
  =/  txt=@t  (scot %p who)
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (refuse 'clear-subscription' 'ship: no such account' txt)
  ?:  =('' stripe-subscription.u.a)
    (note-then-no 'clear-subscription' 'no subscription' txt)
  =/  row=account:arm  u.a(plan '', stripe-subscription '', renews ~)
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir who) %'account.json') [[/ %json] (en-account:arm row)])
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m  (note 'clear-subscription' & '' txt --0)
  (pure:m &)
::  +do-open-account: a fresh account at zero, or a no-op when it is
::  already open
::
++  do-open-account
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-account:arm jon)
  ?:  ?=(%| -.got)  (refuse 'open-account' p.got '')
  =/  who=@p  p.got
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir who) %'account.json'))
  =/  held=(unit account:arm)  (de-account:arm aj)
  ::  a closed account is not reopened by a poke from the ship it
  ::  belongs to; the owner alone can undo a close
  ?:  ?&(?=(^ held) closed.u.held)
    (refuse 'open-account' 'account closed' (scot %p who))
  ;<  made=?  bind:m  (ensure-account who)
  ;<  ~  bind:m  (ensure-group who)
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m
    (note 'open-account' & ?:(made '' 'already open') (scot %p who) --0)
  (pure:m &)
::  +ensure-account: the account directory, its row and its key table.
::  Answers whether it had to make them.
::
++  ensure-account
  |=  who=@p
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  ex=?  bind:m  (peek-exists:io (rf 0 (acct-dir who) %'account.json'))
  ?:  ex  (pure:m |)
  ;<  ~  bind:m  (ensure-dirs 0 / ~[%accounts (scot %p who) %ledger])
  ;<  now=@da  bind:m  get-time:io
  =/  row=account:arm  [who --0 now ~ | '' '' '' ~]
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir who) %'account.json') [[/ %json] (en-account:arm row)])
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'keys.json') [[/ %json] [%o ~]])
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'pending.json') [[/ %json] [%o ~]])
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'checkouts.json') [[/ %json] [%o ~]])
  (pure:m &)
::  +live-account: the account row when it is open and not closed
::
++  live-account
  |=  who=@p
  =/  m  (fiber:fiber:nexus ,(unit account:arm))
  ^-  form:m
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (pure:m ~)
  ?:  closed.u.a  (pure:m ~)
  (pure:m a)
::  +rows-in: the ledger grubs in a ball, each with its grub name
::
++  rows-in
  |=  b=ball:tarball
  ^-  (list [name=@ta =row:arm])
  ?~  fil.b  ~
  %+  murn  ~(tap by contents.u.fil.b)
  |=  [nam=@ta c=[=sang:tarball gain=? bang=(unit tang)]]
  ^-  (unit [@ta row:arm])
  =/  r=(unit row:arm)  (read-row:arm (sang-noun:tarball sang.c))
  ?~(r ~ `[nam u.r])
::  +ledger-of: every row on an account, in no order
::
++  ledger-of
  |=  [up=@ud who=@p]
  =/  m  (fiber:fiber:nexus ,(list [name=@ta =row:arm]))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv up (ledger-dir who)) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (rows-in ball.vw))
::  +has-ref: a credit or a refund with this ref is already recorded,
::  so a webhook delivered twice credits once
::
++  has-ref
  |=  [rows=(list [name=@ta =row:arm]) ref=@t]
  ^-  ?
  |-  ^-  ?
  ?~  rows  |
  ?:  =(ref ref.row.i.rows)  &
  $(rows t.rows)
::  +free-name: the grub name for a new row, n bumped while the name is
::  taken, so two rows in the same second never collide
::
++  free-name
  |=  [rows=(list [name=@ta =row:arm]) at=@da n=@ud]
  ^-  @ta
  =/  taken=(set @ta)  (sy (turn rows |=([nam=@ta =row:arm] nam)))
  |-  ^-  @ta
  =/  nam=@ta  (row-name:arm at n)
  ?.  (~(has in taken) nam)  nam
  $(n +(n))
::  +write-row: one ledger grub and the account's cached balance, which
::  is always the fold over every row
::
++  write-row
  |=  [who=@p rows=(list [name=@ta =row:arm]) a=account:arm new=row:arm]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  nam=@ta  (free-name rows at.new 0)
  ;<  ~  bind:m
    (over:io (rf 0 (ledger-dir who) nam) [[/armillary %row] `stored-row:arm`[%1 new]])
  =/  all=(list row:arm)  (snoc (turn rows |=([nam=@ta r=row:arm] r)) new)
  =/  bal=@sd  (fold-balance:arm all)
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir who) %'account.json') [[/ %json] (en-account:arm a(balance bal))])
  (pure:m ~)
::  +do-credit: money in. A repeated ref is refused, not written twice.
::
++  do-credit
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-credit:arm jon)
  ?:  ?=(%| -.got)  (refuse 'credit' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  a=(unit account:arm)  bind:m  (live-account ship.c)
  ?~  a  (refuse 'credit' 'ship: no open account' who)
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 0 ship.c)
  ?:  (has-ref rows ref.c)  (refuse 'credit' 'ref: already recorded' who)
  ;<  now=@da  bind:m  get-time:io
  =/  new=row:arm  [%credit amount.c 0 '' 0 0 '' rail.c ref.c note.c now]
  ;<  ~  bind:m  (write-row ship.c rows u.a new)
  ;<  ~  bind:m  (do-write-view ship.c)
  ;<  ~  bind:m  (note 'credit' & '' who (sun:si amount.c))
  (pure:m &)
::  +do-refund: money back out. A repeated ref is refused the same way.
::
++  do-refund
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-refund:arm jon)
  ?:  ?=(%| -.got)  (refuse 'refund' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  a=(unit account:arm)  bind:m  (live-account ship.c)
  ?~  a  (refuse 'refund' 'ship: no open account' who)
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 0 ship.c)
  ?:  (has-ref rows ref.c)  (refuse 'refund' 'ref: already recorded' who)
  ;<  now=@da  bind:m  get-time:io
  =/  new=row:arm  [%refund amount.c 0 '' 0 0 '' '' ref.c note.c now]
  ;<  ~  bind:m  (write-row ship.c rows u.a new)
  ;<  ~  bind:m  (do-write-view ship.c)
  ;<  ~  bind:m  (note 'refund' & '' who (new:si | amount.c))
  (pure:m &)
::  +do-debit: what a request cost. Never deduplicated: two identical
::  requests are two charges.
::
++  do-debit
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-debit:arm jon)
  ?:  ?=(%| -.got)  (refuse 'debit' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  a=(unit account:arm)  bind:m  (live-account ship.c)
  ?~  a  (refuse 'debit' 'ship: no open account' who)
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 0 ship.c)
  ;<  now=@da  bind:m  get-time:io
  =/  new=row:arm
    [%debit amount.c cost.c model.c in.c out.c mode.c '' ref.c '' now]
  ;<  ~  bind:m  (write-row ship.c rows u.a new)
  ;<  ~  bind:m  (do-write-view ship.c)
  ;<  ~  bind:m  (note 'debit' & model.c who (new:si | amount.c))
  (pure:m &)
::  +do-add-key: one minted key. The row arrives hashed; the writer
::  never sees a secret. The index keeps the id to ship map a bearer
::  lookup needs.
::
++  do-add-key
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-key:arm jon)
  ?:  ?=(%| -.got)  (refuse 'add-key' p.got '')
  =/  who=@p  ship.p.got
  =/  k=key:arm  key.p.got
  ;<  a=(unit account:arm)  bind:m  (live-account who)
  ?~  a  (refuse 'add-key' 'ship: no open account' (scot %p who))
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?:  (~(has by km) id.k)  (refuse 'add-key' 'id: taken' (scot %p who))
  ?:  (gte ~(wyt by km) max-keys:arm)
    (refuse 'add-key' 'keys: over 20' (scot %p who))
  =/  next=json  [%o (~(put by km) id.k (en-key-row:arm k))]
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'keys.json') [[/ %json] next])
  ;<  ~  bind:m  (index-put id.k who)
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m  (note 'add-key' & '' (scot %p who) --0)
  (pure:m &)
::  +index-put, +index-del: /key-index.json, a key id to the ship that
::  holds it, so a bearer token finds its account in one read instead
::  of a walk over every account
::
++  index-put
  |=  [id=@t who=@p]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ix=json  bind:m  (read-json (rf 0 / %'key-index.json'))
  =/  im=(map @t json)  ?:(?=([%o *] ix) p.ix ~)
  (over:io (rf 0 / %'key-index.json') [[/ %json] [%o (~(put by im) id s+(scot %p who))]])
++  index-del
  |=  id=@t
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ix=json  bind:m  (read-json (rf 0 / %'key-index.json'))
  =/  im=(map @t json)  ?:(?=([%o *] ix) p.ix ~)
  (over:io (rf 0 / %'key-index.json') [[/ %json] [%o (~(del by im) id)]])
::  +do-drop-key: a revoked key is gone from the table and the index
::
++  do-drop-key
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-drop-key:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-key' p.got '')
  =/  who=@p  ship.p.got
  =/  id=@t  id.p.got
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?.  (~(has by km) id)  (refuse 'drop-key' 'no such key' (scot %p who))
  =/  next=json  [%o (~(del by km) id)]
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'keys.json') [[/ %json] next])
  ;<  ~  bind:m  (index-del id)
  ::  a key revoked before its ship fetched it leaves no secret behind
  ;<  pend=json  bind:m  (read-json (rf 0 (acct-dir who) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  ;<  ~  bind:m
    ?.  (~(has by pm) id)  (pure:(fiber:fiber:nexus ,~) ~)
    %+  over:io  (rf 0 (acct-dir who) %'pending.json')
    [[/ %json] [%o (~(del by pm) id)]]
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m  (note 'drop-key' & '' (scot %p who) --0)
  (pure:m &)
::  +do-touch-key: last use, stamped by the writer's clock. No note:
::  one an hour per key would only fill the ring.
::
++  do-touch-key
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-touch-key:arm jon)
  ?:  ?=(%| -.got)  (pure:m |)
  =/  who=@p  ship.p.got
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  =/  row=json  (fall (~(get by km) id.p.got) ~)
  ?.  ?=([%o *] row)  (pure:m |)
  ;<  now=@da  bind:m  get-time:io
  =/  next=json  [%o (~(put by p.row) 'used' (en-time:arm now))]
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir who) %'keys.json') [[/ %json] [%o (~(put by km) id.p.got next)]])
  (pure:m |)
::  +do-close-account: every key revoked, the ledger kept. The account
::  stays readable; nothing more can be spent on it.
::
++  do-close-account
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-account:arm jon)
  ?:  ?=(%| -.got)  (refuse 'close-account' p.got '')
  =/  who=@p  p.got
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (refuse 'close-account' 'ship: no such account' (scot %p who))
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ;<  ~  bind:m  (index-drop-each ~(tap in ~(key by km)))
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'keys.json') [[/ %json] [%o ~]])
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir who) %'account.json') [[/ %json] (en-account:arm u.a(closed &))])
  ::  a closed account keeps no unfetched secrets
  ;<  ~  bind:m  (over:io (rf 0 (acct-dir who) %'pending.json') [[/ %json] [%o ~]])
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m  (note 'close-account' & '' (scot %p who) --0)
  (pure:m &)
++  index-drop-each
  |=  ids=(list @t)
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ids  (pure:m ~)
  ;<  ~  bind:m  (index-del i.ids)
  (index-drop-each t.ids)
::  +do-drop-account: the whole account directory, ledger and all. The
::  gate uses it to leave the ship as it found it; nothing else does.
::
++  do-drop-account
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-account:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-account' p.got '')
  =/  who=@p  p.got
  ;<  ex=?  bind:m  (peek-exists:io (rv 0 (acct-dir who)))
  ?.  ex  (refuse 'drop-account' 'ship: no such account' (scot %p who))
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ;<  ~  bind:m  (index-drop-each ~(tap in ~(key by km)))
  ;<  *  bind:m  (cull-soft:io (rv 0 (acct-dir who)))
  ::  the group goes with the account: an empty ship set leaves nothing
  ::  for the ship to peek, and the view it pointed at is gone anyway
  ;<  ~  bind:m  (ug-set (group-name:arm who) ~ ~ ~)
  ;<  ~  bind:m  (note 'drop-account' & '' (scot %p who) --0)
  (pure:m &)
::  +do-rebuild: refold every account's cached balance from its ledger,
::  so a balance that drifted is repaired from the rows that are the
::  truth
::
++  do-rebuild
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv 0 /accounts) ~)
  ?.  ?=([%ball *] vw)  (note-then-no 'rebuild' 'no accounts' '')
  =/  ships=(list @ta)  ~(tap in ~(key by dir.ball.vw))
  ;<  ~  bind:m  (rebuild-each ships)
  ;<  ~  bind:m  (note 'rebuild' & '' '' --0)
  (pure:m &)
++  rebuild-each
  |=  ships=(list @ta)
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ships  (pure:m ~)
  =/  who=(unit @p)  (slaw %p i.ships)
  ?~  who  (rebuild-each t.ships)
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir u.who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (rebuild-each t.ships)
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 0 u.who)
  =/  bal=@sd  (fold-balance:arm (turn rows |=([nam=@ta r=row:arm] r)))
  ;<  ~  bind:m
    (over:io (rf 0 (acct-dir u.who) %'account.json') [[/ %json] (en-account:arm u.a(balance bal))])
  (rebuild-each t.ships)
::  ==  the account view, on the vendor
::
::  +public-url-of: where a customer reaches this vendor over HTTP. An
::  unset public url means the dev ship, which is where the gate runs.
::
++  public-url-of
  |=  sj=json
  ^-  @t
  =/  u=@t  (gs:arm sj 'public_url')
  ?:(=('' u) 'http://localhost:8080' u)
::  +newest-first: ledger rows by time, newest first, the grub name
::  breaking a tie so two rows in one second keep a stable order
::
++  newest-first
  |=  rows=(list [name=@ta =row:arm])
  ^-  (list row:arm)
  %+  turn
    %+  sort  rows
    |=  [x=[name=@ta =row:arm] y=[name=@ta =row:arm]]
    ^-  ?
    ?:  =(at.row.x at.row.y)  (aor name.y name.x)
    (gth at.row.x at.row.y)
  |=([nam=@ta r=row:arm] r)
::  +do-op-write-view: the write-view op, which is a refresh and nothing
::  else
::
++  do-op-write-view
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-view:arm jon)
  ?:  ?=(%| -.got)  (refuse 'write-view' p.got '')
  ;<  ~  bind:m  (do-write-view p.got)
  (pure:m &)
::  +do-write-view: the account as its own ship reads it, written whole.
::  Every writer op that touches an account ends here, so the view is
::  never stale and the customer never has to ask twice.
::
::    The one secret that crosses the wire is in keys_pending, and it is
::    there because the ship it belongs to is the only ship that may
::    peek this file.
::
++  do-write-view
  |=  who=@p
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  aj=json  bind:m  (read-json (rf 0 (acct-dir who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (pure:m ~)
  ::  a group refused or lost at rise is laid again here, so a view is
  ::  never written that nobody may read
  ;<  gex=?  bind:m  (group-exists who)
  ;<  ~  bind:m  ?:(gex (pure:(fiber:fiber:nexus ,~) ~) (ensure-group who))
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  =/  key-rows=(list json)
    %+  murn  ~(tap by km)
    |=  [id=@t j=json]
    ^-  (unit json)
    =/  k=(unit key:arm)  (de-key:arm j)
    ?~(k ~ `(en-key-public:arm u.k))
  ;<  pend=json  bind:m  (read-json (rf 0 (acct-dir who) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  =/  pend-rows=(list [nonce=@t id=@t name=@t secret=@t])
    %+  turn  ~(tap by pm)
    |=  [id=@t j=json]
    ^-  [@t @t @t @t]
    [(gs:arm j 'nonce') id (gs:arm j 'name') (gs:arm j 'secret')]
  ;<  cj=json  bind:m  (read-json (rf 0 (acct-dir who) %'checkouts.json'))
  ;<  lj=json  bind:m  (read-json (rf 0 (acct-dir who) %'lease.json'))
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 0 who)
  =/  newest=(list json)  (turn (scag 50 (newest-first rows)) en-row:arm)
  ;<  old=json  bind:m  (read-json (rf 0 (acct-dir who) %'view.json'))
  ;<  sj=json  bind:m  (read-json (rf 0 / %'settings.json'))
  ;<  now=@da  bind:m  get-time:io
  =/  lease=json  ?:(=([%o ~] lj) ~ lj)
  ::  the customer's own view says whether it has a subscription and
  ::  when it renews, and never the Stripe ids: those are the vendor's
  =/  subs=json
    (en-subscription:arm stripe-subscription.u.a renews.u.a |)
  =/  v=view:arm
    :*  who
        balance.u.a
        plan.u.a
        subs
        key-rows
        pend-rows
        lease
        cj
        newest
        (public-url-of sj)
        +((gn:arm old 'rev'))
        now
    ==
  (over:io (rf 0 (acct-dir who) %'view.json') [[/ %json] (en-view:arm v)])
::  +do-set-pending: a minted key waiting for its ship to fetch it. The
::  secret lives in pending.json and in the view, and nowhere else.
::
++  do-set-pending
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-pending:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-pending' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  keys=json  bind:m  (read-json (rf 0 (acct-dir ship.c) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ::  add-key lands first. If the writer refused it, over twenty or on a
  ::  closed account, the secret must not be left waiting for nobody.
  ?.  (~(has by km) id.c)  (refuse 'set-pending' 'id: no such key' who)
  ;<  pend=json  bind:m  (read-json (rf 0 (acct-dir ship.c) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  ;<  now=@da  bind:m  get-time:io
  =/  row=json
    %-  pairs:enjs:format
    :~  ['nonce' s+nonce.c]
        ['name' s+name.c]
        ['secret' s+secret.c]
        ['made' (en-time:arm now)]
    ==
  ;<  ~  bind:m
    %+  over:io  (rf 0 (acct-dir ship.c) %'pending.json')
    [[/ %json] [%o (~(put by pm) id.c row)]]
  ;<  ~  bind:m  (do-write-view ship.c)
  ::  the audit row names the op and the ship, never the secret
  ;<  ~  bind:m  (note 'set-pending' & '' who --0)
  (pure:m &)
::  +do-drop-pending: the customer says it has the key, so the secret
::  leaves the vendor
::
++  do-drop-pending
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-drop-pending:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-pending' p.got '')
  =/  who=@p  ship.p.got
  =/  txt=@t  (scot %p who)
  ;<  pend=json  bind:m  (read-json (rf 0 (acct-dir who) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  ?.  (~(has by pm) id.p.got)  (note-then-no 'drop-pending' 'nothing pending' txt)
  ;<  ~  bind:m
    %+  over:io  (rf 0 (acct-dir who) %'pending.json')
    [[/ %json] [%o (~(del by pm) id.p.got)]]
  ;<  ~  bind:m  (do-write-view who)
  ;<  ~  bind:m  (note 'drop-pending' & '' txt --0)
  (pure:m &)
::  +do-set-checkout: one checkout row on an account, keyed by the nonce
::  the customer chose, so the same nonce answers the same row
::
++  do-set-checkout
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-checkout:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-checkout' p.got '')
  =/  c  p.got
  =/  who=@t  (scot %p ship.c)
  ;<  a=(unit account:arm)  bind:m  (live-account ship.c)
  ?~  a  (refuse 'set-checkout' 'ship: no open account' who)
  ;<  cj=json  bind:m  (read-json (rf 0 (acct-dir ship.c) %'checkouts.json'))
  =/  cm=(map @t json)  ?:(?=([%o *] cj) p.cj ~)
  =/  old=json  (fall (~(get by cm) nonce.c) ~)
  =/  row=json
    %-  pairs:enjs:format
    :~  ['nonce' s+nonce.c]
        ['rail' s+rail.c]
        ['plan' s+plan.c]
        ['amount' (en-num:arm amount.c)]
        ['url' s+url.c]
        ['expires' (en-time:arm expires.c)]
        ['status' s+status.c]
    ==
  ?:  =(old row)  (note-then-no 'set-checkout' 'unchanged' who)
  ;<  ~  bind:m
    %+  over:io  (rf 0 (acct-dir ship.c) %'checkouts.json')
    [[/ %json] [%o (~(put by cm) nonce.c row)]]
  ;<  ~  bind:m  (do-write-view ship.c)
  ;<  ~  bind:m  (note 'set-checkout' & status.c who --0)
  (pure:m &)
::  ==  the writer's ops on the customer side
::
::  +do-set-vendor: who this ship buys from. Empty means nobody, and
::  then the client fiber sleeps.
::
++  do-set-vendor
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-vendor:arm jon)
  ?:  ?=(%| -.got)  (refuse 'set-vendor' p.got '')
  =/  txt=@t  ?~(p.got '' (scot %p u.p.got))
  =/  doc=json  (pairs:enjs:format ~[['ship' s+txt]])
  ;<  cur=json  bind:m  (read-json (rf 0 / %'vendor.json'))
  ?:  =(cur doc)  (note-then-no 'set-vendor' 'unchanged' txt)
  ;<  ~  bind:m  (over:io (rf 0 / %'vendor.json') [[/ %json] doc])
  ;<  ~  bind:m  (note 'set-vendor' & '' txt --0)
  (pure:m &)
::  +do-store-key: an inference key fetched from the vendor's view. This
::  ship is the customer, so it keeps the secret.
::
++  do-store-key
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-store-key:arm jon)
  ?:  ?=(%| -.got)  (refuse 'store-key' p.got '')
  =/  k=held-key:arm  p.got
  ;<  keys=json  bind:m  (read-json (rf 0 / %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?:  (~(has by km) id.k)  (note-then-no 'store-key' 'already held' '')
  ;<  ~  bind:m
    (over:io (rf 0 / %'keys.json') [[/ %json] [%o (~(put by km) id.k (en-held:arm k))]])
  ::  the audit row names the key id, never the secret
  ;<  ~  bind:m  (note 'store-key' & id.k '' --0)
  (pure:m &)
++  do-forget-key
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-forget-key:arm jon)
  ?:  ?=(%| -.got)  (refuse 'forget-key' p.got '')
  ;<  keys=json  bind:m  (read-json (rf 0 / %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?.  (~(has by km) p.got)  (note-then-no 'forget-key' 'no such key' '')
  ;<  ~  bind:m
    (over:io (rf 0 / %'keys.json') [[/ %json] [%o (~(del by km) p.got)]])
  ;<  ~  bind:m  (note 'forget-key' & p.got '' --0)
  (pure:m &)
::  +do-store-view: the vendor's view of our account, kept verbatim with
::  the time we read it. No audit row: this runs every five minutes and
::  one row a pass would flush the ring in a day.
::
++  do-store-view
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-store-view:arm jon)
  ?:  ?=(%| -.got)  (refuse 'store-view' p.got '')
  ;<  now=@da  bind:m  get-time:io
  =/  doc=json
    ?.  ?=([%o *] p.got)  p.got
    [%o (~(put by p.p.got) 'fetched' (en-time:arm now))]
  ;<  ~  bind:m  (over:io (rf 0 / %'view.json') [[/ %json] doc])
  (pure:m &)
::  +do-note-op: an op queued for the vendor, by nonce. The client fiber
::  sends what is here and drops a nonce once it shows in the view.
::
++  do-note-op
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-note-op:arm jon)
  ?:  ?=(%| -.got)  (refuse 'note-op' p.got '')
  =/  n  p.got
  ;<  cj=json  bind:m  (read-json (rf 0 / %'client.json'))
  =/  ops=json  (gj:arm cj 'ops')
  =/  om=(map @t json)  ?:(?=([%o *] ops) p.ops ~)
  ;<  now=@da  bind:m  get-time:io
  =/  row=json
    %-  pairs:enjs:format
    :~  ['nonce' s+nonce.n]
        ['payload' payload.n]
        ['sent' b+sent.n]
        ['at' (en-time:arm now)]
    ==
  =/  doc=json  (pairs:enjs:format ~[['ops' [%o (~(put by om) nonce.n row)]]])
  ;<  ~  bind:m  (over:io (rf 0 / %'client.json') [[/ %json] doc])
  (pure:m &)
++  do-drop-op
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  =/  got  (de-op-drop-op:arm jon)
  ?:  ?=(%| -.got)  (refuse 'drop-op' p.got '')
  ;<  cj=json  bind:m  (read-json (rf 0 / %'client.json'))
  =/  ops=json  (gj:arm cj 'ops')
  =/  om=(map @t json)  ?:(?=([%o *] ops) p.ops ~)
  ?.  (~(has by om) p.got)  (pure:m |)
  =/  doc=json  (pairs:enjs:format ~[['ops' [%o (~(del by om) p.got)]]])
  ;<  ~  bind:m  (over:io (rf 0 / %'client.json') [[/ %json] doc])
  (pure:m &)
::  ==  reads: walking the tree
::
::  +read-json: a JSON grub in the instance, [%o ~] when absent
::
++  read-json
  |=  road=road:tarball
  =/  m  (fiber:fiber:nexus ,json)
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io road ~)
  ?.  ?=([%file *] vw)  (pure:m [%o ~])
  (pure:m (fall (mole |.(!<(json (need-vase:tarball sang.vw)))) [%o ~]))
::  +catalog-of: the catalog as rows. A document that will not decode
::  reads as empty rather than crashing a request.
::
++  catalog-of
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(list model-row:arm))
  ^-  form:m
  ;<  jon=json  bind:m  (read-json (rf up / %'catalog.json'))
  =/  got  (de-catalog:arm jon)
  ?:(?=(%| -.got) (pure:m ~) (pure:m p.got))
::  +providers-of: every provider row, by id
::
++  providers-of
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(map @t provider:arm))
  ^-  form:m
  ;<  jon=json  bind:m  (read-json (rf up / %'providers.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] jon) p.jon ~)
  %-  pure:m
  %-  ~(gas by *(map @t provider:arm))
  %+  murn  ~(tap by pm)
  |=  [k=@t j=json]
  ^-  (unit [@t provider:arm])
  =/  p=(unit provider:arm)  (de-provider-stored:arm j)
  ?~(p ~ `[k u.p])
::  +accounts-in: every account under a ball, with its key count
::
++  accounts-in
  |=  b=ball:tarball
  ^-  (list [=account:arm keys=@ud])
  %+  murn  ~(tap by dir.b)
  |=  [nam=@ta ab=ball:tarball]
  ^-  (unit [account:arm @ud])
  ?~  fil.ab  ~
  =/  ga=(unit [=sang:tarball gain=? bang=(unit tang)])
    (~(get by contents.u.fil.ab) %'account.json')
  ?~  ga  ~
  =/  aj=json  (fall (mole |.(!<(json (need-vase:tarball sang.u.ga)))) [%o ~])
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  ~
  =/  gk=(unit [=sang:tarball gain=? bang=(unit tang)])
    (~(get by contents.u.fil.ab) %'keys.json')
  =/  kj=json
    ?~  gk  [%o ~]
    (fall (mole |.(!<(json (need-vase:tarball sang.u.gk)))) [%o ~])
  =/  n=@ud  ?:(?=([%o *] kj) ~(wyt by p.kj) 0)
  `[u.a n]
::  +all-accounts: every account on the vendor
::
++  all-accounts
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(list [=account:arm keys=@ud]))
  ^-  form:m
  ;<  vw=view:nexus  bind:m  (peek:io (rv up /accounts) ~)
  ?.  ?=([%ball *] vw)  (pure:m ~)
  (pure:m (accounts-in ball.vw))
::  ==  the inbox: what other ships ask of this vendor
::
::  +ship-op, +ship-id-op: a writer op naming one ship, and one naming a
::  ship and a key. The ship is always the transport's, never the
::  payload's: that is what makes the poke an identity.
::
++  ship-op
  |=  [op=@t who=@p]
  ^-  json
  (pairs:enjs:format ~[['op' s+op] ['ship' s+(scot %p who)]])
++  ship-id-op
  |=  [op=@t who=@p id=@t]
  ^-  json
  (pairs:enjs:format ~[['op' s+op] ['ship' s+(scot %p who)] ['id' s+id]])
::  +has-nonce: is one of these pending rows already this nonce. A
::  mint-key resent after a timeout must not mint twice.
::
++  has-nonce
  |=  [pm=(map @t json) nonce=@t]
  ^-  ?
  %+  lien  ~(tap by pm)
  |=([id=@t j=json] =(nonce (gs:arm j 'nonce')))
::  +take-inbox: one poke from a ship. Everything is refused cleanly and
::  noted in /tr/inbox; nothing a stranger sends reaches /tr/log.
::
++  take-inbox
  |=  [src=@p =sage:tarball]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=@t  (scot %p src)
  ?.  =([/ %json] p.sage)  (note-inbox 'inbox' | 'payload: not json' who)
  =/  jon=json  (fall (mole |.(!<(json q.sage))) ~)
  =/  got  (de-inbox:arm jon)
  ?:  ?=(%| -.got)  (note-inbox 'inbox' | p.got who)
  =/  o=inbox-op:arm  p.got
  ;<  sj=json  bind:m  (read-json (rf 0 / %'settings.json'))
  ?:  ?&((gb:arm sj 'refuse_comets') (is-comet:arm src))
    (note-inbox 'inbox' | 'comet refused' who)
  ::  a ship with no account gets one on its first op, whatever the op
  ::  was; hello opens it itself
  ;<  ex=?  bind:m  (peek-exists:io (rf 0 (acct-dir src) %'account.json'))
  ;<  ~  bind:m
    ?:  |(ex ?=(%hello -.o))  (pure:(fiber:fiber:nexus ,~) ~)
    (poke-writer 0 (ship-op 'open-account' src))
  (do-inbox-op src o)
::  +do-inbox-op: the op, decoded, turned into writer pokes. This fiber
::  writes no account state of its own and waits for nothing.
::
++  do-inbox-op
  |=  [src=@p o=inbox-op:arm]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=@t  (scot %p src)
  ?-    -.o
      %hello
    ;<  ~  bind:m  (poke-writer 0 (ship-op 'open-account' src))
    (note-inbox 'hello' & '' who)
      %refresh
    ;<  ~  bind:m  (poke-writer 0 (ship-op 'write-view' src))
    (note-inbox 'refresh' & '' who)
      %got-key
    ;<  ~  bind:m  (poke-writer 0 (ship-id-op 'drop-pending' src id.o))
    (note-inbox 'got-key' & '' who)
      %drop-key
    ;<  ~  bind:m  (poke-writer 0 (ship-id-op 'drop-key' src id.o))
    (note-inbox 'drop-key' & '' who)
      %mint-key  (inbox-mint src name.o nonce.o)
      %checkout  (inbox-checkout src rail.o plan.o amount.o nonce.o)
      %lease                 (note-inbox 'lease' | 'not yet' who)
      %drop-lease            (note-inbox 'drop-lease' | 'not yet' who)
      %cancel-subscription   (note-inbox 'cancel-subscription' | 'not yet' who)
  ==
::  +inbox-mint: a key minted for a customer ship, the same way the
::  owner's route mints one. The row goes to keys.json hashed; the
::  secret goes to pending.json and to the view, and nowhere else.
::
++  inbox-mint
  |=  [src=@p name=@t nonce=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=@t  (scot %p src)
  ;<  pend=json  bind:m  (read-json (rf 0 (acct-dir src) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  ::  the nonce is the customer's idempotency key: a resend after a
  ::  timeout is a no-op, not a second key
  ?:  (has-nonce pm nonce)  (note-inbox 'mint-key' & 'already minted' who)
  ;<  eny=@uvJ  bind:m  get-entropy:io
  ;<  now=@da  bind:m  get-time:io
  =/  id=@t  (id-of:arm eny)
  =/  salt=@t  (scot %uv (end [3 10] (rsh [3 5] eny)))
  =/  secret=@t  (secret-of:arm (rsh [3 15] eny))
  =/  k=key:arm  [id name salt (hash-token:arm salt secret) now ~]
  ;<  ~  bind:m
    %+  poke-writer  0
    %-  pairs:enjs:format
    :~  ['op' s+'add-key']
        ['ship' s+who]
        ['key' (en-key-row:arm k)]
    ==
  ;<  ~  bind:m
    %+  poke-writer  0
    %-  pairs:enjs:format
    :~  ['op' s+'set-pending']
        ['ship' s+who]
        ['id' s+id]
        ['secret' s+secret]
        ['nonce' s+nonce]
        ['name' s+name]
    ==
  ::  the note carries the op and the ship: the ring never sees a secret
  (note-inbox 'mint-key' & '' who)
::  +inbox-checkout: phase 2 has no money rails, so stub mode answers a
::  local page that credits the account and live mode answers that the
::  rail is unavailable. Phase 3 replaces the live branch.
::
++  inbox-checkout
  |=  [src=@p rail=@t plan=@t amount=@ud nonce=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=@t  (scot %p src)
  ;<  cj=json  bind:m  (read-json (rf 0 (acct-dir src) %'checkouts.json'))
  =/  cm=(map @t json)  ?:(?=([%o *] cj) p.cj ~)
  ::  a nonce already here answers the row that is already here
  ?:  (~(has by cm) nonce)  (note-inbox 'checkout' & 'already open' who)
  ;<  sj=json  bind:m  (read-json (rf 0 / %'settings.json'))
  ;<  now=@da  bind:m  get-time:io
  =/  stub=?  !=('live' (gs:arm sj 'mode'))
  =/  url=@t
    ?.  stub  ''
    %^  rap  3  (public-url-of sj)
    :~  '/apps/armillary/pay/stub?ship='
        who
        '&nonce='
        nonce
    ==
  =/  op=json
    %-  pairs:enjs:format
    :~  ['op' s+'set-checkout']
        ['ship' s+who]
        ['nonce' s+nonce]
        ['rail' s+rail]
        ['plan' s+plan]
        ['amount' (en-num:arm amount)]
        ['url' s+url]
        ['expires' (en-time:arm (add now ~d1))]
        ['status' s+?:(stub 'pending' 'unavailable')]
    ==
  ;<  ~  bind:m  (poke-writer 0 op)
  ?:  stub  (note-inbox 'checkout' & '' who)
  (note-inbox 'checkout' | 'live rails are phase 3' who)
::  ==  the client: what this ship asks of its vendor
::
::  +client-loop: send what is queued, read the view, sleep five
::  minutes or until prodded. A ship with no vendor waits and costs
::  nothing. The poke that prods it is a prod and nothing else: what to
::  send is in client.json, written by the writer before the prod.
::
++  client-loop
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |-
  ;<  vj=json  bind:m  (read-json (rf 0 / %'vendor.json'))
  =/  vendor=(unit @p)  (slaw %p (gs:arm vj 'ship'))
  ?~  vendor
    ;<  *  bind:m  take-poke-from:io
    $
  ;<  ~  bind:m  (client-pass u.vendor)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (set-timer:io /tick (add now ~m5))
  ;<  *  bind:m  take-poke-from:io
  ;<  ~  bind:m  (cancel-timer:io /tick)
  $
::  +client-pass: one round with the vendor. Send every op not yet sent,
::  then read the view once and take what it holds for us.
::
++  client-pass
  |=  vendor=@p
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  cj=json  bind:m  (read-json (rf 0 / %'client.json'))
  =/  ops=json  (gj:arm cj 'ops')
  =/  om=(map @t json)  ?:(?=([%o *] ops) p.ops ~)
  =/  todo=(list [nonce=@t row=json])
    (skim ~(tap by om) |=([n=@t j=json] !(gb:arm j 'sent')))
  ;<  ~  bind:m  (send-queued vendor todo)
  ::  the vendor's own writer runs only after our poke has landed, so a
  ::  pass that sent something looks again a moment later rather than
  ::  reading the account as it was before the op
  ;<  ~  bind:m  ?~(todo (pure:(fiber:fiber:nexus ,~) ~) (nap ~s2))
  ;<  got=(unit json)  bind:m  (peek-view vendor)
  ?~  got  (pure:m ~)
  (absorb-view vendor u.got)
::  +send-queued: the ops waiting, one at a time. A remote ack is
::  unobservable, so a timeout answers yes and the view is the truth.
::
++  send-queued
  |=  [vendor=@p todo=(list [nonce=@t row=json])]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  todo  (pure:m ~)
  =/  n=@t  nonce.i.todo
  =/  pay=json  (gj:arm row.i.todo 'payload')
  ;<  ok=?  bind:m  (send-op vendor pay)
  ;<  ~  bind:m
    ?.  ok  (pure:(fiber:fiber:nexus ,~) ~)
    ::  an op with no nonce of its own can never show in the view, so a
    ::  send that was taken is the end of it; the rest waits to be seen
    ?:  =('' (gs:arm pay 'nonce'))
      (poke-writer 0 (pairs:enjs:format ~[['op' s+'drop-op'] ['nonce' s+n]]))
    %+  poke-writer  0
    %-  pairs:enjs:format
    :~  ['op' s+'note-op']
        ['nonce' s+n]
        ['payload' pay]
        ['sent' b+&]
    ==
  (send-queued vendor t.todo)
::  +send-op: one op into the vendor's inbox. Our own ship is poked
::  directly, since a ship cannot ames itself.
::
++  send-op
  |=  [vendor=@p jon=json]
  =/  m  (fiber:fiber:nexus ,?)
  ^-  form:m
  ;<  our=@p  bind:m  get-our:io
  ?:  =(vendor our)
    ;<  *  bind:m  (poke-soft:io (rf 0 / %'inbox.sig') [[/ %json] jon])
    (pure:m &)
  (remote-poke-wait vendor [%& armillary-instance:arm %'inbox.sig'] jon)
::  +sang-json: a peeked grub as JSON, however it travelled
::
++  sang-json
  |=  s=sang:tarball
  ^-  (unit json)
  =/  a  (mole |.(!<(json (need-vase:tarball s))))
  ?^  a  a
  (mole |.(;;(json (sang-noun:tarball s))))
::  +peek-view: our account on the vendor, read from the one file the
::  vendor's usergroup lets this ship peek
::
++  peek-view
  |=  vendor=@p
  =/  m  (fiber:fiber:nexus ,(unit json))
  ^-  form:m
  ;<  our=@p  bind:m  get-our:io
  ?:  =(vendor our)
    ;<  jon=json  bind:m  (read-json (rf 0 (acct-dir our) %'view.json'))
    (pure:m (view-doc jon))
  =/  road=road:tarball
    [%& %& (weld armillary-instance:arm (acct-dir our)) %'view.json']
  ;<  vw=(unit view:nexus)  bind:m  (peek-remote-wait vendor road)
  ?.  ?=([~ %file *] vw)  (pure:m ~)
  =/  jon=(unit json)  (sang-json sang.u.vw)
  ?~  jon  (pure:m ~)
  (pure:m (view-doc u.jon))
::  +view-doc: a document that is really a view. An account the vendor
::  has not opened yet reads as an empty object, and storing that would
::  wipe what we already knew.
::
++  view-doc
  |=  jon=json
  ^-  (unit json)
  ?.  ?=([%o *] jon)  ~
  ?~  (de-view:arm jon)  ~
  `jon
::  +absorb-view: store the view, take any key waiting in it, and drop
::  the ops the view now accounts for
::
++  absorb-view
  |=  [vendor=@p jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  ~  bind:m
    (poke-writer 0 (pairs:enjs:format ~[['op' s+'store-view'] ['view' jon]]))
  =/  v=(unit view:arm)  (de-view:arm jon)
  ?~  v  (pure:m ~)
  ;<  cj=json  bind:m  (read-json (rf 0 / %'client.json'))
  =/  ops=json  (gj:arm cj 'ops')
  =/  om=(map @t json)  ?:(?=([%o *] ops) p.ops ~)
  ;<  ~  bind:m  (take-pending vendor keys-pending.u.v om)
  ::  a checkout nonce the vendor now holds is an op that landed
  =/  done=(list @t)
    ?.  ?=([%o *] checkouts.u.v)  ~
    (skim ~(tap in ~(key by p.checkouts.u.v)) |=(n=@t (~(has by om) n)))
  (drop-ops done)
::  +take-pending: a key the vendor minted for us. We store the secret,
::  tell the vendor we have it so it clears the view, and drop the op.
::
++  take-pending
  |=  [vendor=@p rows=(list [nonce=@t id=@t name=@t secret=@t]) om=(map @t json)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  rows  (pure:m ~)
  =/  r  i.rows
  ?.  (~(has by om) nonce.r)  (take-pending vendor t.rows om)
  ;<  now=@da  bind:m  get-time:io
  =/  k=held-key:arm  [id.r name.r secret.r now]
  ;<  ~  bind:m
    (poke-writer 0 (pairs:enjs:format ~[['op' s+'store-key'] ['key' (en-held:arm k)]]))
  ;<  *  bind:m  (send-op vendor (en-inbox:arm [%got-key id.r]))
  ;<  ~  bind:m
    (poke-writer 0 (pairs:enjs:format ~[['op' s+'drop-op'] ['nonce' s+nonce.r]]))
  (take-pending vendor t.rows om)
++  drop-ops
  |=  ns=(list @t)
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?~  ns  (pure:m ~)
  ;<  ~  bind:m
    (poke-writer 0 (pairs:enjs:format ~[['op' s+'drop-op'] ['nonce' s+i.ns]]))
  (drop-ops t.ns)
::  ==  HTTP
::
::  +send-json, +send-err: every error is OpenAI's shape, so one client
::  error path covers the whole API
::
++  send-json
  |=  [eyre-id=@ta code=@ud jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  bod=octs  (as-octs:mimes:html (en:json:html jon))
  (send-simple:srv eyre-id [[code ['content-type' 'application/json'] ~] `bod])
++  send-err
  |=  [eyre-id=@ta code=@ud msg=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %^  send-json  eyre-id  code
  (pairs:enjs:format ~[['error' (pairs:enjs:format ~[['message' s+msg]])]])
::  +send-raw: an upstream body answered exactly as it came, with its
::  own status. The customer sees what the provider said.
::
++  send-raw
  |=  [eyre-id=@ta code=@ud body=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  bod=octs  (as-octs:mimes:html body)
  (send-simple:srv eyre-id [[code ['content-type' 'application/json'] ~] `bod])
::  +poke-writer: one op to our writer, soft (a refusal is noted there)
::
++  poke-writer
  |=  [up=@ud op=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  *  bind:m  (poke-soft:io (rf up / %'main.sig') [[/ %json] op])
  (pure:m ~)
::  +fetch-in: what ends a wait on a provider
::
+$  fetch-in
  $%  [%veto ~]
      [%none ~]
      [%resp resp=client-response:iris]
  ==
::  +take-fetch: the provider's answer, the deadline, or a vetoed road
::
++  take-fetch
  |=  wir=wire
  =/  m  (fiber:fiber:nexus ,fetch-in)
  ^-  form:m
  |=  input:fiber:nexus
  :+  ~  q.state
  ?+  in  [%skip ~]
      ~  [%wait ~]
      [~ %veto *]  [%done [%veto ~]]
      [~ %poke * *]
    ?:  =([/ %timer-wake] p.sage.u.in)
      ?.(=(wir !<(path q.sage.u.in)) [%skip ~] [%done [%none ~]])
    ?.  =([/ %http-response] p.sage.u.in)  [%skip ~]
    =/  resp=client-response:iris  !<(client-response:iris q.sage.u.in)
    ?:(?=(%cancel -.resp) [%done [%none ~]] [%done [%resp resp]])
  ==
::  +fetch: one HTTP request with a two minute deadline. A request that
::  never answers, a cancelled one and a vetoed iris road are all
::  status 0, so the caller has one branch for "no answer".
::
::    The timer wire carries a nonce, so two request fibers in flight
::    never take each other's wake.
::
++  fetch
  |=  =request:http
  =/  m  (fiber:fiber:nexus ,[status=@ud body=@t])
  ^-  form:m
  ;<  wir=wire  bind:m  (nonce:io /fetch)
  ;<  ~  bind:m  (send-request:io request)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (set-timer:io wir (add now ~m2))
  ;<  got=fetch-in  bind:m  (take-fetch wir)
  ;<  ~  bind:m  (cancel-timer:io wir)
  ?:  ?=(%veto -.got)  (pure:m [0 'the iris road is refused'])
  ?:  ?=(%none -.got)  (pure:m [0 ''])
  =/  r=client-response:iris  resp.got
  ?.  ?=(%finished -.r)  (pure:m [0 ''])
  =/  body=@t  ?~(full-file.r '' q.data.u.full-file.r)
  (pure:m [status-code.response-header.r body])
::  +post-json: a JSON POST to a provider with its bearer key
::
++  post-json
  |=  [url=@t api-key=@t body=json]
  =/  m  (fiber:fiber:nexus ,[status=@ud body=@t])
  ^-  form:m
  =/  heads=(list [@t @t])
    :~  ['content-type' 'application/json']
        ['authorization' (rap 3 'Bearer ' api-key ~)]
    ==
  (fetch [%'POST' url heads `(as-octs:mimes:html (en:json:html body))])
::  +get-json: a JSON GET from a provider with its bearer key
::
++  get-json
  |=  [url=@t api-key=@t]
  =/  m  (fiber:fiber:nexus ,[status=@ud body=@t])
  ^-  form:m
  =/  heads=(list [@t @t])  ~[['authorization' (rap 3 'Bearer ' api-key ~)]]
  (fetch [%'GET' url heads ~])
::  +join-url: a provider base url and a route, with exactly one slash
::
++  join-url
  |=  [base=@t leaf=@t]
  ^-  @t
  =/  b=tape  (trip base)
  =/  trimmed=tape  ?:(&(?=(^ b) =('/' (rear `tape`b))) (snip `tape`b) b)
  =/  out=tape  (weld trimmed (trip leaf))
  (crip out)
::  ==  who is asking
::
::  an actor: the owner through the cookie, or a customer's key with
::  the ship that holds it
::
+$  actor  [owner=? ship=@p key=(unit @t)]
::  +identify: the owner cookie, else a valid bearer token, else ~. A
::  key's last use is stamped through the writer at most hourly.
::
++  identify
  |=  [req=inbound-request:eyre src=@p our=@p]
  =/  m  (fiber:fiber:nexus ,(unit actor))
  ^-  form:m
  ?:  &(authenticated.req =(src our))  (pure:m `[& our ~])
  =/  au=(unit @t)  (get-header:http 'authorization' header-list.request.req)
  ?~  au  (pure:m ~)
  =/  tok=(unit [id=@t secret=@t])  (parse-bearer:arm u.au)
  ?~  tok  (pure:m ~)
  ;<  ix=json  bind:m  (read-json (rf 1 / %'key-index.json'))
  =/  who=(unit @p)  (slaw %p (gs:arm ix id.u.tok))
  ?~  who  (pure:m ~)
  ;<  keys=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'keys.json'))
  =/  k=(unit key:arm)  (de-key:arm (gj:arm keys id.u.tok))
  ?~  k  (pure:m ~)
  ?.  (key-ok:arm u.k secret.u.tok)  (pure:m ~)
  ;<  aj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (pure:m ~)
  ?:  closed.u.a  (pure:m ~)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m
    ?:  &(?=(^ used.u.k) (lth now (add u.used.u.k ~h1)))
      (pure:(fiber:fiber:nexus ,~) ~)
    %+  poke-writer  1
    %-  pairs:enjs:format
    :~  ['op' s+'touch-key']
        ['ship' s+(scot %p u.who)]
        ['id' s+id.u.k]
    ==
  (pure:m `[| u.who `id.u.k])
::  ==  the request fiber
::
++  handle-request
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  [src=@p req=inbound-request:eyre]  bind:m
    (get-state-as:io ,[src=@p inbound-request:eyre])
  ;<  our=@p  bind:m  get-our:io
  =/  parsed  (parse-url:http-utils url.request.req)
  ::  drop /apps/armillary; a trailing slash parses as a trailing empty knot
  =/  suffix0=path  (slag 2 site.parsed)
  =/  suffix=path
    ?:  &(?=(^ suffix0) =('' (rear `path`suffix0)))  (snip `path`suffix0)
    suffix0
  =/  meth=@t  method.request.req
  =/  size=@ud  ?~(body.request.req 0 p.u.body.request.req)
  ?:  (gth size max-body:arm)
    (send-err eyre-id 413 'body: over 4 MB')
  ::  a body is read as JSON, so a request carrying one says it is JSON
  =/  ctype=@t
    =/  raw=tape
      (cass (trip (fall (get-header:http 'content-type' header-list.request.req) '')))
    (crip raw)
  ?:  ?&  |(=('POST' meth) =('PUT' meth))
          ?=(^ body.request.req)
          !=(0 p.u.body.request.req)
          !=('application/json' (end [3 16] ctype))
      ==
    (send-err eyre-id 415 'content-type: application/json required')
  =/  jon=json
    (fall (de:json:html ?~(body.request.req '' q.u.body.request.req)) ~)
  =/  s2=@ta  ?:(?=([@ @ @ *] suffix) i.t.t.suffix %$)
  =/  s4=@ta  ?:(?=([@ @ @ @ @ *] suffix) i.t.t.t.t.suffix %$)
  =/  args=quay:eyre  args.parsed
  ::  the two public routes, ahead of the cookie: a customer who is
  ::  paying is a browser with no login on this ship
  ?:  &(=('GET' meth) ?=([%pay %stub ~] suffix))   (serve-pay-page eyre-id args)
  ?:  &(=('POST' meth) ?=([%pay %stub ~] suffix))  (serve-pay-stub eyre-id args jon)
  ;<  who=(unit actor)  bind:m  (identify req src our)
  ?~  who  (send-err eyre-id 403 'forbidden')
  =/  act=actor  u.who
  ::  +own: a route the owner alone may take
  =/  own  |=(f=form:m ^-(form:m ?:(owner.act f (send-err eyre-id 403 'owner only'))))
  ?:  &(=('GET' meth) ?=(~ suffix))                      (own (serve-file eyre-id %'armillary.html'))
  ?:  &(=('GET' meth) ?=([%'armillary.css' ~] suffix))   (own (serve-file eyre-id %'armillary.css'))
  ?:  &(=('GET' meth) ?=([%'armillary.js' ~] suffix))    (own (serve-file eyre-id %'armillary.js'))
  ::  the inference API
  ?:  &(=('GET' meth) ?=([%v1 %models ~] suffix))        (serve-models eyre-id)
  ?:  &(=('POST' meth) ?=([%v1 %chat %completions ~] suffix))
    (serve-proxy eyre-id act jon %chat)
  ?:  &(=('POST' meth) ?=([%v1 %embeddings ~] suffix))
    (serve-proxy eyre-id act jon %embeddings)
  ::  the owner's routes
  ?:  &(=('GET' meth) ?=([%api %settings ~] suffix))     (own (serve-settings eyre-id))
  ?:  &(=('PUT' meth) ?=([%api %settings ~] suffix))     (own (serve-set-settings eyre-id jon))
  ?:  &(=('GET' meth) ?=([%api %providers ~] suffix))    (own (serve-providers eyre-id))
  ?:  &(=('POST' meth) ?=([%api %providers ~] suffix))   (own (serve-add-provider eyre-id jon))
  ?:  &(=('PUT' meth) ?=([%api %providers @ ~] suffix))  (own (serve-put-provider eyre-id s2 jon))
  ?:  &(=('DELETE' meth) ?=([%api %providers @ ~] suffix))
    (own (serve-drop-provider eyre-id s2))
  ?:  &(=('POST' meth) ?=([%api %providers @ %test ~] suffix))
    (own (serve-test-provider eyre-id s2 jon))
  ?:  &(=('POST' meth) ?=([%api %providers @ %import ~] suffix))
    (own (serve-import eyre-id s2))
  ?:  &(=('GET' meth) ?=([%api %catalog ~] suffix))      (own (serve-catalog eyre-id))
  ?:  &(=('PUT' meth) ?=([%api %catalog ~] suffix))      (own (serve-set-catalog eyre-id jon))
  ::  the plans. GET serves both halves: our own list on a vendor, the
  ::  vendor's list on a customer ship, since nothing on a plan is secret
  ?:  &(=('GET' meth) ?=([%api %plans ~] suffix))        (own (serve-plans eyre-id))
  ?:  &(=('POST' meth) ?=([%api %plans ~] suffix))       (own (serve-add-plan eyre-id jon))
  ?:  &(=('PUT' meth) ?=([%api %plans @ ~] suffix))      (own (serve-put-plan eyre-id s2 jon))
  ?:  &(=('DELETE' meth) ?=([%api %plans @ ~] suffix))   (own (serve-drop-plan eyre-id s2))
  ?:  &(=('POST' meth) ?=([%api %plans @ %stripe ~] suffix))
    (own (serve-plan-stripe eyre-id s2))
  ?:  &(=('GET' meth) ?=([%api %accounts ~] suffix))     (own (serve-accounts eyre-id args))
  ?:  &(=('GET' meth) ?=([%api %accounts @ ~] suffix))   (own (serve-account eyre-id s2))
  ?:  &(=('DELETE' meth) ?=([%api %accounts @ ~] suffix))
    (own (serve-drop-account eyre-id s2))
  ?:  &(=('POST' meth) ?=([%api %accounts @ %keys ~] suffix))
    (own (serve-mint eyre-id s2 jon))
  ?:  &(=('DELETE' meth) ?=([%api %accounts @ %keys @ ~] suffix))
    (own (serve-revoke eyre-id s2 s4))
  ?:  &(=('POST' meth) ?=([%api %accounts @ %credit ~] suffix))
    (own (serve-credit eyre-id s2 jon))
  ?:  &(=('POST' meth) ?=([%api %accounts @ %refund ~] suffix))
    (own (serve-refund eyre-id s2 jon))
  ?:  &(=('POST' meth) ?=([%api %accounts @ %close ~] suffix))
    (own (serve-close eyre-id s2))
  ?:  &(=('GET' meth) ?=([%api %log ~] suffix))          (own (serve-log eyre-id))
  ::  the customer's routes, what Talon calls on its own ship
  ?:  &(=('GET' meth) ?=([%api %account ~] suffix))      (own (serve-my-account eyre-id args))
  ?:  &(=('PUT' meth) ?=([%api %vendor ~] suffix))       (own (serve-set-vendor eyre-id jon))
  ?:  &(=('GET' meth) ?=([%api %keys ~] suffix))         (own (serve-my-keys eyre-id))
  ?:  &(=('POST' meth) ?=([%api %keys ~] suffix))        (own (serve-my-mint eyre-id jon))
  ?:  &(=('DELETE' meth) ?=([%api %keys @ ~] suffix))    (own (serve-my-revoke eyre-id s2))
  ?:  &(=('POST' meth) ?=([%api %checkout ~] suffix))    (own (serve-my-checkout eyre-id jon))
  ?:  &(=('GET' meth) ?=([%api %inference ~] suffix))    (own (serve-inference eyre-id))
  ::  leases are phase 5 and the subscription is phase 3
  ?:  &(=('POST' meth) ?=([%api %lease ~] suffix))       (own (send-err eyre-id 501 'not yet'))
  ?:  &(=('DELETE' meth) ?=([%api %lease ~] suffix))     (own (send-err eyre-id 501 'not yet'))
  ?:  &(=('POST' meth) ?=([%api %'cancel-subscription' ~] suffix))
    (own (send-err eyre-id 501 'not yet'))
  (send-err eyre-id 404 'no such route')
::  +ship-of: a ship named in a route. The segment carries its ~.
::
++  ship-of
  |=  seg=@ta
  ^-  (unit @p)
  =/  t=tape  (trip seg)
  ?~  t  ~
  =/  full=@t  ?:(=('~' i.t) seg (cat 3 '~' seg))
  (slaw %p full)
::  ==  settings
::
++  serve-settings
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  doc=json  bind:m  (read-json (rf 1 / %'settings.json'))
  (send-json eyre-id 200 (mask-doc:arm doc))
::  +serve-set-settings: the whole document, replaced. The raw body goes
::  to the writer rather than the decoded row, so the difference between
::  a blank secret (keep) and a null one (clear) survives the trip.
::
++  serve-set-settings
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  got  (de-settings:arm jon)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  cur=json  bind:m  (read-json (rf 1 / %'settings.json'))
  =/  op=json
    (pairs:enjs:format ~[['op' s+'set-settings'] ['settings' jon]])
  ;<  ~  bind:m  (poke-writer 1 op)
  =/  kept=settings:arm  (kept-secrets p.got jon cur)
  (send-json eyre-id 200 (mask-doc:arm (en-settings:arm kept)))
::  +settings-of: the settings as a row. A document that will not decode
::  reads as the starter, so a request never crashes on it.
::
++  settings-of
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,settings:arm)
  ^-  form:m
  ;<  jon=json  bind:m  (read-json (rf up / %'settings.json'))
  =/  got  (de-settings:arm jon)
  ?:  ?=(%| -.got)
    (pure:m [130 5.000.000 '' %stub | '' '' stripe-base:arm])
  (pure:m p.got)
::  +two-xx: did the upstream say yes
::
++  two-xx  |=(s=@ud ^-(? &((gte s 200) (lth s 300))))
::  +stripe-why: what Stripe said went wrong, as a line a customer may
::  read. Stripe never echoes a key back, and nothing here adds one.
::
++  stripe-why
  |=  [status=@ud body=@t]
  ^-  @t
  ?:  =(0 status)  'stripe did not answer within two minutes'
  =/  code=tape  (a-co:co status)
  =/  msg=@t  (read-error:arm body)
  =/  said=@t  ?:(=('' msg) 'no message' msg)
  (rap 3 'stripe answered ' (crip code) ': ' said ~)
::  ==  providers
::
++  serve-providers
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  rows=(list json)
    (turn (sort ~(tap by pm) |=([a=[k=@t *] b=[k=@t *]] (aor k.a k.b))) tail-masked)
  (send-json eyre-id 200 a+rows)
++  tail-masked
  |=  [k=@t p=provider:arm]
  ^-  json
  (en-provider-masked:arm p)
::  +serve-add-provider: a new row. An id already held is 409, so the
::  page never silently overwrites a connection.
::
++  serve-add-provider
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  got  (de-provider:arm jon)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  ?:  (~(has by pm) id.p.got)  (send-err eyre-id 409 'id: already a provider')
  ?:  (gte ~(wyt by pm) max-providers:arm)
    (send-err eyre-id 409 'providers: over 200')
  ;<  ~  bind:m  (poke-provider jon)
  (send-json eyre-id 200 (en-provider-masked:arm p.got))
::  +serve-put-provider: an edit. A blank secret keeps the stored one,
::  which the writer resolves; an unknown id is 409.
::
++  serve-put-provider
  |=  [eyre-id=@ta id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  ?=([%o *] jon)  (send-err eyre-id 400 'a JSON object is required')
  =/  with-id=json  [%o (~(put by p.jon) 'id' s+`@t`id)]
  =/  got  (de-provider:arm with-id)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  ?.  (~(has by pm) `@t`id)  (send-err eyre-id 409 'id: no such provider')
  ;<  ~  bind:m  (poke-provider with-id)
  (send-json eyre-id 200 (en-provider-masked:arm p.got))
++  poke-provider
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (poke-writer 1 (pairs:enjs:format ~[['op' s+'set-provider'] ['provider' jon]]))
++  serve-drop-provider
  |=  [eyre-id=@ta id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  ?.  (~(has by pm) `@t`id)  (send-err eyre-id 404 'no such provider')
  =/  op=json  (pairs:enjs:format ~[['op' s+'drop-provider'] ['id' s+`@t`id]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['id' s+`@t`id] ['ok' b+&]]))
::  +serve-test-provider: one tiny chat completion, so the owner sees
::  whether the key and the base url work before a customer does
::
++  serve-test-provider
  |=  [eyre-id=@ta id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  p=(unit provider:arm)  (~(get by pm) `@t`id)
  ?~  p  (send-err eyre-id 404 'no such provider')
  ;<  cat=(list model-row:arm)  bind:m  (catalog-of 1)
  =/  mine=(list model-row:arm)
    (skim cat |=(r=model-row:arm &(enabled.r =(provider.r `@t`id))))
  =/  model=@t  ?~(mine (gs:arm jon 'model') upstream.i.mine)
  ?:  =('' model)  (send-err eyre-id 400 'model: no enabled row on this provider')
  =/  body=json
    %-  pairs:enjs:format
    :~  ['model' s+model]
        :-  'messages'
        :-  %a
        :~  (pairs:enjs:format ~[['role' s+'user'] ['content' s+'Say ok.']])
        ==
        ['max_tokens' (numb:enjs:format 5)]
    ==
  ;<  res=[status=@ud body=@t]  bind:m
    (post-json (join-url base-url.u.p '/chat/completions') api-key.u.p body)
  =/  answer=json  (fall (de:json:html body.res) ~)
  =/  choices=(list json)  (ga:arm answer 'choices')
  =/  text=@t
    ?^  choices  (gs:arm (gj:arm i.choices 'message') 'content')
    ?:  =(0 status.res)  'no answer within two minutes'
    (read-error:arm body.res)
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['status' (numb:enjs:format status.res)]
      ['model' s+(gs:arm answer 'model')]
      ['text' s+text]
  ==
::  +serve-import: the provider's models listing folded into the
::  catalog. Every fresh row lands disabled, so nothing is sold until
::  the owner says so.
::
++  serve-import
  |=  [eyre-id=@ta id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  p=(unit provider:arm)  (~(get by pm) `@t`id)
  ?~  p  (send-err eyre-id 404 'no such provider')
  ;<  sj=json  bind:m  (read-json (rf 1 / %'settings.json'))
  =/  pct=@ud  ?:(=(0 (gn:arm sj 'markup_pct')) 130 (gn:arm sj 'markup_pct'))
  ;<  res=[status=@ud body=@t]  bind:m
    (get-json (join-url base-url.u.p '/models') api-key.u.p)
  ?:  =(0 status.res)  (send-err eyre-id 504 'no answer from the provider within two minutes')
  ?.  &((gte status.res 200) (lth status.res 300))
    (send-err eyre-id 502 (cat 3 'the provider answered ' (crip (a-co:co status.res))))
  =/  listing=json  (fall (de:json:html body.res) ~)
  =/  fresh=(list model-row:arm)  (import-rows:arm `@t`id pct listing)
  ;<  cat=(list model-row:arm)  bind:m  (catalog-of 1)
  =/  merged=(list model-row:arm)  (merge-import:arm cat fresh)
  =/  added=@ud  (sub (lent merged) (lent cat))
  =/  op=json
    (pairs:enjs:format ~[['op' s+'set-catalog'] ['catalog' (en-catalog:arm merged)]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['added' (numb:enjs:format added)]]))
::  ==  the catalog
::
::  +serve-catalog: our own catalog when this ship is nobody's customer
::  or its own, which is the owner's editable rows; the vendor's public
::  catalog, read live and never cached, when the vendor is elsewhere
::
++  serve-catalog
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  our=@p  bind:m  get-our:io
  ;<  vendor=(unit @p)  bind:m  (vendor-of 1)
  ?:  ?|(?=(~ vendor) =(u.vendor our))
    ;<  jon=json  bind:m  (read-json (rf 1 / %'catalog.json'))
    (send-json eyre-id 200 jon)
  ;<  got=(unit json)  bind:m  (vendor-catalog 1)
  ?~  got  (send-err eyre-id 502 'vendor unreachable')
  (send-json eyre-id 200 u.got)
::  +serve-set-catalog: the whole catalog, replaced. A row naming a
::  provider that is not there is refused by index, the way the lib
::  names any other bad field.
::
++  serve-set-catalog
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  got  (de-catalog:arm jon)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  bad=(unit @t)  (unknown-provider p.got pm 0)
  ?^  bad  (send-err eyre-id 400 u.bad)
  =/  op=json
    (pairs:enjs:format ~[['op' s+'set-catalog'] ['catalog' (en-catalog:arm p.got)]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (en-catalog:arm p.got))
++  unknown-provider
  |=  [rows=(list model-row:arm) pm=(map @t provider:arm) i=@ud]
  ^-  (unit @t)
  ?~  rows  ~
  ?.  (~(has by pm) provider.i.rows)
    =/  at=tape  (a-co:co i)
    `(crip (weld "row " (weld at " provider: unknown")))
  $(rows t.rows, i +(i))
::  ==  plans
::
::  +serve-plans: our own plans when this ship is nobody's customer or
::  its own, which is the owner's editable list; the vendor's plans,
::  read live, when the vendor is elsewhere. Nothing on a plan is a
::  secret, so the two answers are the same shape.
::
++  serve-plans
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  our=@p  bind:m  get-our:io
  ;<  vendor=(unit @p)  bind:m  (vendor-of 1)
  ?:  ?|(?=(~ vendor) =(u.vendor our))
    ;<  plans=(list plan:arm)  bind:m  (plans-of 1)
    (send-json eyre-id 200 (en-plans-public:arm plans))
  =/  road=road:tarball  [%& %& armillary-instance:arm %'plans.json']
  ;<  vw=(unit view:nexus)  bind:m  (peek-remote-wait u.vendor road)
  ?.  ?=([~ %file *] vw)  (send-err eyre-id 502 'vendor unreachable')
  =/  got=(unit json)  (sang-json sang.u.vw)
  ?~  got  (send-err eyre-id 502 'vendor unreachable')
  (send-json eyre-id 200 (en-plans-public:arm (plans-sorted:arm u.got)))
::  +serve-add-plan: a new plan. An id already held is 409, so the page
::  never silently overwrites one.
::
++  serve-add-plan
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  got  (de-plan:arm jon)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  plans=(list plan:arm)  bind:m  (plans-of 1)
  ?^  (find-plan:arm plans id.p.got)  (send-err eyre-id 409 'id: already a plan')
  ;<  ~  bind:m  (poke-plan (en-plan:arm p.got))
  (send-json eyre-id 200 (en-plan:arm p.got))
::  +serve-put-plan: an edit. A blank stripe_price keeps the stored one,
::  so editing a name does not throw away the Price the owner made.
::
++  serve-put-plan
  |=  [eyre-id=@ta id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  ?=([%o *] jon)  (send-err eyre-id 400 'a JSON object is required')
  =/  with-id=json  [%o (~(put by p.jon) 'id' s+`@t`id)]
  =/  got  (de-plan:arm with-id)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  ;<  plans=(list plan:arm)  bind:m  (plans-of 1)
  =/  old=(unit plan:arm)  (find-plan:arm plans `@t`id)
  ?~  old  (send-err eyre-id 409 'id: no such plan')
  =/  price=@t
    ?:(=('' stripe-price.p.got) stripe-price.u.old stripe-price.p.got)
  =/  row=plan:arm  p.got(stripe-price price)
  ;<  ~  bind:m  (poke-plan (en-plan:arm row))
  (send-json eyre-id 200 (en-plan:arm row))
++  poke-plan
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (poke-writer 1 (pairs:enjs:format ~[['op' s+'set-plan'] ['plan' jon]]))
::  +serve-drop-plan: a plan an open subscription names cannot go, or
::  the next invoice would credit nothing
::
++  serve-drop-plan
  |=  [eyre-id=@ta id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  plans=(list plan:arm)  bind:m  (plans-of 1)
  ?~  (find-plan:arm plans `@t`id)  (send-err eyre-id 404 'no such plan')
  ;<  all=(list [=account:arm keys=@ud])  bind:m  (all-accounts 1)
  =/  used=?
    %+  lien  all
    |=  [a=account:arm keys=@ud]
    ^-  ?
    &(=(plan.a `@t`id) !=('' stripe-subscription.a))
  ?:  used  (send-err eyre-id 409 'plan: a subscription names it')
  =/  op=json  (pairs:enjs:format ~[['op' s+'drop-plan'] ['id' s+`@t`id]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['id' s+`@t`id] ['ok' b+&]]))
::  +serve-plan-stripe: the Product and the Price a subscription needs,
::  made on Stripe from the plan the owner already wrote. A top-up plan
::  needs neither: its checkout carries the amount inline.
::
++  serve-plan-stripe
  |=  [eyre-id=@ta id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  plans=(list plan:arm)  bind:m  (plans-of 1)
  =/  p=(unit plan:arm)  (find-plan:arm plans `@t`id)
  ?~  p  (send-err eyre-id 404 'no such plan')
  ?.  ?=(%subscription kind.u.p)
    (send-err eyre-id 400 'kind: only a subscription needs a Stripe price')
  ;<  s=settings:arm  bind:m  (settings-of 1)
  ?:  =('' stripe-key.s)  (send-err eyre-id 400 'stripe_key: not set')
  ;<  pr=[status=@ud body=@t]  bind:m
    (fetch (product-request:astripe stripe-url.s stripe-key.s name.u.p))
  ?.  (two-xx status.pr)  (send-err eyre-id 502 (stripe-why status.pr body.pr))
  =/  prod=(unit @t)  (read-id:astripe body.pr)
  ?~  prod  (send-err eyre-id 502 'stripe answered no product id')
  ::  a price on Stripe is in cents; a plan is in microdollars
  =/  cents=@ud  (div price.u.p 10.000)
  ;<  pz=[status=@ud body=@t]  bind:m
    %-  fetch
    (price-request:astripe stripe-url.s stripe-key.s u.prod cents interval.u.p)
  ?.  (two-xx status.pz)  (send-err eyre-id 502 (stripe-why status.pz body.pz))
  =/  made=(unit @t)  (read-id:astripe body.pz)
  ?~  made  (send-err eyre-id 502 'stripe answered no price id')
  =/  row=plan:arm  u.p(stripe-price u.made)
  ;<  ~  bind:m  (poke-plan (en-plan:arm row))
  (send-json eyre-id 200 (en-plan:arm row))
::  ==  accounts
::
++  serve-accounts
  |=  [eyre-id=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  q=@t  (fall (get-key:kv:html-utils 'q' args) '')
  ;<  all=(list [=account:arm keys=@ud])  bind:m  (all-accounts 1)
  =/  kept=(list [=account:arm keys=@ud])
    ?:  =('' q)  all
    %+  skim  all
    |=  [a=account:arm keys=@ud]
    ^-  ?
    =/  hay=tape  (trip (scot %p ship.a))
    =/  needle=tape  (trip q)
    !=(~ (find needle hay))
  =/  rows=(list json)
    %+  turn  kept
    |=  [a=account:arm keys=@ud]
    ^-  json
    (en-account-summary:arm a keys)
  (send-json eyre-id 200 a+rows)
::  +serve-account: one account with its public keys and the newest
::  hundred ledger rows
::
++  serve-account
  |=  [eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ;<  aj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (send-err eyre-id 404 'no such account')
  ;<  keys=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  =/  key-rows=(list json)
    %+  murn  ~(tap by km)
    |=  [id=@t j=json]
    ^-  (unit json)
    =/  k=(unit key:arm)  (de-key:arm j)
    ?~(k ~ `(en-key-public:arm u.k))
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 1 u.who)
  =/  sorted=(list row:arm)
    %+  turn
      %+  sort  rows
      |=  [x=[name=@ta =row:arm] y=[name=@ta =row:arm]]
      ^-  ?
      ?:  =(at.row.x at.row.y)  (aor name.y name.x)
      (gth at.row.x at.row.y)
    |=([nam=@ta r=row:arm] r)
  =/  newest=(list row:arm)  (scag 100 sorted)
  ::  what the customer has not fetched yet, by id and name. The secret
  ::  stays in pending.json and in that ship's own view.
  ;<  pend=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'pending.json'))
  =/  pm=(map @t json)  ?:(?=([%o *] pend) p.pend ~)
  =/  pend-rows=(list json)
    %+  turn  ~(tap by pm)
    |=  [id=@t j=json]
    ^-  json
    %-  pairs:enjs:format
    :~  ['id' s+id]
        ['name' s+(gs:arm j 'name')]
        ['nonce' s+(gs:arm j 'nonce')]
        ['made' s+(gs:arm j 'made')]
    ==
  ;<  cj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'checkouts.json'))
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['account' (en-account:arm u.a)]
      ['plan' s+plan.u.a]
      ::  the owner's own read, so the Stripe ids are in it
      ['subscription' (en-subscription:arm stripe-subscription.u.a renews.u.a &)]
      ['keys' a+key-rows]
      ['pending' a+pend-rows]
      ['checkouts' cj]
      ['ledger' a+(turn newest en-row:arm)]
  ==
::  +serve-mint: a new inference key. The account is opened when it is
::  not there yet. The secret is answered once and stored only as a
::  salted hash.
::
++  serve-mint
  |=  [eyre-id=@ta seg=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  =/  name=@t  (gs:arm jon 'name')
  ?:  |(=('' name) (gth (met 3 name) max-name:arm))
    (send-err eyre-id 400 'name: 1 to 200 bytes')
  ;<  aj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?:  ?&(?=(^ a) closed.u.a)  (send-err eyre-id 409 'account: closed')
  ;<  ~  bind:m
    ?^  a  (pure:(fiber:fiber:nexus ,~) ~)
    %+  poke-writer  1
    (pairs:enjs:format ~[['op' s+'open-account'] ['ship' s+(scot %p u.who)]])
  ;<  keys=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?:  (gte ~(wyt by km) max-keys:arm)  (send-err eyre-id 409 'keys: over 20')
  ;<  eny=@uvJ  bind:m  get-entropy:io
  ;<  now=@da  bind:m  get-time:io
  =/  id=@t  (id-of:arm eny)
  ?:  (~(has by km) id)  (send-err eyre-id 409 'id: taken, try again')
  =/  salt=@t  (scot %uv (end [3 10] (rsh [3 5] eny)))
  =/  secret=@t  (secret-of:arm (rsh [3 15] eny))
  =/  k=key:arm  [id name salt (hash-token:arm salt secret) now ~]
  =/  op=json
    %-  pairs:enjs:format
    :~  ['op' s+'add-key']
        ['ship' s+(scot %p u.who)]
        ['key' (en-key-row:arm k)]
    ==
  ;<  err=(unit tang)  bind:m  (poke-soft:io (rf 1 / %'main.sig') [[/ %json] op])
  ?^  err  (send-err eyre-id 500 'the writer refused the poke')
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['id' s+id]
      ['name' s+name]
      ['made' (en-time:arm now)]
      ['secret' s+(rap 3 id '.' secret ~)]
  ==
++  serve-revoke
  |=  [eyre-id=@ta seg=@ta kid=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ;<  keys=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  ?.  (~(has by km) `@t`kid)  (send-err eyre-id 404 'no such key')
  =/  op=json
    %-  pairs:enjs:format
    :~  ['op' s+'drop-key']
        ['ship' s+(scot %p u.who)]
        ['id' s+`@t`kid]
    ==
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['id' s+`@t`kid] ['ok' b+&]]))
::  +serve-credit, +serve-refund: the owner's own money rows. The ref
::  stamps the second, so two clicks in one second are one row and the
::  second answers 409.
::
++  serve-credit
  |=  [eyre-id=@ta seg=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (serve-money eyre-id seg jon 'credit')
++  serve-refund
  |=  [eyre-id=@ta seg=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  (serve-money eyre-id seg jon 'refund')
++  serve-money
  |=  [eyre-id=@ta seg=@ta jon=json kind=@t]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  =/  amount=@ud  (gn:arm jon 'amount')
  ?:  =(0 amount)  (send-err eyre-id 400 'amount: a whole number above zero')
  ;<  a=(unit account:arm)  bind:m  (live-account-at 1 u.who)
  ?~  a  (send-err eyre-id 404 'no open account')
  =/  given=@t  (gs:arm jon 'ref')
  ;<  now=@da  bind:m  get-time:io
  =/  stamp=tape  (a-co:co (unix-secs:arm now))
  =/  ref=@t  ?:(=('' given) (crip (weld "owner-" stamp)) given)
  ;<  rows=(list [name=@ta =row:arm])  bind:m  (ledger-of 1 u.who)
  ?:  (has-ref rows ref)  (send-err eyre-id 409 'ref: already recorded')
  =/  op=json
    %-  pairs:enjs:format
    :~  ['op' s+kind]
        ['ship' s+(scot %p u.who)]
        ['amount' (numb:enjs:format amount)]
        ['rail' s+'owner']
        ['ref' s+ref]
        ['note' s+(gs:arm jon 'note')]
    ==
  ;<  err=(unit tang)  bind:m  (poke-soft:io (rf 1 / %'main.sig') [[/ %json] op])
  ?^  err  (send-err eyre-id 500 'the writer refused the poke')
  =/  move=@sd  ?:(=('credit' kind) (sun:si amount) (new:si | amount))
  =/  bal=@sd  (sum:si balance.u.a move)
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['ship' s+(scot %p u.who)]
      ['ref' s+ref]
      ['amount' (numb:enjs:format amount)]
      ['balance' (en-sd:arm bal)]
  ==
++  live-account-at
  |=  [up=@ud who=@p]
  =/  m  (fiber:fiber:nexus ,(unit account:arm))
  ^-  form:m
  ;<  aj=json  bind:m  (read-json (rf up (acct-dir who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (pure:m ~)
  ?:  closed.u.a  (pure:m ~)
  (pure:m a)
++  serve-close
  |=  [eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ;<  aj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'account.json'))
  =/  a=(unit account:arm)  (de-account:arm aj)
  ?~  a  (send-err eyre-id 404 'no such account')
  =/  op=json
    (pairs:enjs:format ~[['op' s+'close-account'] ['ship' s+(scot %p u.who)]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['ship' s+(scot %p u.who)] ['closed' b+&]]))
::  +serve-drop-account: a hard delete, the gate's broom. The owner
::  alone may take it and nothing on the page calls it.
::
++  serve-drop-account
  |=  [eyre-id=@ta seg=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  who=(unit @p)  (ship-of seg)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ;<  ex=?  bind:m  (peek-exists:io (rv 1 (acct-dir u.who)))
  ?.  ex  (send-err eyre-id 404 'no such account')
  =/  op=json
    (pairs:enjs:format ~[['op' s+'drop-account'] ['ship' s+(scot %p u.who)]])
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-json eyre-id 200 (pairs:enjs:format ~[['ship' s+(scot %p u.who)] ['ok' b+&]]))
++  serve-log
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  log=json  bind:m  (read-json (rf 1 /tr %log))
  (send-json eyre-id 200 log)
::  ==  the inference API
::
::  +serve-models: the enabled catalog, rows whose provider still
::  exists, in OpenAI's list shape
::
++  serve-models
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  cat=(list model-row:arm)  bind:m  (catalog-of 1)
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  live=(list model-row:arm)
    (skim cat |=(r=model-row:arm (~(has by pm) provider.r)))
  (send-json eyre-id 200 (en-models-list:arm live))
::  +serve-proxy: spec section 5, steps 1 to 7. The owner's cookie is
::  refused here on purpose: the page must not double as a free client.
::
++  serve-proxy
  |=  [eyre-id=@ta act=actor jon=json kind=?(%chat %embeddings)]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?:  owner.act  (send-err eyre-id 403 'an inference key is required')
  ?.  ?=([%o *] jon)  (send-err eyre-id 400 'a JSON object is required')
  =/  want=@t  (gs:arm jon 'model')
  ;<  cat=(list model-row:arm)  bind:m  (catalog-of 1)
  =/  row=(unit model-row:arm)  (find-model:arm cat want)
  ?~  row  (send-err eyre-id 404 'model: not offered')
  ;<  pm=(map @t provider:arm)  bind:m  (providers-of 1)
  =/  p=(unit provider:arm)  (~(get by pm) provider.u.row)
  ?~  p  (send-err eyre-id 404 'model: not offered')
  ;<  a=(unit account:arm)  bind:m  (live-account-at 1 ship.act)
  ?~  a  (send-err eyre-id 403 'forbidden')
  ?.  (syn:si balance.u.a)  (send-err eyre-id 402 'balance: empty')
  ?:  =(--0 balance.u.a)  (send-err eyre-id 402 'balance: empty')
  ?:  (is-stream:arm jon)
    (send-err eyre-id 400 'stream: not supported on the proxy; take a lease')
  =/  body=json  (swap-model:arm jon upstream.u.row)
  =/  leaf=@t  ?:(?=(%chat kind) '/chat/completions' '/embeddings')
  ;<  res=[status=@ud body=@t]  bind:m
    (post-json (join-url base-url.u.p leaf) api-key.u.p body)
  ?:  =(0 status.res)
    %^  send-json  eyre-id  504
    %-  pairs:enjs:format
    :~  :-  'error'
        %-  pairs:enjs:format
        :~  :-  'message'
            :-  %s
            (rap 3 'no answer from ' name.u.p ' within two minutes' ~)
        ==
    ==
  ?.  &((gte status.res 200) (lth status.res 300))
    ::  the upstream's own body when it is JSON, else a line naming it
    =/  parsed=(unit json)  (de:json:html body.res)
    ?^  parsed  (send-raw eyre-id status.res body.res)
    =/  code=tape  (a-co:co status.res)
    =/  why=@t  (rap 3 name.u.p ' answered ' (crip code) ~)
    (send-err eyre-id status.res why)
  =/  usage=(unit [in=@ud out=@ud])  (read-usage:arm body.res)
  =/  toks=[in=@ud out=@ud]  ?~(usage [0 0] u.usage)
  =/  in-charge=@ud   (charge:arm in.toks in.u.row)
  =/  out-charge=@ud  ?:(?=(%chat kind) (charge:arm out.toks out.u.row) 0)
  =/  in-cost=@ud   (charge:arm in.toks cost-in.u.row)
  =/  out-cost=@ud  ?:(?=(%chat kind) (charge:arm out.toks cost-out.u.row) 0)
  =/  answer=json  (fall (de:json:html body.res) ~)
  =/  mode=@t  'proxy'
  =/  op=json
    %-  pairs:enjs:format
    :~  ['op' s+'debit']
        ['ship' s+(scot %p ship.act)]
        ['amount' (numb:enjs:format (add in-charge out-charge))]
        ['cost' (numb:enjs:format (add in-cost out-cost))]
        ['model' s+id.u.row]
        ['in' (numb:enjs:format in.toks)]
        ['out' (numb:enjs:format ?:(?=(%chat kind) out.toks 0))]
        ['mode' s+mode]
        ['ref' s+(gs:arm answer 'id')]
    ==
  ::  the debit is written before the answer goes out, so a crash
  ::  between the two costs the customer nothing and the owner one
  ::  request
  ;<  ~  bind:m  (poke-writer 1 op)
  (send-raw eyre-id status.res body.res)
::  ==  Talon's routes, on the customer ship
::
::  +nap: park this fiber for a span. Only a request fiber uses it, and
::  only to wait on something the client fiber is doing.
::
++  nap
  |=  span=@dr
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  wir=wire  bind:m  (nonce:io /nap)
  ;<  now=@da  bind:m  get-time:io
  ;<  ~  bind:m  (set-timer:io wir (add now span))
  ;<  ~  bind:m
    |=  input:fiber:nexus
    :+  ~  q.state
    ?+  in  [%skip ~]
        ~  [%wait ~]
        [~ %poke * *]
      ?.  =([/ %timer-wake] p.sage.u.in)  [%skip ~]
      ?.(=(wir !<(path q.sage.u.in)) [%skip ~] [%done ~])
    ==
  (cancel-timer:io wir)
::  +vendor-of: the ship this one buys from, or ~
::
++  vendor-of
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(unit @p))
  ^-  form:m
  ;<  vj=json  bind:m  (read-json (rf up / %'vendor.json'))
  (pure:m (slaw %p (gs:arm vj 'ship')))
::  +prod-client: wake the client fiber. The payload says why; what to
::  send is already in client.json.
::
++  prod-client
  |=  jon=json
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  *  bind:m  (poke-soft:io (rf 1 / %'client.sig') [[/ %json] jon])
  (pure:m ~)
::  +fresh-nonce: an op's idempotency key, from entropy
::
++  fresh-nonce
  =/  m  (fiber:fiber:nexus ,@t)
  ^-  form:m
  ;<  eny=@uvJ  bind:m  get-entropy:io
  (pure:m (secret-of:arm eny))
::  +queue-at: one op onto the send queue under a nonce we chose
::
++  queue-at
  |=  [n=@t payload=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  %+  poke-writer  1
  %-  pairs:enjs:format
  :~  ['op' s+'note-op']
      ['nonce' s+n]
      ['payload' payload]
      ['sent' b+|]
  ==
::  +held-keys: the inference keys this ship fetched
::
++  held-keys
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(list held-key:arm))
  ^-  form:m
  ;<  keys=json  bind:m  (read-json (rf up / %'keys.json'))
  =/  km=(map @t json)  ?:(?=([%o *] keys) p.keys ~)
  (pure:m (murn ~(tap by km) |=([k=@t j=json] (de-held:arm j))))
::  +serve-my-account: the view this ship last read, with who it came
::  from and how old it is. fresh=1 prods the client and waits.
::
++  serve-my-account
  |=  [eyre-id=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  fresh=?  =('1' (fall (get-key:kv:html-utils 'fresh' args) ''))
  ;<  our=@p  bind:m  get-our:io
  ;<  vj=json  bind:m  (read-json (rf 1 / %'vendor.json'))
  ;<  before=json  bind:m  (read-json (rf 1 / %'view.json'))
  ;<  ~  bind:m
    ?.  fresh  (pure:(fiber:fiber:nexus ,~) ~)
    (prod-client (pairs:enjs:format ~[['peek' b+&]]))
  ;<  doc=json  bind:m
    ?.  fresh  (pure:(fiber:fiber:nexus ,json) before)
    (await-fetched (gs:arm before 'fetched') 30)
  ;<  now=@da  bind:m  get-time:io
  =/  seen=(unit @da)  (gt:arm doc 'fetched')
  =/  stale=@ud
    ?~  seen  0
    ?:  (lth now u.seen)  0
    (div (sub now u.seen) ~s1)
  =/  base=(map @t json)  ?:(?=([%o *] doc) p.doc ~)
  =.  base  (~(put by base) 'vendor' s+(gs:arm vj 'ship'))
  =.  base  (~(put by base) 'self' s+(scot %p our))
  =.  base  (~(put by base) 'stale' (en-num:arm stale))
  (send-json eyre-id 200 [%o base])
::  +await-fetched: the view moved, or thirty seconds went by. The
::  answer is whatever is stored either way.
::
++  await-fetched
  |=  [was=@t left=@ud]
  =/  m  (fiber:fiber:nexus ,json)
  ^-  form:m
  ;<  doc=json  bind:m  (read-json (rf 1 / %'view.json'))
  ?.  =(was (gs:arm doc 'fetched'))  (pure:m doc)
  ?:  =(0 left)  (pure:m doc)
  ;<  ~  bind:m  (nudge left)
  ;<  ~  bind:m  (nap ~s1)
  (await-fetched was (dec left))
::  +serve-set-vendor: who this ship buys from. A fresh vendor is told
::  hello at once, which is what opens the account over there.
::
++  serve-set-vendor
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  got  (de-op-vendor:arm jon)
  ?:  ?=(%| -.got)  (send-err eyre-id 400 p.got)
  =/  txt=@t  ?~(p.got '' (scot %p u.p.got))
  ;<  ~  bind:m
    (poke-writer 1 (pairs:enjs:format ~[['op' s+'set-vendor'] ['ship' s+txt]]))
  ;<  ~  bind:m
    ?~  p.got  (pure:(fiber:fiber:nexus ,~) ~)
    ;<  n=@t  bind:(fiber:fiber:nexus ,~)  fresh-nonce
    (queue-at n (en-inbox:arm [%hello ~]))
  ;<  ~  bind:m  (prod-client (pairs:enjs:format ~[['peek' b+&]]))
  (send-json eyre-id 200 (pairs:enjs:format ~[['ship' s+txt] ['ok' b+&]]))
::  +serve-my-keys: the keys this ship holds, never their secrets
::
++  serve-my-keys
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  held=(list held-key:arm)  bind:m  (held-keys 1)
  (send-json eyre-id 200 a+(turn held en-held-public:arm))
::  +serve-my-mint: ask the vendor for a key and wait for it. Thirty
::  seconds without one is 202 with the nonce, not a failure: the op is
::  still queued and the next pass will land it.
::
++  serve-my-mint
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  name=@t  (gs:arm jon 'name')
  ?:  |(=('' name) (gth (met 3 name) max-name:arm))
    (send-err eyre-id 400 'name: 1 to 200 bytes')
  ;<  vendor=(unit @p)  bind:m  (vendor-of 1)
  ?~  vendor  (send-err eyre-id 409 'vendor: not set')
  ;<  held=(list held-key:arm)  bind:m  (held-keys 1)
  =/  before=(set @t)  (sy (turn held |=(k=held-key:arm id.k)))
  ;<  n=@t  bind:m  fresh-nonce
  ;<  ~  bind:m  (queue-at n (en-inbox:arm [%mint-key name n]))
  ;<  ~  bind:m  (prod-client (pairs:enjs:format ~[['peek' b+&]]))
  ;<  got=(unit held-key:arm)  bind:m  (await-key before 30)
  ?~  got
    %^  send-json  eyre-id  202
    (pairs:enjs:format ~[['pending' b+&] ['nonce' s+n]])
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['id' s+id.u.got]
      ['name' s+name.u.got]
      ['made' (en-time:arm made.u.got)]
      ['secret' s+(rap 3 id.u.got '.' secret.u.got ~)]
  ==
::  +await-key: a key id this ship did not hold a moment ago
::
++  await-key
  |=  [before=(set @t) left=@ud]
  =/  m  (fiber:fiber:nexus ,(unit held-key:arm))
  ^-  form:m
  ;<  held=(list held-key:arm)  bind:m  (held-keys 1)
  =/  fresh=(list held-key:arm)
    (skip held |=(k=held-key:arm (~(has in before) id.k)))
  ?^  fresh  (pure:m `i.fresh)
  ?:  =(0 left)  (pure:m ~)
  ::  a nudge every third second, so a pass that peeked a moment too
  ::  early is followed by one that does not
  ;<  ~  bind:m  (nudge left)
  ;<  ~  bind:m  (nap ~s1)
  (await-key before (dec left))
::  +nudge: prod the client every third second of a wait
::
++  nudge
  |=  left=@ud
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ?.  =(0 (mod left 3))  (pure:m ~)
  (prod-client (pairs:enjs:format ~[['peek' b+&]]))
::  +serve-my-revoke: the vendor is told to revoke it and this ship
::  forgets it at once, so a key that is gone here is gone here even if
::  the vendor is down
::
++  serve-my-revoke
  |=  [eyre-id=@ta id=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  held=(list held-key:arm)  bind:m  (held-keys 1)
  ?.  (lien held |=(k=held-key:arm =(id.k `@t`id)))
    (send-err eyre-id 404 'no such key')
  ;<  n=@t  bind:m  fresh-nonce
  ;<  ~  bind:m  (queue-at n (en-inbox:arm [%drop-key `@t`id]))
  ;<  ~  bind:m
    (poke-writer 1 (pairs:enjs:format ~[['op' s+'forget-key'] ['id' s+`@t`id]]))
  ;<  ~  bind:m  (prod-client (pairs:enjs:format ~[['peek' b+&]]))
  (send-json eyre-id 200 (pairs:enjs:format ~[['id' s+`@t`id] ['ok' b+&]]))
::  +serve-my-checkout: ask the vendor to open a checkout and wait for
::  the url to show in the view
::
++  serve-my-checkout
  |=  [eyre-id=@ta jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  rail=@t  (gs:arm jon 'rail')
  ?.  |(=('stripe' rail) =('btcpay' rail))
    (send-err eyre-id 400 'rail: stripe or btcpay')
  =/  plan=@t  (gs:arm jon 'plan')
  =/  amount=@ud  (gn:arm jon 'amount')
  ?:  &(=('' plan) =(0 amount))  (send-err eyre-id 400 'plan or amount required')
  ;<  vendor=(unit @p)  bind:m  (vendor-of 1)
  ?~  vendor  (send-err eyre-id 409 'vendor: not set')
  ;<  n=@t  bind:m  fresh-nonce
  ;<  ~  bind:m  (queue-at n (en-inbox:arm [%checkout rail plan amount n]))
  ;<  ~  bind:m  (prod-client (pairs:enjs:format ~[['peek' b+&]]))
  ;<  got=(unit json)  bind:m  (await-checkout n 30)
  ?~  got
    %^  send-json  eyre-id  202
    (pairs:enjs:format ~[['pending' b+&] ['nonce' s+n]])
  %^  send-json  eyre-id  200
  %-  pairs:enjs:format
  :~  ['nonce' s+n]
      ['url' s+(gs:arm u.got 'url')]
      ['status' s+(gs:arm u.got 'status')]
  ==
++  await-checkout
  |=  [n=@t left=@ud]
  =/  m  (fiber:fiber:nexus ,(unit json))
  ^-  form:m
  ;<  doc=json  bind:m  (read-json (rf 1 / %'view.json'))
  =/  row=json  (gj:arm (gj:arm doc 'checkouts') n)
  ?:  ?=([%o *] row)  (pure:m `row)
  ?:  =(0 left)  (pure:m ~)
  ;<  ~  bind:m  (nudge left)
  ;<  ~  bind:m  (nap ~s1)
  (await-checkout n (dec left))
::  +vendor-catalog: the vendor's public catalog, read live. Our own
::  ship is read locally; another ship is peeked, which needs the
::  vendor to have granted /public a peek on that file.
::
++  vendor-catalog
  |=  up=@ud
  =/  m  (fiber:fiber:nexus ,(unit json))
  ^-  form:m
  ;<  our=@p  bind:m  get-our:io
  ;<  vendor=(unit @p)  bind:m  (vendor-of up)
  ?:  ?|(?=(~ vendor) =(u.vendor our))
    ;<  jon=json  bind:m  (read-json (rf up / %'catalog-public.json'))
    (pure:m `jon)
  =/  road=road:tarball  [%& %& armillary-instance:arm %'catalog-public.json']
  ;<  vw=(unit view:nexus)  bind:m  (peek-remote-wait u.vendor road)
  ?.  ?=([~ %file *] vw)  (pure:m ~)
  (pure:m (sang-json sang.u.vw))
::  +serve-inference: the whole of Talon's integration. The newest key
::  this ship holds, the vendor's proxy base and what it sells.
::
++  serve-inference
  |=  eyre-id=@ta
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ;<  held=(list held-key:arm)  bind:m  (held-keys 1)
  ?~  held  (send-err eyre-id 404 'no key yet')
  =/  newest=held-key:arm
    %+  roll  `(list held-key:arm)`t.held
    |=  [k=held-key:arm best=_i.held]
    ?:((gth made.k made.best) k best)
  ;<  doc=json  bind:m  (read-json (rf 1 / %'view.json'))
  =/  base=@t  (rap 3 (public-url-of doc) '/apps/armillary/v1' ~)
  ;<  cat=(unit json)  bind:m  (vendor-catalog 1)
  =/  models=(list @t)
    ?.  ?=([~ %a *] cat)  ~
    (turn p.u.cat |=(j=json ^-(@t (gs:arm j 'id'))))
  =/  key=@t  (rap 3 id.newest '.' secret.newest ~)
  (send-json eyre-id 200 (inference-json:arm 'proxy' base key models))
::  ==  the stub checkout, public
::
::  +safe-nonce: a nonce as it may appear in a URL and in HTML. Only
::  these characters, so nothing that reaches the page has to be
::  escaped on the way out.
::
++  safe-nonce
  |=  t=@t
  ^-  ?
  =/  tap=tape  (trip t)
  ?:  ?|(?=(~ tap) (gth (lent tap) 64))  |
  %+  levy  `tape`tap
  |=  c=@t
  ^-  ?
  ?|  &((gte c 'a') (lte c 'z'))
      &((gte c 'A') (lte c 'Z'))
      &((gte c '0') (lte c '9'))
      =('-' c)
      =('_' c)
      =('.' c)
  ==
::  +serve-pay-page: the browser page a stub checkout URL opens. Public:
::  the ship paying has no login here. Nothing is written by the GET.
::
++  serve-pay-page
  |=  [eyre-id=@ta args=quay:eyre]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  raw=@t  (fall (get-key:kv:html-utils 'ship' args) '')
  =/  nonce=@t  (fall (get-key:kv:html-utils 'nonce' args) '')
  =/  who=(unit @p)  (slaw %p raw)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ?.  (safe-nonce nonce)  (send-err eyre-id 400 'nonce: 1 to 64 bytes')
  =/  ship=@t  (scot %p u.who)
  =/  parts=(list @t)
    :~  '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>armillary checkout</title></head><body>'
        '<h1>Stub checkout</h1>'
        '<p>Account <code>'
        ship
        '</code>, order <code>'
        nonce
        '</code>.</p>'
        '<p>This vendor is in stub mode. No money moves: paying credits the account so the whole loop can be run without a rail.</p>'
        '<form method="post" action="/apps/armillary/pay/stub?ship='
        ship
        '&amp;nonce='
        nonce
        '"><button type="submit">Pay</button></form>'
        '</body></html>'
    ==
  =/  heads  ~[['content-type' 'text/html; charset=utf-8'] ['cache-control' 'no-store']]
  (send-simple:srv eyre-id [[200 heads] `(as-octs:mimes:html (rap 3 parts))])
::  +serve-pay-stub: the button. In stub mode it credits the checkout's
::  amount and marks the row paid; the credit op dedupes on the ref, so
::  two clicks are one credit.
::
++  serve-pay-stub
  |=  [eyre-id=@ta args=quay:eyre jon=json]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  qship=@t  (fall (get-key:kv:html-utils 'ship' args) '')
  =/  raw=@t  ?:(=('' qship) (gs:arm jon 'ship') qship)
  =/  qnonce=@t  (fall (get-key:kv:html-utils 'nonce' args) '')
  =/  nonce=@t  ?:(=('' qnonce) (gs:arm jon 'nonce') qnonce)
  =/  who=(unit @p)  (slaw %p raw)
  ?~  who  (send-err eyre-id 400 'ship: not an @p')
  ?.  (safe-nonce nonce)  (send-err eyre-id 400 'nonce: 1 to 64 bytes')
  ;<  sj=json  bind:m  (read-json (rf 1 / %'settings.json'))
  ?:  =('live' (gs:arm sj 'mode'))  (send-err eyre-id 403 'stub mode only')
  ;<  cj=json  bind:m  (read-json (rf 1 (acct-dir u.who) %'checkouts.json'))
  =/  cm=(map @t json)  ?:(?=([%o *] cj) p.cj ~)
  =/  row=(unit json)  (~(get by cm) nonce)
  ?~  row  (send-err eyre-id 404 'no such checkout')
  =/  ship=@t  (scot %p u.who)
  =/  amount=@ud  (gn:arm u.row 'amount')
  ::  plans arrive in phase 3, so a plan checkout in stub mode is worth
  ::  ten dollars and nothing turns on the number
  =/  credit=@ud  ?:(=(0 amount) 10.000.000 amount)
  ;<  ~  bind:m
    %+  poke-writer  1
    %-  pairs:enjs:format
    :~  ['op' s+'credit']
        ['ship' s+ship]
        ['amount' (en-num:arm credit)]
        ['rail' s+'stub']
        ['ref' s+(rap 3 'stub-' nonce ~)]
        ['note' s+'stub checkout']
    ==
  ;<  ~  bind:m
    %+  poke-writer  1
    %-  pairs:enjs:format
    :~  ['op' s+'set-checkout']
        ['ship' s+ship]
        ['nonce' s+nonce]
        ['rail' s+(gs:arm u.row 'rail')]
        ['plan' s+(gs:arm u.row 'plan')]
        ['amount' (en-num:arm amount)]
        ['url' s+(gs:arm u.row 'url')]
        ['expires' s+(gs:arm u.row 'expires')]
        ['status' s+'paid']
    ==
  =/  heads  ~[['content-type' 'text/plain; charset=utf-8'] ['cache-control' 'no-store']]
  (send-simple:srv eyre-id [[200 heads] `(as-octs:mimes:html 'paid')])
::  ==  the page
::
::  +serve-file: one of the page's grubs, no-cache so an updated desk
::  shows at the next load
::
++  serve-file
  |=  [eyre-id=@ta name=@ta]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  ct=(unit @t)
    ?+  name  ~
      %'armillary.html'  `'text/html; charset=utf-8'
      %'armillary.css'   `'text/css; charset=utf-8'
      %'armillary.js'    `'text/javascript; charset=utf-8'
    ==
  ?~  ct  (send-err eyre-id 404 'no such file')
  ;<  vw=view:nexus  bind:m  (peek:io (rf 1 / name) `[/ %mime])
  ?.  ?=([%file *] vw)  (send-err eyre-id 404 'no such file')
  =/  got=(unit mime)  (mole |.(!<(mime (need-vase:tarball sang.vw))))
  ?~  got  (send-err eyre-id 500 'unreadable file')
  ::  nosniff: each of the three files is served with its own type, and
  ::  a browser must not guess a different one out of the bytes
  =/  heads
    :~  ['content-type' u.ct]
        ['cache-control' 'no-cache']
        ['x-content-type-options' 'nosniff']
    ==
  (send-simple:srv eyre-id [[200 heads] `q.u.got])
--
