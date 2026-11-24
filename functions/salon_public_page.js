const PUBLIC_HOST = 'trimtime-46539.web.app';
const validSalonId = (id) => /^[A-Za-z0-9_-]{1,128}$/.test(id);
const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (c) =>
  ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
function publicSalon(salon) {
  if (!salon || salon.adminSuspended === true || salon.hidden === true ||
      salon.isDemo === true || salon.isTest === true ||
      ['pending', 'rejected'].includes(salon.approvalStatus)) return null;
  const photos = Array.isArray(salon.photoUrls) ? salon.photoUrls : [];
  const photo = photos.find((url) => typeof url === 'string' && /^https:\/\//i.test(url)) || '';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return {name: String(salon.name || 'Salon'), photo,
    openTime: String(salon.openTime || ''), closeTime: String(salon.closeTime || ''),
    closedDays: (Array.isArray(salon.closedWeekdays) ? salon.closedWeekdays : [])
      .filter((day) => Number.isInteger(day) && day >= 1 && day <= 7).map((day) => days[day - 1]).join(', '),
    services: (Array.isArray(salon.services) ? salon.services : [])
      .filter((service) => service.isAvailable !== false).slice(0, 8)
      .map((service) => String(service.name || '')).filter(Boolean)};
}
function renderSalonPage(id, salon) {
  const data = publicSalon(salon);
  const title = data ? `${data.name} | SalonFe` : 'Salon unavailable | SalonFe';
  const url = `https://${PUBLIC_HOST}/s/${encodeURIComponent(id)}`;
  const e = escapeHtml;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#FF7B54"><title>${e(title)}</title><meta property="og:title" content="${e(title)}"><meta property="og:description" content="View this salon and book your next visit with SalonFe."><meta property="og:url" content="${e(url)}"><meta property="og:type" content="website">${data?.photo ? `<meta property="og:image" content="${e(data.photo)}">` : ''}<meta name="apple-itunes-app" content="app-id=6792811282, app-argument=${e(url)}"><link rel="canonical" href="${e(url)}"><style>body{font:16px system-ui;color:#111;background:#fff8f5;margin:0;padding:24px}main{max-width:560px;margin:24px auto;background:white;border-radius:28px;overflow:hidden;box-shadow:0 12px 50px #55221112}.content{padding:28px}img{width:100%;max-height:360px;object-fit:cover}.brand{color:#bf4323;font-weight:800}h1{font-size:30px}p{line-height:1.6;color:#555}.button{display:block;text-align:center;background:#FF7B54;color:#111;padding:16px;border-radius:14px;font-weight:750;text-decoration:none;margin:14px 0}.stores{display:flex;gap:18px;flex-wrap:wrap;margin:22px 0}a{color:#a63a20}footer{font-size:13px;margin-top:28px}</style></head><body><main>${data?.photo ? `<img src="${e(data.photo)}" alt="${e(data.name)}" referrerpolicy="no-referrer">` : ''}<div class="content"><div class="brand">SalonFe</div><h1>${e(data?.name || 'This salon is not available')}</h1>${data ? `<p>${e(data.services.join(' · '))}</p><p>${e(data.openTime)} – ${e(data.closeTime)}${data.closedDays ? `<br>Closed: ${e(data.closedDays)}` : ''}</p><a class="button" href="salonfe://salon/${e(id)}">Open this salon in SalonFe</a><p>Have the app? Open this salon directly. Otherwise, install SalonFe and return to this link. Sign in is required to book.</p>` : '<p>This salon may be awaiting approval or no longer available.</p>'}<div class="stores"><a href="https://play.google.com/store/apps/details?id=com.trimtime.app">Google Play</a><a href="https://apps.apple.com/app/id6792811282">App Store</a></div><footer><a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms &amp; Conditions</a> · <a href="/support">Support</a></footer></div></main></body></html>`;
}
module.exports = {validSalonId, publicSalon, renderSalonPage};
