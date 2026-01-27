function formatPlanLabel(status, subscription) {
  if (subscription?.is_active || status === 'active') return 'Premium';
  if (status === 'basic') return 'Starter (Free)';
  if (status === 'inactive') return 'Inactive';
  return 'Starter (Free)';
}

document.addEventListener('DOMContentLoaded', async () => {
  const token = localStorage.getItem('access_token');
  if (!token) {
    window.location.href = '/login.html';
    return;
  }

  const email = localStorage.getItem('user_email') || 'you@example.com';
  const emailEl = document.querySelector('[data-user-email]');
  if (emailEl) {
    emailEl.textContent = email;
  }

  const planEl = document.querySelector('[data-plan-label]');
  try {
    const res = await fetch('/api/dashboard/info', {
      headers: { Authorization: `Bearer ${token}` },
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
