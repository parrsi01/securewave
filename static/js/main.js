// SecureWave VPN - Enhanced Main JavaScript
// Version: 2.0.0 - Modern 2026 Edition

const API_BASE = '/api';

// Configuration
const CONFIG = {
  tokenRefreshInterval: 15 * 60 * 1000, // 15 minutes
  apiTimeout: 30000, // 30 seconds
  retryAttempts: 3,
  retryDelay: 1000
};

// Utility: Show loading spinner
function showLoading(show = true) {
  let spinner = document.getElementById('globalSpinner');

  if (!spinner) {
    spinner = document.createElement('div');
    spinner.id = 'globalSpinner';
    spinner.innerHTML = `
      <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 9999; display: flex; align-items: center; justify-content: center;">
        <div style="background: white; padding: 2rem; border-radius: 1rem; box-shadow: 0 20px 60px rgba(0,0,0,0.3);">
          <div class="spinner-border text-primary" role="status" style="width: 3rem; height: 3rem;">
            <span class="visually-hidden">Loading...</span>
          </div>
          <div class="mt-3 fw-semibold text-center">Loading...</div>
        </div>
      </div>
    `;
    document.body.appendChild(spinner);
  }

  spinner.style.display = show ? 'block' : 'none';
}

// Utility: Show toast notification
function showToast(message, type = 'info', duration = 5000) {
  const toastContainer = getOrCreateToastContainer();

  const toast = document.createElement('div');
  toast.className = `toast align-items-center text-white bg-${type} border-0 show`;
  toast.setAttribute('role', 'alert');
  toast.setAttribute('aria-live', 'assertive');
  toast.setAttribute('aria-atomic', 'true');

  const iconMap = {
    success: 'check-circle-fill',
    danger: 'exclamation-triangle-fill',
    warning: 'exclamation-circle-fill',
    info: 'info-circle-fill'
  };

  toast.innerHTML = `
    <div class="d-flex">
      <div class="toast-body">
        <i class="bi bi-${iconMap[type] || iconMap.info} me-2"></i>
        ${message}
      </div>
      <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="Close"></button>
    </div>
  `;

  toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

function getOrCreateToastContainer() {
  let container = document.getElementById('toastContainer');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toastContainer';
    container.className = 'toast-container position-fixed top-0 end-0 p-3';
    container.style.zIndex = '9999';
    document.body.appendChild(container);
  }
  return container;
}

// Enhanced API call with retry logic
async function apiCall(endpoint, options = {}, retryCount = 0) {
  const token = localStorage.getItem('access_token');
  const headers = {
    'Content-Type': 'application/json',
    ...(token && { 'Authorization': `Bearer ${token}` }),
    ...options.headers
  };

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), CONFIG.apiTimeout);

    const response = await fetch(`${API_BASE}${endpoint}`, {
      ...options,
      headers,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    // Handle unauthorized
    if (response.status === 401) {
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      if (!window.location.pathname.includes('login')) {
        window.location.href = '/login.html';
      }
      return null;
    }

    // Handle server errors with retry
    if (response.status >= 500 && retryCount < CONFIG.retryAttempts) {
      await new Promise(resolve => setTimeout(resolve, CONFIG.retryDelay * (retryCount + 1)));
      return apiCall(endpoint, options, retryCount + 1);
    }

    return response;
  } catch (error) {
    if (error.name === 'AbortError') {
      console.error('Request timeout:', endpoint);
      showToast('Request timed out. Please try again.', 'warning');
    } else if (retryCount < CONFIG.retryAttempts) {
      await new Promise(resolve => setTimeout(resolve, CONFIG.retryDelay * (retryCount + 1)));
      return apiCall(endpoint, options, retryCount + 1);
    } else {
      console.error('API Error:', error);
      showToast('Network error. Please check your connection.', 'danger');
    }
    return null;
  }
}

// Check authentication state
async function checkAuthState() {
  const token = localStorage.getItem('access_token');
  const loginBtn = document.getElementById('loginBtn');
  const registerBtn = document.getElementById('registerBtn');
  const logoutBtn = document.getElementById('logoutBtn');
  const dashLink = document.getElementById('dashLink');
  const settingsLink = document.getElementById('settingsLink');

  if (token) {
    const profileResponse = await apiCall('/auth/me', { method: 'GET' });
    if (!profileResponse || !profileResponse.ok) {
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      if (loginBtn) loginBtn.classList.remove('d-none');
      if (registerBtn) registerBtn.classList.remove('d-none');
      if (logoutBtn) logoutBtn.classList.add('d-none');
      if (dashLink) dashLink.classList.add('d-none');
      if (settingsLink) settingsLink.classList.add('d-none');
      return;
    }
    // User is logged in
    if (loginBtn) loginBtn.classList.add('d-none');
    if (registerBtn) registerBtn.classList.add('d-none');
    if (logoutBtn) {
      logoutBtn.classList.remove('d-none');
      const logoutButton = logoutBtn.querySelector('button');
      if (logoutButton) {
        logoutButton.addEventListener('click', logout);
      }
    }
    if (dashLink) dashLink.classList.remove('d-none');
    if (settingsLink) settingsLink.classList.remove('d-none');

    // Start token refresh interval
    startTokenRefresh();
  } else {
    // User is not logged in
    if (loginBtn) loginBtn.classList.remove('d-none');
    if (registerBtn) registerBtn.classList.remove('d-none');
    if (logoutBtn) logoutBtn.classList.add('d-none');
    if (dashLink) dashLink.classList.add('d-none');
    if (settingsLink) settingsLink.classList.add('d-none');
  }
}

// Logout function
async function logout() {
  try {
    await apiCall('/auth/logout', { method: 'POST' });
  } catch (error) {
    console.error('Logout error:', error);
  } finally {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    showToast('Logged out successfully', 'success');
    setTimeout(() => {
      window.location.href = '/home.html';
    }, 1000);
  }
}

// Token refresh
let tokenRefreshTimer = null;

function startTokenRefresh() {
  if (tokenRefreshTimer) clearInterval(tokenRefreshTimer);

  tokenRefreshTimer = setInterval(async () => {
    const refreshToken = localStorage.getItem('refresh_token');
    if (!refreshToken) return;

    try {
      const response = await apiCall('/auth/refresh', {
        method: 'POST',
        body: JSON.stringify({ refresh_token: refreshToken })
      });

      if (response && response.ok) {
        const data = await response.json();
        localStorage.setItem('access_token', data.access_token);
        if (data.refresh_token) {
          localStorage.setItem('refresh_token', data.refresh_token);
        }
      }
    } catch (error) {
      console.error('Token refresh failed:', error);
    }
  }, CONFIG.tokenRefreshInterval);
}

// Form validation helper
function validateForm(formId, validationRules) {
  const form = document.getElementById(formId);
  if (!form) return false;

  let isValid = true;

  for (const [fieldName, rules] of Object.entries(validationRules)) {
    const field = form.querySelector(`[name="${fieldName}"]`);
    if (!field) continue;

    const value = field.value.trim();
    let errorMessage = '';

    // Required validation
    if (rules.required && !value) {
      errorMessage = rules.requiredMessage || `${fieldName} is required`;
      isValid = false;
    }

    // Email validation
    if (rules.email && value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      errorMessage = 'Please enter a valid email address';
      isValid = false;
    }

    // Min length validation
    if (rules.minLength && value && value.length < rules.minLength) {
      errorMessage = `Must be at least ${rules.minLength} characters`;
      isValid = false;
    }

    // Custom validation
    if (rules.custom && !rules.custom(value)) {
      errorMessage = rules.customMessage || 'Invalid input';
      isValid = false;
    }

    // Show/hide error
    const errorElement = field.parentElement.querySelector('.invalid-feedback') ||
                        field.parentElement.querySelector('.error-message');

    if (errorMessage) {
      field.classList.add('is-invalid');
      if (errorElement) errorElement.textContent = errorMessage;
    } else {
      field.classList.remove('is-invalid');
      if (errorElement) errorElement.textContent = '';
    }
  }

  return isValid;
}

// Smooth scroll to element
function smoothScrollTo(elementId) {
  const element = document.getElementById(elementId);
  if (element) {
    element.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}

// Copy to clipboard with feedback
async function copyToClipboard(text, successMessage = 'Copied to clipboard!') {
  try {
    await navigator.clipboard.writeText(text);
    showToast(successMessage, 'success', 2000);
    return true;
  } catch (error) {
    console.error('Copy failed:', error);
    showToast('Failed to copy to clipboard', 'danger');
    return false;
  }
}

// Format date
function formatDate(dateString, options = {}) {
  const date = new Date(dateString);
  const defaultOptions = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    ...options
  };
  return date.toLocaleDateString('en-US', defaultOptions);
}

// Format currency
function formatCurrency(amount, currency = 'USD') {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency
  }).format(amount);
}

// Debounce function
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Initialize on DOM load
document.addEventListener('DOMContentLoaded', async () => {
  const protectedRoutes = ['/dashboard.html', '/dashboard', '/vpn.html', '/vpn', '/settings.html', '/settings', '/subscription.html', '/subscription', '/diagnostics.html', '/diagnostics'];
  const path = window.location.pathname;
  const token = localStorage.getItem('access_token');
  if (protectedRoutes.includes(path) && !token) {
    window.location.href = '/login.html?redirect=' + encodeURIComponent(path);
    return;
  }
  // Check authentication state
  await checkAuthState();

  // Mobile menu toggle (if exists)
  const navToggle = document.querySelector('.navbar-toggler');
  if (navToggle) {
    navToggle.addEventListener('click', () => {
      const navMenu = document.querySelector('.navbar-collapse');
      if (navMenu) {
        navMenu.classList.toggle('show');
      }
    });
  }

  // Add smooth scroll to all anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      const href = this.getAttribute('href');
      if (href !== '#' && href.length > 1) {
        e.preventDefault();
        smoothScrollTo(href.substring(1));
      }
    });
  });

  // Add loading animation to forms
  document.querySelectorAll('form').forEach(form => {
    form.addEventListener('submit', (e) => {
      const submitBtn = form.querySelector('[type="submit"]');
      if (submitBtn && !submitBtn.disabled) {
        submitBtn.disabled = true;
        const originalText = submitBtn.textContent;
        submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Processing...';

        // Re-enable after 10 seconds as fallback
        setTimeout(() => {
          submitBtn.disabled = false;
          submitBtn.textContent = originalText;
        }, 10000);
      }
    });
  });

  // Performance: Lazy load images
  if ('IntersectionObserver' in window) {
    const imageObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const img = entry.target;
          if (img.dataset.src) {
            img.src = img.dataset.src;
            img.removeAttribute('data-src');
          }
          observer.unobserve(img);
        }
      });
    });

    document.querySelectorAll('img[data-src]').forEach(img => {
      imageObserver.observe(img);
    });
  }

  // Console welcome message
  console.log('%c🔐 SecureWave VPN', 'font-size: 20px; font-weight: bold; color: #667eea;');
  console.log('%cVersion 2.0.0 - Modern 2026 Edition', 'font-size: 12px; color: #64748b;');
  console.log('%c⚡ Powered by FastAPI, WireGuard, and Bootstrap 5.3', 'font-size: 10px; color: #94a3b8;');
});

// Handle page visibility changes
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && localStorage.getItem('access_token')) {
    // Page became visible, refresh token if needed
    const refreshToken = localStorage.getItem('refresh_token');
    if (refreshToken) {
      apiCall('/auth/refresh', {
        method: 'POST',
        body: JSON.stringify({ refresh_token: refreshToken })
      }).then(async response => {
        if (response && response.ok) {
          const data = await response.json();
          localStorage.setItem('access_token', data.access_token);
          if (data.refresh_token) {
            localStorage.setItem('refresh_token', data.refresh_token);
          }
        }
      }).catch(error => {
        console.error('Token refresh on visibility change failed:', error);
      });
    }
  }
});

// Export functions for use in other scripts
window.SecureWave = {
  apiCall,
  showToast,
  showLoading,
  checkAuthState,
  logout,
  validateForm,
  copyToClipboard,
  formatDate,
  formatCurrency,
  debounce,
  smoothScrollTo
};
