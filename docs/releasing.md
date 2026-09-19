#  Releasing armillary: what makes ricsul update, and what makes its subscribers update

Armillary is a **stock desk app**: the source of truth is this git repo, the publisher is `~ricsul-bilwyt`, and every other ship gets it from ricsul. Two separate mechanisms move a change along that path, and they fail in different ways. This file is the same in nisfeb/lattice, nisfeb/auspex and nisfeb/calendar, because the mechanism is identical for all four and the thing that costs hours is not knowing which half you are looking at.

Written 2026-09-15 from the grubbery kernel source (`gub/nex/desk.hoon`) and from failures measured on `~ricsul-bilwyt`, `~martyr-sanryg` and `~wex` that day. Line references are to grubbery's `desk/gub/nex/desk.hoon`.

##  The short version

```
you: git push  (ref main)
  |
  |  ricsul's forge polls the remote every 15 min  (config.json "poll": 15)
  v
ricsul's forge repo         /apps/forge.git_forge/repos/armillary.git_repo/data/tree/code
  |
  |  ricsul's armillary.desk watches that tree's code/version.json
  |  and pulls when it DIFFERS from its own root version.json
  v
ricsul's desk               /apps/shell.shell/desks/armillary.desk/desk/code
  |
  |  ricsul REPUBLISHES the version file; subscribers watch that
  v
every subscriber's desk     source.json -> ~ricsul-bilwyt/apps/shell.shell/desks/armillary.desk/desk/code
```

**The single thing that makes anything update is `code/version.json` changing.** Not a new commit, not changed code: the version number. Everything below is detail on that one fact.

##  1. What makes ricsul update

Ricsul's forge repo tracks this repo. Its config:

```json
{"token":"","ref":"main","repo":"nisfeb/armillary","poll":15}
```

So a `git push` to `main` reaches ricsul **on its own within about 15 minutes**. There is no staging state for a desk app: pushing is deploying, on a timer.

To make it immediate instead of waiting for the poll:

```sh
POST https://urbit.sneagan.com/grubbery/forge/api/run
     {"repo":"armillary.git_repo","command":"pull"}
```

It answers `ok`, which means the forge accepted the command, **not** that the desk has rebuilt. The pull checks the repo out into the forge tree; the desk then has to notice.

Ricsul's armillary desk points at that tree:

```json
{"code":"/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code"}
```

A local path, not a ship. Ricsul reads its own forge. (Subscribers point at ricsul over ames instead; see §2.)

##  2. What makes ricsul's subscribers update

Every subscriber's armillary desk has a `source.json` naming ricsul:

```json
{"code":"~ricsul-bilwyt/apps/shell.shell/desks/armillary.desk/desk/code"}
```

The desk nexus keeps a subscription on the source's `code/version.json` (desk.hoon:163-186). On a `%news` for that file it runs `do-snapshot` then `sync-release`. **No user action is required**: nobody has to press Fetch Latest, and no consent prompt appears unless the release adds a road to `ask.json`.

The gate is exactly this (`+source-behind`):

```hoon
(pure:m !=(src-ver own))
```

An inequality between the source's `code/version.json` and the desk's own root `version.json`. Nothing else is compared: not file hashes, not commit ids, not timestamps.

`sync-release` then mirrors the code tree and **republishes the version file locally**, with the kernel's own comment explaining why:

> mirror the source's version file locally, under its own name, so followers of THIS desk watch our republished version

That is the relay hop. It is why a subscriber can itself be a publisher.

##  3. Therefore: bump `code/version.json` on every release

| what you did | what happens |
|---|---|
| changed code, bumped version | ricsul syncs, subscribers sync. Correct. |
| changed code, **forgot** the bump | **nothing propagates.** Ricsul's forge has your commit; no desk ever pulls it. Everything looks fine and nothing shipped. |
| bumped version, no code change | the version file syncs and nothing else does. `sync-dir` is content-addressed: only real changes write, so no nexus rebuilds. |

The second row is the common mistake and it is silent. The third row matters when you are trying to force a rebuild: a version-only bump will not do it.

##  4. Verifying a release actually landed

Check all four, in this order. Each separates a different failure.

```sh
# 1. did the forge fetch?
GET /grubbery/ball/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code/version.json?raw=1

# 2. did ricsul's desk mirror it?
GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/code/version.json?raw=1
GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/version.json?raw=1

# 3. did the instance rebuild, or is it BANGed?
GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app?info=1
#    bang: null  = healthy.  bang: "no built nexus %armillary--app ..." = dead.

# 4. does the route answer?
GET /apps/armillary        # fast 200/403 = alive.  hang = dead instance holding the route.
```

A version number is not proof. **The instance's `bang` is the proof**, and the route is the proof a user cares about.

##  5. The failure modes, all measured

###  5a. Version matches, code tree empty: wedged for ever

Measured on `~martyr-sanryg`, 2026-09-15. Its calendar desk read `{"version": 15}` at the root, ricsul published 15, and `code/` was **empty**: zero children. `source-behind` compared 15 to 15, answered "not behind", and never synced again. The desk page reported itself up to date. `/apps/armillary` hung for 30 seconds on every request.

The version gate is the trap: it suppresses the only thing that would refill the tree. The escape is the unconditional pull, which has no version gate:

```sh
POST /grubbery/desk/armillary/fetch-latest
```

(`+do-fetch`, desk.hoon: *"pull the source's current code now, unconditionally (no version gate)"*. The same thing runs from a `{"action":"fetch"}` poke at the desk's `main.sig`.)

###  5b. A BANGed instance is not healed by a successful sync

Same ship, same incident. After `fetch-latest` refilled the tree, `/nex/armillary/app.hoon` compiled cleanly in 11.8s, and the instance stayed BANGed. `reload-changed-nexuses` ran for 28ms and never visited it, because a nexus that never built has no recorded refs for a changed-refs walk to follow.

It came back only when the instance was reloaded explicitly. Over HTTP, that is a form-encoded POST to the instance's own explorer URL:

```sh
POST /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app
     action=reload-nexus
```

So: **a clean compile does not imply a live app.** Check the bang.

###  5c. A neck-less `/desk/code` never compiles anything

A `/desk/code` that was created as a plain directory, by an older kernel, or by hand, has no `[/ %code]` neck, and a dir without that neck is not a code namespace, so grubbery never runs `build-code` over it. Files land with the right marks and nothing compiles them. The desk page says "nothing to pull" while the app is dead.

`+ensure-code-nexus` repairs it. It used to run only when the desk nexus rose, which a subscriber does not do by itself; since 2026-09-15 it also runs from `sync-release`, so an arriving release repairs it. Check the neck with:

```sh
GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk?info=1
#    "code" child should have  neck: "/code"
```

###  5d. Symptom shapes

| symptom | usual cause |
|---|---|
| route **hangs** (no response, times out) | dead instance still holding the eyre binding |
| route **404s** | no instance bound at all |
| route **403s fast** | healthy; that is just unauthenticated |
| desk says up to date, app dead | 5a (empty tree) or 5c (neck-less dir) |

##  6. Desk apps and the kernel are delivered differently

Do not mix these up. Calendar, lattice, auspex and armillary are **desk apps**. Grubbery itself is the **kernel**.

| | desk app (calendar / lattice / auspex / armillary) | kernel (grubbery) |
|---|---|---|
| source of truth | this git repo | nisfeb/grubbery branch |
| how it reaches ricsul | `git push`, then forge poll or forge pull | `scp` to ricsul's mount, then `\|commit %grubbery` in the dojo |
| how it reaches subscribers | version bump, automatically | kiln desk sync, automatically |
| release unit | `code/version.json` | a clay commit |

Two notes on the kernel side, both learned the hard way:

- Touching `lib/*.hoon` or `app/grubbery.hoon` bumps the **gall agent**: the ship stops answering HTTP for minutes (~4.5 on `~wex`). Touching `gub/nex/*.hoon` only rebuilds a nexus, which is seconds.
- On ricsul, **deletions from the mount never reach clay**; adds and edits do.
- A `\|commit` that prints only `>=` with no rebuild means clay saw no change. That usually means it was already committed, not that the commit failed.

##  7. Testing before you ship

`~wex` is the fake test ship. Writing into a desk's code tree compiles **immediately**, with no commit, which is the fast loop:

```sh
POST /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/code/nex/armillary/app.hoon
     action=write-text  content=<the file>
```

Then read the instance's `?info=1`: `bang: null` means it compiled, and a non-null bang **carries the compile error with line and column**. That is about a minute per iteration. A file that does not exist yet needs `action=create-file&filename=<name>` first. `write-text` 404s on a missing file.

Fake ships derive every keypair from the `@p`, so anything key-dependent behaves differently there than on a real ship. Verify crypto paths on ricsul, not only on wex.

##  8. Armillary's own release checklist

1. `code/version.json` bumped, the number one higher than the last release.
2. `python3 scripts/code-closure.py code` reports nothing missing.
3. `python3 scripts/weir-check.py code/nex/armillary/app.hoon` reports no reached-but-undeclared road. A declared road nothing reaches yet is fine; the other direction is a veto waiting to happen.
4. Unit tests green on `~wex`, all three files, with `<rev>` the revision the `|commit %grubbery` before them printed: `-test /~wex/grubbery/<rev>/tests/lib/armillary ~`, then the same for `tests/lib/armillary-http` and `tests/lib/armillary-stripe`.
5. `python3 scripts/fake-provider.py 3399 stub-key` and `python3 scripts/fake-stripe.py 3400 whsec_gate http://localhost:8080` running in the background. The gates start nothing.
6. `python3 scripts/api-matrix.py http://localhost:8080 /tmp/wex.cookies 3399 3400` prints `ALL OK`, twice in a row. It sweeps the account, the provider and the plans it made before it starts and after it finishes, so a second run is a real second run, and it leaves the ship in stub mode with no Stripe key.
7. `python3 scripts/ship-matrix.py http://localhost:8080 /tmp/wex.cookies` prints `ALL OK`, twice in a row: the account channel and the card rail with the ship as its own customer. With `PEER PJAR` as well it runs the same sequence between two ships, which needs section 9's install recipe first.
8. `python3 scripts/page-smoke.py http://localhost:8080 /tmp/wex.cookies` prints `ALL OK`.
9. Open `/apps/armillary` on `~wex` in a browser with the owner cookie: add a provider, import, enable a row, mint a key, credit a dollar, and see the debit a completion leaves. On the Payments view, save a Stripe key, add a plan and put it on Stripe. With `vendor.json` naming `~wex` itself, click the Account, Keys and Catalog views too, and buy a plan from the Account view.
9a. `live-matrix.py` is not part of this checklist. It is the run by hand against Stripe test mode, with `STRIPE_TEST_KEY` in the environment, when a real key and a real card are available.
10. `git push origin main`, then on `~wex`: `POST /grubbery/forge/api/run {"repo":"armillary.git_repo","command":"pull"}`, and within a minute the desk's root `version.json` reads the new number and the instance's `bang` is `null`. The ask changes whenever the weir does, so re-approve it on `/apps/grubbery/permits` and reload after a release that added a road.
11. The ricsul steps are sneagan's: the catalog line, the kernel commit, the sync, the consent, the publish.

##  9. Ricsul before publishing: not there yet

As of 2026-09-19 armillary runs on `~wex` only. Nothing about it exists on `~ricsul-bilwyt`: no forge repo, no desk, no `published` line in `gub/nex/shell.hoon`, no entry in `permit/share.json`. Phase 1 is the vendor half against a stub provider, and the ship it is proved on is the dev ship.

Putting it on ricsul as an ordinary, unpublished desk, when a phase is ready for it, is the same three steps every other app in the family took:

1. A forge repo on ricsul: `{"repo":"nisfeb/armillary","ref":"main","poll":15}`.
2. A desk that follows that tree: `POST /apps/grubbery/desks/add {"name":"armillary","code":"/apps/forge.git_forge/repos/armillary.git_repo/data/tree/code"}`.
3. Grant the ask on `/apps/grubbery/permits`, then reload. Phase 1 asks for four pokes and one peek, and every later phase adds to that, so each one raises a fresh consent prompt.

From then on section 1 is how a release reaches it: bump `code/version.json`, push, and either wait for the poll or run the pull by hand.

Opening it to beta testers without publishing it:

1. Make a usergroup for them on ricsul, the way `/family` was made: a `<name>.grp` directory under `/sys/ames/usergroups` with the testers' ships in `who.ships`.
2. Open the desk to that group: on `/grubbery/desk/armillary`, under "Usergroups allowed to peek /desk/code", add `/<name>`. Over HTTP that is `POST /grubbery/desk/armillary/share {"add":"/<name>"}`, and `{"remove":"/<name>"}` closes it again. The grant is peek on `/desk/code` and the version file, nothing else.
3. Each tester, on a ship running grubbery: `POST /apps/grubbery/desks/add {"name":"armillary","code":"~ricsul-bilwyt/apps/shell.shell/desks/armillary.desk/desk/code"}`, then approve the ask when the desk prompts, then open `/apps/armillary`.

A vendor is not a thing you hand out casually: whoever installs armillary and points it at a real provider key is spending the owner's money on that key. Publishing proper is the stock desk line beside calendar's in `gub/nex/shell.hoon` and opening the desk to `/public`; nothing about a beta group has to be undone first.

### Two ships from one, for the channel gate

`scripts/ship-matrix.py` with four arguments runs the account channel between two ships, which needs armillary installed on both. With `~wex` as the vendor and `~feb` as the customer, over HTTP with each ship's owner cookie:

1. On `~wex`, open the desk's code to every ship: `POST /grubbery/desk/armillary/share {"add":"/public"}`.
2. On `~feb`, follow it: `POST /apps/grubbery/desks/add {"name":"armillary","code":"~wex/apps/shell.shell/desks/armillary.desk/desk/code"}`.
3. Poll `~feb`'s instance until the code arrives and the compile settles: `GET /grubbery/ball/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app?info=1` every fifteen seconds, for at most three minutes. A bang string is a compile error, not a slow sync.
4. Approve the ask on `~feb`: `POST /apps/grubbery/permits {"action":"approve-weir","app":"/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app","granted":{"poke":["/sys/bowl.sig","/sys/eyre/","/sys/iris/","/sys/behn/","/sys/gall/","/sys/ames/registry"],"peek":["/sys/link/","/sys/ames/ships/","/sys/ames/usergroups/"],"make":["/sys/ames/usergroups/"]}}`, then `POST /apps/grubbery/permits/reload {"app":"<the same app path>"}`, then read the weir back.
5. Run the gate: `python3 scripts/ship-matrix.py http://localhost:8080 <wex jar> http://localhost:8081 <feb jar>`, with the stub provider listening on 3399.

A customer ship needs the four customer roads and nothing else, but the ten-road grant is what the desk asks for and approving it whole is one prompt rather than an argument about which half of the app this ship is.

Two ships on different grubbery generations can print `send to ~feb timed out` on the console for a poke that landed. The code treats a timeout as unknown rather than failure and peeks the view, which is the truth; the gate does the same.
