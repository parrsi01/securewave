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
    hint.style.color = 'var(--red)';
  }
  if (input) input.setAttribute('aria-invalid', 'true');
}

function clearFieldStates(form) {
  form.querySelectorAll('input').forEach((input) => {
    input.removeAttribute('aria-invalid');
    const hint = input.parentElement.querySelector('.field-hint');
    if (hint) {
      hint.style.color = '';
      hint.textContent = hint.getAttribute('data-default') || '';
    }
  });
  setMessage(form, '');
}

function responseMessage(data, fallback) {
  if (typeof data?.detail === 'string') return data.detail;
  if (typeof data?.error?.message === 'string') return data.error.message;
  if (typeof data?.message === 'string') return data.message;
  return fallback;
}

async function hasAuthenticatedSession() {
  const response = await fetch('/api/auth/session', {
    credentials: 'include',
    cache: 'no-store',
  });
  if (!response.ok) return false;
  const session = await response.json().catch(() => ({}));
  return session?.authenticated === true;
}

async function handleAuth(event) {
  event.preventDefault();
  const form = event.currentTarget;
  clearFieldStates(form);

  const action = form.dataset.auth;
  const email = form.querySelector('#email')?.value.trim();
  const password = form.querySelector('#password')?.value || '';
  const confirm = form.querySelector('#passwordConfirm')?.value || '';
  const totpField = form.querySelector('[data-totp-field]');
  const totpInput = form.querySelector('#totpCode');
  const totpCode = totpInput?.value.trim() || '';
  const requiresTotp = action === 'login' && totpField && !totpField.hidden;

  let valid = true;
  if (!email) { setFieldError(form.querySelector('#email'), 'Enter your email.'); valid = false; }
  if (!password) { setFieldError(form.querySelector('#password'), 'Enter your password.'); valid = false; }
  if (requiresTotp && !totpCode) {
    setFieldError(totpInput, 'Enter your authenticator or backup code.');
    valid = false;
  }
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
      ? { email, password, ...(totpCode ? { totp_code: totpCode } : {}) }
      : { email, password, password_confirm: confirm };
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
      credentials: 'include',
    });
    window.clearTimeout(timeoutId);
    const data = await res.json().catch(() => ({}));
    if (res.ok && action === 'login' && data.requires_2fa) {
      if (totpField) totpField.hidden = false;
      if (totpInput) {
        totpInput.required = true;
        totpInput.focus();
      }
      setMessage(form, 'Enter the code from your authenticator app or use a backup code.');
      return;
    }
    if (res.ok && action === 'register' && !data.access_token) {
      setMessage(form, responseMessage(
        data,
        'Account created. Check your email to verify it before signing in.',
      ));
      form.reset();
      return;
    }
    if (res.ok && (action === 'login' || data.access_token)) {
      const authenticated = await hasAuthenticatedSession();
      if (!authenticated) {
        setMessage(form, 'Your account request completed without a valid browser session. Please try again.');
        return;
      }
      localStorage.setItem('user_email', email);
      window.location.href = '/dashboard';
      return;
    }
    setMessage(form, responseMessage(
      data,
      'Unable to continue. Check your details and try again.',
    ));
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
  fetch('/api/auth/session', { credentials: 'include' })
    .then((res) => res.ok ? res.json() : null)
    .then((session) => {
      if (session?.authenticated) {
        window.location.href = '/dashboard';
      }
    })
    .catch(() => {});
  document.querySelectorAll('[data-auth]')?.forEach((form) => {
    form.addEventListener('submit', handleAuth);
  });

  const stagingLink = document.querySelector('[data-staging-login]');
  if (stagingLink && window.location.hostname === 'staging-api.securewaveapp.com') {
    stagingLink.hidden = true;
  }

  const environmentLabel = document.querySelector('[data-auth-environment]');
  if (environmentLabel && window.location.hostname === 'staging-api.securewaveapp.com') {
    environmentLabel.textContent = 'SecureWave staging account';
  }
});
