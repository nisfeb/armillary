# Testing armillary

Armillary is tested on its own fleet set from
[hoon-development](https://github.com/nisfeb/hoon-development), never on
`~ricsul-bilwyt` or `~nisfeb`. A release is a push to `main` and a forge
pull (docs/releasing.md), so test here first.

| | |
|---|---|
| set | `armillary-dev` (in hoon-development's `fleet/sets.conf`) |
| ships | `~syx` (vendor), HTTP http://localhost:8124; `~dyr` (customer), HTTP http://localhost:8125; fake, linked, piers `~/fleet/piers/{syx,dyr}` |
| dojo | `tmux attach -t fleet`, windows `syx` and `dyr` |
| grubbery | the dev platform's pin (hoon-development `platform/grubbery.ref`) on both |
| armillary | a dev desk at `/apps/shell.shell/desks/armillary.desk` on both, following `/armillary-dev/code` in the ball; the whole ask approved |
| test desk | `%armillary-test` on both, mounted, set up for the kit |
| stubs | `scripts/dev-stubs.sh up`: provider 3410, Stripe 3411, BTCPay 3412, Brave 3413, all pointed at ~syx |

The set `armillary` (~sev, ~lur and the stubs on 3399 to 3402) belongs
to other sessions: never point anything here at it.

Below, `F=~/software/personal/hoon-development/fleet/fleet` and
`U=~/software/personal/hoon-development/bridge/u`. Set `FLEET_WHO` to
your session's name so claims know who is asking.

## Reset

```sh
$F reset armillary-dev compiled   # armillary on both, approved, test desks: ~16 s
$F reset armillary-dev            # golden: grubbery and %unix on both, no armillary
$F ls                             # are ~syx and ~dyr up?
$F up armillary-dev               # restart from the event logs (vere 4.6 sometimes segfaults)
$F down armillary-dev             # stop the set when you are done
```

Start every gate from `compiled`; the gates write accounts, plans and
settings. Refresh it after a deploy tests should start from:
`$F snap armillary-dev compiled`. For a throwaway point,
`$F --fast snap armillary-dev before-x` takes seconds.

## Offline tests (no ship)

```sh
scripts/offline-tests.sh                     # all five suites, 167 tests, ~12 s
scripts/offline-tests.sh armillary-stripe    # one suite
python3 scripts/hoon-test-kit/offline-test.py tests/lib/armillary.hoon test-<arm>
```

The five libs under `code/lib` are pure and import-free, so every suite
runs through `vere eval` with no ship: armillary 100, stripe 23, btcpay
18, openrouter 17, http 9. The ship run is the verdict.

## Ship tests

```sh
export VERE=~/software/vere-v4.6-linux-x86_64
scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/syx                  # 167 tests, ~9 s
scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/syx armillary-http   # one suite
node scripts/render-check.js                                          # the page's render, no ship
python3 scripts/code-closure.py code
python3 scripts/weir-check.py code/nex/armillary/app.hoon --io ~/fleet/piers/syx/grubbery/lib/fiberio.hoon
```

On a fresh golden make the test desk once per ship: `|new-desk
%armillary-test` and `|mount %armillary-test` in its dojo, then
`scripts/hoon-test-kit/hoon-test.sh ~/fleet/piers/<ship> setup`.

The gates, from `compiled`, with the stubs up:

```sh
J=/tmp/armillary-dev; mkdir -p $J
scripts/hoon-test-kit/ship-cookie.sh ~/fleet/piers/syx http://localhost:8124 $J/syx.jar
scripts/hoon-test-kit/ship-cookie.sh ~/fleet/piers/dyr http://localhost:8125 $J/dyr.jar
scripts/dev-stubs.sh up

python3 -u scripts/api-matrix.py http://localhost:8124 $J/syx.jar 3410 3411 3412   # 194 checks, ~8.5 min
$F reset armillary-dev compiled; scripts/dev-stubs.sh up

VENDOR_DOWN="tmux send-keys -t =fleet:syx C-d" \
VENDOR_UP="$F up armillary-dev" \
PROVIDER_PORT=3410 STRIPE_PORT=3411 BTCPAY_PORT=3412 BRAVE_PORT=3413 \
python3 -u scripts/ship-matrix.py http://localhost:8124 $J/syx.jar \
  http://localhost:8125 $J/dyr.jar                                          # 219 checks, ~29 min

python3 -u scripts/page-smoke.py http://localhost:8124 $J/syx.jar              # 15 checks, ~5 s
scripts/dev-stubs.sh down; $F reset armillary-dev compiled
```

`compiled` keeps the sessions the jars were minted for, so the jars work
after a reset. The stubs keep state, so restart them with each reset.
ship-matrix's offline section stops ~syx with Ctrl-D in its dojo (never
`|suspend`, which segfaulted vere 4.6) and brings it back with `fleet
up`, which starts only the ship that is down. `live-matrix.py` needs
real Stripe and BTCPay test credentials and is not run here.

## Deploying a change

```sh
scripts/dev-deploy.py http://localhost:8124 $J/syx.jar
scripts/dev-deploy.py http://localhost:8125 $J/dyr.jar
```

It mirrors `code/` into `/armillary-dev/code` and stamps that tree's
`version.json`, which makes the desk pull. `--add` makes the desk the
first time and approves the ask; `--approve` approves again without the
add. How `compiled` was made, from the golden: `dev-deploy.py ... --add`
on both ships (3 min each, in parallel; the platform's kernel parks
inbox, client and tick while jailed, and the script culls and reloads
them), then the test desks.

The scripts speak both kernels. Each asks `/grubbery/api/peek/apps/`
first. The current kernel answers it, keeps the shell at `/apps/shell`
and reads and writes through `/grubbery/api/peek`, `make` and `cull`.
An older kernel does not answer, keeps it at `/apps/shell.shell` and
goes through the explorer at `/grubbery/ball`, as below. On a ship whose
stock armillary desk follows the forge, `--add --replace` culls that
desk first. dev-deploy ends with what did not build and what is banged
under the desk, and exits 1 if anything is.

A `fleet clone` runs in its own network namespace, so it cannot reach
stubs on the host's loopback: every check that needs the provider, the
Stripe or BTCPay API or Brave fails there with a 504. Run the gates on
a set's own ships.

## Looking inside with u

```sh
$U armillary-dev our                    # ~syx
$U armillary-dev:dyr our                # ~dyr
$U armillary-dev kids /armillary-dev/code
$U armillary-dev kids /apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app
$U armillary-dev file /apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/tr/last
```

`u` guards its subcommands. A raw `.^` in an expression that misses
kills every thread on the ship: check a path with `kids` first. Over
HTTP, a ball `?raw=1` read answers 307 on this kernel, so follow it
(`curl -L`).
