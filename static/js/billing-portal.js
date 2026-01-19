/**
 * SecureWave VPN - Billing Portal
 * Subscription management and invoice viewing
 */

const API_BASE = '/api/billing';
let currentSubscription = null;
let invoices = [];
let subscriptionHistory = [];

/**
 * Initialize billing portal
 */
async function initializeBillingPortal() {
  console.log('🔧 Initializing billing portal...');

  // Check authentication
  const token = localStorage.getItem('access_token');
  if (!token) {
    window.location.href = '/login.html?redirect=/billing-portal.html';
    return;
  }

  // Load billing data
  await loadBillingData();

  // Set up event listeners
  setupEventListeners();
}

/**
 * Load all billing data
 */
async function loadBillingData() {
  try {
    // Load in parallel
    await Promise.all([
      loadCurrentSubscription(),
      loadInvoices(),
      loadSubscriptionHistory()
    ]);

    // Hide loading state
    document.getElementById('loadingState').style.display = 'none';
    document.getElementById('billingContent').style.display = 'block';

    console.log('✓ Billing data loaded successfully');

  } catch (error) {
    console.error('Failed to load billing data:', error);
    showError('Failed to load billing information. Please refresh the page.');
  }
}

/**
 * Load current subscription
 */
async function loadCurrentSubscription() {
  try {
    const token = localStorage.getItem('access_token');
    const response = await fetch(`${API_BASE}/subscriptions/current`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to load subscription');
    }

    const data = await response.json();
    currentSubscription = data.subscription;

    if (currentSubscription) {
      displaySubscription(currentSubscription);
    } else {
      displayNoSubscription();
    }

  } catch (error) {
    console.error('Error loading subscription:', error);
    displayNoSubscription();
  }
}

/**
 * Load invoices
 */
async function loadInvoices() {
  try {
    const token = localStorage.getItem('access_token');
    const response = await fetch(`${API_BASE}/invoices`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to load invoices');
    }

    const data = await response.json();
    invoices = data.invoices || [];

    displayInvoices(invoices);

  } catch (error) {
    console.error('Error loading invoices:', error);
    invoices = [];
  }
}

/**
 * Load subscription history
 */
async function loadSubscriptionHistory() {
  try {
    const token = localStorage.getItem('access_token');
    const response = await fetch(`${API_BASE}/subscriptions/history`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to load subscription history');
    }

    const data = await response.json();
    subscriptionHistory = data.subscriptions || [];

    displaySubscriptionHistory(subscriptionHistory);

  } catch (error) {
    console.error('Error loading subscription history:', error);
    subscriptionHistory = [];
  }
}

/**
 * Display subscription information
 */
function displaySubscription(subscription) {
  document.getElementById('activeSubscription').style.display = 'block';
  document.getElementById('noSubscription').style.display = 'none';

  // Status
  const statusElement = document.getElementById('subscriptionStatus');
  statusElement.textContent = subscription.status.toUpperCase();
  statusElement.className = `subscription-status status-${subscription.status}`;

  // Plan name
  document.getElementById('planName').textContent = subscription.plan_name;

  // Price
  const cycle = subscription.billing_cycle === 'monthly' ? 'month' : 'year';
  document.getElementById('planPrice').textContent = `$${subscription.amount.toFixed(2)}/${cycle}`;

  // Next billing date
  if (subscription.next_billing_date) {
    const date = new Date(subscription.next_billing_date);
    document.getElementById('nextBillingDate').textContent = formatDate(date);
  } else {
    document.getElementById('nextBillingDate').textContent = 'N/A';
  }

  // Trial warning
  if (subscription.status === 'trialing' && subscription.trial_end) {
    document.getElementById('trialWarning').style.display = 'block';
    const trialEnd = new Date(subscription.trial_end);
    document.getElementById('trialEndDate').textContent = formatDate(trialEnd);
  } else {
    document.getElementById('trialWarning').style.display = 'none';
  }

  // Cancellation warning
  if (subscription.cancel_at_period_end) {
    document.getElementById('cancellationWarning').style.display = 'block';
    if (subscription.next_billing_date) {
      const date = new Date(subscription.next_billing_date);
      document.getElementById('cancellationDate').textContent = formatDate(date);
    }
  } else {
    document.getElementById('cancellationWarning').style.display = 'none';
  }
}

/**
 * Display no subscription state
 */
function displayNoSubscription() {
  document.getElementById('activeSubscription').style.display = 'none';
  document.getElementById('noSubscription').style.display = 'block';
}

/**
 * Display invoices
 */
function displayInvoices(invoices) {
  const tbody = document.getElementById('invoicesList');

  if (!invoices || invoices.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5" class="text-center text-muted" style="padding: 2rem;">
          No invoices found.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = invoices.map(invoice => `
    <tr>
      <td><strong>${invoice.invoice_number}</strong></td>
      <td>${formatDate(new Date(invoice.created_at))}</td>
      <td>$${invoice.amount_due.toFixed(2)} ${invoice.currency.toUpperCase()}</td>
      <td>
        <span class="badge ${getInvoiceStatusClass(invoice.status)}">
          ${invoice.status.toUpperCase()}
        </span>
      </td>
      <td>
        ${invoice.pdf_url ? `<a href="${invoice.pdf_url}" class="btn btn-sm btn-ghost" target="_blank">Download PDF</a>` : ''}
        ${invoice.hosted_invoice_url ? `<a href="${invoice.hosted_invoice_url}" class="btn btn-sm btn-ghost" target="_blank">View Invoice</a>` : ''}
      </td>
    </tr>
  `).join('');
}

/**
 * Display subscription history
 */
function displaySubscriptionHistory(history) {
  const container = document.getElementById('subscriptionHistory');

  if (!history || history.length === 0) {
    container.innerHTML = '<div class="empty-state"><p>No subscription history available.</p></div>';
    return;
  }

  container.innerHTML = `
    <table class="invoice-table">
      <thead>
        <tr>
          <th>Plan</th>
          <th>Provider</th>
          <th>Amount</th>
          <th>Status</th>
          <th>Created</th>
        </tr>
      </thead>
      <tbody>
        ${history.map(sub => `
          <tr>
            <td><strong>${sub.plan_name}</strong></td>
            <td>${sub.provider.charAt(0).toUpperCase() + sub.provider.slice(1)}</td>
            <td>$${sub.amount.toFixed(2)}/${sub.billing_cycle}</td>
            <td><span class="badge ${getStatusClass(sub.status)}">${sub.status.toUpperCase()}</span></td>
            <td>${formatDate(new Date(sub.created_at))}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
}

/**
 * Set up event listeners
 */
function setupEventListeners() {
  // Upgrade plan
  document.getElementById('upgradePlanBtn')?.addEventListener('click', showUpgradeModal);

  // Update payment method (redirect to Stripe portal)
  document.getElementById('updatePaymentBtn')?.addEventListener('click', openStripePortal);

  // Cancel subscription
  document.getElementById('cancelSubscriptionBtn')?.addEventListener('click', showCancelModal);

  // Reactivate subscription
  document.getElementById('reactivateBtn')?.addEventListener('click', reactivateSubscription);

  // Cancel modal
  document.getElementById('cancelModalCancelBtn')?.addEventListener('click', hideCancelModal);
  document.getElementById('confirmCancelBtn')?.addEventListener('click', confirmCancellation);

  // Upgrade modal
  document.getElementById('upgradeModalCancelBtn')?.addEventListener('click', hideUpgradeModal);
  document.getElementById('confirmUpgradeBtn')?.addEventListener('click', confirmUpgrade);
}

/**
 * Open Stripe billing portal
 */
async function openStripePortal() {
  try {
    const token = localStorage.getItem('access_token');
    const response = await fetch(`${API_BASE}/portal?return_url=${encodeURIComponent(window.location.href)}`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw new Error('Failed to create portal session');
    }

    const data = await response.json();
    if (data.demo) {
      showError(data.message || 'Billing portal is temporarily unavailable.');
      return;
    }

    if (!data.url) {
      throw new Error('No billing portal URL returned');
    }

    window.location.href = data.url;

  } catch (error) {
    console.error('Error opening Stripe portal:', error);
    showError('Failed to open billing portal. Please try again.');
  }
}

/**
 * Show cancel modal
 */
function showCancelModal() {
  document.getElementById('cancelModal').classList.add('active');
}

/**
 * Hide cancel modal
 */
function hideCancelModal() {
  document.getElementById('cancelModal').classList.remove('active');
  document.getElementById('cancellationReason').value = '';
}

/**
 * Confirm cancellation
 */
async function confirmCancellation() {
  if (!currentSubscription) return;

  try {
    const reason = document.getElementById('cancellationReason').value;
    const token = localStorage.getItem('access_token');

    const response = await fetch(`${API_BASE}/subscriptions/${currentSubscription.id}/cancel`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        cancel_at_period_end: true,
        reason: reason || null
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to cancel subscription');
    }

    showSuccess('Subscription will be canceled at the end of your billing period.');
    hideCancelModal();

    // Reload subscription data
    await loadCurrentSubscription();

  } catch (error) {
    console.error('Error canceling subscription:', error);
    showError(error.message);
  }
}

/**
 * Reactivate subscription
 */
async function reactivateSubscription() {
  if (!currentSubscription) return;

  try {
    const token = localStorage.getItem('access_token');

    const response = await fetch(`${API_BASE}/subscriptions/${currentSubscription.id}/reactivate`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to reactivate subscription');
    }

    showSuccess('Subscription reactivated successfully!');

    // Reload subscription data
    await loadCurrentSubscription();

  } catch (error) {
    console.error('Error reactivating subscription:', error);
    showError(error.message);
  }
}

/**
 * Show upgrade modal
 */
function showUpgradeModal() {
  // Populate plan options
  const planOptions = document.getElementById('planOptions');
  planOptions.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 1rem;">
      <label>
        <input type="radio" name="plan" value="basic" ${currentSubscription?.plan_id === 'basic' ? 'checked' : ''}>
        Basic Plan - $9.99/month
      </label>
      <label>
        <input type="radio" name="plan" value="premium" ${currentSubscription?.plan_id === 'premium' ? 'checked' : ''}>
        Premium Plan - $14.99/month
      </label>
      <label>
        <input type="radio" name="plan" value="ultra" ${currentSubscription?.plan_id === 'ultra' ? 'checked' : ''}>
        Ultra Plan - $24.99/month
      </label>
    </div>
  `;

  document.getElementById('upgradeModal').classList.add('active');
}

/**
 * Hide upgrade modal
 */
function hideUpgradeModal() {
  document.getElementById('upgradeModal').classList.remove('active');
}

/**
 * Confirm upgrade
 */
async function confirmUpgrade() {
  if (!currentSubscription) return;

  try {
    const selectedPlan = document.querySelector('input[name="plan"]:checked')?.value;
    if (!selectedPlan) {
      showError('Please select a plan');
      return;
    }

    if (selectedPlan === currentSubscription.plan_id) {
      showError('You are already on this plan');
      return;
    }

    const token = localStorage.getItem('access_token');

    const response = await fetch(`${API_BASE}/subscriptions/${currentSubscription.id}/upgrade`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        new_plan_id: selectedPlan
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to upgrade subscription');
    }

    showSuccess('Subscription upgraded successfully!');
    hideUpgradeModal();

    // Reload subscription data
    await loadCurrentSubscription();

  } catch (error) {
    console.error('Error upgrading subscription:', error);
    showError(error.message);
  }
}

/**
 * Get invoice status class
 */
function getInvoiceStatusClass(status) {
  const classes = {
    'paid': 'badge-success',
    'open': 'badge-warning',
    'void': 'badge-secondary',
    'uncollectible': 'badge-danger'
  };
  return classes[status] || 'badge-secondary';
}

/**
 * Get subscription status class
 */
function getStatusClass(status) {
  const classes = {
    'active': 'badge-success',
    'trialing': 'badge-info',
    'past_due': 'badge-warning',
    'canceled': 'badge-danger',
    'incomplete': 'badge-secondary'
  };
  return classes[status] || 'badge-secondary';
}

/**
 * Format date
 */
function formatDate(date) {
  const options = { year: 'numeric', month: 'short', day: 'numeric' };
  return date.toLocaleDateString('en-US', options);
}

/**
 * Show error message
 */
function showError(message) {
  const errorDiv = document.createElement('div');
  errorDiv.className = 'alert alert-error';
  errorDiv.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    z-index: 9999;
    max-width: 400px;
    padding: 1rem;
    background: #dc2626;
    color: white;
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  `;
  errorDiv.innerHTML = `<strong>Error</strong><p style="margin: 0.5rem 0 0 0;">${message}</p>`;
  document.body.appendChild(errorDiv);

  setTimeout(() => errorDiv.remove(), 5000);
}

/**
 * Show success message
 */
function showSuccess(message) {
  const successDiv = document.createElement('div');
  successDiv.className = 'alert alert-success';
  successDiv.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    z-index: 9999;
    max-width: 400px;
    padding: 1rem;
    background: #10b981;
    color: white;
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  `;
  successDiv.innerHTML = `<strong>Success!</strong><p style="margin: 0.5rem 0 0 0;">${message}</p>`;
  document.body.appendChild(successDiv);

  setTimeout(() => successDiv.remove(), 5000);
}

// Initialize on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeBillingPortal);
} else {
  initializeBillingPortal();
}
