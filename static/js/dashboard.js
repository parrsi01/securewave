function formatPlanLabel(status, subscription) {
  if (subscription?.is_active || status === 'active') return 'Premium';
  if (status === 'basic') return 'Starter (Free)';
  if (status === 'inactive') return 'Inactive';
  return 'Starter (Free)';
}

function setText(selector, value) {
  const element = document.querySelector(selector);
  if (element) element.textContent = value;
}

function formatDate(value) {
  if (!value) return 'Not recorded';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return 'Not recorded';
  return parsed.toLocaleString();
}

function setDashboardMessage(text) {
  const message = document.querySelector('[data-dashboard-message]');
  if (!message) return;
  message.textContent = text || '';
  message.classList.toggle('visible', Boolean(text));
}

document.addEventListener('DOMContentLoaded', async () => {
  let sessionEmail = localStorage.getItem('user_email') || 'you@example.com';
  let account = null;

  setText(
    '[data-account-environment]',
    window.location.hostname === 'staging-api.securewaveapp.com' ? 'Staging' : 'Production',
  );

  try {
    const sessionRes = await fetch('/api/auth/session', {
      credentials: 'include',
      cache: 'no-store',
    });
    const sessionData = await sessionRes.json().catch(() => ({}));
    if (!sessionRes.ok || !sessionData.authenticated) {
      window.location.href = '/login';
      return;
    }
    account = sessionData;
    if (sessionData.email) {
      sessionEmail = sessionData.email;
    }
  } catch (error) {
    setDashboardMessage('Account details are temporarily unavailable. Check your connection and reload this page.');
    return;
  }

  try {
    const detailsRes = await fetch('/api/auth/me', {
      credentials: 'include',
      cache: 'no-store',
    });
    if (detailsRes.ok) {
      account = {
        ...account,
        ...await detailsRes.json().catch(() => ({})),
      };
    }
  } catch {
    // The session response still contains enough safe account state to render.
  }

  setText('[data-user-email]', sessionEmail);
  setText('[data-account-email]', sessionEmail);
  setText('[data-account-status]', account?.is_active ? 'Active' : 'Inactive');
  setText('[data-email-verified]', account?.email_verified ? 'Verified' : 'Verification required');
  setText('[data-two-factor]', account?.has_2fa ? 'Enabled' : 'Not enabled');
  setText('[data-created-at]', formatDate(account?.created_at));
  setText('[data-last-login]', formatDate(account?.last_login));

  // Plan label
  const planEl = document.querySelector('[data-plan-label]');
  try {
    const res = await fetch('/api/dashboard/info', { credentials: 'include' });
    if (res.ok) {
      const data = await res.json().catch(() => ({}));
      if (planEl) {
        planEl.textContent = formatPlanLabel(data.subscription_status, data.subscription);
      }
      setDashboardMessage('');
    } else {
      setDashboardMessage('Your session is active, but some subscription details could not be loaded.');
    }
  } catch (error) {
    if (planEl) {
      planEl.textContent = formatPlanLabel(account?.subscription_status, null);
    }
    setDashboardMessage('Your session is active, but some account details could not be loaded.');
  }
});
