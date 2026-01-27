function setMessage(form, message, type) {
  const box = form.querySelector('[data-form-message]');
  if (!box) return;
  if (!message) {
    box.classList.remove('visible');
    return;
  }
  box.textContent = message;
  box.classList.add('visible');
  box.dataset.type = type || 'info';
}

function setFieldError(form, fieldId, message) {
  const input = form.querySelector(`#${fieldId}`);
  const error = form.querySelector(`#${fieldId}-error`);
  if (input) {
    input.setAttribute('aria-invalid', 'true');
  }
  if (error) {
    error.textContent = message;
    error.classList.add('visible');
  }
}

function clearErrors(form) {
  form.querySelectorAll('.form-error').forEach((el) => el.classList.remove('visible'));
  form.querySelectorAll('input').forEach((input) => input.removeAttribute('aria-invalid'));
}

async function handleLogin(event) {
  event.preventDefault();
  const form = event.currentTarget;
  clearErrors(form);
  setMessage(form, '', 'info');

  const email = form.querySelector('#email')?.value.trim();
  const password = form.querySelector('#password')?.value || '';

  if (!email) {
    setFieldError(form, 'email', 'Enter your email.');
  }
  if (!password) {
    setFieldError(form, 'password', 'Enter your password.');
  }
  if (!email || !password) {
    setMessage(form, 'Please complete the fields to continue.', 'error');
    return;
  }

  const button = form.querySelector('button[type="submit"]');
  if (button) {
    button.disabled = true;
    button.textContent = 'Signing in...';
  }

  try {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    const data = await response.json();
    if (response.ok && data.access_token) {
      localStorage.setItem('access_token', data.access_token);
      localStorage.setItem('user_email', email);
      window.location.href = '/dashboard.html';
      return;
    }
    setMessage(form, data.detail || 'Login failed. Please try again.', 'error');
  } catch (error) {
    setMessage(form, 'Network error. Please try again.', 'error');
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = 'Sign in';
    }
  }
}

async function handleRegister(event) {
  event.preventDefault();
  const form = event.currentTarget;
  clearErrors(form);
  setMessage(form, '', 'info');

  const email = form.querySelector('#email')?.value.trim();
  const password = form.querySelector('#password')?.value || '';
  const confirm = form.querySelector('#passwordConfirm')?.value || '';

  if (!email) {
    setFieldError(form, 'email', 'Enter your email.');
  }
  if (!password) {
    setFieldError(form, 'password', 'Create a password.');
  }
  if (!confirm) {
    setFieldError(form, 'passwordConfirm', 'Confirm your password.');
  }
  if (!email || !password || !confirm) {
    setMessage(form, 'Please complete the fields to continue.', 'error');
    return;
  }
  if (password.length < 8) {
    setFieldError(form, 'password', 'Use at least 8 characters.');
    setMessage(form, 'Password must be at least 8 characters.', 'error');
    return;
  }
  if (password !== confirm) {
    setFieldError(form, 'passwordConfirm', 'Passwords do not match.');
    setMessage(form, 'Passwords do not match.', 'error');
    return;
  }

  const button = form.querySelector('button[type="submit"]');
  if (button) {
    button.disabled = true;
    button.textContent = 'Creating account...';
  }

  try {
    const response = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, password_confirm: confirm })
    });
    const data = await response.json();
    if (response.ok) {
      if (data.access_token) {
        localStorage.setItem('access_token', data.access_token);
        localStorage.setItem('user_email', email);
        window.location.href = '/dashboard.html';
        return;
      }
      window.location.href = '/login.html';
      return;
    }
    setMessage(form, data.detail || 'Registration failed. Try again.', 'error');
  } catch (error) {
    setMessage(form, 'Network error. Please try again.', 'error');
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = 'Create account';
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.querySelector('[data-form="login"]');
  if (loginForm) {
    loginForm.addEventListener('submit', handleLogin);
  }
  const registerForm = document.querySelector('[data-form="register"]');
  if (registerForm) {
    registerForm.addEventListener('submit', handleRegister);
  }
});
