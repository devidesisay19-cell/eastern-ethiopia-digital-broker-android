/*
 * Admin create/edit tools for Marketplace and Cars.
 * This file deliberately uses the existing EEDB client, location data,
 * admin session, and RLS policies instead of creating a second auth path.
 */
(function () {
  "use strict";

  const state = {
    kind: "marketplace",
    id: "",
    existing: [],
    files: [],
    removed: []
  };

  const $ = (id) => document.getElementById(id);
  const esc = (value) => EEDB.esc(value == null ? "" : String(value));
  const bucketFor = (kind) => kind === "cars" ? "car-images" : "marketplace-images";
  const tableFor = (kind) => kind === "cars" ? "cars" : "marketplace_items";

  function safeFileName(name) {
    return String(name || "photo")
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 90) || "photo";
  }

  function locationFields(prefix) {
    return `
      <div class="admin-listing-location">
        <label>Region<select id="${prefix}Region" class="input"></select></label>
        <label>Zone<select id="${prefix}Zone" class="input"></select></label>
        <label>City / Town<select id="${prefix}City" class="input"></select></label>
        <label>Woreda<select id="${prefix}Woreda" class="input"></select></label>
        <label>Area<select id="${prefix}Area" class="input"></select></label>
      </div>`;
  }

  function modalMarkup() {
    const style = document.createElement("style");
    style.textContent = `
      #adminListingModal{position:fixed;inset:0;z-index:1000;display:none;
        align-items:center;justify-content:center;padding:16px;background:#10182899}
      #adminListingModal.show{display:flex}
      #adminListingModal .admin-listing-dialog{width:min(760px,100%);max-height:92vh;
        overflow:auto;background:#fff;border-radius:18px;padding:20px;box-shadow:0 20px 60px #10182833}
      .admin-listing-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
      .admin-listing-grid label,.admin-listing-location label{display:grid;gap:6px;
        color:#344054;font-size:12px;font-weight:700}
      .admin-listing-grid .wide{grid-column:1/-1}
      .admin-listing-location{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;
        margin-top:12px;padding-top:12px;border-top:1px solid #e4e7ec}
      .admin-listing-photos{margin-top:14px;padding-top:14px;border-top:1px solid #e4e7ec}
      .admin-listing-photo-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-top:10px}
      .admin-listing-photo{position:relative;aspect-ratio:1;overflow:hidden;border-radius:10px;background:#f2f4f7}
      .admin-listing-photo img{width:100%;height:100%;object-fit:cover}
      .admin-listing-photo button{position:absolute;top:4px;right:4px;border:0;border-radius:50%;
        width:24px;height:24px;background:#b42318;color:#fff;cursor:pointer}
      .admin-listing-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:18px}
      @media(max-width:600px){.admin-listing-grid,.admin-listing-location{grid-template-columns:1fr}
        .admin-listing-grid .wide{grid-column:auto}.admin-listing-photo-grid{grid-template-columns:repeat(3,1fr)}}
    `;
    document.head.appendChild(style);
    const modal = document.createElement("div");
    modal.id = "adminListingModal";
    modal.innerHTML = `
      <div class="admin-listing-dialog" role="dialog" aria-modal="true">
        <div style="display:flex;justify-content:space-between;gap:12px;align-items:center">
          <h2 id="adminListingTitle" style="margin:0;font-size:20px">Add Listing</h2>
          <button class="btn light" type="button" id="adminListingClose">Close</button>
        </div>
        <form id="adminListingForm">
          <div class="admin-listing-grid" style="margin-top:16px">
            <label class="wide">Title<input id="adminListingTitleField" class="input" required maxlength="160"></label>
            <label id="adminListingCategoryLabel">Category<select id="adminListingCategory" class="input">
              <option value="">Select Category</option>
              <option value="Phone">Phone</option><option value="TV">TV</option><option value="Fridge">Fridge</option>
              <option value="Sofa">Sofa</option><option value="Furniture">Furniture</option><option value="Laptop">Laptop</option>
              <option value="Household Equipment">Household Equipment</option><option value="Work Equipment">Work Equipment</option>
              <option value="Other">Other</option>
            </select></label>
            <label id="adminListingBrandLabel">Brand / Make<input id="adminListingBrand" class="input" maxlength="80"></label>
            <label id="adminListingModelLabel">Model<input id="adminListingModel" class="input" maxlength="80"></label>
            <label id="adminListingYearLabel">Year<input id="adminListingYear" class="input" type="number" min="1950" max="2100"></label>
            <label id="adminListingMileageLabel">Mileage<input id="adminListingMileage" class="input" type="number" min="0"></label>
            <label id="adminListingTransmissionLabel">Transmission<select id="adminListingTransmission" class="input">
              <option value="">Select transmission</option><option value="Manual">Manual</option><option value="Automatic">Automatic</option><option value="Semi-Automatic">Semi-Automatic</option><option value="Other">Other</option>
            </select></label>
            <label id="adminListingFuelLabel">Fuel type<select id="adminListingFuel" class="input">
              <option value="">Select fuel type</option><option value="Petrol">Petrol</option><option value="Diesel">Diesel</option><option value="Hybrid">Hybrid</option><option value="Electric">Electric</option><option value="Other">Other</option>
            </select></label>
            <label id="adminListingColorLabel">Color<input id="adminListingColor" class="input" maxlength="40"></label>
            <label>Condition<select id="adminListingCondition" class="input" required>
              <option value="">Select condition</option><option value="new">New</option><option value="used">Used</option><option value="excellent">Excellent</option><option value="good">Good</option><option value="fair">Fair</option>
            </select></label>
            <label>Listing type<select id="adminListingType" class="input" required><option value="sell">Sell</option><option value="rent">Rent</option></select></label>
            <label>Price<input id="adminListingPrice" class="input" type="number" min="1" step="0.01" required></label>
            <label>Price unit<select id="adminListingPriceUnit" class="input"><option value="total">Total</option><option value="day">Per Day</option><option value="week">Per Week</option><option value="month">Per Month</option></select></label>
            <label>Contact phone<input id="adminListingPhone" class="input" maxlength="40"></label>
            <label class="wide">Description<textarea id="adminListingDescription" class="input" rows="4" maxlength="5000"></textarea></label>
          </div>
          <div id="adminListingLocationFields"></div>
          <div class="admin-listing-photos">
            <label class="btn primary" for="adminListingPhotos" style="display:inline-block;cursor:pointer">＋ Select Photos (max 5)</label>
            <input id="adminListingPhotos" type="file" accept="image/*" multiple
              style="position:absolute;left:-9999px;width:1px;height:1px;opacity:0">
            <small id="adminListingPhotoCount">0 of 5 photos</small>
            <div id="adminListingPhotoGrid" class="admin-listing-photo-grid"></div>
          </div>
          <div class="admin-listing-actions">
            <button class="btn light" type="button" id="adminListingCancel">Cancel</button>
            <button class="btn primary" type="submit" id="adminListingSave">Save listing</button>
          </div>
        </form>
      </div>`;
    document.body.appendChild(modal);
    $("adminListingClose").onclick = close;
    $("adminListingCancel").onclick = close;
    modal.onclick = (event) => { if (event.target === modal) close(); };
    $("adminListingPhotos").onchange = onFiles;
    $("adminListingForm").onsubmit = save;
  }

  function close() {
    const modal = $("adminListingModal");
    if (modal) modal.classList.remove("show");
    state.id = "";
    state.existing = [];
    state.files = [];
    state.removed = [];
  }

  function setValue(id, value) {
    const el = $(id);
    if (el) el.value = value == null ? "" : String(value);
  }

  function currentLocationIds(prefix) {
    return {
      region_id: $(`${prefix}Region`)?.value || null,
      zone_id: $(`${prefix}Zone`)?.value || null,
      city_id: $(`${prefix}City`)?.value || null,
      woreda_id: $(`${prefix}Woreda`)?.value || null,
      area_id: $(`${prefix}Area`)?.value || null
    };
  }

  function setupLocations(kind, row) {
    const prefix = kind === "cars" ? "adminCar" : "adminMarket";
    const ids = {
      region: $(`${prefix}Region`), zone: $(`${prefix}Zone`), city: $(`${prefix}City`),
      woreda: $(`${prefix}Woreda`), area: $(`${prefix}Area`)
    };
    const availableLocations = typeof locations !== "undefined" ? locations : [];
    EEDB.cascade(availableLocations, row || {}, ids);
  }

  function renderPhotos() {
    const all = state.existing.map((url, index) => ({ url, index, existing: true }))
      .concat(state.files.map((file, index) => ({ url: URL.createObjectURL(file), index, existing: false })));
    $("adminListingPhotoCount").textContent = `${all.length} of 5 photos`;
    $("adminListingPhotoGrid").innerHTML = all.map((photo) => `
      <div class="admin-listing-photo">
        <img src="${photo.existing ? esc(photo.url) : photo.url}" alt="Listing photo">
        <button type="button" aria-label="Remove photo" data-photo-existing="${photo.existing}" data-photo-index="${photo.index}">×</button>
      </div>`).join("");
    $("adminListingPhotoGrid").querySelectorAll("button").forEach((button) => {
      button.onclick = () => {
        const index = Number(button.dataset.photoIndex);
        if (button.dataset.photoExisting === "true") {
          state.removed.push(state.existing[index]);
          state.existing.splice(index, 1);
        }
        else state.files.splice(index, 1);
        renderPhotos();
      };
    });
  }

  async function onFiles(event) {
    const input = event.target;
    const incoming = Array.from(input.files || []).filter((file) => EEDB.looksLikeImage(file));
    input.value = "";
    if (!incoming.length) { toast("Please choose image files.", "error"); return; }
    let remaining = Math.max(0, 5 - state.existing.length - state.files.length);
    if (!remaining) { toast("Maximum 5 photos.", "error"); return; }
    for (const file of incoming.slice(0, remaining)) {
      try { state.files.push(await EEDB.prepareImage(file)); }
      catch (e) { toast((file.name || "Photo") + " could not be read. Choose another (JPG/PNG).", "error"); }
    }
    renderPhotos();
  }

  function fillForm(kind, row) {
    const isCar = kind === "cars";
    $("adminListingTitle").textContent = `${row ? "Edit" : "Add"} ${isCar ? "Car" : "Marketplace Item"}`;
    $("adminListingCategoryLabel").style.display = isCar ? "none" : "grid";
    ["Brand", "Model", "Year", "Mileage", "Transmission", "Fuel", "Color"].forEach((name) => {
      const label = $(`adminListing${name}Label`);
      if (label) label.style.display = isCar ? "grid" : "none";
    });
    setValue("adminListingTitleField", row?.title);
    (function(){
      const sel = $("adminListingCategory"), v = row?.category || "";
      if (sel && v && ![...sel.options].some(o => o.value === v)) {
        const o = document.createElement("option"); o.value = v; o.textContent = v; sel.appendChild(o);
      }
      setValue("adminListingCategory", v);
    })();
    setValue("adminListingBrand", row?.brand);
    setValue("adminListingModel", row?.model);
    setValue("adminListingYear", row?.year);
    setValue("adminListingMileage", row?.mileage);
    (function(){const v=String(row?.transmission||"").toLowerCase();setValue("adminListingTransmission",{manual:"Manual",automatic:"Automatic","semi-automatic":"Semi-Automatic",other:"Other"}[v]||"");})();
    (function(){const v=String(row?.fuel_type||"").toLowerCase();setValue("adminListingFuel",{petrol:"Petrol",diesel:"Diesel",hybrid:"Hybrid",electric:"Electric",other:"Other"}[v]||"");})();
    setValue("adminListingColor", row?.color);
    setValue("adminListingCondition", row?.condition);
    setValue("adminListingType", row?.listing_type || "sell");
    setValue("adminListingPrice", row?.price);
    setValue("adminListingPriceUnit", row?.price_unit || "total");
    setValue("adminListingPhone", row?.contact_phone);
    setValue("adminListingDescription", row?.description);
    const prefix = kind === "cars" ? "adminCar" : "adminMarket";
    $("adminListingLocationFields").innerHTML = locationFields(prefix);
    setupLocations(kind, row || {});
    state.existing = Array.isArray(row?.photo_urls) ? row.photo_urls.slice(0, 5) : [];
    state.files = [];
    state.removed = [];
    renderPhotos();
  }

  window.openAdminListingModal = async function (kind, id) {
    if (!$("adminListingModal")) modalMarkup();
    state.kind = kind === "cars" ? "cars" : "marketplace";
    state.id = id || "";
    const source = state.kind === "cars"
      ? (typeof adminCars !== "undefined" ? adminCars : [])
      : (typeof adminMarketplaceItems !== "undefined" ? adminMarketplaceItems : []);
    const row = id ? source.find((item) => item.id === id) : null;
    fillForm(state.kind, row || null);
    $("adminListingModal").classList.add("show");
  };

  function validate() {
    const title = $("adminListingTitleField").value.trim();
    const category = $("adminListingCategory").value.trim();
    const condition = $("adminListingCondition").value;
    const city = currentLocationIds(state.kind === "cars" ? "adminCar" : "adminMarket").city_id;
    const price = Number($("adminListingPrice").value);
    if (!title || !city || !Number.isFinite(price) || price <= 0) {
      toast("Title, city, and a price greater than 0 are required.", "error");
      return false;
    }
    if (state.kind !== "cars" && !category) {
      toast("Marketplace category is required.", "error");
      return false;
    }
    if (!condition) {
      toast("Listing condition is required.", "error");
      return false;
    }
    if (state.existing.length + state.files.length > 5) {
      toast("A listing can have no more than 5 photos.", "error");
      return false;
    }
    return true;
  }

  async function uploadPhotos(kind, id) {
    if (!state.files.length) return state.existing;
    const bucket = bucketFor(kind);
    const urls = [];
    for (const file of state.files) {
      const path = `${me.id}/${id}/${Date.now()}-${safeFileName(file.name)}`;
      const upload = await EEDB.client.storage.from(bucket).upload(path, file, {
        cacheControl: "3600", upsert: false, contentType: file.type
      });
      if (upload.error) throw upload.error;
      const publicUrl = EEDB.client.storage.from(bucket).getPublicUrl(upload.data.path).data.publicUrl;
      urls.push(publicUrl);
    }
    return state.existing.concat(urls).slice(0, 5);
  }

  async function removeStoredPhotos(kind) {
    const bucket = bucketFor(kind);
    for (const url of state.removed) {
      try {
        const marker = `/storage/v1/object/public/${bucket}/`;
        const markerIndex = String(url).indexOf(marker);
        if (markerIndex >= 0) {
          const objectPath = decodeURIComponent(String(url).slice(markerIndex + marker.length));
          await EEDB.client.storage.from(bucket).remove([objectPath]);
        }
      } catch (error) {
        console.warn("Could not remove storage object:", error);
      }
    }
  }

  async function save(event) {
    event.preventDefault();
    if (!me || !profile || !EEDB.isAdminRole(profile.role) || !validate()) return;
    const prefix = state.kind === "cars" ? "adminCar" : "adminMarket";
    const loc = currentLocationIds(prefix);
    const isCar = state.kind === "cars";
    const payload = {
      title: $("adminListingTitleField").value.trim(),
      description: $("adminListingDescription").value.trim() || null,
      condition: $("adminListingCondition").value,
      listing_type: $("adminListingType").value,
      price: Number($("adminListingPrice").value),
      price_unit: $("adminListingPriceUnit").value.trim() || "total",
      contact_phone: $("adminListingPhone").value.trim() || null,
      ...loc,
      updated_at: new Date().toISOString()
    };
    if (isCar) Object.assign(payload, {
      brand: $("adminListingBrand").value.trim() || null,
      model: $("adminListingModel").value.trim() || null,
      year: $("adminListingYear").value ? Number($("adminListingYear").value) : null,
      mileage: $("adminListingMileage").value ? Number($("adminListingMileage").value) : null,
      transmission: $("adminListingTransmission").value || null,
      fuel_type: $("adminListingFuel").value || null,
      color: $("adminListingColor").value.trim() || null
    });
    else payload.category = $("adminListingCategory").value.trim();

    const button = $("adminListingSave");
    button.disabled = true;
    try {
      let id = state.id;
      if (id) {
        const result = await EEDB.client.from(tableFor(state.kind)).update(payload).eq("id", id);
        if (result.error) throw result.error;
      } else {
        id = (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
          : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16); });
        Object.assign(payload, { id, seller_id: me.id, posted_by: me.id, status: "published" });
        const result = await EEDB.client.from(tableFor(state.kind)).insert(payload);
        if (result.error) throw result.error;
      }
      const photoUrls = await uploadPhotos(state.kind, id);
      const photoResult = await EEDB.client.from(tableFor(state.kind)).update({
        photo_urls: photoUrls, updated_at: new Date().toISOString()
      }).eq("id", id);
      if (photoResult.error) throw photoResult.error;
      await removeStoredPhotos(state.kind);
      close();
      toast(`${isCar ? "Car" : "Marketplace item"} saved.`, "success");
      if (isCar) await loadCarsAdmin(); else await loadMarketplaceAdmin();
    } catch (error) {
      toast(error.message || "Could not save listing.", "error");
    } finally {
      button.disabled = false;
    }
  }
})();