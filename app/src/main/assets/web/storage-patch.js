/* Lets demo photos stored as data: URLs work through storage.getPublicUrl(). Real paths are untouched. */
(function () {
  // Photos over ~350 KB are resized (max 1280 px) and re-encoded as JPEG before upload: lists load much faster.
  function compressImage(file) {
    return new Promise(function (resolve) {
      try {
        if (!file || !file.type || file.type.indexOf('image/') !== 0 || file.type === 'image/gif' || file.type === 'image/svg+xml' || file.size < 350 * 1024) return resolve(file);
        var url = URL.createObjectURL(file), img = new Image();
        img.onload = function () {
          try {
            var w = img.naturalWidth, h = img.naturalHeight, sc = Math.min(1, 1280 / Math.max(w, h));
            var c = document.createElement('canvas'); c.width = Math.round(w * sc); c.height = Math.round(h * sc);
            var ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height); ctx.drawImage(img, 0, 0, c.width, c.height);
            c.toBlob(function (b) { URL.revokeObjectURL(url); resolve(b && b.size < file.size ? b : file); }, 'image/jpeg', 0.8);
          } catch (e) { URL.revokeObjectURL(url); resolve(file); }
        };
        img.onerror = function () { URL.revokeObjectURL(url); resolve(file); };
        img.src = url;
      } catch (e) { resolve(file); }
    });
  }
  if (!window.supabase || !window.supabase.createClient || window.supabase.__eedbPatched) return;
  const orig = window.supabase.createClient;
  window.supabase.createClient = function () {
    const c = orig.apply(this, arguments);
    try {
      const from = c.storage.from.bind(c.storage);
      c.storage.from = function (bucket) {
        const b = from(bucket), get = b.getPublicUrl.bind(b), up = b.upload.bind(b);
        b.upload = function (path, file, opts) {
          return compressImage(file).then(function (f) {
            var o = Object.assign({}, opts || {});
            if (f !== file) o.contentType = 'image/jpeg';
            return up(path, f, o);
          });
        };
        b.getPublicUrl = function (p, o) {
          return (typeof p === 'string' && p.indexOf('data:') === 0) ? { data: { publicUrl: p } } : get(p, o);
        };
        return b;
      };
    } catch (e) { /* ignore */ }
    return c;
  };
  window.supabase.__eedbPatched = true;
})();
