import { apiFetch, getTokens } from './main.js';

function setMessage(text, isError = false) {
  const box = document.getElementById('dashboardMessage');
  if (!box) return;
  box.textContent = text;
  box.className = isError ? 'alert error' : 'alert';
}

async function loadUser() {
  const res = await apiFetch('/dashboard/user');
  if (!res.ok) {
    setMessage('Please login to view your dashboard', true);
    return;
  }
  const data = await res.json();
  const emailEl = document.getElementById('userEmail');
  const statusEl = document.getElementById('subStatus');
  if (emailEl) emailEl.textContent = data.email;
  if (statusEl) statusEl.textContent = data.subscription_status || 'inactive';
}

async function loadSubscription() {
  const res = await apiFetch('/dashboard/subscription');
  if (!res.ok) return;
  const data = await res.json();
  const subBox = document.getElementById('subscriptionBox');
  if (!subBox) return;
  subBox.innerHTML = `
    <div class="chip">Provider: ${data.provider || 'n/a'}</div>
    <div class="chip">Status: ${data.status || 'none'}</div>
    <div class="chip">Expires: ${data.expires_at || 'n/a'}</div>
  `;
}

async function generateConfig() {
  setMessage('Generating WireGuard profile...');
  const res = await apiFetch('/vpn/generate', { method: 'POST' });
  if (!res.ok) {
    const msg = (await res.json()).detail || 'Could not generate config';
    setMessage(msg, true);
    return;
  }
  setMessage('Config ready. You can download or view the QR.');
}

async function downloadConfig() {
  const res = await apiFetch('/vpn/config/download');
  if (!res.ok) {
    setMessage('Download failed', true);
    return;
  }
  const blob = await res.blob();
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'securewave.conf';
  document.body.appendChild(a);
  a.click();
  a.remove();
  window.URL.revokeObjectURL(url);
}

async function loadQr() {
  const res = await apiFetch('/vpn/config/qr');
  if (!res.ok) {
    setMessage('Generate your config first', true);
    return;
  }
  const data = await res.json();
  const qrImg = document.getElementById('qrImage');
  if (qrImg) {
    qrImg.src = `data:image/png;base64,${data.qr_base64}`;
    qrImg.style.display = 'block';
  }
}

async function startStripe() {
  const res = await apiFetch('/payments/stripe', { method: 'POST' });
  if (!res.ok) {
    setMessage('Stripe not configured', true);
    return;
  }
  const data = await res.json();
  window.location.href = data.checkout_url;
}

async function startPaypal() {
  const res = await apiFetch('/payments/paypal', {
    method: 'POST',
    body: JSON.stringify({ amount: 9.99 })
  });
  if (!res.ok) {
    setMessage('PayPal not configured', true);
    return;
  }
  const data = await res.json();
  const approveLink = (data.links || []).find(l => l.rel === 'approve');
  if (approveLink) {
    window.location.href = approveLink.href;
  } else {
    setMessage('PayPal response missing approval link', true);
  }
}

export function initDashboard() {
  const tokens = getTokens();
  if (!tokens.access) {
    setMessage('Login required to access the dashboard', true);
    return;
  }
  loadUser();
  loadSubscription();
  const genBtn = document.getElementById('generateConfig');
  if (genBtn) genBtn.addEventListener('click', generateConfig);
  const dlBtn = document.getElementById('downloadConfig');
  if (dlBtn) dlBtn.addEventListener('click', downloadConfig);
  const qrBtn = document.getElementById('viewQr');
  if (qrBtn) qrBtn.addEventListener('click', loadQr);
  const stripeBtn = document.getElementById('payStripe');
  if (stripeBtn) stripeBtn.addEventListener('click', startStripe);
  const paypalBtn = document.getElementById('payPaypal');
  if (paypalBtn) paypalBtn.addEventListener('click', startPaypal);
}

document.addEventListener('DOMContentLoaded', initDashboard);
