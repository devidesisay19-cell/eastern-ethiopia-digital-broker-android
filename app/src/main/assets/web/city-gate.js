/* City selection: shown the first time the app opens, remembered afterwards.
   Lists EVERY active city of the location cascade (region > zone > city), grouped by region, with search.
   Uses the #cityFilter select + applyFilters() of index.html. */
(function () {
  // Storage keys belong to ONE Supabase project, so data saved while the app pointed at another project is ignored.
  var NS = '';
  try { NS = String(SUPABASE_URL).replace(/^https?:\/\//, '').split('.')[0]; } catch (e) {}
  var KEY = 'eedb_city_' + NS, CACHE = 'eedb_cities_' + NS;
  try { localStorage.removeItem('eedb_city'); localStorage.removeItem('eedb_cities_v2'); } catch (e) {}   // old test-project leftovers
  var TXT = {
    en: { title: 'Select your city', sub: 'Choose where you want to buy, sell, rent or find jobs.', all: 'See all cities', search: 'Search city or region...', none: 'No city found.' },
    om: { title: 'Magaalaa kee filadhu', sub: 'Bakka bituu, gurguruu, kireessuu ykn hojii barbaaddu filadhu.', all: 'Magaalota hunda ilaali', search: 'Magaalaa ykn naannoo barbaadi...', none: 'Magaalaan hin argamne.' },
    am: { title: 'ከተማዎን ይምረጡ', sub: 'ለመግዛት፣ ለመሸጥ፣ ለመከራየት ወይም ሥራ ለመፈለግ የሚፈልጉትን ከተማ ይምረጡ።', all: 'ሁሉንም ከተሞች ይመልከቱ', search: 'ከተማ ወይም ክልል ይፈልጉ...', none: 'ከተማ አልተገኘም።' }
  };
  function t() { var l = 'en'; try { l = getCurrentLanguage(); } catch (e) {} return TXT[l] || TXT.en; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]; }); }
  function saved() { try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; } }
  function save(id, name) { try { localStorage.setItem(KEY, JSON.stringify({ id: id, name: name })); } catch (e) {} }
  function client() { try { return (typeof db !== 'undefined') ? db : null; } catch (e) { return null; } }

  // ---- data: all active locations (paged, PostgREST returns max 1000 rows per request) ----
  function fetchAll() {
    var c = client(); if (!c) return Promise.resolve(null);
    var rows = [], from = 0, step = 1000;
    function next() {
      return c.from('locations').select('id,parent_id,name,type').eq('is_active', true).order('name').range(from, from + step - 1)
        .then(function (r) {
          if (r.error) return null;
          rows = rows.concat(r.data || []);
          if (!r.data || r.data.length < step || from > 20000) return rows;
          from += step; return next();
        });
    }
    return next().catch(function () { return null; });
  }
  function build(rows) {
    var by = {}; rows.forEach(function (r) { by[r.id] = r; });
    var out = [];
    rows.forEach(function (r) {
      if (r.type !== 'city') return;
      var path = [], p = by[r.parent_id], g = 0;
      while (p && g < 6) { path.unshift(p.name); p = by[p.parent_id]; g++; }
      out.push({ id: r.id, name: r.name, path: path.join(' \u203A '), group: path[0] || '' });
    });
    out.sort(function (a, b) { return a.group === b.group ? a.name.localeCompare(b.name) : a.group.localeCompare(b.group); });
    return out;
  }
  function store(list) { try { localStorage.setItem(CACHE, JSON.stringify({ at: Date.now(), list: list })); } catch (e) {} }
  function fromSelect() {
    var sel = document.getElementById('cityFilter'); if (!sel) return [];
    return Array.prototype.filter.call(sel.options, function (o) { return o.value !== 'all'; })
      .map(function (o) { return { id: o.value, name: o.textContent.trim(), path: '', group: '' }; });
  }
  function withTimeout(p, ms) {
    return new Promise(function (resolve) {
      var done = false, t = setTimeout(function () { if (!done) { done = true; resolve(null); } }, ms);
      p.then(function (v) { if (!done) { done = true; clearTimeout(t); resolve(v); } }, function () { if (!done) { done = true; clearTimeout(t); resolve(null); } });
    });
  }
  function getCities() {
    return withTimeout(fetchAll(), 5000).then(function (rows) {
      if (rows) { var l = build(rows); if (l.length) { store(l); return l; } }
      var cached = null; try { cached = JSON.parse(localStorage.getItem(CACHE) || 'null'); } catch (e) {}
      if (cached && cached.list && cached.list.length) return cached.list;
      return fromSelect();
    });
  }

  // ---- UI ----
  function ensureOption(id, name) {
    var sel = document.getElementById('cityFilter'); if (!sel) return;
    if (!sel.querySelector('option[value="' + id + '"]')) {
      var o = document.createElement('option'); o.value = id; o.textContent = name; sel.appendChild(o);
    }
    sel.value = id;
  }
  function chip(name) {
    var c = document.getElementById('eedbCityChip');
    if (!c) {
      c = document.createElement('button'); c.id = 'eedbCityChip'; c.type = 'button';
      c.style.cssText = 'position:fixed;left:12px;bottom:14px;z-index:9000;border:0;border-radius:999px;padding:10px 14px;background:#0d47a1;color:#fff;font:700 14px Arial,sans-serif;box-shadow:0 6px 18px rgba(0,0,0,.28);cursor:pointer;max-width:55vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
      c.onclick = function () { picker(true); };
      document.body.appendChild(c);
    }
    c.textContent = '\uD83D\uDCCD ' + name + ' \u25BE';
  }
  var resolver = null;
  function choose(id, name, again) {
    save(id, name);
    if (id === 'all') { var sel = document.getElementById('cityFilter'); if (sel) sel.value = 'all'; } else ensureOption(id, name);
    chip(id === 'all' ? t().all : name);
    var ov = document.getElementById('eedbCityGate'); if (ov) ov.remove();
    if (again && typeof applyFilters === 'function') applyFilters();
    if (resolver) { var r = resolver; resolver = null; r(); }
  }
  function picker(again) {
    var old = document.getElementById('eedbCityGate'); if (old) old.remove();
    var s = t(), ov = document.createElement('div');
    ov.id = 'eedbCityGate';
    ov.style.cssText = 'position:fixed;inset:0;z-index:99999;background:linear-gradient(160deg,#0d47a1,#1e88e5);color:#fff;overflow:auto;padding:22px 16px 40px;font-family:Arial,sans-serif';
    ov.innerHTML = '<div style="max-width:480px;margin:0 auto"><div style="text-align:center"><div style="font-size:40px">\uD83D\uDCCD</div>' +
      '<h1 style="font-size:25px;margin:6px 0">' + esc(s.title) + '</h1><p style="opacity:.9;font-size:14px;margin-bottom:14px">' + esc(s.sub) + '</p></div>' +
      '<input id="eedbCitySearch" type="search" placeholder="' + esc(s.search) + '" style="width:100%;padding:13px;border:0;border-radius:12px;font-size:16px;margin-bottom:12px;display:none">' +
      '<div id="eedbCityList" style="min-height:60px;text-align:center;opacity:.9">...</div>' +
      '<div style="text-align:center"><button type="button" data-all="1" style="margin-top:10px;padding:12px;border:0;background:transparent;color:#fff;font:600 15px Arial,sans-serif;text-decoration:underline;cursor:pointer">' + esc(s.all) + '</button></div></div>';
    document.body.appendChild(ov);
    var listEl = ov.querySelector('#eedbCityList'), search = ov.querySelector('#eedbCitySearch'), cities = [];
    function render(q) {
      q = (q || '').trim().toLowerCase();
      var shown = cities.filter(function (c) { return !q || (c.name + ' ' + c.path).toLowerCase().indexOf(q) >= 0; });
      if (!shown.length) { listEl.innerHTML = '<div style="padding:18px">' + esc(s.none) + '</div>'; return; }
      var html = '', last = null, grouped = cities.length > 8;
      shown.forEach(function (c) {
        if (grouped && c.group !== last) { last = c.group; html += '<div style="text-align:left;font:700 12px Arial;letter-spacing:.06em;text-transform:uppercase;opacity:.85;margin:14px 4px 6px">' + esc(c.group || '-') + '</div>'; }
        html += '<button type="button" data-id="' + esc(c.id) + '" data-name="' + esc(c.name) + '" style="display:block;width:100%;margin:0 0 8px;padding:14px;border:0;border-radius:14px;background:#fff;color:#0d47a1;text-align:left;font:700 17px Arial,sans-serif;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,.16)">' + esc(c.name) +
          (c.path ? '<span style="display:block;font:400 12px Arial;color:#667085;margin-top:2px">' + esc(c.path) + '</span>' : '') + '</button>';
      });
      listEl.innerHTML = html;
    }
    ov.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      if (b.getAttribute('data-all')) choose('all', s.all, again);
      else if (b.getAttribute('data-id')) choose(b.getAttribute('data-id'), b.getAttribute('data-name'), again);
    });
    search.addEventListener('input', function () { render(search.value); });
    getCities().then(function (list) {
      cities = list || [];
      if (cities.length > 8) search.style.display = 'block';
      render('');
    });
    return new Promise(function (res) { resolver = res; });
  }

  window.cityGate = function () {
    var sv = saved();
    if (sv && sv.id === 'all') { chip(t().all); return Promise.resolve(); }
    if (sv && sv.id) {
      ensureOption(sv.id, sv.name); chip(sv.name);
      getCities().then(function (list) {
        if (list && list.length > 1 && !list.some(function (c) { return c.id === sv.id; })) {
          try { localStorage.removeItem(KEY); } catch (e) {}
          picker(true);
        }
      });
      return Promise.resolve();
    }
    return picker(false);
  };
  window.eedbRestoreCity = function () {
    var sv = saved(), sel = document.getElementById('cityFilter');
    if (sv && sv.id && sv.id !== 'all' && sel) ensureOption(sv.id, sv.name);
  };
})();
