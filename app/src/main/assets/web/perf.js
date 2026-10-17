/* Speed helpers loaded on every page.
   1) Images load lazily and decode off the main thread (long lists no longer download every photo at once).
   2) EEDBCache: last-known data is shown instantly on the next app start and refreshed in the background. */
(function () {
  function tune(img) {
    if (!img || img.tagName !== 'IMG') return;
    if (!img.hasAttribute('loading')) img.setAttribute('loading', 'lazy');
    img.setAttribute('decoding', 'async');
  }
  try {
    new MutationObserver(function (list) {
      list.forEach(function (m) {
        Array.prototype.forEach.call(m.addedNodes, function (n) {
          if (n.nodeType !== 1) return;
          if (n.tagName === 'IMG') tune(n);
          else if (n.querySelectorAll) Array.prototype.forEach.call(n.querySelectorAll('img'), tune);
        });
      });
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}

  var NS = '';
  function ns() {
    if (NS) return NS;
    try { NS = String(SUPABASE_URL).replace(/^https?:\/\//, '').split('.')[0]; } catch (e) {}
    return NS || 'x';
  }
  var MAX_AGE = 7 * 24 * 3600 * 1000;
  window.EEDBCache = {
    get: function (k) {
      try {
        var o = JSON.parse(localStorage.getItem('eedb_c_' + ns() + '_' + k) || 'null');
        return (o && o.d && Date.now() - o.t < MAX_AGE) ? o.d : null;
      } catch (e) { return null; }
    },
    set: function (k, d) {
      var key = 'eedb_c_' + ns() + '_' + k, val;
      try { val = JSON.stringify({ t: Date.now(), d: d }); } catch (e) { return; }
      try { localStorage.setItem(key, val); }
      catch (e) {
        try {   // storage full: drop our old cache entries and retry once
          Object.keys(localStorage).forEach(function (x) { if (x.indexOf('eedb_c_') === 0) localStorage.removeItem(x); });
          localStorage.setItem(key, val);
        } catch (e2) {}
      }
    }
  };

  // ---- loading helpers (no more endless "Loading...") ----
  window.eedbWithTimeout = function (p, ms) {
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () { reject(new Error('Timed out. Please check your internet connection and try again.')); }, ms || 15000);
      Promise.resolve(p).then(function (v) { clearTimeout(t); resolve(v); }, function (e) { clearTimeout(t); reject(e); });
    });
  };
  // current user from the locally stored session (no network round trip, unlike auth.getUser())
  window.eedbUser = function (client) {
    return client.auth.getSession().then(function (r) { return (r && r.data && r.data.session && r.data.session.user) || null; });
  };
  // if the element still shows "Loading" after `ms`, replace it with a message and a Retry link
  window.eedbWatchdog = function (id, ms) {
    setTimeout(function () {
      var el = document.getElementById(id);
      if (el && /^\s*Loading/i.test(el.textContent || '')) {
        el.innerHTML = '<div style="text-align:center;padding:40px 16px;color:#667085;font-family:Arial,sans-serif">Loading is taking too long.<br><br><a href="#" onclick="location.reload();return false" style="display:inline-block;background:#0d47a1;color:#fff;padding:12px 20px;border-radius:12px;text-decoration:none;font-weight:700">Retry</a></div>';
      }
    }, ms || 20000);
  };
})();
