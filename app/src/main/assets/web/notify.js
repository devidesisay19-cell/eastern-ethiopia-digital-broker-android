/* Notification bell + chat shortcut + device registration for push (FCM).
   Include at the END of a page (after supabase-js):  <script src="notify.js"></script> */
(function () {
  if (!window.supabase || !window.supabase.createClient) return;
  var URL_ = 'https://ubkfrpkapqnlaiscrxim.supabase.co';
  var KEY_ = 'sb_publishable_5EokG_AyxU4BvcMiq1zyqg_B-NIMoeE';
  // Re-use the client the page already created (a second client on the same login causes lock waits and slow pages).
  var nb = window.eedbClient || null;
  try { if (!nb && typeof supabaseClient !== 'undefined' && supabaseClient) nb = supabaseClient; } catch (e) {}
  try { if (!nb && typeof db !== 'undefined' && db) nb = db; } catch (e) {}
  if (!nb) nb = window.supabase.createClient(URL_, KEY_, { auth: { autoRefreshToken: false, detectSessionInUrl: false } });
  var uid = null, items = [], timer = null, lastToken = null;

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]; }); }
  function safeLink(l) { return (l && /^[a-z0-9_-]+\.html(\?[A-Za-z0-9=&_-]*)?$/.test(l)) ? l : null; }

  function registerDevice() {
    var t = window.EEDB_FCM_TOKEN;
    if (!uid || !t) return;
    lastToken = t;
    try { localStorage.setItem('eedb_fcm_token', t); } catch (e) {}
    nb.rpc('eedb_register_device', { p_token: t }).then(function () {}, function () {});
  }
  window.addEventListener('eedb-fcm-token', registerDevice);

  function ui() {
    if (document.getElementById('eedbNotifWrap')) return;
    var w = document.createElement('div');
    w.id = 'eedbNotifWrap';
    w.innerHTML =
      '<style>#eedbNotifWrap{position:fixed;right:12px;bottom:14px;z-index:9500;display:flex;flex-direction:column;gap:10px;align-items:flex-end;font-family:Arial,sans-serif}' +
      '#eedbNotifWrap .fab{position:relative;width:48px;height:48px;border:0;border-radius:50%;background:#0d47a1;color:#fff;font-size:21px;box-shadow:0 6px 18px rgba(0,0,0,.28);cursor:pointer;text-decoration:none;display:flex;align-items:center;justify-content:center}' +
      '#eedbNotifBadge{position:absolute;top:-4px;right:-4px;min-width:20px;height:20px;border-radius:10px;background:#d92d20;color:#fff;font:700 12px Arial;display:none;align-items:center;justify-content:center;padding:0 5px}' +
      '#eedbNotifPanel{position:fixed;left:0;right:0;bottom:0;max-height:70vh;overflow:auto;background:#fff;color:#172033;border-radius:18px 18px 0 0;box-shadow:0 -8px 30px rgba(0,0,0,.25);padding:14px;display:none;z-index:9600}' +
      '#eedbNotifPanel .it{padding:11px 4px;border-bottom:1px solid #eef2f6;cursor:pointer}#eedbNotifPanel .it.un b:before{content:"\\25CF ";color:#d92d20}' +
      '#eedbNotifPanel small{color:#667085;display:block;margin-top:2px}#eedbToast{position:fixed;left:12px;right:12px;top:12px;z-index:99998;background:#0d47a1;color:#fff;padding:12px 14px;border-radius:12px;font:600 14px Arial;display:none;box-shadow:0 6px 18px rgba(0,0,0,.3)}</style>' +
      '<a class="fab" id="eedbChatBtn" href="chat.html" title="Messages">\uD83D\uDCAC</a>' +
      '<button class="fab" id="eedbBell" type="button" title="Notifications">\uD83D\uDD14<span id="eedbNotifBadge">0</span></button>';
    document.body.appendChild(w);
    var p = document.createElement('div'); p.id = 'eedbNotifPanel'; document.body.appendChild(p);
    var t = document.createElement('div'); t.id = 'eedbToast'; document.body.appendChild(t);
    document.getElementById('eedbBell').onclick = function () {
      p.style.display = p.style.display === 'block' ? 'none' : 'block';
      if (p.style.display === 'block') renderPanel();
    };
    document.addEventListener('click', function (e) {
      if (p.style.display === 'block' && !p.contains(e.target) && !w.contains(e.target)) p.style.display = 'none';
    });
  }

  function badge() {
    var n = items.filter(function (x) { return !x.is_read; }).length;
    var b = document.getElementById('eedbNotifBadge'); if (!b) return;
    b.textContent = n > 99 ? '99+' : n; b.style.display = n ? 'flex' : 'none';
  }

  function renderPanel() {
    var p = document.getElementById('eedbNotifPanel'); if (!p) return;
    p.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px"><b style="font-size:17px">Notifications</b><button id="eedbMarkAll" type="button" style="border:0;background:#e6efed;padding:7px 10px;border-radius:9px;font-weight:700;cursor:pointer">Mark all read</button></div>' +
      (items.length ? items.map(function (x) {
        return '<div class="it ' + (x.is_read ? '' : 'un') + '" data-id="' + x.id + '"><b>' + esc(x.title) + '</b>' + (x.body ? '<div style="font-size:14px">' + esc(x.body) + '</div>' : '') + '<small>' + new Date(x.created_at).toLocaleString() + '</small></div>';
      }).join('') : '<div style="padding:24px;text-align:center;color:#667085">No notifications yet.</div>');
    var ma = document.getElementById('eedbMarkAll');
    if (ma) ma.onclick = function () { nb.from('notifications').update({ is_read: true }).eq('user_id', uid).eq('is_read', false).then(load); };
    Array.prototype.forEach.call(p.querySelectorAll('.it'), function (el) {
      el.onclick = function () {
        var it = items.filter(function (x) { return x.id === el.getAttribute('data-id'); })[0]; if (!it) return;
        nb.from('notifications').update({ is_read: true }).eq('id', it.id).then(function () {
          var l = safeLink(it.link); if (l) location.href = l; else load();
        });
      };
    });
  }

  function toast(text) {
    var t = document.getElementById('eedbToast'); if (!t) return;
    t.textContent = text; t.style.display = 'block';
    setTimeout(function () { t.style.display = 'none'; }, 4500);
  }

  function load() {
    if (!uid) return;
    nb.from('notifications').select('id,kind,title,body,link,is_read,created_at').order('created_at', { ascending: false }).limit(30)
      .then(function (r) { if (r.error) return; items = r.data || []; badge(); if (document.getElementById('eedbNotifPanel').style.display === 'block') renderPanel(); });
  }

  function start(session) {
    uid = session.user.id; ui(); load(); registerDevice();
    try {
      nb.channel('eedb-notif-' + uid).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: 'user_id=eq.' + uid },
        function (payload) { var n = payload.new || {}; toast((n.title || 'New notification') + (n.body ? ': ' + n.body : '')); load(); }).subscribe();
    } catch (e) {}
    if (timer) clearInterval(timer);
    timer = setInterval(load, 60000);
  }

  function boot() {
    nb.auth.getSession().then(function (r) { if (r.data && r.data.session) start(r.data.session); });
    nb.auth.onAuthStateChange(function (event, session) {
      if (event === 'SIGNED_IN' && session && !uid) start(session);
      if (event === 'SIGNED_OUT') {
        var t = lastToken || window.EEDB_FCM_TOKEN || null;
        if (t) nb.rpc('eedb_forget_device', { p_token: t }).then(function () {}, function () {});
        uid = null; items = []; var w = document.getElementById('eedbNotifWrap'); if (w) w.remove();
      }
    });
  }
  // start after the page has finished its own loading, so the notification bell never slows the page down
  function schedule() { setTimeout(boot, 800); }
  if (document.readyState === 'complete') schedule(); else window.addEventListener('load', schedule);
})();
