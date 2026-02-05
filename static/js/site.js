document.addEventListener('DOMContentLoaded', () => {
  // Load the local-only SecureWave Assistant widget on marketing/dashboard pages.
  // This is intentionally optional: if the script fails to load, the site continues to work.
  const ensureAssistant = () => {
    if (window.SecureWaveAssistant && typeof window.SecureWaveAssistant.init === 'function') {
      window.SecureWaveAssistant.init({});
      return;
    }

    if (document.querySelector('script[data-sw-assistant]')) return;
    const script = document.createElement('script');
    script.src = '/js/chat_assistant.js';
    script.defer = true;
    script.setAttribute('data-sw-assistant', '1');
    script.addEventListener('load', () => {
      try {
        if (window.SecureWaveAssistant && typeof window.SecureWaveAssistant.init === 'function') {
          window.SecureWaveAssistant.init({});
        }
      } catch {
        // Ignore assistant init errors to avoid breaking the site.
      }
    });
    document.head.appendChild(script);
  };

  const nav = document.querySelector('.navbar');
  const toggle = document.querySelector('[data-nav-toggle]');
  if (nav && toggle) {
    toggle.setAttribute('aria-expanded', 'false');
    toggle.addEventListener('click', () => {
      const isOpen = nav.classList.toggle('nav-open');
      toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });
  }

  const navActions = document.querySelector('.nav-actions');
  const getCookie = (name) => {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return '';
  };

  if (navActions) {
    fetch('/api/auth/me', { credentials: 'include' })
      .then((res) => {
        if (!res.ok) return;
        navActions.innerHTML = `
          <a class="btn btn-secondary" href="/dashboard.html">Dashboard</a>
          <button class="btn btn-outline" type="button" data-logout>Sign out</button>
        `;
        const logoutButton = navActions.querySelector('[data-logout]');
        if (!logoutButton) return;
        logoutButton.addEventListener('click', async () => {
          const csrfToken = getCookie('csrf_token');
          try {
            await fetch('/api/auth/logout', {
              method: 'POST',
              headers: { 'X-CSRF-Token': csrfToken },
              credentials: 'include',
            });
          } finally {
            localStorage.removeItem('user_email');
            window.location.href = '/login.html';
          }
        });
      })
      .catch(() => {});
  }

  const yearEl = document.querySelector('[data-year]');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  ensureAssistant();
});
