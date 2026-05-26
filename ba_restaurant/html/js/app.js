const app = document.getElementById('app');
const content = document.getElementById('content');
const closeBtn = document.getElementById('closeBtn');
const isTvDisplay = new URLSearchParams(window.location.search).get('tv') === '1';
if (isTvDisplay) document.body.classList.add('tv-display');

let state = { view: null, restaurantId: null, payload: {}, cart: [], activeCategory: null, modalProduct: null, modalQty: 1, managerTab: 'categories', editing: null, adminRestaurant: null, cashierSearch: '', submittingOrder: false, confirmDialog: null };

function closeUi(){
  state.view = null;
  state.restaurantId = null;
  state.modalProduct = null;
  state.confirmDialog = null;
  state.submittingOrder = false;
  app.classList.add('hidden');
  app.classList.remove('tv-app');
  content.innerHTML = '';
  document.body.classList.remove('menu-open', 'tv-display');
  document.documentElement.style.removeProperty('background');
  document.body.style.background = 'transparent';
}

function post(name, data = {}) { return fetch(`https://${GetParentResourceName()}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) }).catch(console.error); }
function money(value) { return `${state.payload.currency || '$'}${Number(value || 0).toFixed(2)}`; }
function safe(v) { return String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c])); }
function statusLabel(status){
  return ({open:'Neu',in_progress:'In Bearbeitung',ready:'Fertig zur Ausgabe',completed:'Ausgegeben',awaiting_payment:'Wartet auf Zahlung'})[status] || status || '-';
}
function paymentLabel(status, method){
  if(status === 'paid_card' || method === 'card') return 'Kartenzahlung';
  if(status === 'paid_cash') return 'Bar bezahlt';
  if(status === 'pending_cash' || method === 'cash') return 'Barzahlung offen';
  return status || '-';
}
function fmtTime(value){ return value ? safe(value) : '-'; }
function validColor(v, fallback){ v=String(v||'').trim(); return /^#[0-9a-f]{6}$/i.test(v) ? v : fallback; }
function hexToRgb(hex){ hex=validColor(hex,'#e85d3f').slice(1); return `${parseInt(hex.slice(0,2),16)},${parseInt(hex.slice(2,4),16)},${parseInt(hex.slice(4,6),16)}`; }
function activeTheme(){ return state.payload.theme || (state.payload.restaurants && state.adminRestaurant && state.payload.restaurants[state.adminRestaurant]?.theme) || {}; }
function applyTheme(theme){
  theme = theme || {};
  const primary = validColor(theme.primary, '#e85d3f');
  const accent = validColor(theme.accent, '#28c7b7');
  const background = validColor(theme.background, '#111827');
  document.documentElement.style.setProperty('--theme-primary', primary);
  document.documentElement.style.setProperty('--theme-accent', accent);
  document.documentElement.style.setProperty('--theme-bg', background);
  document.documentElement.style.setProperty('--theme-primary-rgb', hexToRgb(primary));
  document.documentElement.style.setProperty('--theme-accent-rgb', hexToRgb(accent));
  document.documentElement.style.setProperty('--theme-bg-rgb', hexToRgb(background));
}
function imagePath(item) { const raw = (typeof item === 'string' ? item : (item?.image || '')).trim(); if (!raw) return ''; if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('nui://') || raw.startsWith('html/')) return raw; if (raw.includes('/') || raw.includes('.png') || raw.includes('.jpg') || raw.includes('.jpeg') || raw.includes('.webp') || raw.includes('.svg')) return raw; return `html/img/items/${raw}.png`; }
function imgTag(item, alt) { const src = imagePath(item); return src ? `<img src="${safe(src)}" alt="${safe(alt)}" onerror="this.outerHTML='<div class=no-img>🍔</div>'">` : '<div class="no-img">🍔</div>'; }
function iconForCategory(name,label){ const t=(name+' '+label).toLowerCase(); if(t.includes('drink')||t.includes('geträn')) return '🥤'; if(t.includes('beilage')||t.includes('pommes')) return '🍟'; if(t.includes('menu')||t.includes('menü')) return '🍱'; return '🍔'; }
function catTabContent(c){ const img=imagePath(c); return img ? `<span class="cat-tab-img"><img src="${safe(img)}" onerror="this.parentNode.innerHTML='${safe(iconForCategory(c.name,c.label))}'"></span> ${safe(c.label)}` : `${safe(c.icon || iconForCategory(c.name, c.label))} ${safe(c.label)}`; }

if (closeBtn) closeBtn.onclick = () => { closeUi(); post('close'); };
if (isTvDisplay && closeBtn) closeBtn.style.display = 'none';
window.addEventListener('keydown', (event) => {
  if(event.key === 'Escape' && !isTvDisplay && !app.classList.contains('hidden')){
    closeUi();
    post('close');
  }
});


function tvItems(o){ let items=[]; try{items=JSON.parse(o.items_json||'[]')}catch(e){} return items; }
function renderTvDisplay(payload){
  payload = payload || {};
  const view = payload.view || 'pickup';
  const orders = payload.orders || [];
  state.payload = { currency: state.payload.currency || '$' };
  app.classList.remove('hidden');
  app.classList.add('tv-app');

  if(view === 'kitchen'){
    const cards = orders.slice(0, 8).map(o=>{
      const items = tvItems(o);
      const status = String(statusLabel(o.status)).toUpperCase();
      return `<article class="tv-order ${safe(o.status)}"><div><span class="tv-number">#${safe(o.order_number)}</span><b>${status}</b></div><ul>${items.slice(0,6).map(i=>`<li>${Number(i.amount||1)}x ${safe(i.label||'Artikel')}</li>`).join('')}</ul></article>`;
    }).join('');
    content.innerHTML = `<section class="tv-screen kitchen-tv"><header><h1>KÜCHE</h1><span>${orders.length} offen</span></header><div class="tv-grid">${cards || '<div class="tv-empty">Keine offenen Bestellungen</div>'}</div></section>`;
    return;
  }

  const working = orders.filter(o=>o.status !== 'ready');
  const ready = orders.filter(o=>o.status === 'ready');
  content.innerHTML = `<section class="tv-screen pickup-tv"><header><h1>ABHOLUNG</h1><span>Live</span></header><div class="pickup-columns"><div><h2>In Bearbeitung</h2><div class="pickup-nums">${working.map(o=>`<span>#${safe(o.order_number)}</span>`).join('') || '<small>-</small>'}</div></div><div><h2>Abholbereit</h2><div class="pickup-nums ready">${ready.map(o=>`<span>#${safe(o.order_number)}</span>`).join('') || '<small>-</small>'}</div></div></div></section>`;
}


// TV-DUI muss auch ohne erste Message sichtbar sein. Die echte Liste kommt danach per SendDuiMessage.
if (isTvDisplay) {
  window.addEventListener('DOMContentLoaded', () => {
    renderTvDisplay({ view: new URLSearchParams(window.location.search).get('type') || 'pickup', orders: [] });
  });
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'tvDisplay') { applyTheme((data.payload || {}).theme); renderTvDisplay(data.payload || {}); return; }
  if (data.action === 'forceClose') { closeUi(); return; }
  if (data.action === 'open') { state.view = data.view; state.restaurantId = data.restaurantId; state.payload = data.payload || {}; applyTheme(activeTheme()); state.cart = []; state.activeCategory = null; state.modalProduct = null; state.managerTab = 'categories'; state.editing = null; state.submittingOrder = false; app.classList.remove('hidden'); document.body.classList.add('menu-open'); render(); }
  if (data.action === 'managerData') { state.payload = data.payload || {}; applyTheme(activeTheme()); state.editing = null; renderManager(); }
  if (data.action === 'adminData') { state.payload = data.payload || {}; applyTheme(activeTheme()); state.editing = null; renderAdmin(); }
  if (data.action === 'ordersRefresh') { state.payload.orders = data.payload.orders || []; renderOrders(); }
  if (data.action === 'menuData') { state.payload = data.payload || {}; state.activeCategory = null; renderTerminal(); }
  if (data.action === 'orderCreated') { state.cart = []; state.modalProduct = null; state.submittingOrder = false; state.lastOrder = data.payload || {}; renderTerminal(); }
  if (data.action === 'orderFailed') { state.submittingOrder = false; renderTerminal(); }
});

function render(){ if(state.view === 'terminal') renderTerminal(); else if(state.view === 'manager') renderManager(); else if(state.view === 'admin') renderAdmin(); else renderOrders(); }
function cartTotal(){ return state.cart.reduce((s,i)=>s+(Number(i.price)*Number(i.amount)),0); }
function addToCart(product, amount=1){ const key=(product.type||'product')+':'+product.id; const f=state.cart.find(i=>i.key===key); if(f) f.amount += amount; else state.cart.push({ key, id: product.id, type: product.type||'product', label: product.label, price: Number(product.price), amount }); state.modalProduct=null; renderTerminal(); }
function openProduct(product){ state.modalProduct = product; state.modalQty = 1; renderTerminal(); }

function renderTerminal(){
  const cats = (state.payload.categories || []).filter(c => Number(c.enabled ?? 1) === 1);
  const products = (state.payload.products || []).filter(p => Number(p.enabled ?? 1) === 1).map(p => ({...p, type:'product'}));
  const menus = (state.payload.menus || []).filter(m => Number(m.enabled ?? 1) === 1).map(m => ({...m, type:'menu', category:'__menus', category_label:'Menüs', item_name:m.image || 'burger_menu'}));
  const tabs = [...cats];
  const hasMenuCategory = cats.some(c => (String(c.name).toLowerCase().includes('men') || String(c.label).toLowerCase().includes('menü') || String(c.label).toLowerCase().includes('menu')));
  if (menus.length && !hasMenuCategory) tabs.push({ name:'__menus', label:'Menüs', icon:'🍱', enabled:1, sort_order:999 });
  if(!state.activeCategory && tabs[0]) state.activeCategory = tabs[0].name;
  let visible = state.activeCategory === '__menus' ? menus : products.filter(p => p.category === state.activeCategory);
  const activeTab = tabs.find(c => c.name === state.activeCategory);
  const activeIsMenuCategory = activeTab && (String(activeTab.name).toLowerCase().includes('men') || String(activeTab.label).toLowerCase().includes('menü') || String(activeTab.label).toLowerCase().includes('menu'));
  if (activeIsMenuCategory && state.activeCategory !== '__menus') visible = [...menus, ...visible];
  content.innerHTML = `
    <section class="brand compact-brand"><div><h1>${safe(state.payload.restaurant || 'Hobbs Grillkiste')}</h1><div class="sub">- Bestellterminal -</div></div><div class="balance"><small>Zahlung</small><b>Karte / Bar</b></div></section>
    <nav class="tabs">${tabs.map(c=>`<button class="tab ${c.name===state.activeCategory?'active':''}" data-cat="${safe(c.name)}">${catTabContent(c)}</button>`).join('')}</nav>
    <section class="terminal-body"><div class="product-grid">${visible.map(p=>productCard(p)).join('') || '<p class="muted">Keine Produkte in dieser Kategorie.</p>'}</div></section>
    ${state.lastOrder ? lastOrderHtml() : ''}
    <section class="bottom-cart"><div class="cart-summary"><small>Warenkorb</small><div class="cart-items">${state.cart.length ? state.cart.map(i=>`${i.amount}x ${safe(i.label)}`).join(' · ') : '<span class="badge">Leer</span>'}</div></div><div class="total"><small>Gesamt</small><b>${money(cartTotal())}</b></div><div class="cart-actions"><button class="btn" id="clearCart">Leeren</button><button class="btn primary" id="payCard" ${(!state.cart.length||state.submittingOrder)?'disabled':''}>Karte zahlen</button><button class="btn" id="payCash" ${(!state.cart.length||state.submittingOrder)?'disabled':''}>Bar / Zettel</button></div></section>
    ${state.modalProduct ? modalHtml(state.modalProduct) : ''}`;
  document.querySelectorAll('[data-cat]').forEach(b=>b.onclick=()=>{state.activeCategory=b.dataset.cat; renderTerminal();});
  document.querySelectorAll('[data-product]').forEach(b=>{ const p=[...products,...menus].find(x=>`${x.type}:${x.id}`===b.dataset.product); b.onclick=()=>openProduct(p); });
  document.getElementById('clearCart').onclick=()=>{state.cart=[]; renderTerminal();};
  document.getElementById('payCard').onclick=()=>{ if(state.submittingOrder) return; state.submittingOrder=true; renderTerminal(); post('createOrder',{restaurantId:state.restaurantId,items:state.cart,paymentMethod:'card'}); };
  document.getElementById('payCash').onclick=()=>{ if(state.submittingOrder) return; state.submittingOrder=true; renderTerminal(); post('createOrder',{restaurantId:state.restaurantId,items:state.cart,paymentMethod:'cash'}); };
  const cancel=document.getElementById('modalCancel'); if(cancel) cancel.onclick=()=>{state.modalProduct=null; renderTerminal();};
  const add=document.getElementById('modalAdd'); if(add) add.onclick=()=>addToCart(state.modalProduct,state.modalQty);
  const plus=document.getElementById('qtyPlus'); if(plus) plus.onclick=()=>{state.modalQty++; renderTerminal();};
  const minus=document.getElementById('qtyMinus'); if(minus) minus.onclick=()=>{state.modalQty=Math.max(1,state.modalQty-1); renderTerminal();};
}
function productCard(p){ return `<article class="product-card visual-card"><div class="product-image">${imgTag(p,p.label)}</div><div class="product-info"><h3>${safe(p.label)}</h3><b class="product-price">${money(p.price)}</b></div><button class="order-btn" data-product="${p.type||'product'}:${p.id}"><span>Bestellen</span></button></article>`; }
function modalHtml(p){ return `<div class="modal-back"><div class="modal"><div class="modal-img">${imgTag(p,p.label)}</div><div class="modal-content"><h2>${safe(p.label)}</h2><div class="modal-row"><span class="price">${money(Number(p.price)*state.modalQty)}</span><div class="qty"><button id="qtyMinus">−</button><span>${state.modalQty}</span><button id="qtyPlus">+</button></div></div><div class="modal-actions"><button class="btn" id="modalCancel">Abbrechen</button><button class="btn primary" id="modalAdd">Hinzufügen</button></div></div></div></div>`; }

function lastOrderHtml(){
  const o = state.lastOrder || {}; const items = o.items || [];
  const paid = o.paid === true || o.paymentMethod === 'card' || o.paymentStatus === 'paid_card' || o.paymentStatus === 'paid';
  const title = paid ? 'Kassenbon' : 'Bestellzettel';
  return `<section class="order-note receipt-preview"><b>${title} #${safe(o.orderNumber)}</b><p class="muted">${safe(o.restaurant || state.payload.restaurant || 'Restaurant')}</p><ul>${items.map(i=>`<li>${safe(i.amount)}x ${safe(i.label)} · ${money(Number(i.price)*Number(i.amount))}</li>`).join('') || '<li>Keine Positionen übertragen</li>'}</ul><div><b>Summe: ${money(o.total)}</b></div><p>${paid?'Mit Karte bezahlt. Deine Bestellung wurde an die Küche geschickt.':'Noch nicht bezahlt. Geh mit dem Zettel zur Kasse und nenne die Bestellnummer.'}</p></section>`;
}


function openConfirm(title, text, postName, data){
  state.confirmDialog = { title, text, postName, data };
  render();
}
function confirmHtml(){
  const c = state.confirmDialog;
  if(!c) return '';
  return `<div class="modal-back confirm-back"><div class="modal confirm-modal"><div class="modal-content"><h2>${safe(c.title)}</h2><p>${safe(c.text)}</p><div class="modal-actions"><button class="btn" id="confirmCancel">Abbrechen</button><button class="btn danger" id="confirmOk">Endgueltig loeschen</button></div></div></div></div>`;
}
function bindConfirm(){
  if(!state.confirmDialog) return;
  const cancel = document.getElementById('confirmCancel');
  const ok = document.getElementById('confirmOk');
  if(cancel) cancel.onclick = () => { state.confirmDialog = null; render(); };
  if(ok) ok.onclick = () => {
    const c = state.confirmDialog;
    state.confirmDialog = null;
    if(c) post(c.postName, c.data || {});
    render();
  };
}

function renderOrders(){
  const raw = state.payload.orders || [];
  if(raw && raw.ok === false){ content.innerHTML = `<section class="screen"><h1>${state.view==='kitchen'?'Küchensteuerung':'Kasse'}</h1><div class="panel"><p class="muted">${safe(raw.error||'Keine Berechtigung.')}</p></div></section>`; return; }
  const orders = Array.isArray(raw) ? raw : [];
  if(state.view === 'pickup'){
    const left = orders.filter(o=>o.status==='open'||o.status==='in_progress'); const right = orders.filter(o=>o.status==='ready');
    content.innerHTML = `<section class="screen"><h1>Abholmonitor</h1><div class="screen-columns"><div class="screen-box"><h2>In Bearbeitung</h2>${left.map(o=>`<span class="num">#${o.order_number}</span>`).join('')}</div><div class="screen-box"><h2>Abholbereit</h2>${right.map(o=>`<span class="num">#${o.order_number}</span>`).join('')}</div></div></section>`; return;
  }
  if(state.view === 'cashier'){
    const q = String(state.cashierSearch || '').trim();
    const filtered = q ? orders.filter(o=>String(o.order_number).includes(q) || String(o.id).includes(q)) : orders;
    content.innerHTML = `<section class="screen"><h1>Kasse</h1><div class="panel"><div class="cashier-search"><input id="cashierSearch" placeholder="Bestellnummer" value="${safe(q)}"></div>${filtered.length?filtered.map(orderCard).join(''):'<p class="muted">Keine offene Kassen-Bestellung gefunden.</p>'}</div></section>`;
    const search = document.getElementById('cashierSearch'); if(search){ search.oninput=()=>{state.cashierSearch=search.value; renderOrders();}; }
  } else {
    content.innerHTML = `<section class="screen"><h1>Küchensteuerung</h1><div class="panel">${orders.length?orders.map(orderCard).join(''):'<p class="muted">Keine Bestellungen vorhanden.</p>'}</div></section>`;
  }
  document.querySelectorAll('[data-status]').forEach(btn=>btn.onclick=()=>post('setOrderStatus',{restaurantId:state.restaurantId,orderId:Number(btn.dataset.order),status:btn.dataset.status}));
  document.querySelectorAll('[data-paymethod]').forEach(btn=>btn.onclick=()=>post('cashierPayment',{restaurantId:state.restaurantId,orderId:Number(btn.dataset.order),method:btn.dataset.paymethod}));
}
function orderCard(o){ let items=[]; try{items=JSON.parse(o.items_json||'[]')}catch(e){} const actions=state.view==='kitchen'?`${o.status==='open'?`<button class="btn mini" data-order="${o.id}" data-status="in_progress">Annehmen</button>`:''}${o.status==='ready'?`<button class="btn mini primary" data-order="${o.id}" data-status="completed">Ausgabe erledigt</button>`:`<button class="btn mini primary" data-order="${o.id}" data-status="ready">Fertig zur Ausgabe</button>`}`:state.view==='cashier'?`<button class="btn mini primary" data-order="${o.id}" data-paymethod="cash">Barzahlung bestätigen / Bon erstellen</button>`:''; return `<article class="order"><span class="badge">#${o.order_number} · ${safe(statusLabel(o.status))} · ${safe(paymentLabel(o.payment_status,o.payment_method))}</span><h3>${money(o.total)}</h3><ul>${items.map(i=>`<li>${i.amount}x ${safe(i.label)}</li>`).join('')}</ul>${actions}</article>`; }

function renderManager(){
  if(!state.payload.ok){ content.innerHTML=`<section class="panel"><h1>Manager</h1><p>${safe(state.payload.error||'Keine Berechtigung.')}</p></section>`; return; }
  const tabs=['categories','products','menus','cash'];
  content.innerHTML=`<section class="manager compact-manager"><div class="manager-top"><h1>Manager-Laptop</h1></div><div class="manager-grid"><aside class="side">${tabs.map(t=>`<button class="btn ${state.managerTab===t?'primary':''}" data-mtab="${t}">${t==='categories'?'Kategorien':t==='products'?'Produkte':t==='menus'?'Menüs':'Kasse'}</button>`).join('')}</aside><section class="panel">${managerPanel()}</section></div></section>`;
  content.insertAdjacentHTML('beforeend', confirmHtml());
  document.querySelectorAll('[data-mtab]').forEach(b=>b.onclick=()=>{state.managerTab=b.dataset.mtab;state.editing=null;renderManager();}); bindManager(); bindConfirm();
}
function managerPanel(){ return state.managerTab==='categories'?categoryPanel():state.managerTab==='products'?productPanel():state.managerTab==='menus'?menuPanel():cashPanel(); }
function paymentItemsHtml(row){
  let items=[]; try{items=JSON.parse(row.items_json||'[]')}catch(e){}
  if(!items.length) return '<div class="payment-items muted">Keine Positionsdaten.</div>';
  return '<div class="payment-items"><ul>'+items.map(i=>'<li><span>'+safe(i.amount||1)+'x '+safe(i.label||'Artikel')+'</span><b>'+money(Number(i.price||0)*Number(i.amount||1))+'</b></li>').join('')+'</ul></div>';
}
function paymentCard(p){
  const isOpen = String(state.openPayment||'') === String(p.id);
  const method = p.method === 'card' ? 'Kartenzahlung' : 'Barzahlung';
  const actor = p.method === 'card' ? 'Automatisch verbucht' : safe(p.cashier_name || 'Kasse');
  return '<article class="payment-card '+(isOpen?'open':'')+'" data-payment="'+safe(p.id)+'"><div class="payment-main"><div><b>#'+safe(p.order_number||'-')+'</b><span>'+method+' - '+actor+'</span></div><strong>'+money(p.amount)+'</strong><time>'+fmtTime(p.booked_time)+'</time></div>'+(isOpen?paymentItemsHtml(p):'')+'</article>';
}
function cashPanel(){
  const stats=state.payload.cashStats||{today:0,open:0,total:0,cardToday:0,cardTotal:0,orders:[],cashiers:[],payments:[]};
  const orders=stats.orders||[], cashiers=stats.cashiers||[], payments=stats.payments||[];
  return '<h2>Kasse</h2><div class="stats"><div><small>Heute bar</small><b>'+money(stats.today)+'</b></div><div><small>Offener Kassensturz</small><b>'+money(stats.open)+'</b></div><div><small>Heute Karte</small><b>'+money(stats.cardToday)+'</b></div><div><small>Gesamt Karte</small><b>'+money(stats.cardTotal)+'</b></div></div><h2>Kassensturz</h2><div class="cash-close-list">'+(cashiers.length?cashiers.map(c=>'<article class="cash-close-card"><div><b>'+safe(c.cashier_name||'Unbekannt')+'</b><span>'+Number(c.order_count||0)+' Zahlung(en) - '+fmtTime(c.first_paid_time)+' bis '+fmtTime(c.last_paid_time)+'</span></div><strong>'+money(c.total)+'</strong><button class="btn mini primary" data-closecash="'+safe(c.cashier_identifier||'')+'">Kassensturz abschliessen</button></article>').join(''):'<p class="muted">Keine offenen Bar-Einnahmen fuer einen Kassensturz.</p>')+'</div><h2>Buchungen</h2><div class="payment-list">'+(payments.length?payments.map(paymentCard).join(''):'<p class="muted">Noch keine Buchungen vorhanden.</p>')+'</div><h2>Letzte Barzahlungen</h2><table class="table"><tr><th>Bestellung</th><th>Betrag</th><th>Kassierer</th><th>Zeit</th><th>Status</th></tr>'+orders.map(o=>'<tr><td>#'+o.order_number+'</td><td>'+money(o.total)+'</td><td>'+safe(o.cashier_name||o.cashier_identifier||'-')+'</td><td>'+fmtTime(o.paid_time||o.paid_at||o.updated_at)+'</td><td>'+(o.cash_closed_at?'Abgeschlossen':'Offen')+'</td></tr>').join('')+'</table>';
}
function categoryPanel(){ const cats=state.payload.categories||[]; const e=state.editing||{}; return `<h2>Kategorien</h2><div class="form"><input id="catLabel" class="full" placeholder="Kategoriename" value="${safe(e.label || e.name)}"><input id="catImage" class="full" placeholder="Bild-URL" value="${safe(e.image)}"><div class="image-help full"><div class="image-preview" id="catImagePreview">${imgTag({image:e.image}, e.label||'Kategorie')}</div></div><input id="catSort" type="number" placeholder="Sortierung" value="${safe(e.sort_order||1)}"><select id="catEnabled"><option value="1">Aktiv</option><option value="0" ${Number(e.enabled)===0?'selected':''}>Inaktiv</option></select><button class="btn primary" id="saveCat">Speichern</button></div><table class="table"><tr><th>Bild</th><th>Name</th><th>Sort</th><th></th></tr>${cats.map(c=>{ const disabled=Number(c.enabled)===0; return `<tr class="${disabled?'is-disabled':''}"><td><div class="table-img">${imgTag(c,c.label)}</div></td><td>${safe(c.label)}</td><td>${c.sort_order}</td><td><button class="btn mini" data-editcat="${c.id}">Bearbeiten</button>${disabled?`<button class="btn mini" data-togglecat="${c.id}">Aktivieren</button><button class="btn mini danger" data-harddelcat="${c.id}">Endgültig löschen</button>`:`<button class="btn mini" data-delcat="${c.id}">Deaktivieren</button>`}</td></tr>`; }).join('')}</table>`; }
function productPanel(){ const cats=state.payload.categories||[], products=state.payload.products||[], e=state.editing||{}; const isEdit=!!e.id; return `<div class="manager-headline"><div><h2>PRODUKTE</h2></div><button class="btn" id="newProd">+ Neues Produkt</button></div><div class="form"><select id="prodCat">${cats.map(c=>`<option value="${safe(c.name)}" ${e.category===c.name?'selected':''}>${safe(c.label)}</option>`).join('')}</select><input id="prodLabel" placeholder="Name" value="${safe(e.label)}"><input id="prodPrice" type="number" step="0.01" min="0" placeholder="Preis" value="${safe(e.price||'')}"><select id="prodEnabled"><option value="1">Aktiv</option><option value="0" ${Number(e.enabled)===0?'selected':''}>Inaktiv</option></select><input id="prodImage" class="full" placeholder="Bild-Link" value="${safe(e.image)}"><div class="image-help full"><div class="image-preview" id="prodImagePreview">${imgTag({image:e.image}, e.label||'Vorschau')}</div><div><input id="oxImageSearch" placeholder="Bild" value=""><small class="muted ox-hint">Mindestens 3 Anfangsbuchstaben eingeben, dann erscheinen Bilder aus dem Inventory.</small><div class="ox-suggestions" id="oxImageSuggestions"></div></div></div><div class="full form-actions"><button class="btn primary" id="saveProd">${isEdit?'Änderungen speichern':'Produkt hinzufügen'}</button>${isEdit?'<button class="btn" id="duplicateProd">Als neues Produkt kopieren</button><button class="btn" id="cancelProdEdit">Bearbeitung abbrechen</button>':''}</div></div><table class="table"><tr><th>Bild</th><th>Name</th><th>Preis</th><th></th></tr>${products.map(p=>{ const disabled=Number(p.enabled)===0; return `<tr class="${disabled?'is-disabled':''}"><td><div class="table-img">${imgTag(p,p.label)}</div></td><td>${safe(p.label)}</td><td>${money(p.price)}</td><td><button class="btn mini" data-editprod="${p.id}">Bearbeiten</button><button class="btn mini" data-toggleprod="${p.id}" data-enabled="${Number(p.enabled)?0:1}">${Number(p.enabled)?'Deaktivieren':'Aktivieren'}</button>${disabled?`<button class="btn mini danger" data-harddelprod="${p.id}">Endgültig löschen</button>`:''}</td></tr>`; }).join('')}</table>`; }
function menuPanel(){ const products=state.payload.products||[], menus=state.payload.menus||[], e=state.editing||{}; let chosen=[]; try{chosen=JSON.parse(e.products_json||'[]')}catch(x){} return `<h2>Menüs</h2><div class="form"><input id="menuLabel" placeholder="Menüname" value="${safe(e.label)}"><input id="menuPrice" type="number" step="0.01" placeholder="Eigener Preis optional" value="${safe(e.price||'')}"><div class="full">${products.map(p=>`<label style="display:inline-block;margin:6px 12px 6px 0"><input type="checkbox" class="menuProd" value="${p.id}" ${chosen.includes(Number(p.id))?'checked':''}> ${safe(p.label)} (${money(p.price)})</label>`).join('')}</div><button class="btn primary full" id="saveMenu">Menü speichern</button></div><table class="table"><tr><th>ID</th><th>Name</th><th>Preis</th><th>Status</th><th></th></tr>${menus.map(m=>`<tr><td>${m.id}</td><td>${safe(m.label)}</td><td>${money(m.price)}</td><td>${Number(m.enabled)?'Aktiv':'Inaktiv'}</td><td><button class="btn mini" data-editmenu="${m.id}">Bearbeiten</button><button class="btn mini" data-delmenu="${m.id}">Deaktivieren</button></td></tr>`).join('')}</table>`; }
function bindManager(){
  (document.getElementById('saveCat')||{}).onclick=()=>post('saveCategory',{id:state.editing?.id,restaurantId:state.restaurantId,label:catLabel.value,image:catImage.value,sort_order:Number(catSort.value),enabled:catEnabled.value==='1'});
  const catImageInput = document.getElementById('catImage'); if(catImageInput){ catImageInput.oninput=()=>{ const pv=document.getElementById('catImagePreview'); if(pv) pv.innerHTML=imgTag({image:catImageInput.value}, catLabel?.value||'Kategorie'); }; }
  const prodImageInput = document.getElementById('prodImage'); if(prodImageInput){ prodImageInput.oninput=()=>{ const pv=document.getElementById('prodImagePreview'); if(pv) pv.innerHTML=imgTag({image:prodImageInput.value}, prodLabel?.value||'Vorschau'); }; }
  const oxSearch = document.getElementById('oxImageSearch');
  const oxBox = document.getElementById('oxImageSuggestions');
  let oxTimer = null;
  if(oxSearch && oxBox){
    oxSearch.oninput=()=>{
      clearTimeout(oxTimer);
      const q = oxSearch.value.trim();
      if(q.length < 3){ oxBox.innerHTML=''; return; }
      oxTimer = setTimeout(()=>post('searchOxInventoryImages',{query:q}).then(r=>r&&r.json?r.json():r).then(res=>{
        const items = (res && res.items) || [];
        oxBox.innerHTML = items.length ? items.map(i=>`<button type="button" class="ox-suggestion" data-oximage="${safe(i.path)}" data-oxname="${safe(i.name)}"><img src="${safe(i.path)}"><span>${safe(i.label)}</span><small>${safe(i.name)}</small></button>`).join('') : '<span class="muted">Keine Treffer.</span>';
        oxBox.querySelectorAll('[data-oximage]').forEach(btn=>btn.onclick=()=>{
          prodImage.value = btn.dataset.oximage;
          if(!prodLabel.value) prodLabel.value = btn.querySelector('span')?.textContent || '';
          const pv=document.getElementById('prodImagePreview'); if(pv) pv.innerHTML=imgTag({image:prodImage.value}, prodLabel?.value||'Vorschau');
        });
      }), 180);
    };
  }
  document.querySelectorAll('[data-closecash]').forEach(b=>b.onclick=()=>post('closeCashierShift',{restaurantId:state.restaurantId,cashierIdentifier:b.dataset.closecash}));
  document.querySelectorAll('[data-payment]').forEach(card=>card.onclick=()=>{ state.openPayment = state.openPayment === card.dataset.payment ? null : card.dataset.payment; renderManager(); });
  const saveCurrentProduct = (forceNew=false)=>post('saveProduct',{id:forceNew?null:state.editing?.id,restaurantId:state.restaurantId,category:prodCat.value,label:prodLabel.value,price:Number(prodPrice.value),image:prodImage.value,description:'',enabled:prodEnabled.value==='1'});
  (document.getElementById('saveProd')||{}).onclick=()=>saveCurrentProduct(false);
  (document.getElementById('duplicateProd')||{}).onclick=()=>saveCurrentProduct(true);
  (document.getElementById('cancelProdEdit')||{}).onclick=()=>{state.editing=null;renderManager();};
  (document.getElementById('newProd')||{}).onclick=()=>{state.editing=null;renderManager();};
  (document.getElementById('saveMenu')||{}).onclick=()=>post('saveMenu',{id:state.editing?.id,restaurantId:state.restaurantId,label:menuLabel.value,description:'',price:Number(menuPrice.value||0),products:[...document.querySelectorAll('.menuProd:checked')].map(x=>Number(x.value))});
  document.querySelectorAll('[data-editcat]').forEach(b=>b.onclick=()=>{state.editing=(state.payload.categories||[]).find(x=>Number(x.id)===Number(b.dataset.editcat));renderManager();});
  document.querySelectorAll('[data-editprod]').forEach(b=>b.onclick=()=>{state.editing=(state.payload.products||[]).find(x=>Number(x.id)===Number(b.dataset.editprod));renderManager();});
  document.querySelectorAll('[data-editmenu]').forEach(b=>b.onclick=()=>{state.editing=(state.payload.menus||[]).find(x=>Number(x.id)===Number(b.dataset.editmenu));renderManager();});
  document.querySelectorAll('[data-delcat]').forEach(b=>b.onclick=()=>post('deleteCategory',{restaurantId:state.restaurantId,id:Number(b.dataset.delcat)}));
  document.querySelectorAll('[data-togglecat]').forEach(b=>b.onclick=()=>{ const c=(state.payload.categories||[]).find(x=>Number(x.id)===Number(b.dataset.togglecat)); if(!c) return; post('saveCategory',{id:c.id,restaurantId:state.restaurantId,label:c.label||c.name,image:c.image||'',sort_order:Number(c.sort_order||1),enabled:true}); });
  document.querySelectorAll('[data-harddelcat]').forEach(b=>b.onclick=()=>openConfirm('Kategorie loeschen', 'Diese Kategorie wird endgueltig entfernt.', 'hardDeleteCategory', {restaurantId:state.restaurantId,id:Number(b.dataset.harddelcat)}));
  document.querySelectorAll('[data-harddelprod]').forEach(b=>b.onclick=()=>openConfirm('Produkt loeschen', 'Dieses Produkt wird endgueltig entfernt.', 'hardDeleteProduct', {restaurantId:state.restaurantId,id:Number(b.dataset.harddelprod)}));
  document.querySelectorAll('[data-toggleprod]').forEach(b=>b.onclick=()=>{ const p=(state.payload.products||[]).find(x=>Number(x.id)===Number(b.dataset.toggleprod)); if(!p) return; post('saveProduct',{id:p.id,restaurantId:state.restaurantId,category:p.category,label:p.label,price:Number(p.price),item_name:p.item_name||'',image:p.image||'',description:p.description||'',enabled:b.dataset.enabled==='1'}); });
  document.querySelectorAll('[data-delmenu]').forEach(b=>b.onclick=()=>post('deleteMenu',{restaurantId:state.restaurantId,id:Number(b.dataset.delmenu)}));
}


function restaurantArray(){ const r = state.payload.restaurants || {}; return Object.keys(r).sort((a,b)=>Number(r[b].enabled??1)-Number(r[a].enabled??1)||String(r[a].label).localeCompare(String(r[b].label))).map(id=>({id, ...r[id]})); }
function pointLabel(t){ return {terminals:'Bestellterminal',manager:'Manager-Laptop',kitchen:'Küchenmonitor',pickup:'Abholmonitor',cashier:'Kasse'}[t] || t; }
function renderAdmin(){
  if(!state.payload.ok){ content.innerHTML=`<section class="panel"><h1>Restaurant-Creator</h1><p>${safe(state.payload.error||'Keine Berechtigung.')}</p></section>`; return; }
  const list = restaurantArray();
  if(!state.adminRestaurant && list[0]) state.adminRestaurant = list[0].id;
  const active = list.find(r=>r.id===state.adminRestaurant) || {};
  const e = state.editing || active || {};
  applyTheme((e && e.theme) || (active && active.theme));
  const types = ['terminals','manager','kitchen','pickup','cashier'];
  content.innerHTML = `<section class="manager admin-creator"><div class="manager-top"><h1>Restaurant-Creator</h1></div><div class="manager-grid"><aside class="side"><button class="btn primary" id="newRestaurant">+ Neuer Laden</button>${list.map(r=>`<button class="btn ${r.id===state.adminRestaurant?'primary':''} ${Number(r.enabled??1)?'':'is-disabled'}" data-adminrest="${safe(r.id)}">${safe(r.label)}<small>${safe(r.id)}${Number(r.enabled??1)?'':' · deaktiviert'}</small></button>`).join('')}</aside><section class="panel">${adminPanel(e, active, types)}</section></div></section>`;
  content.insertAdjacentHTML('beforeend', confirmHtml());
  bindAdmin(); bindConfirm();
}
function adminPanel(e, active, types){
  const isNew = !(e && e.id);
  const rid = e.id || active.id || '';
  const pointsHtml = active && active.id ? types.map(t=>{
    const points = (active.points && active.points[t]) || [];
    const monitorControls = (t==='kitchen'||t==='pickup') ? '<select class="monitor-size"><option value="large">Bildschirm: gross</option><option value="small">Bildschirm: klein</option></select><button class="btn mini" data-placetv="'+t+'">TV platzieren</button>' : '';
    return '<div class="point-box"><div><b>'+pointLabel(t)+'</b></div>'+monitorControls+'<button class="btn mini primary" data-setpoint="'+t+'">Hier setzen</button>'+points.map(p=>'<div class="point-row"><span>#'+p.id+' - '+safe(p.screen_size||'standard')+' - '+Number(p.x).toFixed(2)+', '+Number(p.y).toFixed(2)+', '+Number(p.z).toFixed(2)+'</span><button class="btn mini" data-delpoint="'+p.id+'">Entfernen</button></div>').join('')+'</div>';
  }).join('') : '<p class="muted">Speichere den Laden zuerst, dann kannst du Punkte setzen.</p>';
  const disabled = active && active.id && Number(active.enabled??1)===0;
  return '<div class="manager-headline"><div><h2>'+(isNew?'Neuen Laden erstellen':'Laden bearbeiten')+(disabled?' - deaktiviert':'')+'</h2></div>'+((active&&active.id&&Number(active.enabled??1)!==0)?'<button class="btn" id="openManagerForRestaurant">Produkte/Kategorien oeffnen</button>':'')+'</div><div class="form"><input id="adminId" placeholder="Interne ID z.B. burgershot" value="'+safe(rid)+'" '+(isNew?'':'readonly')+'><input id="adminLabel" placeholder="Anzeigename z.B. Burger Shot" value="'+safe(e.label||'')+'"><input id="adminJob" placeholder="Jobname z.B. burgershot" value="'+safe(e.job||'')+'"><input id="adminSociety" placeholder="Society-Konto, leer = society_jobname" value="'+safe(e.societyAccount||e.society_account||'')+'"><button class="btn primary full" id="saveRestaurant">'+(disabled?'Laden reaktivieren / speichern':'Laden speichern')+'</button>'+((active&&active.id&&Number(active.enabled??1)!==0)?'<button class="btn full" id="deleteRestaurant">Laden deaktivieren</button>':'')+(disabled?'<button class="btn danger full" id="hardDeleteRestaurant">Endgueltig loeschen</button>':'')+'</div><h2>Punkte setzen</h2><div class="point-grid">'+pointsHtml+'</div>';
}
function bindAdmin(){
  const theme = activeTheme();
  const primary = validColor(theme.primary, '#e85d3f');
  const accent = validColor(theme.accent, '#28c7b7');
  const background = validColor(theme.background, '#111827');
  const saveBtn = document.getElementById('saveRestaurant');
  if(saveBtn && !document.getElementById('themePrimary')){
    saveBtn.insertAdjacentHTML('beforebegin', `<div class="theme-editor full"><label><span>Hauptfarbe</span><input id="themePrimary" type="color" value="${primary}"></label><label><span>Akzent</span><input id="themeAccent" type="color" value="${accent}"></label><label><span>Hintergrund</span><input id="themeBackground" type="color" value="${background}"></label><div class="theme-preview"><i style="background:${primary}"></i><i style="background:${accent}"></i><i style="background:${background}"></i></div></div>`);
  }
  document.querySelectorAll('[data-adminrest]').forEach(b=>b.onclick=()=>{state.adminRestaurant=b.dataset.adminrest; state.editing=null; renderAdmin();});
  (document.getElementById('newRestaurant')||{}).onclick=()=>{state.editing={id:'',label:'',job:'',societyAccount:'',theme:{primary:'#e85d3f',accent:'#28c7b7',background:'#111827'}}; state.adminRestaurant=null; renderAdmin();};
  const readThemeInputs = () => ({ primary: document.getElementById('themePrimary')?.value, accent: document.getElementById('themeAccent')?.value, background: document.getElementById('themeBackground')?.value });
  ['themePrimary','themeAccent','themeBackground'].forEach(id=>{ const el=document.getElementById(id); if(el) el.oninput=()=>applyTheme(readThemeInputs()); });
  (document.getElementById('saveRestaurant')||{}).onclick=()=>post('saveRestaurant',{id:adminId.value,label:adminLabel.value,job:adminJob.value,societyAccount:adminSociety.value,theme:readThemeInputs()});
  (document.getElementById('deleteRestaurant')||{}).onclick=()=>{ if(state.adminRestaurant) post('deleteRestaurant',{restaurantId:state.adminRestaurant}); };
  (document.getElementById('hardDeleteRestaurant')||{}).onclick=()=>{ if(state.adminRestaurant) openConfirm('Laden loeschen', 'Produkte, Punkte, Menues, Bestellungen und Buchungen werden endgueltig entfernt.', 'hardDeleteRestaurant', {restaurantId:state.adminRestaurant,confirm:true}); };
  (document.getElementById('openManagerForRestaurant')||{}).onclick=()=>{ if(state.adminRestaurant) post('openRestaurantManager',{restaurantId:state.adminRestaurant}); };
  document.querySelectorAll('[data-setpoint]').forEach(b=>b.onclick=()=>{ const size=b.closest('.point-box')?.querySelector('.monitor-size')?.value; if(state.adminRestaurant) post('setPointHere',{restaurantId:state.adminRestaurant,pointType:b.dataset.setpoint,screenSize:size}); });
  document.querySelectorAll('[data-placetv]').forEach(b=>b.onclick=()=>{ const size=b.closest('.point-box')?.querySelector('.monitor-size')?.value || 'large'; if(state.adminRestaurant) post('placeMonitorTv',{restaurantId:state.adminRestaurant,pointType:b.dataset.placetv,screenSize:size}); });
  document.querySelectorAll('[data-delpoint]').forEach(b=>b.onclick=()=>post('deletePoint',{id:Number(b.dataset.delpoint)}));
}
