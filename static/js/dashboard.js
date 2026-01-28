function formatPlanLabel(status, subscription) {
  if (subscription?.is_active || status === 'active') return 'Premium';
  if (status === 'basic') return 'Starter (Free)';
  if (status === 'inactive') return 'Inactive';
  return 'Starter (Free)';
}

document.addEventListener('DOMContentLoaded', async () => {
  let sessionEmail = localStorage.getItem('user_email') || 'you@example.com';
  try {
    const sessionRes = await fetch('/api/auth/me', { credentials: 'include' });
    if (!sessionRes.ok) {
      window.location.href = '/login.html';
      return;
    }
    const sessionData = await sessionRes.json().catch(() => ({}));
    if (sessionData.email) {
      sessionEmail = sessionData.email;
    }
  } catch (error) {
    window.location.href = '/login.html';
    return;
  }

  const emailEl = document.querySelector('[data-user-email]');
  if (emailEl) {
    emailEl.textContent = sessionEmail;
  }

  const planEl = document.querySelector('[data-plan-label]');
  try {
    const res = await fetch('/api/dashboard/info', {
      credentials: 'include',
    });
    if (res.ok) {
      const data = await res.json().catch(() => ({}));
      if (planEl) {
        planEl.textContent = formatPlanLabel(data.subscription_status, data.subscription);
      }
    }
  } catch (error) {
    if (planEl) {
      planEl.textContent = formatPlanLabel('basic', null);
    }
  }
});
