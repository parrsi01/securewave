document.addEventListener('DOMContentLoaded', () => {
  const nav = document.querySelector('.navbar');
  const toggle = document.querySelector('[data-nav-toggle]');
  if (nav && toggle) {
    toggle.setAttribute('aria-expanded', 'false');
    toggle.addEventListener('click', () => {
      const isOpen = nav.classList.toggle('nav-open');
      toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });
  }

  const token = localStorage.getItem('access_token');
  const navActions = document.querySelector('.nav-actions');
  if (token && navActions) {
    navActions.innerHTML = `
      <a class="btn btn-secondary" href="/dashboard.html">Dashboard</a>
      <button class="btn btn-outline" type="button" data-logout>Sign out</button>
    `;
  }

  document.querySelectorAll('[data-logout]').forEach((button) => {
    button.addEventListener('click', () => {
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      localStorage.removeItem('user_email');
      window.location.href = '/login.html';
    });
  });

  const yearEl = document.querySelector('[data-year]');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
});
