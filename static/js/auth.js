// Authentication handlers with correct API routes
// CRITICAL FIX: Prevent premature validation errors

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('loginForm');
  const registerForm = document.getElementById('registerForm');

  if (loginForm) {
    loginForm.addEventListener('submit', handleLogin);
    // Disable aggressive blur validation - only validate on submit
    setupFormInputClearErrors(loginForm);
  }

  if (registerForm) {
    registerForm.addEventListener('submit', handleRegister);
    setupFormInputClearErrors(registerForm);
  }
});

// Clear error states when user types (but don't trigger new errors)
function setupFormInputClearErrors(form) {
  const inputs = form.querySelectorAll('input');
  inputs.forEach(input => {
    input.addEventListener('input', () => {
      input.classList.remove('is-invalid');
      const errorEl = document.getElementById(`${input.id}-error`);
      if (errorEl) {
        errorEl.classList.add('hidden');
      }
      // Clear Bootstrap validation
      input.setCustomValidity('');
    });
  });
}

async function handleLogin(e) {
  e.preventDefault();

  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const submitBtn = e.target.querySelector('button[type="submit"]');

  // Clear any previous errors
  clearFormErrors(e.target);

  submitBtn.disabled = true;
  submitBtn.textContent = 'Logging in...';

  try {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    const data = await response.json();

    if (response.ok && data.access_token) {
      localStorage.setItem('access_token', data.access_token);
      if (data.refresh_token) {
        localStorage.setItem('refresh_token', data.refresh_token);
      }
      const redirectTo = getRedirectTarget() || '/dashboard.html';
      window.location.href = redirectTo;
    } else {
      const errorMessage = getErrorMessage(data);
      showAlert(errorMessage, 'error');
    }
  } catch (error) {
    console.error('Login error:', error);
    showAlert('Login failed. Please check your connection and try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Login to Dashboard';
  }
}

async function handleRegister(e) {
  e.preventDefault();

  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const passwordConfirm = document.getElementById('passwordConfirm')?.value || '';
  const submitBtn = e.target.querySelector('button[type="submit"]');

  // Validate password strength on submit only
  if (password.length < 8) {
    showAlert('Password must be at least 8 characters long', 'error');
    return;
  }

  if (password !== passwordConfirm) {
    const confirmInput = document.getElementById('passwordConfirm');
    const confirmError = document.getElementById('passwordConfirm-error');
    if (confirmInput) {
      confirmInput.classList.add('is-invalid');
    }
    if (confirmError) {
      confirmError.classList.remove('hidden');
    }
    showAlert('Passwords do not match', 'error');
    return;
  }

  // Clear any previous errors
  clearFormErrors(e.target);

  submitBtn.disabled = true;
  submitBtn.textContent = 'Creating account...';

  try {
    const response = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, password_confirm: passwordConfirm })
    });

    const data = await response.json();

    if (response.ok) {
      if (data.access_token) {
        localStorage.setItem('access_token', data.access_token);
        if (data.refresh_token) {
          localStorage.setItem('refresh_token', data.refresh_token);
        }
        showAlert('Account created successfully!', 'success');
        const redirectTo = getRedirectTarget() || '/dashboard.html';
        setTimeout(() => window.location.href = redirectTo, 800);
      } else {
        showAlert('Account created! Redirecting to login...', 'success');
        setTimeout(() => window.location.href = '/login.html', 1200);
      }
    } else {
      const errorMessage = getErrorMessage(data);
      showAlert(errorMessage, 'error');
    }
  } catch (error) {
    console.error('Registration error:', error);
    showAlert('Registration failed. Please check your connection and try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Create Account';
  }
}

function clearFormErrors(form) {
  const inputs = form.querySelectorAll('input');
  inputs.forEach(input => {
    input.classList.remove('is-invalid');
    input.setCustomValidity('');
  });

  const errorElements = form.querySelectorAll('.invalid-feedback, .form-error-message');
  errorElements.forEach(el => el.classList.add('hidden'));

  const alertElement = form.querySelector('.alert-danger, .alert-error');
  if (alertElement) {
    alertElement.classList.add('d-none', 'hidden');
  }
}

function getErrorMessage(data) {
  if (data && data.error && data.error.message) {
    return data.error.message;
  }
  // Handle different error response formats from FastAPI
  if (typeof data.detail === 'string') {
    return data.detail;
  }

  // Handle validation errors (array of error objects)
  if (Array.isArray(data.detail)) {
    return data.detail.map(err => err.msg || JSON.stringify(err)).join(', ');
  }

  // Handle object error details
  if (typeof data.detail === 'object') {
    if (data.detail.msg) {
      return data.detail.msg;
    }
    return JSON.stringify(data.detail);
  }

  // Fallback error messages
  if (data.message) {
    return data.message;
  }

  return 'An error occurred. Please try again.';
}

function getRedirectTarget() {
  const params = new URLSearchParams(window.location.search);
  const redirect = params.get('redirect');
  if (!redirect) return null;
  if (redirect.startsWith('/')) {
    return redirect;
  }
  return null;
}

function showAlert(message, type = 'info') {
  // Remove existing alerts
  const existingAlerts = document.querySelectorAll('.alert');
  existingAlerts.forEach(alert => {
    if (!alert.id || alert.id.includes('Alert')) {
      alert.remove();
    }
  });

  const alert = document.createElement('div');
  alert.className = `alert alert-${type === 'error' ? 'danger' : type}`;
  alert.style.cssText = 'margin-top: 1rem; animation: slideDown 0.3s ease;';
  alert.textContent = message;

  const container = document.querySelector('.auth-card') ||
                    document.querySelector('.container-sm') ||
                    document.querySelector('.container');

  if (container) {
    const form = container.querySelector('form');
    if (form) {
      form.insertAdjacentElement('afterend', alert);
    } else {
      container.insertBefore(alert, container.firstChild);
    }

    setTimeout(() => alert.remove(), 5000);
  }
}
