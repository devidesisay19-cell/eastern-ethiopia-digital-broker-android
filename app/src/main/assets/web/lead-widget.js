/* Lead (customer inquiry) widget. Usage:
   EEDBLead.mount(el, { client, kind:'property|marketplace|car|job', id, city_id, title }) */
const EEDBLead = (() => {
  const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function mount(el, o) {
    if (!el || !o || !o.client || !o.id) return;
    el.innerHTML =
      '<div style="border:1px solid #e4e7ec;border-radius:14px;padding:14px;background:#f8fafc">' +
      '<div style="font-weight:800;margin-bottom:4px">📩 Request a call back</div>' +
      '<div style="color:#667085;font-size:13px;margin-bottom:10px">Leave your name and phone. A broker will contact you.</div>' +
      '<input id="ldName" placeholder="Your name" maxlength="120" style="width:100%;padding:11px;border:1px solid #d0d5dd;border-radius:10px;margin-bottom:8px;font-size:15px">' +
      '<input id="ldPhone" placeholder="Phone (e.g. 09xxxxxxxx)" inputmode="tel" maxlength="30" style="width:100%;padding:11px;border:1px solid #d0d5dd;border-radius:10px;margin-bottom:8px;font-size:15px">' +
      '<textarea id="ldMsg" placeholder="Message (optional)" maxlength="1000" rows="2" style="width:100%;padding:11px;border:1px solid #d0d5dd;border-radius:10px;margin-bottom:8px;font-size:15px"></textarea>' +
      '<button id="ldBtn" style="width:100%;border:0;background:#0f766e;color:#fff;font-weight:700;padding:12px;border-radius:12px;font-size:15px;cursor:pointer">Send request</button>' +
      '<div id="ldOut" style="margin-top:8px;font-size:14px"></div></div>';
    const q = s => el.querySelector(s);
    q('#ldBtn').onclick = async () => {
      const name = q('#ldName').value.trim(), phone = q('#ldPhone').value.trim();
      const out = q('#ldOut');
      if (name.length < 2 || phone.replace(/\D/g, '').length < 6) { out.style.color = '#b42318'; out.textContent = 'Please enter your name and a valid phone number.'; return; }
      q('#ldBtn').disabled = true;
      const msg = (q('#ldMsg').value.trim() + (o.title ? '\n[Listing: ' + o.title + ']' : '')).trim().slice(0, 1000);
      const { error } = await o.client.from('leads').insert({
        listing_kind: o.kind, listing_id: o.id, city_id: o.city_id || null,
        customer_name: name, customer_phone: phone, message: msg || null
      });
      if (error) { q('#ldBtn').disabled = false; out.style.color = '#b42318'; out.textContent = 'Could not send. Please try again.'; return; }
      out.style.color = '#027a48'; out.textContent = '✅ Request sent. We will call you soon.';
      q('#ldName').value = q('#ldPhone').value = q('#ldMsg').value = '';
    };
  }
  return { mount, esc };
})();
