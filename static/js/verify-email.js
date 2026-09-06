(() => {
  'use strict';
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  const query = new URLSearchParams(window.location.search);
  let token = fragment.get('token') || query.get('token');
  // Remove the token before any subsequent navigation. Never persist or log it.
  window.history.replaceState(null, '', window.location.pathname);
  const status = document.getElementById('verification-status');
  const retry = document.getElementById('verification-retry');
  let pending = false;

  async function verify() {
    if (pending) return;
    retry.hidden = true;
    if (!token) {
      status.textContent = 'This link has no verification token. Open the full link from your verification email.';
      return;
    }
    pending = true;
    status.textContent = 'Verifying your email…';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch('/api/auth/verify-email', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({token}),
        credentials: 'omit',
        cache: 'no-store',
        referrerPolicy: 'no-referrer',
        redirect: 'error',
        signal: controller.signal,
      });
      const data = await response.json();
      if (response.ok && data.verified === true) {
        token = null;
        status.textContent = 'Email verified. You can now log in to SecureWave.';
      } else if (response.status === 400) {
        const message = data.error?.message || data.detail || '';
        status.textContent = message === 'Verification token has expired'
          ? 'This verification link has expired. Use a newer verification email, or contact support for help.'
          : 'This verification link is invalid or has already been used. If you already verified your email, try logging in.';
        token = null;
      } else {
        status.textContent = 'We could not verify your email right now. Please try again.';
        retry.hidden = false;
      }
    } catch (_) {
      status.textContent = 'We could not reach the verification service. Check your connection and try again.';
      retry.hidden = false;
    } finally {
      clearTimeout(timeout);
      pending = false;
    }
  }
  retry.addEventListener('click', verify);
  verify();
})();
