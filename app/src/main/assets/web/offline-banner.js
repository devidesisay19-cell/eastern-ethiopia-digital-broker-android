/* Shows a small banner when the phone has no internet connection. */
(function () {
  function bar() {
    var b = document.getElementById('eedbOffline');
    if (b) return b;
    b = document.createElement('div');
    b.id = 'eedbOffline';
    b.textContent = 'No internet connection. Some features will not work until you are back online.';
    b.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:2147483647;background:#b42318;color:#fff;font:600 13px Arial,sans-serif;text-align:center;padding:8px 12px;display:none';
    (document.body || document.documentElement).appendChild(b);
    return b;
  }
  function update() { bar().style.display = navigator.onLine ? 'none' : 'block'; }
  window.addEventListener('online', update);
  window.addEventListener('offline', update);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', update); else update();
})();
