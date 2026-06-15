const app = document.getElementById('app');
const paper = document.getElementById('paper');
const closeBtn = document.getElementById('close');

function safe(v){return String(v ?? '').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
function money(v, c){return `${c || '$'}${Number(v || 0).toFixed(2)}`;}
function parseItems(meta){
  meta = meta || {};
  const sources = [meta.items, meta.items_json, meta.items_text];
  for (const items of sources) {
    if(Array.isArray(items) && items.length) return items;
    if(typeof items === 'string' && items.trim()){
      try { const parsed = JSON.parse(items); if(Array.isArray(parsed) && parsed.length) return parsed; } catch(e) {}
      return items.split('\n').filter(Boolean).map(line=>({ raw: line }));
    }
  }
  const flat = [];
  for(let i=1;i<=20;i++){
    const label = meta[`item_${i}_label`];
    if(!label) continue;
    flat.push({
      label,
      amount: meta[`item_${i}_amount`] || 1,
      price: meta[`item_${i}_price`] || 0,
      total: meta[`item_${i}_total`] || ((Number(meta[`item_${i}_price`]||0)) * (Number(meta[`item_${i}_amount`]||1)))
    });
  }
  return flat;
}
function normalizeMeta(raw){
  let meta = raw && (raw.metadata || raw.info || raw) || {};
  if(meta.item && (meta.item.metadata || meta.item.info)) meta = meta.item.metadata || meta.item.info;
  return meta || {};
}
function isPaid(meta){
  const status = String(meta.payment_status || meta.paid_status || meta.status || '').toLowerCase();
  const label = String(meta.payment_text || meta.payment_label || meta.payment || meta.status_label || '').toLowerCase();
  return meta.paid === true || meta.paid === 'true' || meta.paid === 1 || meta.paid === '1' || meta.is_paid === true || meta.is_paid === 1 || meta.is_paid === '1' || meta.receipt_type === 'receipt' || status === 'paid' || status === 'paid_cash' || status === 'paid_card' || label.includes('bezahlt');
}
function render(meta){
  meta = normalizeMeta(meta);
  const paid = isPaid(meta);
  const currency = meta.currency || '$';
  const items = parseItems(meta);
  const orderNumber = meta.order_number || meta.orderNumber || meta.order_id || '-';
  const tip = Number(meta.tip_amount || meta.tip || 0);
  const subtotal = Number(meta.subtotal || Math.max(0, Number(meta.total || 0) - tip));
  paper.innerHTML = `
    <div class="top">
      <h1>${paid ? 'KASSENBON' : 'BESTELLZETTEL'}</h1>
      <p>${safe(meta.restaurant_name || meta.restaurant || 'Unbekanntes Restaurant')}</p>
    </div>
    <div class="meta">
      <span>Bestellung</span><b>#${safe(orderNumber)}</b>
      <span>Uhrzeit</span><b>${safe(meta.created_at || meta.time || '-')}</b>
      <span>Status</span><b class="${paid ? 'paid' : 'open'}">${paid ? safe(meta.payment_text || meta.payment_label || meta.payment || (meta.payment_method === 'cash' ? 'Bar bezahlt' : 'Mit Karte bezahlt')) : 'Noch nicht bezahlt'}</b>
    </div>
    <hr>
    <ul class="items">
      ${items.length ? items.map(i=> i.raw ? `<li><span>${safe(i.raw)}</span></li>` : `<li><span>${safe(i.amount || 1)}x ${safe(i.label || 'Artikel')}</span><b>${money(i.total ?? ((i.price||0)*(i.amount||1)), currency)}</b></li>`).join('') : '<li><span>Keine Positionen gespeichert</span></li>'}
    </ul>
    <hr>
    ${tip > 0 ? `<div class="total muted-line"><span>Zwischensumme</span><b>${money(subtotal, currency)}</b></div><div class="total muted-line"><span>Trinkgeld</span><b>${money(tip, currency)}</b></div>` : ''}
    <div class="total"><span>Summe</span><b>${money(meta.total, currency)}</b></div>
    <p class="hint">${paid ? 'Dieser Bon ist bereits bezahlt. Bitte als Nachweis bis zur Abholung behalten.' : 'Mit diesem Zettel bitte zur Kasse gehen und die Bestellnummer nennen.'}</p>
  `;
}

window.addEventListener('message', e=>{
  const data = e.data || {};
  if(data.action === 'open') { render(data.payload || {}); app.classList.remove('hidden'); document.body.classList.add('receipt-open'); }
  if(data.action === 'close') { app.classList.add('hidden'); document.body.classList.remove('receipt-open'); }
});
closeBtn.onclick = ()=>fetch(`https://${GetParentResourceName()}/close`, {method:'POST', body:'{}'});
document.addEventListener('keyup', e=>{ if(e.key === 'Escape') closeBtn.click(); });
