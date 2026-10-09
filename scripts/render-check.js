// render-check.js: the page's pure render functions, run under node with
// no ship. `node scripts/render-check.js` prints ok or throws.
var r = require('../code/nex/armillary/armillary.js');
var now = Date.parse('2026-09-21T12:00:00Z');
var rows = [
  { kind: 'credit', amount: 5000000, at: '2026-09-01T00:00:00Z' },
  { kind: 'debit', amount: 39, cost: 30, mode: 'lease', model: '', in: 0, out: 0, at: '2026-09-21T10:00:00Z' },
  { kind: 'debit', amount: 1300, model: 'gpt-5', in: 100, out: 50, at: '2026-09-20T10:00:00Z' },
  { kind: 'debit', amount: 2600, model: 'gpt-5', in: 200, out: 100, at: '2026-09-19T10:00:00Z' },
  { kind: 'debit', amount: 9999, model: 'old', in: 1, out: 1, at: '2026-07-01T10:00:00Z' },
];
var u = r.usage(rows, now);
function is(c, m) { if (!c) throw new Error(m); }
is(u.month === 3939, 'month ' + u.month);
is(u.charges === 3, 'charges');
is(u.tokens === 450, 'tokens ' + u.tokens);
is(u.models[0].model === 'gpt-5' && u.models[0].amount === 3900, 'top model');
is(u.models[1].model === 'lease', 'a lease charge lands in its own bucket');
is(u.spent === 13938 && u.credited === 5000000, 'totals');
is(u.floor === false, 'floor');
var fifty = []; for (var i = 0; i < 50; i++) fifty.push(rows[1]);
is(r.usage(fifty, now).floor === true, 'fifty rows is a floor');
is(r.usageCard({ ledger: rows }).indexOf('gpt-5') > 0, 'the card names the model');
is(r.usageCard({ ledger: [] }).indexOf('No requests') > 0, 'the empty card');
is(r.myAccount({ vendor: '~nisfeb', balance: 1, ledger: rows }, []).indexOf('Usage') > 0, 'the account view carries usage');
is(r.myAccount({ vendor: '' }, []).indexOf('Provider mode') > 0, 'a ship with no vendor is told about provider mode');
var co = { n1: { status: 'pending', url: 'https://pay/x', amount: 5000000 }, n2: { status: 'cancelled', url: '', amount: 1 } };
is(r.checkoutRows(co, true).split('data-cancel-checkout').length === 2, 'only the pending row of the customer offers Cancel');
is(r.checkoutRows(co).indexOf('data-cancel-checkout') < 0, "the owner's view of an account offers no Cancel");
is(r.freshness({ stale: 120, fetched: 'x', fetch_ms: 2100 }).indexOf('2 min ago, in 2.1 s') > 0, 'the balance says its age and read time');
is(r.freshness({}).indexOf('Refresh reads it now') > 0, 'a balance never read says so');
var card = r.suggestedCard([{ id: 'a/b', enabled: true }, { id: 'c/d', enabled: false }]);
is(card.indexOf('Orrery generator') > 0 && card.indexOf('value="a/b"') > 0, 'the tier pickers offer what is sold');
is(card.indexOf('Talon decision gate') > 0 && card.indexOf('data-tier="decision"') > 0, 'every feature and the decision tier are there');
is(card.indexOf('value="c/d"') < 0, 'and not what is not');
var bc = r.braveCard({ key_set: true, searches: { '~lur': { '2026-10': 2 } } });
is(bc.indexOf('~lur') > 0 && bc.indexOf('2026-10: 2') > 0 && bc.indexOf('data-clear-brave') > 0, 'the Brave card counts each ship and offers removal');
is(r.braveCard({}).indexOf('no key set') > 0, 'a vendor without a key is told so');
console.log('render-check ok');
