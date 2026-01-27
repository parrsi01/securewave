document.addEventListener('DOMContentLoaded', () => {
  const email = localStorage.getItem('user_email') || 'you@example.com';
  const emailEl = document.querySelector('[data-user-email]');
  if (emailEl) {
    emailEl.textContent = email;
  }

  const logoutBtn = document.querySelector('[data-logout]');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', () => {
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      localStorage.removeItem('user_email');
      window.location.href = '/login.html';
    });
  }
});
