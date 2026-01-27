document.addEventListener('DOMContentLoaded', () => {
  const nav = document.querySelector('.navbar');
  const toggle = document.querySelector('[data-nav-toggle]');
  if (nav && toggle) {
    toggle.addEventListener('click', () => nav.classList.toggle('nav-open'));
  }

  const yearEl = document.querySelector('[data-year]');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
});
