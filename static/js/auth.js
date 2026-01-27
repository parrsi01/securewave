function setMessage(form, text) {
  const box = form.querySelector('[data-form-message]');
  if (!box) return;
  if (!text) {
    box.classList.remove('visible');
    box.textContent = '';
    return;
  }
  box.textContent = text;
  box.classList.add('visible');
}

function setFieldError(input, text) {
  const hint = input?.parentElement.querySelector('.field-hint');
  if (hint && text) {
    hint.textContent = text;
    hint.style.color = '#c26b1f';
  }
  if (input) input.setAttribute('aria-invalid', 'true');
}

function clearFieldStates(form) {
  form.querySelectorAll('input').forEach((input) => {
    input.removeAttribute('aria-invalid');
    const hint = input.parentElement.querySelector('.field-hint');
    if (hint) hint.style.color = 'var(--ink-soft)';
  });
  setMessage(form, '');
}

async function handleAuth(event) {
  event.preventDefault();
  const form = event.currentTarget;
  clearFieldStates(form);

  const action = form.dataset.auth;
  const email = form.querySelector('#email')?.value.trim();
  const password = form.querySelector('#password')?.value || '';
  const confirm = form.querySelector('#passwordConfirm')?.value || '';

  let valid = true;
  if (!email) { setFieldError(form.querySelector('#email'), 'Enter your email.'); valid = false; }
  if (!password) { setFieldError(form.querySelector('#password'), 'Enter your password.'); valid = false; }
  if (action === 'register') {
    if (password.length < 8) { setFieldError(form.querySelector('#password'), 'Use at least 8 characters.'); valid = false; }
    if (!confirm) { setFieldError(form.querySelector('#passwordConfirm'), 'Confirm your password.'); valid = false; }
    if (confirm && confirm !== password) { setFieldError(form.querySelector('#passwordConfirm'), 'Passwords do not match.'); valid = false; }
  }
  if (!valid) {
    setMessage(form, 'Please complete the fields to continue.');
    return;
  }

  const button = form.querySelector('button[type="submit"]');
  if (button) { button.disabled = true; button.textContent = action === 'login' ? 'Signing in...' : 'Creating account...'; }

  try {
    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 8000);
    const url = action === 'login' ? '/api/auth/login' : '/api/auth/register';
    const body = action === 'login'
      ? { email, password }
      : { email, password, password_confirm: confirm };
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    window.clearTimeout(timeoutId);
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      if (data.access_token) {
        localStorage.setItem('access_token', data.access_token);
        localStorage.setItem('user_email', email);
      }
      window.location.href = '/dashboard.html';
      return;
    }
    setMessage(form, data.detail || 'Unable to continue. Check your details and try again.');
  } catch (error) {
    if (error?.name === 'AbortError') {
      setMessage(form, 'Login is taking longer than expected. Please try again.');
    } else {
      setMessage(form, 'Network issue. Please try again.');
    }
  } finally {
    if (button) { button.disabled = false; button.textContent = action === 'login' ? 'Sign in' : 'Create account'; }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  if (localStorage.getItem('access_token')) {
    window.location.href = '/dashboard.html';
    return;
  }
  document.querySelectorAll('[data-auth]')?.forEach((form) => {
    form.addEventListener('submit', handleAuth);
  });
});
