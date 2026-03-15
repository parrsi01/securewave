function setMessage(form, text, type) {
  const box = form.querySelector('[data-form-message]');
  if (!box) return;
  if (!text) {
    box.classList.remove('visible');
    box.textContent = '';
    box.removeAttribute('data-type');
    return;
  }
  box.textContent = text;
  box.setAttribute('data-type', type || 'error');
  box.classList.add('visible');
}

function setFieldError(input, text) {
  const hint = input?.parentElement.querySelector('.field-hint');
  if (hint && text) {
    hint.textContent = text;
    hint.style.color = 'var(--sw-danger)';
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

async function handleAuth(event) {
  event.preventDefault();
  const form = event.currentTarget;
  clearFieldStates(form);

  const action = form.dataset.auth;
  const email = form.querySelector('#email')?.value.trim();
  const password = form.querySelector('#password')?.value || '';
  const confirm = form.querySelector('#passwordConfirm')?.value || '';

  let valid = true;

  if (action === 'forgot-password') {
    if (!email) { setFieldError(form.querySelector('#email'), 'Enter your email.'); valid = false; }
    if (!valid) {
      setMessage(form, 'Please enter your email address.');
      return;
    }
    const button = form.querySelector('button[type="submit"]');
    if (button) { button.disabled = true; button.textContent = 'Sending...'; }
    try {
      const controller = new AbortController();
      const timeoutId = window.setTimeout(() => controller.abort(), 8000);
      const res = await fetch('/api/auth/password-reset/request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
        signal: controller.signal,
        credentials: 'include',
      });
      window.clearTimeout(timeoutId);
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        form.querySelector('.form-group').style.display = 'none';
        button.style.display = 'none';
        setMessage(form, 'Check your email for a password reset link.', 'success');
        return;
      }
      setMessage(form, data.detail || 'Unable to send reset link. Please try again.');
    } catch (error) {
      if (error?.name === 'AbortError') {
        setMessage(form, 'Request timed out. Please try again.');
      } else {
        setMessage(form, 'Network issue. Please try again.');
      }
    } finally {
      if (button) { button.disabled = false; button.textContent = 'Send Reset Link'; }
    }
    return;
  }

  if (action === 'reset-password') {
    const token = form.querySelector('#resetToken')?.value || '';
    if (!token) {
      setMessage(form, 'Invalid or missing reset token. Please use the link from your email.');
      return;
    }
    if (!password) { setFieldError(form.querySelector('#password'), 'Enter your new password.'); valid = false; }
    if (password && password.length < 8) { setFieldError(form.querySelector('#password'), 'Use at least 8 characters.'); valid = false; }
    if (!confirm) { setFieldError(form.querySelector('#passwordConfirm'), 'Confirm your new password.'); valid = false; }
    if (confirm && confirm !== password) { setFieldError(form.querySelector('#passwordConfirm'), 'Passwords do not match.'); valid = false; }
    if (!valid) {
      setMessage(form, 'Please complete the fields to continue.');
      return;
    }
    const button = form.querySelector('button[type="submit"]');
    if (button) { button.disabled = true; button.textContent = 'Resetting...'; }
    try {
      const controller = new AbortController();
      const timeoutId = window.setTimeout(() => controller.abort(), 8000);
      const res = await fetch('/api/auth/password-reset/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, new_password: password, confirm_password: confirm }),
        signal: controller.signal,
        credentials: 'include',
      });
      window.clearTimeout(timeoutId);
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        form.querySelectorAll('.form-group').forEach(g => g.style.display = 'none');
        form.querySelector('#resetToken').style.display = 'none';
        button.style.display = 'none';
        setMessage(form, 'Password reset successfully. You can now sign in.', 'success');
        return;
      }
      setMessage(form, data.detail || 'Unable to reset password. The link may have expired.');
    } catch (error) {
      if (error?.name === 'AbortError') {
        setMessage(form, 'Request timed out. Please try again.');
      } else {
        setMessage(form, 'Network issue. Please try again.');
      }
    } finally {
      if (button) { button.disabled = false; button.textContent = 'Reset Password'; }
    }
    return;
  }

  // Login / Register flow
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
      credentials: 'include',
    });
    window.clearTimeout(timeoutId);
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      localStorage.setItem('user_email', email);
      window.location.href = '/dashboard';
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
  // Populate reset token from URL query param
  const resetTokenInput = document.querySelector('#resetToken');
  if (resetTokenInput) {
    const params = new URLSearchParams(window.location.search);
    const token = params.get('token');
    if (token) {
      resetTokenInput.value = token;
    }
  }

  // Redirect to dashboard if already logged in (login/register pages only)
  const authForm = document.querySelector('[data-auth="login"], [data-auth="register"]');
  if (authForm) {
    fetch('/api/auth/me', { credentials: 'include' })
      .then((res) => {
        if (res.ok) {
          window.location.href = '/dashboard';
        }
      })
      .catch(() => {});
  }

  document.querySelectorAll('[data-auth]')?.forEach((form) => {
    form.addEventListener('submit', handleAuth);
  });
});
