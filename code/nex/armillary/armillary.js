// armillary's vendor page: providers, the catalog and accounts over
// /apps/armillary/api. Pure render functions first, then the app that
// wires them to the API and the beacon stream.
(function () {
  'use strict';
  var API = '/apps/armillary/api';
  var V1 = '/apps/armillary/v1';
  var KEEP = '/grubbery/api/keep/apps/shell.shell/desks/armillary.desk/desk/data/armillary.armillary_app/beacon/rev';

  // ---- render, pure ----
  function esc(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[<>&"']/g, function (c) {
      return { '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  // every amount on the ship is an integer of microdollars: one dollar
  // is a million. The page is the only place dollars exist.
  function dollars(micro, places) {
    var n = Number(micro || 0) / 1000000;
    return n.toFixed(places === undefined ? 2 : places);
  }
  function micro(text) {
    var n = parseFloat(String(text === null || text === undefined ? '' : text).replace(/[$,\s]/g, ''));
    if (!isFinite(n)) return null;
    return Math.round(n * 1000000);
  }
  function fmtTime(t) { return t ? esc(String(t).replace('T', ' ').replace('Z', '')) : ''; }
  function signed(micro) {
    var n = Number(micro || 0);
    return '<span class="' + (n < 0 ? 'neg' : '') + '">' + esc(dollars(n)) + '</span>';
  }
  // the margin a row earns, when the upstream cost is known
  function margin(row) {
    var cost = Number(row.cost_in || 0) + Number(row.cost_out || 0);
    var price = Number(row.in || 0) + Number(row.out || 0);
    if (!cost) return '';
    return Math.round(((price - cost) / cost) * 100) + '%';
  }
  function thead(cols) {
    return '<table><thead><tr>' + cols.map(function (c) {
      return '<th scope="col"' + (c.num ? ' class="num"' : '') + '>' + esc(c.name || c) + '</th>';
    }).join('') + '</tr></thead><tbody>';
  }
  function cell(label, html, cls) {
    return '<td data-label="' + esc(label) + '"' + (cls ? ' class="' + cls + '"' : '') + '>' + html + '</td>';
  }

  function providers(rows, tests, edit) {
    var out = '<h1>Providers</h1>';
    if (!rows.length) out += '<p class="muted">No providers yet. Add one below.</p>';
    else {
      out += '<div class="card">' + thead(['Id', 'Name', 'Kind', 'Base URL', 'Key', '']);
      rows.forEach(function (p) {
        var t = tests[p.id];
        out += '<tr>' +
          cell('Id', '<code>' + esc(p.id) + '</code>') +
          cell('Name', esc(p.name)) +
          cell('Kind', esc(p.kind)) +
          cell('URL', esc(p.base_url)) +
          cell('Key', '<code>' + esc(p.api_key || 'not set') + '</code>') +
          cell('', '<button data-test="' + esc(p.id) + '">Test</button>' +
            '<button data-import="' + esc(p.id) + '">Import</button>' +
            '<button data-edit="' + esc(p.id) + '">Edit</button>' +
            '<button class="danger" data-drop="' + esc(p.id) + '">Delete</button>' +
            (t ? '<div class="result' + (t.bad ? ' bad' : '') + '">' + esc(t.text) + '</div>' : '')) +
          '</tr>';
      });
      out += '</tbody></table></div>';
    }
    var cur = edit ? (rows.filter(function (p) { return p.id === edit; })[0] || null) : null;
    out += form(cur);
    return out;
  }
  // the add form, or the same form filled for an edit. On an edit the id
  // is fixed and the two secrets read as their masks: blank keeps them.
  function form(p) {
    var open = p || { id: '', name: '', kind: 'openai-compatible', base_url: '' };
    var or = open.kind === 'openrouter';
    var hold = p ? ' placeholder="leave blank to keep"' : '';
    return '<div class="card" id="provider-form">' +
      '<h2>' + (p ? 'Edit ' + esc(p.id) : 'Add a provider') + '</h2>' +
      '<div class="inline">' +
      '<div class="field"><label for="p-id">Id</label><input id="p-id" name="id" value="' + esc(open.id) + '"' + (p ? ' readonly' : '') + '></div>' +
      '<div class="field"><label for="p-name">Name</label><input id="p-name" name="name" value="' + esc(open.name) + '"></div>' +
      '<div class="field"><label>Kind</label>' +
      '<label><input type="radio" name="kind" value="openai-compatible"' + (or ? '' : ' checked') + '> openai-compatible</label> ' +
      '<label><input type="radio" name="kind" value="openrouter"' + (or ? ' checked' : '') + '> openrouter</label></div>' +
      '<div class="field wide"><label for="p-url">Base URL</label><input id="p-url" name="base_url" value="' + esc(open.base_url) + '"></div>' +
      '<div class="field"><label for="p-key">API key</label><input id="p-key" name="api_key" type="password"' + hold + '></div>' +
      '<div class="field" id="p-prov"' + (or ? '' : ' hidden') + '><label for="p-pkey">Provisioning key</label><input id="p-pkey" name="provisioning_key" type="password"' + hold + '></div>' +
      '</div>' +
      '<button data-save-provider="' + esc(open.id) + '">' + (p ? 'Save' : 'Add') + '</button>' +
      (p ? '<button data-cancel-edit="1">Cancel</button>' : '') +
      '</div>';
  }

  function catalog(rows, filter) {
    var f = String(filter || '').toLowerCase();
    var kept = rows.filter(function (r) {
      return !f || String(r.id).toLowerCase().indexOf(f) >= 0 || String(r.provider).toLowerCase().indexOf(f) >= 0;
    });
    var out = '<h1>Catalog</h1><div class="card">' +
      '<div class="field"><label for="cat-filter">Filter</label>' +
      '<input id="cat-filter" type="search" value="' + esc(filter || '') + '" placeholder="id or provider"></div>' +
      '<button data-save-catalog="1">Save catalog</button>' +
      '<span class="muted"> ' + kept.length + ' of ' + rows.length + ' rows</span></div>';
    if (!rows.length) return out + '<p class="muted">Nothing in the catalog. Import from a provider first.</p>';
    out += '<div class="card">' + thead(['Id', 'Provider',
      { name: 'In $/M', num: true }, { name: 'Out $/M', num: true },
      { name: 'Cost in', num: true }, { name: 'Cost out', num: true },
      { name: 'Margin', num: true }, 'On', 'Tags']);
    kept.forEach(function (r) {
      out += '<tr>' +
        cell('Id', '<code>' + esc(r.id) + '</code>') +
        cell('Provider', esc(r.provider)) +
        cell('In', '<input class="price" data-row="' + esc(r.id) + '" data-field="in" value="' + esc(dollars(r.in, 4)) + '">', 'num') +
        cell('Out', '<input class="price" data-row="' + esc(r.id) + '" data-field="out" value="' + esc(dollars(r.out, 4)) + '">', 'num') +
        cell('Cost in', esc(dollars(r.cost_in, 4)), 'num') +
        cell('Cost out', esc(dollars(r.cost_out, 4)), 'num') +
        cell('Margin', esc(margin(r)), 'num') +
        cell('On', '<input type="checkbox" data-row="' + esc(r.id) + '" data-field="enabled"' + (r.enabled ? ' checked' : '') + '>') +
        cell('Tags', '<input class="tags" data-row="' + esc(r.id) + '" data-field="tags" value="' + esc((r.tags || []).join(', ')) + '">') +
        '</tr>';
    });
    return out + '</tbody></table></div>';
  }

  function accounts(rows, search) {
    var f = String(search || '').toLowerCase();
    var kept = rows.filter(function (a) { return !f || String(a.ship).toLowerCase().indexOf(f) >= 0; });
    // an account opens when its first key is minted, so the way in to a
    // ship with no account yet is its own detail page
    var open_form = '<div class="card"><h2>Open an account</h2>' +
      '<div class="inline"><div class="field"><label for="acct-open">Ship</label>' +
      '<input id="acct-open" value="" placeholder="~feb"></div>' +
      '<div class="field"><label>&nbsp;</label><button data-open="1">Open</button></div></div></div>';
    var out = '<h1>Accounts</h1><div class="card">' +
      '<div class="field"><label for="acct-search">Search</label>' +
      '<input id="acct-search" type="search" value="' + esc(search || '') + '" placeholder="a ship"></div></div>';
    if (!kept.length) return out + open_form + '<p class="muted">No accounts yet. One opens when you mint a key.</p>';
    out += '<div class="card">' + thead(['Ship', { name: 'Balance', num: true }, { name: 'Keys', num: true }, 'Last seen', 'State']);
    kept.forEach(function (a) {
      out += '<tr' + (a.closed ? ' class="closed"' : '') + '>' +
        cell('Ship', '<a href="#accounts/' + esc(a.ship) + '">' + esc(a.ship) + '</a>') +
        cell('Balance', signed(a.balance), 'num') +
        cell('Keys', esc(a.keys), 'num') +
        cell('Seen', fmtTime(a.seen)) +
        cell('State', a.closed ? 'closed' : 'open') +
        '</tr>';
    });
    return out + '</tbody></table></div>' + open_form;
  }

  // d is null when the ship has no account yet: the view still draws, so
  // the owner can mint the first key, which is what opens one
  function account(ship, d, minted) {
    var fresh = !d;
    var a = (d && d.account) || { ship: ship, balance: 0, closed: false };
    var keys = (d && d.keys) || [];
    var rows = (d && d.ledger) || [];
    var out = '<h1>' + esc(ship) + '</h1>' +
      '<p><a href="#accounts">All accounts</a></p>' +
      '<div class="card"><h2>Balance</h2><p style="font-size:1.6rem;margin:.2rem 0">' + signed(a.balance) + '</p>' +
      '<p class="muted">' + (fresh ? 'No account yet. Minting a key opens one.'
        : 'Opened ' + fmtTime(a.made) + (a.closed ? ' &middot; closed' : '')) + '</p>' +
      '<div class="inline">' +
      '<div class="field"><label for="c-amount">Credit, dollars</label><input id="c-amount" value=""></div>' +
      '<div class="field"><label for="c-note">Note</label><input id="c-note" value=""></div>' +
      '<div class="field"><label>&nbsp;</label><button data-credit="1">Credit</button></div>' +
      '<div class="field"><label for="r-amount">Refund, dollars</label><input id="r-amount" value=""></div>' +
      '<div class="field"><label for="r-note">Note</label><input id="r-note" value=""></div>' +
      '<div class="field"><label>&nbsp;</label><button data-refund="1">Refund</button></div>' +
      '</div>' +
      (a.closed ? '' : '<button class="danger" data-close="1">Close account</button>') +
      '</div>';
    // the owner's own read, so the Stripe ids are here; the customer's
    // view of the same account never carries them
    var sub = (d && d.subscription) || {};
    if (sub.active) {
      out += '<div class="card"><h2>Subscription</h2><p>Plan <code>' +
        esc((d && d.plan) || '') + '</code>' +
        (sub.renews ? ', renews ' + fmtTime(sub.renews).slice(0, 10) : '') + '</p>' +
        '<p class="muted">Stripe <code>' + esc(sub.id || '') + '</code>, customer <code>' +
        esc(a.stripe_customer || '') + '</code></p>' +
        '<button class="danger" data-clear-sub="1">Clear</button></div>';
    }
    out += '<div class="card"><h2>Keys</h2>';
    if (minted) {
      out += '<div class="secret"><p>Copy this now. The ship keeps only a salted hash of it.</p>' +
        '<code>' + esc(minted.secret) + '</code>' +
        '<p><button data-dismiss="1">Done</button></p></div>';
    }
    if (!keys.length) out += '<p class="muted">No keys.</p>';
    else {
      out += thead(['Id', 'Name', 'Made', 'Last used', '']);
      keys.forEach(function (k) {
        out += '<tr>' +
          cell('Id', '<code>' + esc(k.id) + '</code>') +
          cell('Name', esc(k.name)) +
          cell('Made', fmtTime(k.made)) +
          cell('Used', fmtTime(k.used)) +
          cell('', '<button class="danger" data-revoke="' + esc(k.id) + '" data-name="' + esc(k.name) + '">Revoke</button>') +
          '</tr>';
      });
      out += '</tbody></table>';
    }
    if (!a.closed) {
      out += '<div class="inline"><div class="field"><label for="k-name">New key name</label>' +
        '<input id="k-name" value=""></div>' +
        '<div class="field"><label>&nbsp;</label><button data-mint="1">Mint a key</button></div></div>';
    }
    out += '</div>';
    out += leaseCard(d);
    // the same renderer the customer reads, so the owner sees each
    // checkout's rail and where it got to
    out += checkoutRows(d && d.checkouts);
    out += '<div class="card"><h2>Ledger</h2>';
    if (!rows.length) out += '<p class="muted">Nothing yet.</p>';
    else {
      out += thead(['At', 'Kind', { name: 'Amount', num: true }, 'Model', { name: 'Tokens', num: true }, 'Ref']);
      rows.forEach(function (r) {
        out += '<tr>' +
          cell('At', fmtTime(r.at)) +
          cell('Kind', esc(r.kind)) +
          cell('Amount', esc(dollars(r.amount)), 'num') +
          cell('Model', esc(r.model)) +
          cell('Tokens', r.kind === 'debit' ? esc(r.in + ' in, ' + r.out + ' out') : '', 'num') +
          cell('Ref', '<code>' + esc(r.ref) + '</code>') +
          '</tr>';
      });
      out += '</tbody></table>';
    }
    return out + '</div>';
  }

  // the owner's half of a lease: the hash and the figures, never the
  // key. The key lives on the vendor and in that ship's own view.
  function leaseCard(d) {
    var l = d && d.lease;
    var err = (d && d.lease_error) || '';
    var out = '<div class="card"><h2>Lease</h2>';
    if (err) out += '<p class="neg">' + esc(err) + '</p>';
    if (!l) return out + '<p class="muted">No lease.</p></div>';
    return out + '<p>Key <code>' + esc(l.hash) + '</code> on <code>' + esc(l.provider) + '</code>' +
      (l.disabled ? ' &middot; <span class="neg">disabled</span>' : '') + '</p>' +
      '<p>Spent $' + esc(dollars(l.usage_seen)) + ' against a $' + esc(dollars(l.limit)) +
      ' cap, read ' + fmtTime(l.checked) + '</p>' +
      '<button data-reconcile="1">Reconcile now</button> ' +
      '<button class="danger" data-drop-lease="1">Drop lease</button></div>';
  }

  // ---- payments, the vendor's half ----
  var STRIPE_DEFAULT = 'https://api.stripe.com';
  function planRows(plans, withStripe) {
    var out = thead(['Id', 'Name', 'Kind', { name: 'Price', num: true },
      { name: 'Credit', num: true }, 'Interval', 'Stripe price', '']);
    plans.forEach(function (p) {
      var sp = p.stripe_price
        ? '<code>' + esc(p.stripe_price) + '</code>'
        : (p.kind === 'subscription' && withStripe
          ? '<button data-plan-stripe="' + esc(p.id) + '">Create on Stripe</button>'
          : '<span class="muted">not needed</span>');
      out += '<tr>' +
        cell('Id', '<code>' + esc(p.id) + '</code>') +
        cell('Name', esc(p.name)) +
        cell('Kind', esc(p.kind)) +
        cell('Price', esc(dollars(p.price)), 'num') +
        cell('Credit', esc(dollars(p.credit)), 'num') +
        cell('Interval', esc(p.interval || '')) +
        cell('Stripe', sp) +
        cell('', '<button data-plan-edit="' + esc(p.id) + '">Edit</button>' +
          '<button class="danger" data-plan-drop="' + esc(p.id) + '">Delete</button>') +
        '</tr>';
    });
    return out + '</tbody></table>';
  }
  function planForm(p) {
    var open = p || { id: '', name: '', kind: 'topup', price: 0, credit: 0, interval: 'month' };
    var sub = open.kind === 'subscription';
    return '<div class="card" id="plan-form"><h2>' +
      (p ? 'Edit ' + esc(p.id) : 'Add a plan') + '</h2><div class="inline">' +
      '<div class="field"><label for="pl-id">Id</label><input id="pl-id" value="' + esc(open.id) + '"' + (p ? ' readonly' : '') + '></div>' +
      '<div class="field"><label for="pl-name">Name</label><input id="pl-name" value="' + esc(open.name) + '"></div>' +
      '<div class="field"><label>Kind</label>' +
      '<label><input type="radio" name="plan-kind" value="topup"' + (sub ? '' : ' checked') + '> top-up</label> ' +
      '<label><input type="radio" name="plan-kind" value="subscription"' + (sub ? ' checked' : '') + '> subscription</label></div>' +
      '<div class="field"><label for="pl-price">Price, dollars</label><input id="pl-price" value="' + esc(dollars(open.price)) + '"></div>' +
      '<div class="field"><label for="pl-credit">Credit, dollars</label><input id="pl-credit" value="' + esc(dollars(open.credit)) + '"></div>' +
      '<div class="field"><label for="pl-interval">Interval</label>' +
      '<select id="pl-interval"><option value="month"' + (open.interval === 'year' ? '' : ' selected') + '>month</option>' +
      '<option value="year"' + (open.interval === 'year' ? ' selected' : '') + '>year</option></select></div>' +
      '</div><button data-plan-save="' + esc(open.id) + '">' + (p ? 'Save' : 'Add') + '</button>' +
      (p ? '<button data-plan-cancel="1">Cancel</button>' : '') + '</div>';
  }
  // which provider's provisioning key mints leases. Only an OpenRouter
  // provider can: no other kind has a per-customer capped key.
  function leaseSetting(s, provs) {
    var rows = (provs || []).filter(function (p) { return p.kind === 'openrouter'; });
    var out = '<div class="card"><h2>Leases</h2>' +
      '<p class="muted">A lease is a real provider key capped at the customer\'s balance, so a client calls the provider directly. Pick the OpenRouter provider whose provisioning key mints them; none means this vendor offers no leases.</p>';
    if (!rows.length) {
      return out + '<p class="muted">No OpenRouter provider yet. Add one with a provisioning key under Providers.</p></div>';
    }
    out += '<div class="inline"><div class="field"><label for="ls-prov">Lease provider</label>' +
      '<select id="ls-prov"><option value=""' + (s.lease_provider ? '' : ' selected') + '>none</option>';
    rows.forEach(function (p) {
      out += '<option value="' + esc(p.id) + '"' +
        (s.lease_provider === p.id ? ' selected' : '') + '>' + esc(p.name || p.id) + '</option>';
    });
    return out + '</select></div><div class="field"><label>&nbsp;</label>' +
      '<button data-save-lease="1">Save</button></div></div></div>';
  }
  function payments(st, plans, log, editing, provs) {
    var s = st || {};
    var pub = s.public_url || '';
    var hook = (pub || 'your public URL') + '/apps/armillary/hooks/stripe';
    var out = '<h1>Payments</h1><div class="card"><h2>Stripe</h2>' +
      '<p class="muted">The key and the signing secret are shown masked. Leave a field blank to keep what is stored.</p>' +
      '<div class="inline">' +
      '<div class="field"><label for="st-key">Secret key</label>' +
      '<input id="st-key" type="password" placeholder="leave blank to keep"></div>' +
      '<div class="field"><label for="st-hook">Webhook signing secret</label>' +
      '<input id="st-hook" type="password" placeholder="leave blank to keep"></div>' +
      '<div class="field"><label for="st-pub">Public URL</label>' +
      '<input id="st-pub" value="' + esc(pub) + '" placeholder="https://your.ship"></div>' +
      '<div class="field"><label>Mode</label>' +
      '<label><input type="radio" name="st-mode" value="stub"' + (s.mode === 'live' ? '' : ' checked') + '> stub</label> ' +
      '<label><input type="radio" name="st-mode" value="live"' + (s.mode === 'live' ? ' checked' : '') + '> live</label></div>' +
      '</div>' +
      '<p>Key <code>' + esc(s.stripe_key || 'not set') + '</code>, ' +
      'signing secret <code>' + esc(s.stripe_webhook_secret || 'not set') + '</code></p>' +
      (s.stripe_url && s.stripe_url !== STRIPE_DEFAULT
        ? '<p class="muted">API base <code>' + esc(s.stripe_url) + '</code>, not Stripe itself.</p>' : '') +
      '<p class="muted">Paste this into Stripe as the endpoint: <code>' + esc(hook) + '</code></p>' +
      '<button data-save-stripe="1">Save</button></div>';
    var bhook = (pub || 'your public URL') + '/apps/armillary/hooks/btcpay';
    out += '<div class="card"><h2>BTCPay Server</h2>' +
      '<p class="muted">One invoice offers on chain and Lightning. The api key and the webhook secret are shown masked. Leave a field blank to keep what is stored.</p>' +
      '<div class="inline">' +
      '<div class="field"><label for="bt-url">Instance URL</label>' +
      '<input id="bt-url" value="' + esc(s.btcpay_url || '') + '" placeholder="https://btcpay.example.com"></div>' +
      '<div class="field"><label for="bt-store">Store id</label>' +
      '<input id="bt-store" value="' + esc(s.btcpay_store || '') + '"></div>' +
      '<div class="field"><label for="bt-key">API key</label>' +
      '<input id="bt-key" type="password" placeholder="leave blank to keep"></div>' +
      '<div class="field"><label for="bt-hook">Webhook secret</label>' +
      '<input id="bt-hook" type="password" placeholder="leave blank to keep"></div>' +
      '</div>' +
      '<p>Key <code>' + esc(s.btcpay_key || 'not set') + '</code>, ' +
      'webhook secret <code>' + esc(s.btcpay_webhook_secret || 'not set') + '</code></p>' +
      '<p class="muted">Add a webhook on the store pointing at <code>' + esc(bhook) + '</code> ' +
      'with the events InvoiceSettled, InvoiceProcessing, InvoiceExpired and InvoiceInvalid.</p>' +
      '<p class="muted">Subscriptions are card only. A bitcoin customer tops up.</p>' +
      '<button data-save-btcpay="1">Save</button></div>';
    out += '<div class="card"><h2>Plans</h2>' +
      (plans.length ? planRows(plans, !!s.stripe_key) : '<p class="muted">No plans yet.</p>') +
      '</div>';
    var cur = editing ? (plans.filter(function (p) { return p.id === editing; })[0] || null) : null;
    out += planForm(cur);
    out += leaseSetting(s, provs);
    out += ringCard('Recent Stripe outcomes', 'stripe.', log);
    out += ringCard('Recent BTCPay outcomes', 'btcpay.', log);
    return out;
  }
  // the last ten ring rows whose op starts with one rail's name
  function ringCard(title, prefix, log) {
    var rows = (log || []).filter(function (r) {
      return String(r.op || '').indexOf(prefix) === 0;
    }).slice(0, 10);
    var out = '<div class="card"><h2>' + esc(title) + '</h2>';
    if (!rows.length) return out + '<p class="muted">Nothing yet.</p></div>';
    out += thead(['At', 'What', 'Ok', 'Why']);
    rows.forEach(function (r) {
      out += '<tr>' +
        cell('At', fmtTime(r.at)) +
        cell('What', esc(r.op)) +
        cell('Ok', r.ok ? 'yes' : 'no') +
        cell('Why', esc(r.why || '')) +
        '</tr>';
    });
    return out + '</tbody></table></div>';
  }

  // ---- the customer's own views ----
  // the ledger table is the same one the owner reads, so one renderer
  // serves both sides
  function ledger(rows) {
    if (!rows.length) return '<p class="muted">Nothing yet.</p>';
    var out = thead(['At', 'Kind', { name: 'Amount', num: true }, 'Model', { name: 'Tokens', num: true }, 'Ref']);
    rows.forEach(function (r) {
      out += '<tr>' +
        cell('At', fmtTime(r.at)) +
        cell('Kind', esc(r.kind)) +
        cell('Amount', esc(dollars(r.amount)), 'num') +
        cell('Model', esc(r.model)) +
        cell('Tokens', r.kind === 'debit' ? esc(r.in + ' in, ' + r.out + ' out') : '', 'num') +
        cell('Ref', '<code>' + esc(r.ref) + '</code>') +
        '</tr>';
    });
    return out + '</tbody></table>';
  }
  // a rail as a person names it, rather than as the ship stores it
  function railName(r) {
    if (r === 'stripe') return 'Card';
    if (r === 'btcpay') return 'Bitcoin';
    return r || '';
  }
  // processing is the on-chain wait: the money is seen and not yet
  // confirmed, so the row says why it has not become a credit
  function statusLine(c) {
    var s = c.status || '';
    if (s === 'processing') return 'processing &middot; waiting for confirmations';
    if (s === 'refused' && c.note) return esc(s) + ' &middot; ' + esc(c.note);
    return esc(s);
  }
  function checkoutRows(obj) {
    var keys = Object.keys(obj || {});
    if (!keys.length) return '';
    var out = '<div class="card"><h2>Checkouts</h2>' +
      thead(['Order', 'Rail', { name: 'Amount', num: true }, 'Status', '']);
    keys.forEach(function (n) {
      var c = obj[n] || {};
      out += '<tr>' +
        cell('Order', '<code>' + esc(n) + '</code>') +
        cell('Rail', esc(railName(c.rail))) +
        cell('Amount', esc(dollars(c.amount)), 'num') +
        cell('Status', statusLine(c)) +
        cell('', c.url ? '<a href="' + esc(c.url) + '" target="_blank" rel="noopener">Open</a>' : '') +
        '</tr>';
    });
    return out + '</tbody></table></div>';
  }
  // the plans the vendor sells, as buttons. A top-up plan credits what
  // it costs; a subscription says how often it charges.
  function planButtons(plans) {
    if (!plans || !plans.length) return '';
    return '<div class="field wide"><label>Plans</label><div>' +
      plans.map(function (p) {
        var how = p.kind === 'subscription'
          ? ' per ' + esc(p.interval || 'month')
          : ' for ' + esc(dollars(p.credit)) + ' of credit';
        return '<button data-buy="' + esc(p.id) + '">' + esc(p.name) +
          ' &middot; $' + esc(dollars(p.price)) + how + '</button> ';
      }).join('') + '</div></div>';
  }
  function subscriptionLine(d, plans) {
    var sub = (d && d.subscription) || {};
    if (!sub.active) return '';
    var named = (plans || []).filter(function (p) { return p.id === d.plan; })[0];
    var name = named ? named.name : (d.plan || 'a plan');
    var when = sub.renews ? ', renews ' + fmtTime(sub.renews).slice(0, 10) : '';
    return '<p>Subscribed to ' + esc(name) + esc(when) +
      ' <button class="danger" data-cancel-sub="1">Cancel</button></p>';
  }
  function myAccount(d, plans) {
    var vendor = (d && d.vendor) || '';
    var out = '<h1>Account</h1>' +
      '<div class="card"><h2>Vendor</h2><p>' +
      (vendor ? '<code>' + esc(vendor) + '</code>' : '<span class="muted">none set</span>') +
      (d && d.stale !== undefined ? ' <span class="muted">read ' + esc(d.stale) + 's ago</span>' : '') +
      '</p><div class="inline">' +
      '<div class="field"><label for="v-ship">Set vendor</label>' +
      '<input id="v-ship" value="' + esc(vendor) + '" placeholder="~wex"></div>' +
      '<div class="field"><label>&nbsp;</label><button data-set-vendor="1">Save</button>' +
      '<button data-refresh-view="1">Refresh</button></div></div></div>';
    if (!vendor) return out + '<p class="muted">Name a vendor ship above to open an account on it.</p>';
    out += '<div class="card"><h2>Balance</h2>' +
      '<p style="font-size:1.6rem;margin:.2rem 0">' + signed(d && d.balance) + '</p>' +
      subscriptionLine(d, plans) +
      '<div class="inline">' +
      planButtons(plans) +
      '<div class="field"><label for="t-amount">Top up, dollars</label><input id="t-amount" value=""></div>' +
      '<div class="field"><label>Rail</label>' +
      '<label><input type="radio" name="rail" value="stripe" checked> Card</label> ' +
      '<label><input type="radio" name="rail" value="btcpay"> Bitcoin</label>' +
      '<span class="muted">Subscriptions are card only.</span></div>' +
      '<div class="field"><label>&nbsp;</label><button data-topup="1">Top up</button></div>' +
      '</div></div>';
    out += checkoutRows(d && d.checkouts);
    return out + '<div class="card"><h2>Ledger</h2>' + ledger((d && d.ledger) || []) + '</div>';
  }
  // the customer's own half of a lease. The key is not shown here: the
  // inference config box below is where a client reads it.
  function myLease(d) {
    var l = d && d.lease;
    var err = (d && d.lease_error) || '';
    var out = '<div class="card"><h2>Lease</h2>' +
      '<p class="muted">A lease is a real provider key capped at your balance, so a client calls the provider directly: streaming, tools and the provider\'s own latency.</p>';
    if (err) out += '<p class="neg">' + esc(err) + '</p>';
    if (!l) {
      return out + '<p class="muted">No lease.</p>' +
        '<button data-take-lease="1">Take a lease</button></div>';
    }
    return out + '<p>On <code>' + esc(l.base_url) + '</code>' +
      (l.disabled ? ' &middot; <span class="neg">disabled, top up to spend again</span>' : '') + '</p>' +
      '<p>Spent $' + esc(dollars(l.usage)) + ' against a $' + esc(dollars(l.limit)) + ' cap</p>' +
      '<button data-take-lease="1">Refresh</button> ' +
      '<button class="danger" data-drop-my-lease="1">Drop</button></div>';
  }
  function myKeys(keys, cfg, minted, acct) {
    var out = '<h1>Keys</h1><div class="card">';
    if (minted) {
      out += '<div class="secret"><p>Copy this now. The vendor keeps only a salted hash of it.</p>' +
        '<code>' + esc(minted.secret) + '</code>' +
        '<p><button data-dismiss="1">Done</button></p></div>';
    }
    if (!keys.length) out += '<p class="muted">No keys yet.</p>';
    else {
      out += thead(['Id', 'Name', 'Made', '']);
      keys.forEach(function (k) {
        out += '<tr>' +
          cell('Id', '<code>' + esc(k.id) + '</code>') +
          cell('Name', esc(k.name)) +
          cell('Made', fmtTime(k.made)) +
          cell('', '<button class="danger" data-drop-key="' + esc(k.id) + '" data-name="' + esc(k.name) + '">Revoke</button>') +
          '</tr>';
      });
      out += '</tbody></table>';
    }
    out += '<div class="inline"><div class="field"><label for="my-k-name">New key name</label>' +
      '<input id="my-k-name" value=""></div>' +
      '<div class="field"><label>&nbsp;</label><button data-my-mint="1">Mint a key</button></div></div></div>';
    out += myLease(acct);
    out += '<div class="card"><h2>Inference config</h2>';
    if (!cfg) out += '<p class="muted">No key yet, so there is nothing for a client to run on.</p>';
    else {
      out += '<p class="muted">This is what <code>GET /api/inference</code> answers.</p>' +
        '<p class="muted">Mode <code>' + esc(cfg.mode || '') + '</code>.</p>' +
        '<pre id="inference">' + esc(JSON.stringify(cfg, null, 2)) + '</pre>' +
        '<button data-copy-inference="1">Copy</button>';
    }
    return out + '</div>';
  }
  function buyCatalog(rows, filter) {
    var f = String(filter || '').toLowerCase();
    var kept = (rows || []).filter(function (r) {
      return !f || String(r.id).toLowerCase().indexOf(f) >= 0 || String(r.provider).toLowerCase().indexOf(f) >= 0;
    });
    var out = '<h1>Catalog</h1><div class="card">' +
      '<div class="field"><label for="buy-filter">Filter</label>' +
      '<input id="buy-filter" type="search" value="' + esc(filter || '') + '" placeholder="id or provider"></div>' +
      '<span class="muted"> ' + kept.length + ' of ' + (rows || []).length + ' models</span></div>';
    if (!kept.length) return out + '<p class="muted">The vendor offers nothing yet.</p>';
    out += '<div class="card">' + thead(['Model', 'Provider',
      { name: 'In $/M', num: true }, { name: 'Out $/M', num: true }, 'Tags']);
    kept.forEach(function (r) {
      out += '<tr>' +
        cell('Model', '<code>' + esc(r.id) + '</code>') +
        cell('Provider', esc(r.provider)) +
        cell('In', esc(dollars(r.in, 4)), 'num') +
        cell('Out', esc(dollars(r.out, 4)), 'num') +
        cell('Tags', esc((r.tags || []).join(', '))) +
        '</tr>';
    });
    return out + '</tbody></table></div>';
  }

  function route(hash) {
    var h = String(hash || '').replace(/^#/, '') || 'providers';
    // #account is this ship's own account on its vendor; #accounts/~ship
    // is one of the accounts this ship sells to
    if (h === 'account') return { name: 'my-account' };
    if (h.indexOf('accounts/') === 0) return { name: 'account', ship: h.slice(9) };
    return { name: h };
  }
  // one block of the raw beacon stream: only its "event:" and "data:"
  // lines carry anything
  function sseEvent(block) {
    var name = '', data = '';
    String(block).split('\n').forEach(function (ln) {
      if (ln.indexOf('event: ') === 0) name = ln.slice(7).trim();
      else if (ln.indexOf('data: ') === 0) data = ln.slice(6).trim();
    });
    return { name: name, data: data };
  }

  var render = {
    esc: esc, dollars: dollars, micro: micro, margin: margin,
    providers: providers, catalog: catalog, accounts: accounts, account: account,
    payments: payments, planRows: planRows, planButtons: planButtons,
    leaseCard: leaseCard, leaseSetting: leaseSetting,
    subscriptionLine: subscriptionLine,
    myAccount: myAccount, myKeys: myKeys, myLease: myLease, buyCatalog: buyCatalog,
    route: route, sseEvent: sseEvent,
  };
  if (typeof module !== 'undefined' && module.exports) { module.exports = render; }
  if (typeof document === 'undefined') { return; }

  // ---- the app ----
  var view = document.getElementById('view');
  var statusEl = document.getElementById('status');
  var lastRev = null;
  var tests = Object.create(null);     // a provider id to its last Test or Import line
  var editing = null;                  // the provider id whose form is open
  var minted = null;                   // a secret shown once, until dismissed
  var catRows = [];                    // the catalog as the page holds it, edited in place
  var catFilter = '';
  var acctSearch = '';
  // the customer half. isVendor is true when this ship sells, isBuyer
  // when it buys; both are true on a ship that is its own customer.
  var isVendor = true, isBuyer = false;
  var buyFilter = '';
  var custMinted = null;               // a fetched secret shown once
  var planEditing = null;              // the plan id whose form is open
  var st0 = null;                      // the settings the Payments view last read
  var myPlans = [];                    // the vendor's plans, as the customer reads them

  function say(msg, bad) { statusEl.textContent = msg; statusEl.className = 'status' + (bad ? ' bad' : ''); }
  // the settings PUT replaces the document whole, so a save from one
  // card carries the other card's stored fields back with it. Every
  // secret goes out blank, which is what keeps what the ship holds.
  function saveSettings(extra) {
    var was = st0 || {};
    var modeEl = view.querySelector('input[name="st-mode"]:checked');
    var pubEl = document.getElementById('st-pub');
    var body = {
      markup_pct: was.markup_pct || 130,
      min_topup: was.min_topup === undefined ? 5000000 : was.min_topup,
      public_url: pubEl ? pubEl.value.trim() : (was.public_url || ''),
      mode: modeEl ? modeEl.value : (was.mode || 'stub'),
      refuse_comets: !!was.refuse_comets,
      stripe_key: '',
      stripe_webhook_secret: '',
      stripe_url: was.stripe_url || '',
      btcpay_url: was.btcpay_url || '',
      btcpay_store: was.btcpay_store || '',
      btcpay_key: '',
      btcpay_webhook_secret: '',
      lease_provider: was.lease_provider || '',
      stripe_minutes: was.stripe_minutes === undefined ? 1440 : was.stripe_minutes,
      btcpay_minutes: was.btcpay_minutes === undefined ? 60 : was.btcpay_minutes,
    };
    Object.keys(extra).forEach(function (k) { body[k] = extra[k]; });
    return post('/settings', body, 'PUT');
  }
  function api(path, opts) {
    return fetch(API + path, opts).then(function (r) {
      if (!r.ok) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          throw new Error((d.error && d.error.message) || ('http ' + r.status));
        });
      }
      return r.json();
    });
  }
  function post(path, bodyObj, method) {
    return api(path, {
      method: method || 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(bodyObj === undefined ? {} : bodyObj),
    });
  }
  function seg(s) { return encodeURIComponent(s); }

  // +drawer: a writer for the view, fixed to the hash it was made at.
  // A read that comes back after the hash moved is dropped.
  function drawer() {
    var at = location.hash;
    return function (html) { if (location.hash === at) view.innerHTML = html; };
  }
  var refreshing = false, again = false;
  function refresh() {
    if (refreshing) { again = true; return; }
    refreshing = true;
    var r = route(location.hash);
    if (r.name !== 'account') minted = null;
    if (r.name !== 'keys') custMinted = null;
    if (r.name !== 'payments') planEditing = null;
    var p;
    // a read can take thirty seconds when it waits on the vendor, and
    // by then the person may be somewhere else: draw only what the view
    // is still showing
    var draw = drawer();
    if (r.name === 'my-account') {
      p = api('/account').then(function (d) {
        return api('/plans').catch(function () { return []; }).then(function (pl) {
          myPlans = pl || [];
          draw(myAccount(d, myPlans));
        });
      });
    } else if (r.name === 'payments') {
      p = api('/settings').then(function (st) {
        st0 = st;
        return api('/plans').then(function (pl) {
          return api('/log').catch(function () { return []; }).then(function (lg) {
            return api('/providers').catch(function () { return []; }).then(function (pv) {
              draw(payments(st, pl || [], lg || [], planEditing, pv || []));
            });
          });
        });
      });
    } else if (r.name === 'keys') {
      p = api('/keys').then(function (keys) {
        return api('/inference').catch(function () { return null; })
          .then(function (cfg) {
            return api('/account').catch(function () { return null; })
              .then(function (acct) { draw(myKeys(keys || [], cfg, custMinted, acct)); });
          });
      });
    } else if (r.name === 'catalog' && isBuyer && !isVendor) {
      p = api('/catalog').then(function (rows) { draw(buyCatalog(rows || [], buyFilter)); });
    } else if (r.name === 'catalog') {
      p = api('/catalog').then(function (rows) { catRows = rows || []; draw(catalog(catRows, catFilter)); });
    } else if (r.name === 'accounts') {
      p = api('/accounts').then(function (rows) { draw(accounts(rows || [], acctSearch)); });
    } else if (r.name === 'account') {
      // a ship with no account is a 404, and the view draws anyway
      p = api('/accounts/' + seg(r.ship)).catch(function () { return null; })
        .then(function (d) { draw(account(r.ship, d, minted)); });
    } else {
      p = api('/providers').then(function (rows) { draw(providers(rows || [], tests, editing)); });
    }
    p = p.then(function () { say(''); }).catch(function (e) { say(String(e.message || e), true); });
    p.then(function () { refreshing = false; if (again) { again = false; refresh(); } });
  }
  // a write answers before the writer applies, so the refetch waits
  function later() { setTimeout(refresh, 400); }

  function providerForm() {
    function val(id) { var el = document.getElementById(id); return el ? el.value.trim() : ''; }
    var kindEl = view.querySelector('#provider-form input[name="kind"]:checked');
    var body = {
      id: val('p-id'), name: val('p-name'),
      kind: kindEl ? kindEl.value : 'openai-compatible',
      base_url: val('p-url'),
    };
    // a blank secret means keep, which is exactly what an untouched
    // field sends; on a fresh row it means there is none yet
    body.api_key = val('p-key');
    body.provisioning_key = val('p-pkey');
    return body;
  }
  // the catalog rows as edited: the two price inputs are dollars, the
  // ship stores microdollars
  function readCatalog() {
    var bad = null;
    view.querySelectorAll('[data-row]').forEach(function (el) {
      var row = catRows.filter(function (r) { return r.id === el.dataset.row; })[0];
      if (!row) return;
      var f = el.dataset.field;
      if (f === 'enabled') row.enabled = el.checked;
      else if (f === 'tags') row.tags = el.value.split(',').map(function (t) { return t.trim(); }).filter(Boolean);
      else {
        var n = micro(el.value);
        if (n === null || n < 0) { bad = row.id + ' ' + f + ': not a price'; return; }
        row[f] = n;
      }
    });
    return bad;
  }

  view.addEventListener('input', function (ev) {
    var el = ev.target;
    if (el.id === 'cat-filter') { catFilter = el.value; view.innerHTML = catalog(catRows, catFilter); var f = document.getElementById('cat-filter'); if (f) { f.focus(); f.setSelectionRange(f.value.length, f.value.length); } }
    else if (el.id === 'buy-filter') { buyFilter = el.value; }
    else if (el.id === 'acct-search') { acctSearch = el.value; }
  });
  view.addEventListener('change', function (ev) {
    if (ev.target.name === 'kind') {
      var box = document.getElementById('p-prov');
      if (box) box.hidden = ev.target.value !== 'openrouter';
    } else if (ev.target.id === 'acct-search' || ev.target.id === 'buy-filter') {
      refresh();
    }
  });

  view.addEventListener('click', function (ev) {
    var b = ev.target.closest('button');
    if (!b) return;
    var d = b.dataset;
    if (d.test) {
      say('testing ' + d.test);
      post('/providers/' + seg(d.test) + '/test', {}).then(function (r) {
        tests[d.test] = { text: r.status + ' · ' + (r.model || '') + ' · ' + (r.text || '') , bad: r.status !== 200 };
        refresh();
      }).catch(function (e) { tests[d.test] = { text: e.message, bad: true }; refresh(); });
    } else if (d['import']) {
      say('importing from ' + d['import']);
      post('/providers/' + seg(d['import']) + '/import').then(function (r) {
        tests[d['import']] = { text: 'added ' + r.added, bad: false };
        refresh();
      }).catch(function (e) { tests[d['import']] = { text: e.message, bad: true }; refresh(); });
    } else if (d.edit) {
      editing = d.edit; refresh();
    } else if (d.cancelEdit) {
      editing = null; refresh();
    } else if (d.drop) {
      if (!confirm('Delete the provider "' + d.drop + '"? Its catalog rows stop answering.')) return;
      api('/providers/' + seg(d.drop), { method: 'DELETE' }).then(later).catch(function (e) { say(e.message, true); });
    } else if (d.saveProvider !== undefined) {
      var body = providerForm();
      if (!body.id) { say('id: 1 to 64 bytes', true); return; }
      var was = editing;
      var call = was ? post('/providers/' + seg(was), body, 'PUT') : post('/providers', body);
      editing = null;
      call.then(function () { say('saved'); later(); })
        .catch(function (e) { editing = was; say(e.message, true); refresh(); });
    } else if (d.saveCatalog) {
      var bad = readCatalog();
      if (bad) { say(bad, true); return; }
      post('/catalog', catRows, 'PUT').then(function () { say('catalog saved'); })
        .catch(function (e) { say(e.message, true); refresh(); });
    } else if (d.credit || d.refund) {
      var ship = route(location.hash).ship;
      var which = d.credit ? 'credit' : 'refund';
      var amount = micro(document.getElementById(d.credit ? 'c-amount' : 'r-amount').value);
      var note = document.getElementById(d.credit ? 'c-note' : 'r-note').value;
      if (!amount || amount <= 0) { say('amount: dollars above zero', true); return; }
      post('/accounts/' + seg(ship) + '/' + which, { amount: amount, note: note })
        .then(function () { say(which + ' of $' + dollars(amount)); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.mint) {
      var who = route(location.hash).ship;
      var name = document.getElementById('k-name').value.trim();
      if (!name) { say('name: 1 to 200 bytes', true); return; }
      post('/accounts/' + seg(who) + '/keys', { name: name })
        .then(function (k) { minted = k; refresh(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.dismiss) {
      // one Done button serves both halves: the owner's mint and the
      // customer's fetched key
      minted = null; custMinted = null; refresh();
    } else if (d.revoke) {
      if (!confirm('Revoke "' + d.name + '"? Its next request is refused.')) return;
      var s = route(location.hash).ship;
      api('/accounts/' + seg(s) + '/keys/' + seg(d.revoke), { method: 'DELETE' })
        .then(later).catch(function (e) { say(e.message, true); });
    } else if (d.open) {
      var want = document.getElementById('acct-open').value.trim();
      if (!want) { say('ship: not an @p', true); return; }
      location.hash = '#accounts/' + (want.charAt(0) === '~' ? want : '~' + want);
    } else if (d.close) {
      var c = route(location.hash).ship;
      if (!confirm('Close ' + c + '? Every key is revoked and the ledger is kept.')) return;
      post('/accounts/' + seg(c) + '/close').then(later).catch(function (e) { say(e.message, true); });
    } else if (d.setVendor) {
      var v = document.getElementById('v-ship').value.trim();
      say('setting the vendor');
      post('/vendor', { ship: v }, 'PUT').then(function () { boot(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.refreshView) {
      say('reading the vendor');
      var drawAccount = drawer();
      api('/account?fresh=1').then(function (dd) {
        // the plans go with it, or the buttons and the plan's name
        // vanish on the redraw
        return api('/plans').catch(function () { return myPlans; }).then(function (pl) {
          myPlans = pl || [];
          drawAccount(myAccount(dd, myPlans));
          say('');
        });
      }).catch(function (e) { say(e.message, true); });
    } else if (d.topup) {
      var amount = micro(document.getElementById('t-amount').value);
      var railEl = view.querySelector('input[name="rail"]:checked');
      if (!amount || amount <= 0) { say('amount: dollars above zero', true); return; }
      say('opening a checkout');
      post('/checkout', { rail: railEl ? railEl.value : 'stripe', amount: amount })
        .then(function (r) {
          if (r.url) { window.open(r.url, '_blank', 'noopener'); say('checkout open'); }
          else say('the vendor has not answered yet; it will show under Checkouts');
          later();
        })
        .catch(function (e) { say(e.message, true); });
    } else if (d.myMint) {
      var mn = document.getElementById('my-k-name').value.trim();
      if (!mn) { say('name: 1 to 200 bytes', true); return; }
      say('asking the vendor for a key');
      post('/keys', { name: mn }).then(function (k) {
        if (k.secret) { custMinted = k; say(''); } else say('the key is on its way; it will show here');
        refresh();
      }).catch(function (e) { say(e.message, true); });
    } else if (d.dropKey) {
      if (!confirm('Revoke "' + d.name + '"? Its next request is refused.')) return;
      api('/keys/' + seg(d.dropKey), { method: 'DELETE' })
        .then(later).catch(function (e) { say(e.message, true); });
    } else if (d.takeLease) {
      say('asking the vendor for a lease');
      post('/lease').then(function () { say('lease in hand'); later(); })
        .catch(function (e) { say(e.message, true); refresh(); });
    } else if (d.dropMyLease) {
      if (!confirm('Drop the lease? The provider key is deleted and clients fall back to the proxy.')) return;
      api('/lease', { method: 'DELETE' })
        .then(function () { say('dropped'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.saveStripe) {
      // a blank secret keeps what the ship holds, which is what an
      // untouched field sends
      saveSettings({
        stripe_key: document.getElementById('st-key').value.trim(),
        stripe_webhook_secret: document.getElementById('st-hook').value.trim(),
      }).then(function () { say('saved'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.saveBtcpay) {
      saveSettings({
        btcpay_url: document.getElementById('bt-url').value.trim(),
        btcpay_store: document.getElementById('bt-store').value.trim(),
        btcpay_key: document.getElementById('bt-key').value.trim(),
        btcpay_webhook_secret: document.getElementById('bt-hook').value.trim(),
      }).then(function () { say('saved'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.saveLease) {
      var lp = document.getElementById('ls-prov');
      saveSettings({ lease_provider: lp ? lp.value : '' })
        .then(function () { say('saved'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.reconcile) {
      var rs = route(location.hash).ship;
      say('reading the key upstream');
      post('/accounts/' + seg(rs) + '/reconcile').then(function (r) {
        say(r.ok ? ('reconciled' + (r.why ? ': ' + r.why : '')) : r.why, !r.ok);
        later();
      }).catch(function (e) { say(e.message, true); });
    } else if (d.dropLease) {
      var ds = route(location.hash).ship;
      if (!confirm('Drop the lease on ' + ds + '? The provider key is deleted.')) return;
      api('/accounts/' + seg(ds) + '/lease', { method: 'DELETE' })
        .then(later).catch(function (e) { say(e.message, true); });
    } else if (d.planEdit) {
      planEditing = d.planEdit; refresh();
    } else if (d.planCancel) {
      planEditing = null; refresh();
    } else if (d.planSave !== undefined) {
      var kindEl = view.querySelector('#plan-form input[name="plan-kind"]:checked');
      var body = {
        id: document.getElementById('pl-id').value.trim(),
        name: document.getElementById('pl-name').value.trim(),
        kind: kindEl ? kindEl.value : 'topup',
        price: micro(document.getElementById('pl-price').value),
        credit: micro(document.getElementById('pl-credit').value),
        interval: document.getElementById('pl-interval').value,
      };
      if (!body.id) { say('id: 1 to 64 bytes', true); return; }
      if (!body.price || !body.credit) { say('price and credit: dollars above zero', true); return; }
      var was = planEditing;
      var call = was ? post('/plans/' + seg(was), body, 'PUT') : post('/plans', body);
      planEditing = null;
      call.then(function () { say('saved'); later(); })
        .catch(function (e) { planEditing = was; say(e.message, true); refresh(); });
    } else if (d.planDrop) {
      if (!confirm('Delete the plan "' + d.planDrop + '"?')) return;
      api('/plans/' + seg(d.planDrop), { method: 'DELETE' })
        .then(later).catch(function (e) { say(e.message, true); });
    } else if (d.planStripe) {
      say('making the product and the price on Stripe');
      post('/plans/' + seg(d.planStripe) + '/stripe')
        .then(function (p) { say('price ' + p.stripe_price); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.buy) {
      var plan = myPlans.filter(function (p) { return p.id === d.buy; })[0] || {};
      var buyRailEl = view.querySelector('input[name="rail"]:checked');
      var buyRail = buyRailEl ? buyRailEl.value : 'stripe';
      if (plan.kind === 'subscription' && buyRail !== 'stripe') {
        say('subscriptions are card only; choose Card to subscribe', true);
        return;
      }
      say('opening a checkout');
      post('/checkout', { rail: buyRail, plan: d.buy })
        .then(function (r) {
          if (r.url) { window.open(r.url, '_blank', 'noopener'); say('checkout open'); }
          else say('the vendor has not answered yet; it will show under Checkouts');
          later();
        })
        .catch(function (e) { say(e.message, true); });
    } else if (d.cancelSub) {
      if (!confirm('Cancel the subscription at the end of the period?')) return;
      post('/cancel-subscription').then(function () { say('asked the vendor to cancel'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.clearSub) {
      var cs = route(location.hash).ship;
      if (!confirm('Clear the subscription on ' + cs + '? Only do this when Stripe says it is gone.')) return;
      post('/accounts/' + seg(cs) + '/clear-subscription')
        .then(later).catch(function (e) { say(e.message, true); });
    } else if (d.copyInference) {
      var pre = document.getElementById('inference');
      if (pre && navigator.clipboard) {
        navigator.clipboard.writeText(pre.textContent).then(function () { say('copied'); },
          function () { say('could not copy', true); });
      } else if (pre) {
        var sel = window.getSelection();
        var rg = document.createRange();
        rg.selectNodeContents(pre);
        sel.removeAllRanges();
        sel.addRange(rg);
        say('selected');
      }
    }
  });

  window.addEventListener('hashchange', refresh);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) refresh(); });

  // ---- the beacon stream, read raw (the initial event is named "old
  // /rev", which EventSource cannot subscribe to; it carries the current
  // rev, so a bump missed while nobody watched shows as a difference) ----
  var timer = null;
  // a re-render replaces the forms and the inline price inputs, so a
  // bump waits while one of them has focus; the next bump after blur
  // refreshes
  function typing() {
    var el = document.activeElement;
    return !!(el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') && view.contains(el));
  }
  function bumped() {
    if (typing()) return;
    clearTimeout(timer);
    timer = setTimeout(function () { if (!typing()) refresh(); }, 300);
  }
  async function stream() {
    for (;;) {
      if (document.hidden) { await new Promise(function (r) { setTimeout(r, 1000); }); continue; }
      try {
        var resp = await fetch(KEEP, { headers: { Accept: 'text/event-stream' } });
        if (!resp.ok) {
          say('live updates off', true);
          await new Promise(function (r) { setTimeout(r, 30000); });
          continue;
        }
        var rd = resp.body.getReader();
        var dec = new TextDecoder();
        var buf = '';
        for (;;) {
          var chunk = await rd.read();
          if (chunk.done) break;
          buf += dec.decode(chunk.value, { stream: true });
          var evs = buf.split('\n\n');
          buf = evs.pop();
          evs.forEach(function (ev) {
            if (document.hidden) return;
            var parsed = sseEvent(ev);
            var name = parsed.name, data = parsed.data;
            if (!name || name.slice(-4) !== '/rev') return;
            if (name.indexOf('old') === 0) { if (lastRev !== null && data && data !== lastRev) bumped(); lastRev = data; return; }
            lastRev = data;
            bumped();
          });
        }
      } catch (e) { /* the stream severed: reconnect below */ }
      await new Promise(function (r) { setTimeout(r, 3000); });
    }
  }
  // ---- which half of the app this ship is ----
  // vendor.json decides: empty means this ship sells only, our own ship
  // means it sells and buys from itself, another ship means it buys.
  // GET /api/account carries both, so one read settles it.
  function boot() {
    return api('/account').catch(function () { return {}; }).then(function (d) {
      var vendor = (d && d.vendor) || '';
      var self = (d && d.self) || '';
      isBuyer = !!vendor;
      isVendor = !vendor || vendor === self;
      document.getElementById('nav-vendor').hidden = !isVendor;
      document.getElementById('nav-customer').hidden = !isBuyer;
      document.getElementById('both').hidden = !(isVendor && isBuyer);
      var r = route(location.hash);
      // a customer-only ship has no #providers to land on
      if (!isVendor && (r.name === 'providers' || r.name === 'accounts')) {
        location.hash = '#account';
        return;
      }
      refresh();
    });
  }

  boot();
  stream();
  setInterval(function () { if (!document.hidden) refresh(); }, 60000);
})();
