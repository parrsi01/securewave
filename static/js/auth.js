// Authentication handlers with correct API routes
// CRITICAL FIX: Prevent premature validation errors

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('loginForm');
  const registerForm = document.getElementById('registerForm');

  if (loginForm) {
    loginForm.addEventListener('submit', handleLogin);
    // Disable aggressive blur validation - only validate on submit
    setupFormInputClearErrors(loginForm);
    clearFormErrors(loginForm);
    setFormMessage(loginForm, '', 'info', true);
  }

  if (registerForm) {
    registerForm.addEventListener('submit', handleRegister);
    setupFormInputClearErrors(registerForm);
    clearFormErrors(registerForm);
    setFormMessage(registerForm, '', 'info', true);
  }
});

// Clear error states when user types (but don't trigger new errors)
function setupFormInputClearErrors(form) {
  const inputs = form.querySelectorAll('input');
  inputs.forEach(input => {
    input.addEventListener('input', () => {
      input.classList.remove('is-invalid');
      const group = input.closest('.form-group');
      if (group) {
        group.classList.remove('error');
      }
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
  setFormMessage(e.target, '', 'info', true);

  if (!email || !password) {
    if (!email) {
      setFieldError('email', 'Enter a valid email address');
    }
    if (!password) {
      setFieldError('password', 'Enter your password to continue');
    }
    setFormMessage(e.target, 'Enter your email and password to sign in.', 'error');
    return;
  }

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
      const redirectTo = getRedirectTarget();
      if (redirectTo) {
        window.location.href = redirectTo;
        return;
      }
      window.location.href = '/dashboard.html';
    } else {
      const errorMessage = getErrorMessage(data);
      setFormMessage(e.target, errorMessage, 'error');
    }
  } catch (error) {
    console.error('Login error:', error);
    setFormMessage(e.target, 'Login failed. Please check your connection and try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Continue to SecureWave';
  }
}

async function handleRegister(e) {
  e.preventDefault();

  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const passwordConfirm = document.getElementById('passwordConfirm')?.value || '';
  const submitBtn = e.target.querySelector('button[type="submit"]');

  if (!email || !password || !passwordConfirm) {
    if (!email) {
      setFieldError('email', 'Enter a valid email address');
    }
    if (!password) {
      setFieldError('password', 'Create a password to continue');
    }
    if (!passwordConfirm) {
      setFieldError('passwordConfirm', 'Confirm your password');
    }
    setFormMessage(e.target, 'Complete all required fields to continue.', 'error');
    return;
  }

  // Validate password strength on submit only
  if (password.length < 8) {
    setFieldError('password', 'Use at least 8 characters');
    setFormMessage(e.target, 'Password must be at least 8 characters long.', 'error');
    return;
  }

  if (password !== passwordConfirm) {
    const confirmInput = document.getElementById('passwordConfirm');
    const confirmError = document.getElementById('passwordConfirm-error');
    if (confirmInput) {
      confirmInput.classList.add('is-invalid');
      confirmInput.closest('.form-group')?.classList.add('error');
    }
    if (confirmError) {
      confirmError.classList.remove('hidden');
    }
    setFormMessage(e.target, 'Passwords do not match.', 'error');
    return;
  }

  // Clear any previous errors
  clearFormErrors(e.target);
  setFormMessage(e.target, '', 'info', true);

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
        setFormMessage(e.target, 'Account created successfully! Redirecting...', 'success');
        setTimeout(() => window.location.href = '/dashboard.html', 400);
      } else {
        setFormMessage(e.target, 'Account created! Redirecting to login...', 'success');
        setTimeout(() => window.location.href = '/login.html?redirect=/dashboard.html', 600);
      }
    } else {
      const errorMessage = getErrorMessage(data);
      setFormMessage(e.target, errorMessage, 'error');
    }
  } catch (error) {
    console.error('Registration error:', error);
    setFormMessage(e.target, 'Registration failed. Please check your connection and try again.', 'error');
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
    const group = input.closest('.form-group');
    if (group) {
      group.classList.remove('error');
    }
  });

  const errorElements = form.querySelectorAll('.invalid-feedback, .form-error-message');
  errorElements.forEach(el => el.classList.add('hidden'));

  const alertElement = form.querySelector('.alert-danger, .alert-error');
  if (alertElement) {
    alertElement.classList.add('d-none', 'hidden');
  }
}

function setFieldError(fieldId, message) {
  const input = document.getElementById(fieldId);
  if (!input) return;
  const group = input.closest('.form-group');
  if (group) {
    group.classList.add('error');
  }
  const errorEl = document.getElementById(`${fieldId}-error`);
  if (errorEl) {
    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
  }
}

function getErrorMessage(data) {
  if (data && data.error && data.error.message) {
    return data.error.message;
  }
  // Handle different error response formats from FastAPI
  if (typeof data.detail === 'string') {
    if (data.detail.toLowerCase().includes('invalid credentials')) {
      return 'Email or password did not match. Try again.';
    }
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


function setFormMessage(form, message, type = 'info', hidden = false) {
  const container = form.closest('.auth-card') || form.parentElement;
  if (!container) return;
  const messageEl = container.querySelector('#authMessage');
  if (!messageEl) return;
  messageEl.classList.remove('success', 'error', 'info');
  messageEl.classList.add(type);
  messageEl.textContent = message;
  if (hidden || !message) {
    messageEl.classList.add('hidden');
  } else {
    messageEl.classList.remove('hidden');
  }
}
