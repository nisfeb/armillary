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

  // the four tiers a vendor fills, and the features of its customers'
  // apps it maps onto them; a feature stored that is not here still shows
  var TIERS = [
    ['frontier', 'Frontier'],
    ['decision', 'Decision (the decisions API)'],
    ['zdr', 'ZDR (keeps no data)'],
    ['private', 'Private'],
  ];
  var FEATURES = [
    ['catch_up', 'Talon catch-up'],
    ['assistant', 'Talon assistant'],
    ['decision', 'Talon decision gate'],
    ['orrery_generator', 'Orrery generator, refine and brief'],
    ['orrery_mail', 'Orrery mail reader'],
    ['orrery_chat', 'Orrery chat reader'],
    ['orrery_telegram', 'Orrery Telegram reader'],
    ['orrery_read', 'Orrery read channel'],
    ['orrery_decider', 'Orrery decider'],
  ];
  // +fuzzyScore, +rankModels: Talon's model search (its rankModels): each
  // word of the query in the id, its name or the part after the last
  // slash, fuzzily (its letters in order, gaps allowed); a word the id
  // starts with ranks before one inside it, before letters strewn through
  function fuzzyScore(q, names) {
    var best = null;
    names.forEach(function (n) {
      // a word the name starts with, then one a word in it starts with
      // (after - / _ or a space: "5" fits opus-5.5 before opus-4.5), then
      // one inside a word, then letters strewn through it
      var at = n.indexOf(q), s = null;
      if (at === 0) s = 0;
      else if (at > 0) {
        s = 1;
        for (var j = at; j >= 0 && s === 1; j = n.indexOf(q, j + 1)) if ('-/_ '.indexOf(n[j - 1]) >= 0) s = 0.5;
      }
      if (s === null) {
        var i = 0, k = 0;
        for (; k < q.length && i >= 0; k++) { i = n.indexOf(q[k], i); if (i >= 0) i++; }
        if (i >= 0) s = 2;
      }
      if (s !== null && (best === null || s < best)) best = s;
    });
    return best;
  }
  function rankModels(query, models) {
    var words = String(query || '').toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return models.slice();
    return models.map(function (m) {
      var id = String(m.id).toLowerCase(), name = String(m.name || m.id).toLowerCase();
      var names = [id, name, id.slice(id.lastIndexOf('/') + 1)], score = 0;
      // the provider counts whole or in part, never letters strewn
      // through it: "pro" strewn through "openrouter" took every model
      var prov = String(m.provider || '').toLowerCase();
      for (var w = 0; w < words.length; w++) {
        var sc = fuzzyScore(words[w], names);
        var ps = prov.indexOf(words[w]) === 0 ? 0 : prov.indexOf(words[w]) > 0 ? 1 : null;
        if (ps !== null && (sc === null || ps < sc)) sc = ps;
        if (sc === null) return null;
        score += sc;
      }
      return [m, score];
    }).filter(Boolean).sort(function (a, b) { return a[1] - b[1] || String(a[0].id).length - String(b[0].id).length; }).map(function (x) { return x[0]; });
  }
  // +modelBox: a model id, searched or typed. The box keeps whatever is
  // typed; the list under it is the models that fit, best first, and a
  // click or Enter on one takes it
  var pickModels = {};   // each model box's candidates, by the box's id
  function modelBox(id, attrs, value, models, placeholder) {
    pickModels[id] = models;
    return '<div class="pick"><input id="' + id + '" ' + attrs + ' value="' + esc(value) +
      '" placeholder="' + esc(placeholder || 'search, or type a model id') +
      '" autocomplete="off" spellcheck="false" data-pick="1" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="' + id + '-list">' +
      '<ul class="pick-list" id="' + id + '-list" role="listbox" hidden></ul></div>';
  }
  function pickList(input) {
    var list = document.getElementById(input.id + '-list');
    if (!list) return null;
    var hits = rankModels(input.value, pickModels[input.id] || []).slice(0, 40);
    list.innerHTML = hits.length ? hits.map(function (m, i) {
      return '<li role="option" data-pick-id="' + esc(m.id) + '"' + (i === 0 ? ' class="on"' : '') + '>' + esc(m.id) +
        (m.note ? ' <span class="muted">' + esc(m.note) + '</span>' : '') + '</li>';
    }).join('') : '<li class="muted none">No model fits; Save keeps what you typed.</li>';
    list.hidden = false;
    input.setAttribute('aria-expanded', 'true');
    return list;
  }
  function pickClose(input) {
    var list = document.getElementById(input.id + '-list');
    if (list) list.hidden = true;
    input.setAttribute('aria-expanded', 'false');
  }
  // what the owner typed and has not saved, so a redraw (the catalog
  // filter, the minute's refresh) does not lose it
  var sgDraft = { tiers: {}, features: {} };
  // +suggestedCard: the tiers this vendor fills and the tier each feature
  // of its customers' apps uses. An app following it switches when the
  // revision moves.
  function suggestedCard(rows) {
    var zdrNote = function (r) { return (r.tags || []).indexOf('zdr') >= 0 ? 'ZDR' : ''; };
    var sold = rows.filter(function (r) { return r.enabled; }).map(function (r) { return { id: r.id, name: r.name, provider: r.provider, note: zdrNote(r) }; });
    // a model the catalog holds but does not sell is listed too, marked,
    // so the search never says a model is not there when it is; saving
    // one is refused until it is switched on
    var unsold = rows.filter(function (r) { return !r.enabled; }).map(function (r) { return { id: r.id, name: r.name, provider: r.provider, note: (zdrNote(r) ? 'ZDR, ' : '') + 'not for sale: switch it on in the catalog below' }; });
    var tiers = Object.assign({}, mySuggested.tiers || {}, sgDraft.tiers);
    var feats = Object.assign({}, mySuggested.features || {}, sgDraft.features);
    var out = '<div class="card"><h2>Your customers\' AI</h2>' +
      '<p class="muted">Every paying customer\'s apps use these unless the customer picks a model of their own for a feature. A change reaches each customer ship within five minutes. Revision ' +
      esc(mySuggested.rev || 0) + '.</p>' +
      '<p class="muted">Every feature below reads your customers\' own messages, mail or notes. A feature on a tier whose model keeps data sends that content to the model\'s provider; the ZDR and private tiers are for them.</p>' +
      '<h3>Tiers</h3><div class="inline">';
    TIERS.forEach(function (t) {
      var cur = tiers[t[0]] || '';
      // the decision tier names a model for the decisions route, which no
      // chat catalog sells: Jev first, then what is sold
      var models = t[0] === 'decision'
        ? [{ id: 'typesafe/jev-1.13', note: 'decisions' }].concat(sold.filter(function (m) { return m.id !== 'typesafe/jev-1.13'; }))
        : sold.concat(unsold);
      var field = modelBox('tier-' + t[0], 'data-tier="' + t[0] + '"', cur, models,
        t[0] === 'decision' ? 'typesafe/jev-1.13' : 'search, or type a model id');
      out += '<div class="field wide"><label for="tier-' + t[0] + '">' + esc(t[1]) + '</label>' + field + '</div>';
    });
    out += '</div><h3>Features</h3><div class="inline">';
    var feList = FEATURES.slice();
    Object.keys(feats).forEach(function (k) {
      if (!feList.some(function (f) { return f[0] === k; })) feList.push([k, k]);
    });
    feList.forEach(function (f) {
      var cur = feats[f[0]] || '';
      out += '<div class="field"><label for="feat-' + esc(f[0]) + '">' + esc(f[1]) + '</label>' +
        '<select id="feat-' + esc(f[0]) + '" data-feature="' + esc(f[0]) + '"><option value="">none</option>' +
        TIERS.map(function (t) {
          return '<option value="' + t[0] + '"' + (t[0] === cur ? ' selected' : '') + '>' + esc(t[0]) + '</option>';
        }).join('') + '</select></div>';
    });
    return out + '</div><p><button data-save-suggested="1">Save</button></p></div>';
  }
  // +braveCard: the vendor's Brave key, never shown, and the searches
  // each customer ship made through it, by month
  function braveCard(b) {
    b = b || {};
    var counts = b.searches || {};
    var rows = Object.keys(counts).map(function (ship) {
      var months = counts[ship] || {};
      var line = Object.keys(months).sort().reverse().map(function (mo) { return esc(mo) + ': ' + esc(months[mo]); }).join(', ');
      return '<tr>' + cell('Ship', '<code>' + esc(ship) + '</code>') + cell('Searches', line) + '</tr>';
    }).join('');
    return '<div class="card"><h2>Brave search</h2>' +
      '<p class="muted">Your customers\' apps search through you: Talon\'s web search and Orrery\'s place lookups. The key stays on this ship and each search is counted on the account that made it.</p>' +
      '<div class="inline"><div class="field"><label for="brave-key">Brave API key</label>' +
      '<input id="brave-key" type="password" placeholder="' + (b.key_set ? 'a key is set; blank keeps it' : 'no key set') + '"></div>' +
      '<div class="field"><label>&nbsp;</label><button data-save-brave="1">Save key</button>' +
      (b.key_set ? ' <button class="danger" data-clear-brave="1">Remove key</button>' : '') + '</div></div>' +
      (rows ? thead(['Ship', 'Searches']) + rows + '</tbody></table>' : '<p class="muted">No searches yet.</p>') + '</div>';
  }
  function catalog(rows, filter) {
    // the filter is the model search's: fuzzy, best first
    var kept = rankModels(filter, rows);
    var out = '<h1>Catalog</h1>';
    if (!rows.length) return out + '<p class="muted">Nothing in the catalog. Import from a provider first.</p>';
    out += suggestedCard(rows);
    out += braveCard(myBrave);
    // the filter sits on its own table: above the two cards, what it found
    // was two screens down, and typing seemed to do nothing
    out += '<div class="card"><h2>Models</h2><div class="inline">' +
      '<div class="field"><label for="cat-filter">Filter</label>' +
      '<input id="cat-filter" type="search" value="' + esc(filter || '') + '" placeholder="search: opus 5, gpt mini, kimi" autocomplete="off" spellcheck="false"></div>' +
      '<div class="field"><button data-save-catalog="1">Save catalog</button>' +
      '<span class="muted"> ' + kept.length + ' of ' + rows.length + ' rows</span></div></div>' +
      thead(['Id', 'Provider',
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
    out += '<div class="card">' + thead(['Ship', { name: 'Balance', num: true }, { name: 'Keys', num: true }, 'Lease', 'Last seen', 'State']);
    kept.forEach(function (a) {
      var ls = a.lease_state || 'none';
      var lcls = ls === 'disabled' || ls === 'stale' ? 'neg' : (ls === 'active' ? 'pos' : 'muted');
      out += '<tr' + (a.closed ? ' class="closed"' : '') + '>' +
        cell('Ship', '<a href="#accounts/' + esc(a.ship) + '">' + esc(a.ship) + '</a>') +
        cell('Balance', signed(a.balance), 'num') +
        cell('Keys', esc(a.keys), 'num') +
        cell('Lease', '<span class="' + lcls + '">' + esc(ls) + '</span>') +
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
      // one Stripe Customer per ship, whether or not it ever subscribed
      (a.stripe_customer
        ? '<p class="muted">Stripe customer <code>' + esc(a.stripe_customer) + '</code></p>' : '') +
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
        '<p class="muted">Stripe <code>' + esc(sub.id || '') + '</code></p>' +
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
      var tok = rows.some(hasTokens);
      out += thead(['At', 'Kind', { name: 'Amount', num: true }, 'Model'].concat(tok ? [{ name: 'Tokens', num: true }] : [], ['Ref']));
      rows.forEach(function (r) {
        out += '<tr>' +
          cell('At', fmtTime(r.at)) +
          cell('Kind', esc(r.kind)) +
          cell('Amount', esc(dollars(r.amount)), 'num') +
          cell('Model', esc(r.model)) +
          (tok ? cell('Tokens', tokenCell(r), 'num') : '') +
          cell('Ref', '<code>' + esc(r.ref) + '</code>') +
          '</tr>';
      });
      out += '</tbody></table>';
    }
    return out + '</div>';
  }

  // the owner's half of a lease: the hash and the figures, never the
  // key. The key lives on the vendor and in that ship's own view.
  // the live read of a lease's key from the provider, kept per ship
  // until the next read; drawn beside the ship's own figures
  var liveLease = {};
  function ageWord(iso) {
    if (!iso) return '';
    var ms = Date.now() - Date.parse(iso);
    if (isNaN(ms)) return '';
    var m = Math.round(ms / 60000);
    return m < 1 ? 'just now' : (m < 60 ? m + ' min ago' : Math.round(m / 60) + ' h ago');
  }
  function leaseCard(d) {
    var l = d && d.lease;
    var err = (d && d.lease_error) || '';
    var out = '<div class="card"><h2>Lease</h2>';
    if (err) out += '<p class="neg">' + esc(err) + '</p>';
    if (!l) return out + '<p class="muted">No lease.</p></div>';
    var pct = (d && d.markup_pct) || 130;
    var stale = l.checked && (Date.now() - Date.parse(l.checked)) > 20 * 60000;
    var state = l.disabled ? '<span class="neg">disabled</span>' : (stale ? '<span class="neg">stale</span>' : '<span class="pos">active</span>');
    var left = Math.max(0, (l.limit || 0) - (l.usage_seen || 0));
    out += '<p>' + state + ' &middot; key <code>' + esc(l.hash) + '</code> on <code>' + esc(l.provider) + '</code>' +
      ' &middot; made ' + fmtTime(l.made) + '</p>';
    out += '<table><thead><tr><th></th><th class="num">Provider dollars</th><th class="num">Customer dollars</th></tr></thead><tbody>' +
      '<tr><td>Spent, as billed</td><td class="num">$' + esc(dollars(l.usage_seen)) + '</td><td class="num">$' + esc(dollars(Math.ceil((l.usage_seen || 0) * pct / 100))) + '</td></tr>' +
      '<tr><td>Cap</td><td class="num">$' + esc(dollars(l.limit)) + '</td><td class="num">$' + esc(dollars(Math.ceil((l.limit || 0) * pct / 100))) + '</td></tr>' +
      '<tr><td>Left under the cap</td><td class="num">$' + esc(dollars(left)) + '</td><td class="num">$' + esc(dollars(Math.ceil(left * pct / 100))) + '</td></tr>' +
      '</tbody></table>';
    out += '<p class="muted">Last reconciled ' + fmtTime(l.checked) + (l.checked ? ' (' + esc(ageWord(l.checked)) + ')' : '') +
      '. The tick reads the key every ten minutes; the cap follows the balance at ' + esc(String(pct)) + ' percent.</p>';
    var lv = liveLease[d.ship];
    if (lv && lv.error) out += '<p class="neg">' + esc(lv.error) + '</p>';
    else if (lv) {
      var o = lv.openrouter || {};
      var drift = lv.unbilled || 0;
      out += '<h3>From the provider, read ' + esc(ageWord(lv.at)) + '</h3>' +
        '<table><tbody>' +
        '<tr><td>Usage now</td><td class="num">$' + esc(dollars(o.usage)) + '</td></tr>' +
        '<tr><td>Today / this week / this month</td><td class="num">$' + esc(dollars(o.usage_daily)) + ' / $' + esc(dollars(o.usage_weekly)) + ' / $' + esc(dollars(o.usage_monthly)) + '</td></tr>' +
        '<tr><td>Cap on the key</td><td class="num">$' + esc(dollars(o.limit)) + '</td></tr>' +
        '<tr><td>Provider says remaining</td><td class="num">' + (o.limit_remaining == null ? '<span class="muted">no cap</span>' : '$' + esc(dollars(o.limit_remaining))) + '</td></tr>' +
        '<tr><td>Disabled at the provider</td><td class="num">' + (o.disabled ? '<span class="neg">yes</span>' : 'no') + '</td></tr>' +
        '<tr><td>Not yet billed</td><td class="num">' + (drift > 0 ? '<span class="neg">$' + esc(dollars(drift)) + ' (bills $' + esc(dollars(Math.ceil(drift * pct / 100))) + ' at the next reconcile)</span>' : '$0.00') + '</td></tr>' +
        '<tr><td>Key made / last changed</td><td class="num">' + fmtTime(o.created_at) + ' / ' + fmtTime(o.updated_at) + '</td></tr>' +
        '</tbody></table>';
    }
    var debits = ((d && d.ledger) || []).filter(function (r) { return r.kind === 'debit' && r.mode === 'lease'; });
    if (debits.length) {
      out += '<h3>Lease charges, newest first</h3>' + thead(['When', { name: 'Charged', num: true }, { name: 'Provider cost', num: true }, 'Ref']);
      debits.slice(0, 20).forEach(function (r) {
        out += '<tr>' + cell('When', fmtTime(r.at)) + cell('Charged', '$' + esc(dollars(r.amount)), 'num') +
          cell('Cost', '$' + esc(dollars(r.cost)), 'num') + cell('Ref', '<code>' + esc(r.ref) + '</code>') + '</tr>';
      });
      out += '</tbody></table>';
    }
    return out + '<p><button data-lease-live="1">Read from the provider now</button> ' +
      '<button data-reconcile="1">Reconcile now</button> ' +
      '<button class="danger" data-drop-lease="1">Drop lease</button></p></div>';
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
      '<p class="muted">A lease is a real provider key capped at the customer\'s balance, so a client calls the provider directly. Pick the OpenRouter provider whose provisioning key mints them, and every paying customer is given one within ten minutes; none means this vendor offers no leases and customers go through the proxy.</p>';
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
  function payments(st, plans, log, editing, provs, refunds) {
    var s = st || {};
    var pub = s.public_url || '';
    var hook = (pub || 'your public URL') + '/apps/armillary/hooks/stripe';
    var out = '<h1>Payments</h1><div class="card"><h2>Stripe</h2>' +
      '<p class="muted">The key and the signing secret are shown masked. Leave a field blank to keep what is stored.</p>' +
      '<div class="inline">' +
      '<div class="field"><label for="st-key">Secret key</label>' +
      '<input id="st-key" type="password" placeholder="rk_live_..."></div>' +
      '<div class="field"><label for="st-hook">Webhook signing secret</label>' +
      '<input id="st-hook" type="password" placeholder="leave blank to keep">' +
      '<span class="muted">Live mode will not save without it.</span></div>' +
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
    out += refundsCard(refunds || []);
    out += ringCard('Recent Stripe outcomes', 'stripe.', log);
    out += ringCard('Recent BTCPay outcomes', 'btcpay.', log);
    return out;
  }
  // bitcoin payments that landed on accounts being deleted: the owner
  // refunds each from BTCPay and says so here
  function refundsCard(rows) {
    if (!rows.length) return '';
    var out = '<div class="card"><h2>Refunds due</h2>' +
      '<p class="muted">A payment that landed on an account as it was deleted. Refund it from the invoice on BTCPay Server, then mark it done.</p><table><tr><th>Invoice</th><th>Amount</th><th>When</th><th></th></tr>';
    rows.forEach(function (r) {
      out += '<tr><td><code>' + esc(r.id) + '</code></td><td>' + '$' + esc(dollars(r.amount)) + '</td>' +
        '<td>' + fmtTime(r.at) + '</td><td><button data-refund-done="' + esc(r.id) + '">Done</button></td></tr>';
    });
    return out + '</table></div>';
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

  // ---- the report ----
  // one window of the ledger, in dollars. No charts: a table of eleven
  // numbers reads faster than any picture of them.
  // ==  the Data view (version 25): use by day as charts, by model, and
  // what it comes to. A customer sees its own, from the ninety days its
  // vendor puts in its view; a provider sees every account, its leases
  // and what its OpenRouter account has left.
  //
  // +bars: a series of days as bars scaled to the largest day, each
  // titled with its day and value, first and last day under it
  function bars(series, key, fmt, label) {
    var vals = (series || []).map(function (d) { return Number(d[key] || 0); });
    var max = Math.max.apply(null, vals.concat([0]));
    var n = vals.length || 1, W = 600, H = 120, gap = n > 60 ? 1 : 2, bw = (W - gap * (n - 1)) / n;
    var out = '<figure class="chart"><figcaption>' + esc(label) +
      ' <span class="muted">' + (max ? 'most in a day ' + esc(fmt(max)) : 'nothing yet') + '</span></figcaption>' +
      '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" role="img" aria-label="' + esc(label) + '">';
    vals.forEach(function (v, i) {
      var h = max ? Math.max(v ? 1.5 : 0, v / max * H) : 0;
      out += '<rect x="' + (i * (bw + gap)).toFixed(2) + '" y="' + (H - h).toFixed(2) + '" width="' + bw.toFixed(2) +
        '" height="' + h.toFixed(2) + '"><title>' + esc(series[i].day + ': ' + fmt(v)) + '</title></rect>';
    });
    var first = series && series.length ? series[0].day : '', last = series && series.length ? series[series.length - 1].day : '';
    return out + '</svg><div class="chart-days"><span>' + esc(first) + '</span><span>' + esc(last) + '</span></div></figure>';
  }
  function sumOf(series, key, n) {
    return (series || []).slice(-n).reduce(function (a, d) { return a + Number(d[key] || 0); }, 0);
  }
  // +rateOf: the average a day over the .n whole days before today
  // (today is not over), or over fewer when the series is shorter
  function rateOf(series, key, n) {
    var done = (series || []).slice(0, -1).slice(-n);
    return done.length ? sumOf(done, key, n) / done.length : 0;
  }
  function tokens(n) {
    n = Number(n || 0);
    return n >= 1e9 ? (n / 1e9).toFixed(1) + 'B' : n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e4 ? Math.round(n / 1e3) + 'k' : String(n);
  }
  function stat(n, l) { return '<div><span class="n">' + esc(String(n)) + '</span><span class="l">' + esc(l) + '</span></div>'; }
  function money$(m) { return '$' + dollars(m); }
  // +runway: how long .balance lasts at .rate a day, in words
  function runway(balance, rate) {
    if (balance <= 0) return { n: 'empty', l: 'balance' };
    if (!(rate > 0)) return { n: 'no spend', l: 'lately, so the balance holds' };
    var days = balance / rate;
    if (days > 365) return { n: 'over a year', l: 'the balance lasts at that rate' };
    var when = new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
    var whole = Math.floor(days);
    return { n: whole < 1 ? 'under a day' : whole + (whole === 1 ? ' day' : ' days'), l: 'the balance lasts at that rate, to ' + when };
  }
  function modelRows(models) {
    if (!models || !models.length) return '<p class="muted">Nothing used yet.</p>';
    var tok = models.some(function (m) { return Number(m['in'] || 0) + Number(m.out || 0) > 0; });
    return thead(['Model', { name: 'Spent', num: true }, { name: 'Requests', num: true }].concat(tok ? [{ name: 'Tokens', num: true }] : [])) +
      models.map(function (m) {
        return '<tr>' + cell('Model', '<code>' + esc(m.model) + '</code>') + cell('Spent', esc(money$(m.spent)), 'num') +
          cell('Requests', esc(m.requests), 'num') + (tok ? cell('Tokens', esc(tokens(Number(m['in'] || 0) + Number(m.out || 0))), 'num') : '') + '</tr>';
      }).join('') + '</tbody></table>';
  }
  var LEASE_NOTE = '<p class="muted">Under a lease your calls go straight to the provider, which reports what was spent every ten minutes but not the tokens or the model; that spend shows as <code>openrouter</code>.</p>';
  // +myData: a customer's own use, from its account view
  function myData(d) {
    var out = '<h1>Data</h1>';
    if (!d || !d.vendor) return out + '<div class="card"><p class="muted">Name a vendor on Account first; your use shows here once you buy from one.</p></div>';
    var u = d.daily;
    if (!u || !u.series) return out + '<div class="card"><p class="muted">Your vendor\'s Armillary does not send use by day yet. It will once it runs version 25.</p></div>';
    var s = u.series, bal = Number(d.balance || 0);
    var rate = rateOf(s, 'spent', 7) || rateOf(s, 'spent', 30);
    var run = runway(bal, rate);
    var tok = sumOf(s, 'in', s.length) + sumOf(s, 'out', s.length) > 0;
    out += '<div class="card"><h2>The last 30 days</h2><div class="stats">' +
      stat(money$(sumOf(s, 'spent', 30)), 'spent') + stat(sumOf(s, 'requests', 30), 'requests') +
      (tok ? stat(tokens(sumOf(s, 'in', 30) + sumOf(s, 'out', 30)), 'tokens') : '') + stat(money$(sumOf(s, 'credited', 30)), 'credited') + '</div></div>';
    out += '<div class="card"><h2>Ahead</h2><div class="stats">' +
      stat(money$(bal), 'balance now') + stat(money$(rate), 'a day lately') + stat(money$(rate * 30), 'the next 30 days at that rate') +
      stat(run.n, run.l) + '</div>' +
      '<p class="muted">"Lately" is the average of the last seven whole days, or of the last thirty when the week was idle.</p>';
    var l = d.lease;
    if (l && l.limit !== undefined) {
      out += '<p>Lease: spent $' + esc(dollars(l.usage)) + ' of a $' + esc(dollars(l.limit)) + ' cap' +
        (l.disabled ? ' <span class="neg">(disabled: top up to spend again)</span>' : '') + '.</p>';
    }
    out += '</div><div class="card"><h2>By day, the last ' + esc(u.days) + ' days</h2>' +
      bars(s, 'spent', money$, 'Spent') + bars(s, 'requests', String, 'Requests') +
      (tok ? bars(s.map(function (x) { return { day: x.day, t: Number(x['in'] || 0) + Number(x.out || 0) }; }), 't', tokens, 'Tokens') : '') + '</div>';
    out += '<div class="card"><h2>By model, the last ' + esc(u.days) + ' days</h2>' + modelRows(u.models) + (l && !tok ? LEASE_NOTE : '') + '</div>';
    return out;
  }
  // +vendorData: every account's use, the leases' caps, the day totals
  // with the provider's cost, and what each provider has left
  function vendorData(d, days) {
    d = d || {};
    var pick = [7, 30, 90].map(function (n) {
      return '<button data-data-days="' + n + '"' + (Number(days) === n ? ' class="on"' : '') + '>' + n + ' days</button>';
    }).join(' ');
    var t = d.totals || {}, s = t.series || [];
    var spent = sumOf(s, 'spent', s.length), cost = sumOf(s, 'cost', s.length);
    var rate = rateOf(s, 'spent', 7) || rateOf(s, 'spent', 30), costRate = rateOf(s, 'cost', 7) || rateOf(s, 'cost', 30);
    var out = '<h1>Data</h1><div class="card"><p>' + pick + '</p><div class="stats">' +
      stat(money$(spent), 'charged') + stat(money$(cost), 'cost') + stat(money$(spent - cost), 'margin') +
      stat(sumOf(s, 'requests', s.length), 'requests') +
      (sumOf(s, 'in', s.length) + sumOf(s, 'out', s.length) > 0 ? stat(tokens(sumOf(s, 'in', s.length) + sumOf(s, 'out', s.length)), 'tokens') : '') +
      stat(money$(sumOf(s, 'credited', s.length)), 'credited') + '</div>' +
      '<div class="stats">' + stat(money$(rate), 'charged a day lately') + stat(money$(rate * 30), 'charged the next 30 days') +
      stat(money$(costRate * 30), 'cost the next 30 days') + '</div></div>';
    // what each provider's account has left, against what the leases on
    // it may still spend. OpenRouter's figures are the whole account's,
    // which may pay for keys outside Armillary too, so no "lasts": a
    // rate from Armillary's cost alone said thousands of days.
    var provs = (d.providers || []).filter(function (p) { return p.credits; });
    if (provs.length) {
      var headroom = function (pid) {
        return (d.accounts || []).reduce(function (sum, x) {
          var l = x.lease;
          if (!l || l.provider !== pid || l.disabled || (x.account || {}).closed) return sum;
          return sum + Math.max(0, Number(l.limit || 0) - Number(l.usage_seen || 0));
        }, 0);
      };
      var short = [];
      out += '<div class="card"><h2>Provider credits</h2>' +
        thead(['Provider', { name: 'Bought', num: true }, { name: 'Used', num: true }, { name: 'Left', num: true }, { name: 'Leases may spend', num: true }]) +
        provs.map(function (p) {
          var c = p.credits;
          if (c.error) return '<tr>' + cell('Provider', esc(p.name || p.id)) + '<td colspan="4" class="neg">' + esc(c.error) + '</td></tr>';
          var left = (Number(c.total || 0) - Number(c.used || 0)) * 1000000, may = headroom(p.id);
          if (may > left) short.push((p.name || p.id) + ': the leases may spend ' + money$(may) + ' but the account has ' + money$(left) + ' left');
          return '<tr>' + cell('Provider', esc(p.name || p.id)) + cell('Bought', esc(money$(Number(c.total || 0) * 1000000)), 'num') +
            cell('Used', esc(money$(Number(c.used || 0) * 1000000)), 'num') + cell('Left', '<strong>' + esc(money$(left)) + '</strong>', 'num') +
            cell('Leases may spend', '<span class="' + (may > left ? 'neg' : '') + '">' + esc(money$(may)) + '</span>', 'num') + '</tr>';
        }).join('') + '</tbody></table>' +
        short.map(function (t) { return '<p class="neg">' + esc(t) + '. Top up the provider account, or customers\' calls are refused before their caps stop them.</p>'; }).join('') +
        '<p class="muted">Read live from the provider with its provisioning key. Its figures are the whole provider account\'s, which may also pay for keys outside Armillary. "Leases may spend" is each open lease\'s cap less what it has spent, in the provider\'s dollars.</p></div>';
    }
    out += '<div class="card"><h2>By day</h2>' + bars(s, 'spent', money$, 'Charged') + bars(s, 'cost', money$, 'Cost') +
      bars(s, 'requests', String, 'Requests') + '</div>';
    var accts = (d.accounts || []).slice().sort(function (a, b) {
      return sumOf((b.usage || {}).series, 'spent', 999) - sumOf((a.usage || {}).series, 'spent', 999);
    });
    out += '<div class="card"><h2>Customers</h2>';
    if (!accts.length) out += '<p class="muted">No accounts yet.</p>';
    else {
      var atok = accts.some(function (x) { var us = (x.usage || {}).series || []; return sumOf(us, 'in', us.length) + sumOf(us, 'out', us.length) > 0; });
      out += thead(['Ship', { name: 'Balance', num: true }, { name: 'Spent', num: true }, { name: 'Requests', num: true }]
        .concat(atok ? [{ name: 'Tokens', num: true }] : [], ['Lease cap', 'Lasts', 'Last used'])) +
        accts.map(function (x) {
          var a = x.account || {}, us = (x.usage || {}).series || [], l = x.lease;
          var r = rateOf(us, 'spent', 7) || rateOf(us, 'spent', 30), run = runway(Number(a.balance || 0), r);
          var lastDay = us.slice().reverse().filter(function (dd) { return Number(dd.spent || 0) > 0; })[0];
          var cap = l ? '$' + dollars(l.usage_seen) + ' of $' + dollars(l.limit) + (l.disabled ? ' <span class="neg">off</span>' : '') : '<span class="muted">none</span>';
          return '<tr' + (a.closed ? ' class="closed"' : '') + '>' +
            cell('Ship', '<a href="#accounts/' + esc(a.ship) + '"><code>' + esc(a.ship) + '</code></a>') +
            cell('Balance', esc(money$(a.balance)), 'num') + cell('Spent', esc(money$(sumOf(us, 'spent', us.length))), 'num') +
            cell('Requests', esc(sumOf(us, 'requests', us.length)), 'num') + (atok ? cell('Tokens', esc(tokens(sumOf(us, 'in', us.length) + sumOf(us, 'out', us.length))), 'num') : '') +
            cell('Lease cap', cap) + cell('Lasts', esc(run.n)) + cell('Last used', esc(lastDay ? lastDay.day : 'not in these days')) + '</tr>';
        }).join('') + '</tbody></table>' +
        '<p class="muted">A lease\'s cap and spend are in the provider\'s dollars, before your markup. "Lasts" is the balance at the account\'s spend lately.</p>';
    }
    out += '</div><div class="card"><h2>By model</h2>' + modelRows(t.models) + '</div>';
    return out;
  }
  function report(d, days) {
    var r = d || {};
    var c = r.credits || {};
    var pick = [7, 30, 90].map(function (n) {
      return '<button data-days="' + n + '"' +
        (Number(days) === n ? ' class="on"' : '') + '>' + n + ' days</button>';
    }).join(' ');
    var out = '<h1>Report</h1><div class="card"><p>' + pick + '</p>' +
      '<p class="muted">Accounts that moved money: ' + esc(r.accounts || 0) + '</p></div>';
    out += '<div class="card"><h2>Money</h2>' +
      thead(['What', { name: 'Dollars', num: true }]) +
      money('Credit by card', c.stripe) +
      money('Credit by bitcoin', c.btcpay) +
      money('Credit by the owner', c.owner) +
      money('Credit through the stub', c.stub) +
      (Number(c.other || 0) ? money('Credit by another rail', c.other) : '') +
      money('Refunded', r.refunds) +
      money('Charged', r.charged) +
      money('Cost upstream', r.cost) +
      '<tr>' + cell('What', 'Margin') +
      cell('Dollars', signed(r.margin), 'num') + '</tr>' +
      money('Spent on leases', r.lease_spend) +
      '</tbody></table></div>';
    out += '<div class="card"><h2>Work</h2>' +
      thead(['What', { name: 'Count', num: true }]) +
      count('Proxy requests', r.requests) +
      count('Tokens in', r.tokens_in) +
      count('Tokens out', r.tokens_out) +
      '</tbody></table></div>';
    out += '<div class="card"><h2>Top models</h2>';
    var tops = r.top_models || [];
    if (!tops.length) return out + '<p class="muted">Nothing charged yet.</p></div>';
    out += thead(['Model', { name: 'Charged', num: true },
      { name: 'Cost', num: true }, { name: 'Requests', num: true }]);
    tops.forEach(function (t) {
      out += '<tr>' +
        cell('Model', '<code>' + esc(t.model) + '</code>') +
        cell('Charged', esc(dollars(t.charged)), 'num') +
        cell('Cost', esc(dollars(t.cost)), 'num') +
        cell('Requests', esc(t.requests), 'num') +
        '</tr>';
    });
    return out + '</tbody></table></div>';
  }
  function money(label, micros) {
    return '<tr>' + cell('What', esc(label)) +
      cell('Dollars', esc(dollars(micros)), 'num') + '</tr>';
  }
  function count(label, n) {
    return '<tr>' + cell('What', esc(label)) +
      cell('Count', esc(Number(n || 0)), 'num') + '</tr>';
  }

  // ---- the customer's own views ----
  // the ledger table is the same one the owner reads, so one renderer
  // serves both sides
  // +tokenCell: a charge's tokens, when it has counts. A lease's charge
  // is what the provider says the key spent over ten minutes, with no
  // tokens or model, and printed "0 in, 0 out" as if it were a count.
  // A table none of whose rows has counts shows no Tokens column at all
  // (sneagan: "if the value will always be empty don't even show it").
  function hasTokens(r) { return r.kind === 'debit' && (Number(r['in'] || 0) > 0 || Number(r.out || 0) > 0); }
  function tokenCell(r) { return hasTokens(r) ? esc(r['in'] + ' in, ' + r.out + ' out') : ''; }
  function ledger(rows) {
    if (!rows.length) return '<p class="muted">Nothing yet.</p>';
    var tok = rows.some(hasTokens);
    var out = thead(['At', 'Kind', { name: 'Amount', num: true }, 'Model'].concat(tok ? [{ name: 'Tokens', num: true }] : [], ['Ref']));
    rows.forEach(function (r) {
      out += '<tr>' +
        cell('At', fmtTime(r.at)) +
        cell('Kind', esc(r.kind)) +
        cell('Amount', esc(dollars(r.amount)), 'num') +
        cell('Model', esc(r.model)) +
        (tok ? cell('Tokens', tokenCell(r), 'num') : '') +
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
    if (c.note && s !== 'cancelled') return esc(s) + ' &middot; ' + esc(c.note);
    return esc(s);
  }
  // .mine: the customer's own rows, which a pending one can cancel; the
  // owner's view of an account shows them without the button
  function checkoutRows(obj, mine) {
    var keys = Object.keys(obj || {});
    if (!keys.length) return '';
    var out = '<div class="card"><h2>Checkouts</h2>' +
      thead(['Order', 'Rail', { name: 'Amount', num: true }, 'Status', '']);
    keys.forEach(function (n) {
      var c = obj[n] || {};
      var open = c.url ? '<a href="' + esc(c.url) + '" target="_blank" rel="noopener">Open</a>' : '';
      var cancel = mine && c.status === 'pending'
        ? ' <button data-cancel-checkout="' + esc(n) + '">Cancel</button>' : '';
      out += '<tr>' +
        cell('Order', '<code>' + esc(n) + '</code>') +
        cell('Rail', esc(railName(c.rail))) +
        cell('Amount', esc(dollars(c.amount)), 'num') +
        cell('Status', statusLine(c)) +
        cell('', open + cancel) +
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
          : ' for $' + esc(dollars(p.credit)) + ' of credit';
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
  // +usage: what the ledger says about spending. The view carries the
  // newest fifty rows, so the month figure is exact while a month holds
  // fewer than fifty charges and a floor after that; the all-time
  // figures come from the balance instead, which the ship keeps whole.
  function usage(rows, now) {
    var t = now || Date.now();
    var month = t - 30 * 86400000;
    var u = { month: 0, charges: 0, tokens: 0, models: [], credited: 0, spent: 0, floor: false };
    var by = Object.create(null);
    (rows || []).forEach(function (r) {
      if (r.kind === 'credit') { u.credited += (r.amount || 0); return; }
      if (r.kind !== 'debit') return;
      u.spent += (r.amount || 0);
      var at = Date.parse(r.at || '') || 0;
      if (at < month) return;
      u.month += (r.amount || 0);
      u.charges += 1;
      u.tokens += (r.in || 0) + (r.out || 0);
      var m = r.model || (r.mode === 'lease' ? 'lease' : 'other');
      by[m] = (by[m] || 0) + (r.amount || 0);
    });
    u.floor = (rows || []).length >= 50;
    u.models = Object.keys(by).map(function (m) { return { model: m, amount: by[m] }; })
      .sort(function (a, b) { return b.amount - a.amount; }).slice(0, 5);
    return u;
  }
  function usageCard(d) {
    var u = usage((d && d.ledger) || []);
    var out = '<div class="card"><h2>Usage</h2><div class="stats">' +
      '<div><span class="n">$' + esc(dollars(u.month)) + (u.floor ? '+' : '') + '</span><span class="l">spent, last 30 days</span></div>' +
      '<div><span class="n">' + u.charges + (u.floor ? '+' : '') + '</span><span class="l">requests</span></div>' +
      (u.tokens ? '<div><span class="n">' + esc(String(u.tokens)) + (u.floor ? '+' : '') + '</span><span class="l">tokens</span></div>' : '') +
      '</div>';
    if (u.models.length) {
      out += thead(['Model', { name: 'Spent', num: true }]);
      u.models.forEach(function (m) {
        out += '<tr>' + cell('Model', '<code>' + esc(m.model) + '</code>') +
          cell('Spent', '$' + esc(dollars(m.amount)), 'num') + '</tr>';
      });
      out += '</tbody></table>';
    } else out += '<p class="muted">No requests in the last 30 days.</p>';
    if (u.floor) out += '<p class="muted">The ledger below shows the newest fifty rows, so these figures are a floor.</p>';
    return out + '</div>';
  }
  // +freshness: how old this ship's copy of the balance is, and how long
  // its last read from the vendor took
  function freshness(d) {
    if (!d || d.stale === undefined || !d.fetched) return 'Not read from the vendor yet. Refresh reads it now.';
    var s = Number(d.stale), age = s < 90 ? s + ' s' : Math.round(s / 60) + ' min';
    var took = d.fetch_ms ? ', in ' + (Number(d.fetch_ms) / 1000).toFixed(1) + ' s' : '';
    return 'As of ' + esc(age) + ' ago' + took + '. Your ship rereads it every five minutes; Refresh reads it now.';
  }
  function myAccount(d, plans) {
    var vendor = (d && d.vendor) || '';
    myVendor = vendor;
    var out = '<h1>Account</h1>' +
      '<div class="card"><h2>Vendor</h2><p>' +
      (vendor ? '<code>' + esc(vendor) + '</code>' : '<span class="muted">none set</span>') +
      (vendor && d.stale !== undefined ? ' <span class="muted">read ' + esc(d.stale) + 's ago</span>' : '') +
      '</p><div class="inline">' +
      '<div class="field"><label for="v-ship">Set vendor</label>' +
      '<input id="v-ship" value="' + esc(vendor) + '" placeholder="~wex"></div>' +
      '<div class="field"><label>&nbsp;</label><button data-set-vendor="1">Save</button>' +
      '<button data-refresh-view="1">Refresh</button></div></div></div>';
    if (!vendor) return out + '<p class="muted">Name a vendor ship above to open an account on it. Talon sets this for you when you add the Armillary provider.</p>' +
      '<p class="muted">Running a service of your own instead? Switch on Provider mode in the header.</p>';
    myCheckouts = (d && d.checkouts) || {};
    out += '<div class="card"><h2>Balance</h2>' +
      '<p style="font-size:1.6rem;margin:.2rem 0">$' + signed(d && d.balance) + '</p>' +
      '<p class="muted">' + freshness(d) + '</p>' +
      '<p id="pay-watch" class="watch ' + watchSaid.cls + '">' + esc(watchSaid.text) + '</p>' +
      subscriptionLine(d, plans) +
      '<div class="inline">' +
      planButtons(plans) +
      '<div class="field"><label for="t-amount">Top up, dollars</label><input id="t-amount" value=""></div>' +
      '<div class="field"><label>Rail</label>' +
      '<span class="rails"><label><input type="radio" name="rail" value="stripe" checked> Card</label> ' +
      '<label><input type="radio" name="rail" value="btcpay"> Bitcoin</label></span>' +
      (plans.some(function (p) { return p.kind === 'subscription'; }) ? '<span class="muted">Subscriptions are card only.</span>' : '') + '</div>' +
      '<div class="field"><label>&nbsp;</label><button data-topup="1">Top up</button></div>' +
      '</div></div>';
    out += checkoutRows(d && d.checkouts, true);
    out += usageCard(d);
    return out + '<div class="card"><h2>Ledger</h2>' + ledger((d && d.ledger) || []) + '</div>';
  }
  // the customer's own half of a lease. The key is not shown here: the
  // inference config box below is where a client reads it.
  function myLease(d) {
    var l = d && d.lease;
    var err = (d && d.lease_error) || '';
    var out = '<div class="card"><h2>Lease</h2>' +
      '<p class="muted">A lease is a real provider key capped at your balance, so a client calls the provider directly: streaming, tools and the provider\'s own latency.</p>';
    if (err === 'given back') out += '<p class="muted">You gave your lease back, so your vendor will not give you another until you take one.</p>';
    else if (err === 'dropped by the owner') out += '<p class="muted">Your vendor took this lease back. You can take another.</p>';
    else if (err) out += '<p class="neg">' + esc(err) + '</p>';
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
    var kept = rankModels(filter, rows || []);
    var out = '<h1>Catalog</h1><div class="card">' +
      '<div class="field"><label for="buy-filter">Filter</label>' +
      '<input id="buy-filter" type="search" value="' + esc(filter || '') + '" placeholder="search: opus 5, gpt mini, kimi" autocomplete="off" spellcheck="false"></div>' +
      '<span class="muted"> ' + kept.length + ' of ' + (rows || []).length + ' models</span></div>';
    if (!kept.length) return out + '<p class="muted">' + ((rows || []).length ? 'No model fits.' : 'The vendor offers nothing yet.') + '</p>';
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

  // state the render functions read, declared before the node export so
  // scripts/render-check.js sees it too
  var myVendor = '';                   // the vendor the account view last named
  var myCheckouts = {};                // the checkout rows that view last held
  var mySuggested = { rev: 0, tiers: {}, features: {}, models: {} };   // the AI this vendor drives
  var myBrave = { key_set: false, searches: {} };   // the vendor's Brave settings, without the key
  var watchSaid = { text: '', cls: '' };    // the line the Balance card shows
  var render = {
    esc: esc, dollars: dollars, micro: micro, margin: margin,
    providers: providers, catalog: catalog, accounts: accounts, account: account,
    payments: payments, planRows: planRows, planButtons: planButtons,
    leaseCard: leaseCard, leaseSetting: leaseSetting, report: report,
    subscriptionLine: subscriptionLine,
    myAccount: myAccount, myKeys: myKeys, myLease: myLease, buyCatalog: buyCatalog,
    usage: usage, usageCard: usageCard,
    checkoutRows: checkoutRows, freshness: freshness, suggestedCard: suggestedCard, braveCard: braveCard, rankModels: rankModels, catalog: catalog, buyCatalog: buyCatalog, myData: myData, vendorData: vendorData, ledger: ledger, bars: bars, rateOf: rateOf, runway: runway,
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
  // provider mode shows the views that run a service; off, the page is
  // a customer's balance and usage. The choice is kept in this browser.
  var providerMode = false;
  var VENDOR_VIEWS = { providers: 1, accounts: 1, account: 1, payments: 1, report: 1 };
  var buyFilter = '';
  var dataDays = 30;                   // the provider's Data window
  var buyRows = [];                    // what the vendor sells, as last read, for the live filter
  var custMinted = null;               // a fetched secret shown once
  var planEditing = null;              // the plan id whose form is open
  var st0 = null;                      // the settings the Payments view last read
  var reportDays = 30;                 // the Report view's window
  var myPlans = [];                    // the vendor's plans, as the customer reads them
  var held = null;                     // [html, class] the next redraw puts back

  function say(msg, bad) { statusEl.textContent = msg; statusEl.className = 'status' + (bad ? ' bad' : ''); }
  // +startCheckout: a checkout from a plan or an amount, said step by
  // step in the status line and in the new tab, while the button says it
  // is busy. The tab opens inside the click: one opened after the vendor
  // answers comes too late, and the browser blocks it without a word.
  // the new tab is its own document, so it carries the page's two
  // palettes itself and follows the system the same way
  var TAB_STYLE = '<style>:root{color-scheme:light dark}' +
    'body{margin:0;font:18px/1.5 system-ui,sans-serif;color:#1b2a4a;background:#fbfbfd}' +
    'div{max-width:34rem;margin:18vh auto;padding:0 1rem;text-align:center}.bad{color:#b3261e}' +
    '@media (prefers-color-scheme:dark){body{color:#e4e8f2;background:#11151f}.bad{color:#ff8a80}}</style>';
  function startCheckout(body, btn) {
    var tab = window.open('', '_blank');
    if (tab) { tab.opener = null; tab.document.title = 'Checkout'; }
    var who = myVendor || 'the vendor';
    var t0 = Date.now(), polls = 0, label = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Opening checkout…';
    // the seconds count on their own, so a wait never looks frozen
    var cur = '', tick = setInterval(function () { if (cur) tell(cur); }, 1000);
    function tell(msg, bad, html) {
      cur = bad ? '' : msg;
      var line = msg + (bad ? '' : ' (' + Math.round((Date.now() - t0) / 1000) + ' s)');
      say(line, bad);
      if (!tab) return;
      try {
        tab.document.body.innerHTML = TAB_STYLE +
          '<div class="' + (bad ? 'bad' : '') + '">' + esc(line) + (html || '') + '</div>';
      } catch (e) { /* the tab has left for the checkout */ }
    }
    function done() {
      clearInterval(tick);
      held = [statusEl.innerHTML, statusEl.className];
      btn.disabled = false; btn.textContent = label; later();
    }
    function fail(e) { tell(e.message, true, '<p>You can close this tab.</p>'); done(); }
    function land(p) {
      if (!p.url || p.status === 'refused' || p.status === 'unavailable') {
        tell(who + ' refused the checkout: ' + (p.note || p.status), true, '<p>You can close this tab.</p>');
        return done();
      }
      if (tab) {
        tell('Checkout ready; opening it');
        tab.location.replace(p.url);
        say('Checkout opened in a new tab');
      } else {
        // a blocker refused even the tab opened in the click: a link is
        // a click of its own, which no blocker refuses
        statusEl.innerHTML = 'Checkout ready: <a href="' + esc(p.url) + '" target="_blank" rel="noopener">open it</a>';
        statusEl.className = 'status';
      }
      watch(p.nonce);
      done();
    }
    tell('Placing the order on your ship');
    body.wait = false;
    post('/checkout', body).then(function (r) {
      (function poll() {
        polls++;
        api('/checkout/' + seg(r.nonce) + (polls % 2 ? '' : '?nudge=1')).then(function (p) {
          p.nonce = r.nonce;
          if (p.phase === 'answered') return land(p);
          if (Date.now() - t0 > 90000) {
            tell('No answer from ' + who + ' in 90 s. Your ship keeps asking; the checkout will appear under Checkouts with an Open link', true, '<p>You can close this tab.</p>');
            return done();
          }
          tell(p.phase === 'sent' ? 'Sent to ' + who + '; waiting for the checkout'
            : p.phase === 'queued' ? 'Sending the order to ' + who
            : 'Placing the order on your ship');
          setTimeout(poll, 1500);
        }).catch(fail);
      })();
    }).catch(fail);
  }
  // +busy: the status line saying .msg with its seconds counting, until
  // the function it answers is called
  function busy(msg) {
    var t0 = Date.now();
    function show() { say(msg + ' (' + Math.round((Date.now() - t0) / 1000) + ' s)'); }
    show();
    var iv = setInterval(show, 1000);
    return function () { clearInterval(iv); };
  }
  // the checkouts this browser opened, nonce to the time it opened them,
  // kept across a reload. The vendor credits a payment the moment its
  // rail says so, but this ship only rereads the vendor every five
  // minutes, so a watched checkout is read fresh until it is paid or over.
  var WATCH_KEY = 'armillary.watch';
  function watched() {
    try { return JSON.parse(localStorage.getItem(WATCH_KEY) || '{}') || {}; } catch (e) { return {}; }
  }
  function setWatched(w) {
    try { localStorage.setItem(WATCH_KEY, JSON.stringify(w)); } catch (e) { /* a private window */ }
  }
  function watch(n) { var w = watched(); w[n] = Date.now(); setWatched(w); payWatch(); }
  function unwatch(n) { var w = watched(); delete w[n]; setWatched(w); }
  var watching = false;
  // +payWatch: one loop at a time. Each round reads the vendor fresh and
  // says what came of every watched checkout; between rounds the line
  // says when it last looked. A card checkout is watched for fifteen
  // minutes, a bitcoin one confirming for two hours.
  function payWatch() {
    if (watching || !Object.keys(watched()).length) return;
    watching = true;
    var checking = 0, last = 0, waiting = '';
    function secs(t) { return Math.round((Date.now() - t) / 1000); }
    function line(text, cls) { watchSaid = { text: text, cls: cls || '' }; show(); }
    function show() {
      if (checking) watchSaid = { text: 'Checking with ' + (myVendor || 'the vendor') + ' for your payment (' + secs(checking) + ' s)', cls: '' };
      else if (waiting) watchSaid = { text: waiting + ' Last checked ' + secs(last) + ' s ago.', cls: '' };
      var el = document.getElementById('pay-watch');
      if (el) { el.textContent = watchSaid.text; el.className = 'watch ' + watchSaid.cls; }
    }
    var tick = setInterval(show, 1000);
    function stop() { clearInterval(tick); watching = false; waiting = ''; show(); }
    (function round() {
      checking = Date.now(); show();
      api('/account?fresh=1').then(function (d) {
        checking = 0; last = Date.now(); waiting = '';
        var w = watched(), rows = d.checkouts || {}, said = '', cls = '';
        Object.keys(w).forEach(function (n) {
          var r = rows[n] || {}, age = Date.now() - w[n], amt = '$' + dollars(r.amount);
          if (r.status === 'paid') { said = 'Payment received: ' + amt + ' added.'; cls = 'pos'; delete w[n]; }
          else if (r.status === 'failed') { said = 'The ' + amt + ' payment did not go through.'; cls = 'neg'; delete w[n]; }
          else if (r.status === 'expired') { said = 'The ' + amt + ' checkout expired before it was paid.'; delete w[n]; }
          else if (r.status === 'cancelled' || r.status === 'refused') { delete w[n]; }
          else if (r.status === 'processing') {
            if (age > 2 * 3600000) delete w[n];
            else waiting = 'Bitcoin payment of ' + amt + ' seen; waiting for confirmations, usually ten to twenty minutes.';
          } else if (age > 15 * 60000) {
            said = 'Stopped watching the ' + amt + ' checkout after fifteen minutes. Refresh reads the balance again.'; delete w[n];
          } else if (!waiting) waiting = 'Waiting for your ' + amt + ' payment. It shows here as soon as ' + (myVendor || 'the vendor') + ' has it.';
        });
        setWatched(w);
        // the fresh read stored the new balance; a redraw shows it, unless
        // the person is typing into the page
        if (route(location.hash).name === 'my-account' && !typing()) refresh();
        if (said) line(said, cls);
        if (Object.keys(w).length) return setTimeout(round, 10000);
        if (!said) line('', '');
        stop();
        // the last word stays two minutes, through any redraw
        setTimeout(function () { if (!watching) { watchSaid = { text: '', cls: '' }; show(); } }, 120000);
      }).catch(function () {
        checking = 0; last = Date.now();
        waiting = 'Could not reach ' + (myVendor || 'the vendor') + ' just now; trying again.';
        setTimeout(round, 15000);
      });
    })();
  }
  // +cancelCheckout: ask the vendor to stop a pending checkout, with the
  // ask's seconds counting until the row moves; the vendor answers by
  // rewriting the row, cancelled or with its reason
  function cancelCheckout(n, btn) {
    var who = myVendor || 'the vendor';
    var before = myCheckouts[n] || {};
    var t0 = Date.now(), polls = 0;
    btn.disabled = true; btn.textContent = 'Cancelling…';
    var stop = busy('Asking ' + who + ' to cancel the checkout');
    function end(msg, bad) {
      stop(); say(msg, bad);
      held = [statusEl.innerHTML, statusEl.className];
      later();
    }
    post('/checkout/' + seg(n) + '/cancel', { wait: false }).then(function () {
      (function poll() {
        polls++;
        api('/checkout/' + seg(n) + (polls % 2 ? '' : '?nudge=1')).then(function (p) {
          if (p.phase === 'answered' && (p.status !== before.status || p.note !== (before.note || ''))) {
            if (p.status === 'cancelled') { unwatch(n); return end('Checkout cancelled'); }
            return end(who + ' did not cancel it: ' + (p.note || p.status), true);
          }
          if (Date.now() - t0 > 60000) {
            return end('No answer from ' + who + ' in 60 s. Your ship keeps asking; the row updates when it answers', true);
          }
          setTimeout(poll, 1500);
        }).catch(function (e) { end(e.message, true); });
      })();
    }).catch(function (e) { end(e.message, true); });
  }
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
          payWatch();   // a checkout opened before a reload is still watched
        });
      });
    } else if (r.name === 'payments') {
      p = api('/settings').then(function (st) {
        st0 = st;
        return api('/plans').then(function (pl) {
          return api('/log').catch(function () { return []; }).then(function (lg) {
            return api('/providers').catch(function () { return []; }).then(function (pv) {
              return api('/refunds-due').catch(function () { return []; }).then(function (rd) {
                draw(payments(st, pl || [], lg || [], planEditing, pv || [], rd || []));
              });
            });
          });
        });
      });
    } else if (r.name === 'data' && !providerMode) {
      p = api('/account').then(function (d) { draw(myData(d)); });
    } else if (r.name === 'data') {
      p = api('/data?days=' + encodeURIComponent(dataDays)).then(function (d) { draw(vendorData(d, dataDays)); });
    } else if (r.name === 'report') {
      p = api('/report?days=' + encodeURIComponent(reportDays))
        .then(function (d) { draw(report(d, reportDays)); });
    } else if (r.name === 'keys') {
      p = api('/keys').then(function (keys) {
        return api('/inference').catch(function () { return null; })
          .then(function (cfg) {
            return api('/account').catch(function () { return null; })
              .then(function (acct) { draw(myKeys(keys || [], cfg, custMinted, acct)); });
          });
      });
    } else if (r.name === 'catalog' && !providerMode) {
      p = api('/catalog').then(function (rows) { buyRows = rows || []; draw(buyCatalog(buyRows, buyFilter)); });
    } else if (r.name === 'catalog') {
      p = api('/catalog').then(function (rows) {
        catRows = rows || [];
        return api('/suggested').catch(function () { return mySuggested; }).then(function (sg) {
          mySuggested = sg || mySuggested;
          return api('/brave').catch(function () { return myBrave; }).then(function (bv) {
            myBrave = bv || myBrave;
            draw(catalog(catRows, catFilter));
          });
        });
      });
    } else if (r.name === 'accounts') {
      p = api('/accounts').then(function (rows) { draw(accounts(rows || [], acctSearch)); });
    } else if (r.name === 'account') {
      // a ship with no account is a 404, and the view draws anyway
      p = api('/accounts/' + seg(r.ship)).catch(function () { return null; })
        .then(function (d) { draw(account(r.ship, d, minted)); });
    } else {
      p = api('/providers').then(function (rows) { draw(providers(rows || [], tests, editing)); });
    }
    // a checkout's last word outlives the redraw that follows it
    p = p.then(function () {
      if (held) { statusEl.innerHTML = held[0]; statusEl.className = held[1]; } else say('');
      held = null;
    }).catch(function (e) { say(String(e.message || e), true); });
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
    else if (el.id === 'buy-filter') { buyFilter = el.value; view.innerHTML = buyCatalog(buyRows, buyFilter); var bf = document.getElementById('buy-filter'); if (bf) { bf.focus(); bf.setSelectionRange(bf.value.length, bf.value.length); } }
    else if (el.id === 'acct-search') { acctSearch = el.value; }
    if (el.dataset.tier) sgDraft.tiers[el.dataset.tier] = el.value;
    if (el.dataset.pick) pickList(el);
  });
  // the model boxes: open on focus, arrows move, Enter or a click takes
  // the model, Escape or leaving closes
  view.addEventListener('focusin', function (ev) { if (ev.target.dataset && ev.target.dataset.pick) pickList(ev.target); });
  view.addEventListener('focusout', function (ev) { if (ev.target.dataset && ev.target.dataset.pick) pickClose(ev.target); });
  view.addEventListener('keydown', function (ev) {
    var el = ev.target;
    if (!el.dataset || !el.dataset.pick) return;
    var list = document.getElementById(el.id + '-list');
    if (!list) return;
    if (ev.key === 'Escape') { pickClose(el); return; }
    if (list.hidden && (ev.key === 'ArrowDown' || ev.key === 'ArrowUp')) list = pickList(el);
    var items = Array.prototype.slice.call(list.querySelectorAll('li[data-pick-id]'));
    var at = items.findIndex(function (li) { return li.classList.contains('on'); });
    if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
      ev.preventDefault();
      if (!items.length) return;
      var next = ev.key === 'ArrowDown' ? Math.min(items.length - 1, at + 1) : Math.max(0, at - 1);
      items.forEach(function (li, i) { li.classList.toggle('on', i === next); });
      items[next].scrollIntoView({ block: 'nearest' });
    } else if (ev.key === 'Enter' && !list.hidden && at >= 0) {
      ev.preventDefault();
      el.value = items[at].dataset.pickId;
      if (el.dataset.tier) sgDraft.tiers[el.dataset.tier] = el.value;
      pickClose(el);
    }
  });
  // mousedown, not click: a click lands after the box has lost focus and
  // closed its list
  view.addEventListener('mousedown', function (ev) {
    var li = ev.target.closest && ev.target.closest('li[data-pick-id]');
    if (!li) return;
    ev.preventDefault();
    var input = document.getElementById(li.parentNode.id.replace(/-list$/, ''));
    if (!input) return;
    input.value = li.dataset.pickId;
    if (input.dataset.tier) sgDraft.tiers[input.dataset.tier] = input.value;
    pickClose(input);
  });
  view.addEventListener('change', function (ev) {
    if (ev.target.dataset && ev.target.dataset.feature) sgDraft.features[ev.target.dataset.feature] = ev.target.value;
    if (ev.target.name === 'kind') {
      var box = document.getElementById('p-prov');
      if (box) box.hidden = ev.target.value !== 'openrouter';
    } else if (ev.target.id === 'acct-search') {
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
        tests[d['import']] = { text: 'added ' + r.added + (r.zdr != null ? '; ' + r.zdr + ' tagged zdr from its ZDR list' : ''), bad: false };
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
    } else if (d.saveSuggested) {
      var sgTiers = {}, sgFeatures = {};
      view.querySelectorAll('[data-tier]').forEach(function (el) { sgTiers[el.dataset.tier] = el.value.trim(); });
      view.querySelectorAll('select[data-feature]').forEach(function (el) { sgFeatures[el.dataset.feature] = el.value; });
      var stopSave = busy('Saving your customers\' AI');
      post('/suggested', { tiers: sgTiers, features: sgFeatures }, 'PUT').then(function () {
        stopSave();
        sgDraft = { tiers: {}, features: {} };
        say('Suggestion saved; customer ships pick it up within five minutes');
        held = [statusEl.innerHTML, statusEl.className];
        later();
      }).catch(function (e) { stopSave(); say(e.message, true); });
    } else if (d.saveBrave || d.clearBrave) {
      var bk = document.getElementById('brave-key');
      var braveBody = d.clearBrave ? { key: null } : { key: bk ? bk.value.trim() : '' };
      if (!d.clearBrave && !braveBody.key) { say('paste a Brave API key first', true); return; }
      var stopBrave = busy(d.clearBrave ? 'Removing the Brave key' : 'Saving the Brave key');
      post('/brave', braveBody, 'PUT').then(function () {
        stopBrave();
        say(d.clearBrave ? 'Brave key removed; your customers\' searches stop' : 'Brave key saved; your customers\' apps search through it');
        held = [statusEl.innerHTML, statusEl.className];
        later();
      }).catch(function (e) { stopBrave(); say(e.message, true); });
    } else if (d.cancelCheckout) {
      cancelCheckout(d.cancelCheckout, b);
    } else if (d.refreshView) {
      var stopRead = busy('Reading your balance from ' + (myVendor || 'the vendor'));
      var drawAccount = drawer();
      api('/account?fresh=1').then(function (dd) {
        // the plans go with it, or the buttons and the plan's name
        // vanish on the redraw
        return api('/plans').catch(function () { return myPlans; }).then(function (pl) {
          myPlans = pl || [];
          drawAccount(myAccount(dd, myPlans));
          stopRead();
          say('Balance read from ' + (myVendor || 'the vendor') + ' just now');
        });
      }).catch(function (e) { stopRead(); say(e.message, true); });
    } else if (d.topup) {
      var amount = micro(document.getElementById('t-amount').value);
      var railEl = view.querySelector('input[name="rail"]:checked');
      if (!amount || amount <= 0) { say('amount: dollars above zero', true); return; }
      startCheckout({ rail: railEl ? railEl.value : 'stripe', amount: amount }, b);
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
    } else if (d.dataDays) {
      dataDays = Number(d.dataDays) || 30;
      refresh();
    } else if (d.days) {
      reportDays = Number(d.days) || 30;
      refresh();
    } else if (d.takeLease) {
      say('asking the vendor for a lease');
      // the card draws from the stored view, so the vendor is read
      // once more before the redraw
      post('/lease').then(function () {
        return api('/account?fresh=1').catch(function () { return null; });
      }).then(function () { say('lease in hand'); refresh(); })
        .catch(function (e) { say(e.message, true); refresh(); });
    } else if (d.dropMyLease) {
      if (!confirm('Drop the lease? The provider key is deleted and clients fall back to the proxy.')) return;
      api('/lease', { method: 'DELETE' }).then(function () {
        return api('/account?fresh=1').catch(function () { return null; });
      }).then(function () { say('dropped'); refresh(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.saveStripe) {
      // a blank secret keeps what the ship holds, which is what an
      // untouched field sends
      saveSettings({
        stripe_key: document.getElementById('st-key').value.trim(),
        stripe_webhook_secret: document.getElementById('st-hook').value.trim(),
      }).then(function () { say('saved'); later(); })
        .catch(function (e) { say(e.message, true); });
    } else if (d.refundDone) {
      post('/refunds-due/done', { id: d.refundDone })
        .then(function () { say('marked refunded'); refresh(); })
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
    } else if (d.leaseLive) {
      var ls2 = route(location.hash).ship;
      say('reading the key from the provider');
      api('/accounts/' + seg(ls2) + '/lease/live').then(function (r) {
        r.at = new Date().toISOString();
        liveLease[ls2] = r; say('read'); refresh();
      }).catch(function (e) { liveLease[ls2] = { error: e.message, at: new Date().toISOString() }; say(e.message, true); refresh(); });
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
      startCheckout({ rail: buyRail, plan: d.buy }, b);
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
  // ---- which mode the page opens in ----
  // This browser's last choice wins. With no choice yet, a ship with a
  // provider configured is running a service and opens in provider
  // mode; every other ship is a customer and opens on its account.
  function storedMode() {
    try { return localStorage.getItem('armillary.provider'); } catch (e) { return null; }
  }
  function setMode(on) {
    providerMode = !!on;
    try { localStorage.setItem('armillary.provider', on ? '1' : '0'); } catch (e) { /* a private window */ }
    applyMode();
    refresh();
  }
  function applyMode() {
    document.getElementById('nav-vendor').hidden = !providerMode;
    document.getElementById('admin-note').hidden = !providerMode;
    var b = document.getElementById('mode');
    b.className = 'mode' + (providerMode ? ' on' : '');
    b.textContent = providerMode ? 'Provider mode: on' : 'Provider mode';
    var r = route(location.hash);
    if (!providerMode && VENDOR_VIEWS[r.name]) location.hash = '#account';
  }
  function boot() {
    var stored = storedMode();
    var p = stored === null
      ? api('/providers').catch(function () { return []; }).then(function (rows) { return (rows || []).length > 0; })
      : Promise.resolve(stored === '1');
    return p.then(function (on) {
      providerMode = on;
      var before = location.hash;
      applyMode();
      // a hash change redraws on its own; a kept hash needs the first draw
      if (location.hash === before) refresh();
    });
  }
  document.getElementById('mode').addEventListener('click', function () { setMode(!providerMode); });

  boot();
  stream();
  // the minute's refresh waits while a field has focus: a redraw would
  // take the box from under the owner's typing
  setInterval(function () { if (!document.hidden && !typing()) refresh(); }, 60000);
})();
