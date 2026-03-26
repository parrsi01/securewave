(function () {
  function safeJson(res) {
    return res.json().catch(() => ({}));
  }

  async function fetchJson(url) {
    const res = await fetch(url, { credentials: 'include' });
    const data = await safeJson(res);
    return { ok: res.ok, status: res.status, data };
  }

  function applyTone(el, tone) {
    if (!el) return;
    el.classList.remove('text-success', 'text-warning', 'text-danger', 'text-default');
    if (tone) {
      el.classList.add(tone);
    }
  }

  function setStatus(el, okText, badText, ok) {
    if (!el) return;
    el.textContent = ok ? okText : badText;
    applyTone(el, ok ? 'text-success' : 'text-warning');
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const me = await fetch('/api/auth/me', { credentials: 'include' });
    if (!me.ok) {
      window.location.href = '/login';
      return;
    }

    const apiEl = document.querySelector('[data-diag-api]');
    const dbEl = document.querySelector('[data-diag-db]');
    const subEl = document.querySelector('[data-diag-sub]');
    const stripeEl = document.querySelector('[data-diag-stripe]');

    const results = await Promise.allSettled([
      fetchJson('/api/health'),
      fetchJson('/api/ready'),
      fetchJson('/api/billing/subscriptions/current'),
      fetchJson('/api/billing/stripe-status'),
    ]);

    const api = results[0].status === 'fulfilled' ? results[0].value : { ok: false, data: {} };
    const ready = results[1].status === 'fulfilled' ? results[1].value : { ok: false, data: {} };
    const sub = results[2].status === 'fulfilled' ? results[2].value : { ok: false, data: {} };
    const stripe = results[3].status === 'fulfilled' ? results[3].value : { ok: false, data: {} };

    setStatus(apiEl, 'Online', 'Degraded', api.ok);
    setStatus(dbEl, 'Connected', 'Unavailable', ready.ok);

    if (sub.ok) {
      const s = sub.data?.subscription;
      if (!s) {
        subEl.textContent = 'Free tier';
        applyTone(subEl, 'text-default');
      } else {
        subEl.textContent = `${s.plan_name || s.plan_id || 'Plan'} (${s.status || '--'})`;
        applyTone(subEl, s.is_active ? 'text-success' : 'text-warning');
      }
    } else {
      setStatus(subEl, 'OK', 'Unknown', false);
    }

    if (stripe.ok) {
      const configured = !!stripe.data?.configured;
      const mode = stripe.data?.mode || '--';
      stripeEl.textContent = configured ? `Configured (${mode})` : 'Not configured';
      applyTone(stripeEl, configured ? 'text-success' : 'text-warning');
    } else {
      setStatus(stripeEl, 'OK', 'Unknown', false);
    }
  });
}());
