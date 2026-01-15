// SecureWave Subscription Page Logic

const BILLING_API_BASE = '/api/billing';
const DEFAULT_PLAN_ID = 'premium';
const DEFAULT_BILLING_CYCLE = 'monthly';

function setPlanCard({ name, statusText, actions }) {
  const planNameEl = document.getElementById('currentPlanName');
  const planStatusEl = document.getElementById('currentPlanStatus');
  const planActionsEl = document.getElementById('currentPlanActions');

  if (planNameEl) {
    planNameEl.textContent = name;
  }
  if (planStatusEl) {
    planStatusEl.textContent = statusText;
  }
  if (planActionsEl) {
    planActionsEl.innerHTML = '';
    if (actions) {
      planActionsEl.appendChild(actions);
    }
  }
}

function showSubscriptionToast(message, type = 'info') {
  if (typeof showToast === 'function') {
    showToast(message, type);
  }
}

function buildActionButton(label, href, variant = 'primary') {
  const button = document.createElement('a');
  button.className = `btn btn-${variant} btn-sm`;
  button.href = href;
  button.textContent = label;
  return button;
}

function updatePlanCardForGuest() {
  const action = buildActionButton('Log In', '/login.html?redirect=/subscription.html', 'primary');
  setPlanCard({
    name: 'Sign in to view your plan',
    statusText: 'Log in to manage your subscription and billing status.',
    actions: action
  });
}

async function loadCurrentSubscription(token) {
  try {
    const response = await fetch(`${BILLING_API_BASE}/subscriptions/current`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      setPlanCard({
        name: 'Subscription unavailable',
        statusText: 'We could not load your billing status right now.',
        actions: buildActionButton('Retry', '/subscription.html', 'outline')
      });
      return;
    }

    const data = await response.json();
    if (!data.subscription) {
      setPlanCard({
        name: 'Free Plan',
        statusText: 'Status: inactive',
        actions: buildActionButton('Upgrade Plan', '#pricing', 'primary')
      });
      return;
    }

    const planName = data.subscription.plan_name || 'Premium Plan';
    const status = data.subscription.status || 'active';
    const statusText = `Status: ${status}`;
    const action = buildActionButton('Manage Settings', '/settings.html', 'outline');

    setPlanCard({
      name: planName,
      statusText,
      actions: action
    });
  } catch (error) {
    setPlanCard({
      name: 'Subscription unavailable',
      statusText: 'We could not load your billing status right now.',
      actions: buildActionButton('Retry', '/subscription.html', 'outline')
    });
  }
}

function setButtonLoading(button, loadingText) {
  if (!button) return null;
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = loadingText;
  return originalText;
}

function resetButton(button, originalText) {
  if (!button) return;
  button.disabled = false;
  button.textContent = originalText;
}

async function startSubscription(provider, button) {
  const token = localStorage.getItem('access_token');
  if (!token) {
    window.location.href = '/login.html?redirect=/subscription.html';
    return;
  }

  const originalText = setButtonLoading(button, 'Processing...');

  try {
    const response = await fetch(`${BILLING_API_BASE}/subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        plan_id: DEFAULT_PLAN_ID,
        billing_cycle: DEFAULT_BILLING_CYCLE,
        provider
      })
    });

    const data = await response.json();
    if (!response.ok) {
      showSubscriptionToast(data.detail || 'Unable to start subscription', 'warning');
      return;
    }

    showSubscriptionToast(data.message || 'Subscription updated', 'success');
    await loadCurrentSubscription(token);
  } catch (error) {
    showSubscriptionToast('Unable to start subscription', 'warning');
  } finally {
    resetButton(button, originalText);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const token = localStorage.getItem('access_token');
  const payStripeBtn = document.getElementById('payStripe');
  const payPaypalBtn = document.getElementById('payPaypal');

  if (!token) {
    updatePlanCardForGuest();
  } else {
    loadCurrentSubscription(token);
  }

  if (payStripeBtn) {
    payStripeBtn.addEventListener('click', () => startSubscription('stripe', payStripeBtn));
  }

  if (payPaypalBtn) {
    payPaypalBtn.addEventListener('click', () => startSubscription('paypal', payPaypalBtn));
  }
});
