/**
 * SecureWave VPN - Payment Integration
 * Stripe Elements and PayPal SDK integration for subscription payments
 */

const API_BASE = '/api/billing';

// Initialize Stripe (load from CDN in HTML)
let stripe = null;
let stripeElements = null;
let paymentElement = null;

// Plan configuration
const PLANS = {
  basic: {
    name: 'Basic Plan',
    price_monthly: 9.99,
    price_yearly: 99.99,
    features: [
      '3 VPN connections',
      'Unlimited bandwidth',
      '30+ server locations',
      'Standard support'
    ]
  },
  premium: {
    name: 'Premium Plan',
    price_monthly: 14.99,
    price_yearly: 149.99,
    features: [
      '10 VPN connections',
      'Unlimited bandwidth',
      '50+ server locations',
      'AI-powered server selection',
      'Priority support',
      'Ad blocker included'
    ]
  },
  ultra: {
    name: 'Ultra Plan',
    price_monthly: 24.99,
    price_yearly: 249.99,
    features: [
      'Unlimited VPN connections',
      'Unlimited bandwidth',
      '50+ server locations',
      'AI-powered server selection',
      'Dedicated IP address',
      'Priority 24/7 support',
      'Ad blocker + malware protection',
      'Port forwarding'
    ]
  }
};

// Current selection
let selectedPlan = 'premium';
let selectedCycle = 'monthly';

/**
 * Initialize payment system
 */
async function initializePaymentSystem() {
  console.log('🔧 Initializing payment system...');

  // Initialize Stripe
  const stripePublicKey = await getStripePublicKey();
  if (stripePublicKey) {
    stripe = Stripe(stripePublicKey);
    console.log('✓ Stripe initialized');
  }

  // Initialize PayPal
  if (typeof paypal !== 'undefined') {
    console.log('✓ PayPal SDK loaded');
  }

  // Set up event listeners
  setupEventListeners();

  // Render initial pricing
  renderPricingPlans();
}

/**
 * Get Stripe publishable key from backend
 */
async function getStripePublicKey() {
  try {
    const response = await fetch('/api/config/stripe-key');
    if (!response.ok) {
      throw new Error('Failed to get Stripe key');
    }
    const data = await response.json();
    return data.publishable_key;
  } catch (error) {
    console.error('Failed to get Stripe key:', error);
    // Fallback to environment variable if available
    return window.STRIPE_PUBLISHABLE_KEY || null;
  }
}

/**
 * Set up event listeners
 */
function setupEventListeners() {
  // Plan selection
  document.querySelectorAll('[data-plan]').forEach(button => {
    button.addEventListener('click', (e) => {
      selectedPlan = e.target.dataset.plan;
      updatePlanSelection();
      renderPricingPlans();
    });
  });

  // Billing cycle toggle
  document.querySelectorAll('[data-cycle]').forEach(button => {
    button.addEventListener('click', (e) => {
      selectedCycle = e.target.dataset.cycle;
      updateCycleSelection();
      renderPricingPlans();
    });
  });

  // Payment buttons
  document.getElementById('payStripe')?.addEventListener('click', handleStripePayment);
  document.getElementById('payPaypal')?.addEventListener('click', handlePayPalPayment);
}

/**
 * Render pricing plans dynamically
 */
function renderPricingPlans() {
  Object.keys(PLANS).forEach(planId => {
    const plan = PLANS[planId];
    const priceKey = `price_${selectedCycle}`;
    const price = plan[priceKey];

    // Update price displays
    const priceElement = document.querySelector(`[data-price="${planId}"]`);
    if (priceElement) {
      priceElement.textContent = `$${price.toFixed(2)}`;
    }

    // Update cycle text
    const cycleElement = document.querySelector(`[data-cycle-text="${planId}"]`);
    if (cycleElement) {
      cycleElement.textContent = selectedCycle === 'monthly' ? 'per month' : 'per year';
    }

    // Show yearly savings
    if (selectedCycle === 'yearly') {
      const monthlyTotal = plan.price_monthly * 12;
      const savings = monthlyTotal - plan.price_yearly;
      const savingsElement = document.querySelector(`[data-savings="${planId}"]`);
      if (savingsElement) {
        savingsElement.textContent = `Save $${savings.toFixed(2)}/year`;
        savingsElement.style.display = 'block';
      }
    } else {
      const savingsElement = document.querySelector(`[data-savings="${planId}"]`);
      if (savingsElement) {
        savingsElement.style.display = 'none';
      }
    }
  });
}

/**
 * Update plan selection UI
 */
function updatePlanSelection() {
  document.querySelectorAll('[data-plan]').forEach(button => {
    if (button.dataset.plan === selectedPlan) {
      button.classList.add('active');
    } else {
      button.classList.remove('active');
    }
  });
}

/**
 * Update billing cycle selection UI
 */
function updateCycleSelection() {
  document.querySelectorAll('[data-cycle]').forEach(button => {
    if (button.dataset.cycle === selectedCycle) {
      button.classList.add('active');
    } else {
      button.classList.remove('active');
    }
  });
}

/**
 * Handle Stripe payment
 */
async function handleStripePayment() {
  console.log('💳 Initiating Stripe payment...');

  if (!stripe) {
    showError('Stripe is not initialized. Please refresh the page.');
    return;
  }

  // Check if user is logged in
  const token = localStorage.getItem('token');
  if (!token) {
    window.location.href = '/login.html?redirect=/subscription.html';
    return;
  }

  try {
    // Show loading state
    const button = document.getElementById('payStripe');
    const originalText = button.innerHTML;
    button.disabled = true;
    button.innerHTML = '<span class="spinner"></span> Processing...';

    // Create Stripe checkout session
    const response = await fetch('/api/billing/create-checkout-session', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        plan_id: selectedPlan,
        billing_cycle: selectedCycle,
        provider: 'stripe',
        success_url: `${window.location.origin}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${window.location.origin}/subscription.html`
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to create checkout session');
    }

    const data = await response.json();

    // Redirect to Stripe Checkout
    const result = await stripe.redirectToCheckout({
      sessionId: data.session_id
    });

    if (result.error) {
      throw new Error(result.error.message);
    }

  } catch (error) {
    console.error('Stripe payment error:', error);
    showError(error.message);

    // Restore button
    const button = document.getElementById('payStripe');
    button.disabled = false;
    button.innerHTML = originalText;
  }
}

/**
 * Handle PayPal payment
 */
async function handlePayPalPayment() {
  console.log('💙 Initiating PayPal payment...');

  // Check if user is logged in
  const token = localStorage.getItem('token');
  if (!token) {
    window.location.href = '/login.html?redirect=/subscription.html';
    return;
  }

  try {
    // Show loading state
    const button = document.getElementById('payPaypal');
    const originalText = button.innerHTML;
    button.disabled = true;
    button.innerHTML = '<span class="spinner"></span> Processing...';

    // Create PayPal subscription
    const response = await fetch(`${API_BASE}/subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        plan_id: selectedPlan,
        billing_cycle: selectedCycle,
        provider: 'paypal',
        return_url: `${window.location.origin}/billing/success`,
        cancel_url: `${window.location.origin}/subscription.html`
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to create PayPal subscription');
    }

    const data = await response.json();

    // Redirect to PayPal for approval
    if (data.approval_url) {
      window.location.href = data.approval_url;
    } else {
      throw new Error('No approval URL received from PayPal');
    }

  } catch (error) {
    console.error('PayPal payment error:', error);
    showError(error.message);

    // Restore button
    const button = document.getElementById('payPaypal');
    button.disabled = false;
    button.innerHTML = originalText;
  }
}

/**
 * Show error message
 */
function showError(message) {
  // Create error notification
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
  errorDiv.innerHTML = `
    <strong>Payment Error</strong>
    <p style="margin: 0.5rem 0 0 0;">${message}</p>
  `;

  document.body.appendChild(errorDiv);

  // Remove after 5 seconds
  setTimeout(() => {
    errorDiv.remove();
  }, 5000);
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
  successDiv.innerHTML = `
    <strong>Success!</strong>
    <p style="margin: 0.5rem 0 0 0;">${message}</p>
  `;

  document.body.appendChild(successDiv);

  setTimeout(() => {
    successDiv.remove();
  }, 5000);
}

// Initialize on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializePaymentSystem);
} else {
  initializePaymentSystem();
}

// Export functions for use in other scripts
window.PaymentSystem = {
  initialize: initializePaymentSystem,
  handleStripePayment,
  handlePayPalPayment,
  showError,
  showSuccess
};
