(function () {
  function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return '';
  }

  function safeJson(res) {
    return res.json().catch(() => ({}));
  }

  async function fetchJson(url, opts = {}) {
    const res = await fetch(url, { credentials: 'include', ...opts });
    const data = await safeJson(res);
    return { ok: res.ok, status: res.status, data };
  }

  function setText(sel, text) {
    const el = document.querySelector(sel);
    if (el) el.textContent = text;
  }

  function showAlert(el, message, variant) {
    if (!el) return;
    el.style.display = 'flex';
    el.className = `alert alert-${variant || 'info'}`;
    el.textContent = message;
  }

  function hideAlert(el) {
    if (!el) return;
    el.style.display = 'none';
    el.textContent = '';
  }

  function formatMaybeDate(iso) {
    if (!iso) return '--';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '--';
    return date.toLocaleString();
  }

  function renderSubscription(subscription) {
    if (!subscription) {
      setText('[data-billing-plan]', 'Free');
      setText('[data-billing-status]', 'No active subscription');
      setText('[data-billing-next]', '--');
      setText('[data-billing-provider]', '--');
      setText('[data-subscription-summary]', 'Free tier (no billing)');
      setText('[data-subscription-cancel]', '--');
      return;
    }

    setText('[data-billing-plan]', subscription.plan_name || subscription.plan_id || '--');
    setText('[data-billing-status]', subscription.status || '--');
    setText('[data-billing-next]', formatMaybeDate(subscription.next_billing_date));
    setText('[data-billing-provider]', subscription.provider || '--');
    setText(
      '[data-subscription-summary]',
      `${subscription.plan_name || subscription.plan_id || 'Plan'} (${subscription.billing_cycle || 'monthly'})`,
    );
    setText('[data-subscription-cancel]', subscription.cancel_at_period_end ? 'Yes' : 'No');
  }

  function renderStripeStatus(statusData) {
    const configured = !!statusData?.configured;
    const mode = statusData?.mode || '--';
    const webhookConfigured = !!statusData?.webhook_configured;

    setText('[data-stripe-config]', configured ? `Configured (${mode})` : 'Not configured');
    setText('[data-stripe-webhook]', webhookConfigured ? 'Configured' : 'Not configured');
    setText('[data-stripe-mode]', configured ? `Mode: ${mode}` : 'Mode: --');
  }

  function renderPlanOptions(plans) {
    const select = document.querySelector('[data-plan-select]');
    if (!select) return;
    if (!Array.isArray(plans) || plans.length === 0) {
      select.innerHTML = '<option value="" selected disabled>No plans available</option>';
      return;
    }

    const paid = plans.filter(p => p && p.id && p.id !== 'free');
    select.innerHTML = paid
      .map(p => `<option value="${p.id}">${p.name || p.id}</option>`)
      .join('');
  }

  async function ensureAuth() {
    const me = await fetch('/api/auth/me', { credentials: 'include' });
    if (!me.ok) {
      window.location.href = '/login';
      return false;
    }
    return true;
  }

  async function loadAll() {
    const billingAlert = document.querySelector('[data-billing-alert]');
    hideAlert(billingAlert);

    const results = await Promise.allSettled([
      fetchJson('/api/billing/subscriptions/current'),
      fetchJson('/api/billing/plans'),
      fetchJson('/api/billing/stripe-status'),
    ]);

    const subResp = results[0].status === 'fulfilled' ? results[0].value : { ok: false, data: {} };
    const plansResp = results[1].status === 'fulfilled' ? results[1].value : { ok: false, data: {} };
    const stripeResp = results[2].status === 'fulfilled' ? results[2].value : { ok: false, data: {} };

    if (subResp.ok) {
      renderSubscription(subResp.data?.subscription || null);
    } else {
      renderSubscription(null);
      showAlert(billingAlert, 'Failed to load subscription status.', 'warning');
    }

    if (plansResp.ok) {
      renderPlanOptions(plansResp.data?.plans || []);
    }

    if (stripeResp.ok) {
      renderStripeStatus(stripeResp.data);
    }
  }

  async function openPortal() {
    const billingAlert = document.querySelector('[data-billing-alert]');
    hideAlert(billingAlert);

    const csrf = getCookie('csrf_token');
    const resp = await fetchJson('/api/payments/stripe/create-portal-session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body: JSON.stringify({ return_url: '/billing' }),
    });

    if (!resp.ok) {
      const msg = resp.data?.error?.message || 'Failed to create billing portal session.';
      showAlert(billingAlert, msg, 'danger');
      return;
    }

    const url = resp.data?.url;
    if (!url) {
      showAlert(billingAlert, 'Billing portal unavailable.', 'warning');
      return;
    }
    window.location.href = url;
  }

  async function startCheckout(planId, billingCycle) {
    const checkoutAlert = document.querySelector('[data-checkout-alert]');
    hideAlert(checkoutAlert);

    if (!planId) {
      showAlert(checkoutAlert, 'Select a plan to continue.', 'warning');
      return;
    }

    const csrf = getCookie('csrf_token');
    const resp = await fetchJson('/api/payments/stripe/create-checkout-session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
      body: JSON.stringify({ plan_id: planId, billing_cycle: billingCycle || 'monthly' }),
    });

    if (!resp.ok) {
      const msg = resp.data?.error?.message || 'Failed to create checkout session.';
      showAlert(checkoutAlert, msg, 'danger');
      return;
    }

    const checkoutUrl = resp.data?.checkout_url;
    if (!checkoutUrl) {
      showAlert(checkoutAlert, 'No checkout URL returned.', 'warning');
      return;
    }
    window.location.href = checkoutUrl;
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const ok = await ensureAuth();
    if (!ok) return;

    await loadAll();

    const portalBtn = document.querySelector('[data-open-portal]');
    if (portalBtn) {
      portalBtn.addEventListener('click', async () => {
        portalBtn.disabled = true;
        try {
          await openPortal();
        } finally {
          portalBtn.disabled = false;
        }
      });
    }

    const refreshBtn = document.querySelector('[data-refresh-billing]');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', async () => {
        refreshBtn.disabled = true;
        try {
          await loadAll();
        } finally {
          refreshBtn.disabled = false;
        }
      });
    }

    const form = document.querySelector('[data-checkout-form]');
    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const planSel = document.querySelector('[data-plan-select]');
        const cycleSel = document.querySelector('[data-cycle-select]');
        const planId = planSel ? planSel.value : '';
        const cycle = cycleSel ? cycleSel.value : 'monthly';

        const btn = document.querySelector('[data-start-checkout]');
        if (btn) btn.disabled = true;
        try {
          await startCheckout(planId, cycle);
        } finally {
          if (btn) btn.disabled = false;
        }
      });
    }
  });
}());

