/* Eastern Ethiopia Digital Broker - shared core helpers */
const EEDB = (() => {
  const URL = "https://ubkfrpkapqnlaiscrxim.supabase.co";
  const KEY = "sb_publishable_5EokG_AyxU4BvcMiq1zyqg_B-NIMoeE";
  const client = window.supabase.createClient(URL, KEY);
  const esc = (v='') => String(v).replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const fmtMoney = n => Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2}) + ' ETB';
  const normalizeRole = r => String(r||'').trim().toLowerCase();
  const normalizeListingType = v => { const x=String(v||'').trim().toLowerCase(); return x==='sale'?'sell':x; };
  const isFeaturedNow = p => Boolean(p && p.is_featured && (!p.featured_until || new Date(p.featured_until).getTime() > Date.now()));
  const isPublicLocationTree = (rows) => { const map=new Map(rows.map(x=>[x.id,x])); const memo=new Map(); const ok=id=>{ if(!id)return true; if(memo.has(id))return memo.get(id); const x=map.get(id); if(!x || x.is_active!==true){memo.set(id,false);return false;} const good=x.type==='region' ? true : ok(x.parent_id); memo.set(id,good); return good; }; return rows.filter(x=>ok(x.id)); };

  const isAdminRole = r => ['super_admin','admin','city_admin'].includes(normalizeRole(r));
  const toast = (msg,type='info') => { const box=document.getElementById('toast'); if(!box)return; box.textContent=msg; box.className='toast '+type+' show'; clearTimeout(window.__toast); window.__toast=setTimeout(()=>box.classList.remove('show'),3200); };
  const children = (locations,parentId,type) => locations.filter(x=>x.parent_id===parentId && x.type===type && x.is_active).sort((a,b)=>a.name.localeCompare(b.name));
  const path = (locations,id) => { const out=[]; let cur=locations.find(x=>x.id===id), guard=0; while(cur&&guard++<10){out.unshift(cur.name);cur=locations.find(x=>x.id===cur.parent_id)} return out; };
  async function sessionProfile(){ const {data:{user}}=await client.auth.getUser(); if(!user)return {user:null,profile:null}; const {data:profile,error}=await client.from('profiles').select('*').eq('id',user.id).maybeSingle(); if(error) throw error; return {user,profile}; }
  async function locations(){ const {data,error}=await client.from('locations').select('id,parent_id,name,type,is_active').eq('is_active',true).order('name'); if(error)throw error; return isPublicLocationTree(data||[]); }
  function cascade(locations, ids={}, els, onChange){
    const rows=Array.isArray(locations)?locations:[];
    const child=(parent,type)=>rows.filter(x=>x.parent_id===parent && x.type===type && x.is_active).sort((a,b)=>a.name.localeCompare(b.name));
    const fill=(el,list,label,disabled=false)=>{ if(!el)return; el.innerHTML=`<option value="">${esc(label)}</option>`+list.map(x=>`<option value="${esc(x.id)}">${esc(x.name)}</option>`).join(''); el.disabled=disabled; };
    const clear=(names)=>names.forEach(n=>fill(els[n],[],`Select ${n.charAt(0).toUpperCase()+n.slice(1)}`,true));
    const apply=(el,val)=>{ if(el && val){ const opt=[...el.options].find(o=>o.value===val); if(opt)el.value=val; } };
    const regions=rows.filter(x=>x.type==='region').sort((a,b)=>a.name.localeCompare(b.name));
    fill(els.region,regions,'Select Region',regions.length===0); apply(els.region,ids.region_id||ids.region);
    const refreshZones=()=>{ const r=els.region?.value||''; clear(['zone','city','woreda','area']); if(!r){onChange?.();return;} const zones=child(r,'zone'); const directCities=child(r,'city');
      if(zones.length){fill(els.zone,zones,'Select Zone',false);apply(els.zone,ids.zone_id||ids.zone);}
      else fill(els.zone,[], 'Not used for this location', true);
      const refreshCities=()=>{ const z=els.zone?.value||''; const cities=z?child(z,'city'):directCities; fill(els.city,cities,'Select City',cities.length===0); apply(els.city,ids.city_id||ids.city);
        const refreshWoredas=()=>{ const c=els.city?.value||''; const ws=child(c,'woreda'); fill(els.woreda,ws,'Select Woreda',ws.length===0); apply(els.woreda,ids.woreda_id||ids.woreda);
          const refreshAreas=()=>{ const w=els.woreda?.value||''; const c2=els.city?.value||''; const wa=w?child(w,'area'):[]; const ca=child(c2,'area'); const areas=wa.length?wa:ca; fill(els.area,areas,'Select Area',areas.length===0); apply(els.area,ids.area_id||ids.area); onChange?.(); };
          if(els.woreda) els.woreda.onchange=refreshAreas; refreshAreas();
        };
        if(els.city) els.city.onchange=refreshWoredas; refreshWoredas();
      };
      if(els.zone) els.zone.onchange=refreshCities; refreshCities();
    };
    if(els.region) els.region.onchange=()=>{ const keep={}; ids=keep; refreshZones(); };
    refreshZones();
  }
  function getSelectedIds(els){ return {region_id:els.region?.value||null,zone_id:els.zone?.value||null,city_id:els.city?.value||null,woreda_id:els.woreda?.value||null,area_id:els.area?.value||null}; }
  function locationText(locations, ids){ const last=ids.area_id||ids.woreda_id||ids.city_id||ids.zone_id||ids.region_id; return last?path(locations,last).join(' → '):''; }
  return {client,esc,fmtMoney,normalizeRole,normalizeListingType,isFeaturedNow,isAdminRole,toast,children,path,sessionProfile,locations,cascade,getSelectedIds,locationText};
})();
