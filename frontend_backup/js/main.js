const apiBase = '';

export function getTokens() {
  return {
    access: localStorage.getItem('access_token'),
    refresh: localStorage.getItem('refresh_token'),
  };
}

export function setTokens(access, refresh) {
  if (access) localStorage.setItem('access_token', access);
  if (refresh) localStorage.setItem('refresh_token', refresh);
}

export function clearTokens() {
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
}

export async function apiFetch(path, options = {}) {
  const tokens = getTokens();
  const headers = options.headers || {};
  if (tokens.access) headers['Authorization'] = `Bearer ${tokens.access}`;
  headers['Content-Type'] = headers['Content-Type'] || 'application/json';
  const response = await fetch(`${apiBase}${path}`, { ...options, headers });
  if (response.status === 401 && tokens.refresh) {
    const refreshed = await refreshToken(tokens.refresh);
    if (refreshed) {
      headers['Authorization'] = `Bearer ${refreshed}`;
      return fetch(`${apiBase}${path}`, { ...options, headers });
    }
  }
  return response;
}

async function refreshToken(refreshTokenValue) {
  try {
    const res = await fetch('/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshTokenValue }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    setTokens(data.access_token, data.refresh_token);
    return data.access_token;
  } catch (err) {
    console.error('Refresh failed', err);
    clearTokens();
    return null;
  }
}

export function bindNavHighlight() {
  const links = document.querySelectorAll('.nav-links a');
  links.forEach((link) => {
    if (link.href === window.location.href) {
      link.classList.add('active');
    }
  });
}

export function ensureAuthUI() {
  const authButtons = document.querySelectorAll('[data-auth-only]');
  const tokens = getTokens();
  authButtons.forEach((btn) => {
    btn.style.display = tokens.access ? 'inline-flex' : 'none';
  });
  const anonButtons = document.querySelectorAll('[data-anon-only]');
  anonButtons.forEach((btn) => {
    btn.style.display = tokens.access ? 'none' : 'inline-flex';
  });
}

document.addEventListener('DOMContentLoaded', () => {
  bindNavHighlight();
  ensureAuthUI();
  const logoutButtons = document.querySelectorAll('[data-logout]');
  logoutButtons.forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      clearTokens();
      window.location.href = '/login.html';
    });
  });
});
