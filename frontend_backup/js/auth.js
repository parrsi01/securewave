import { setTokens } from './main.js';

async function handleLogin() {
  const form = document.getElementById('loginForm');
  const message = document.getElementById('authMessage');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    message.textContent = '';
    const payload = {
      email: form.email.value,
      password: form.password.value,
    };
    const res = await fetch('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) {
      message.textContent = data.detail || 'Login failed';
      message.className = 'alert error';
      return;
    }
    setTokens(data.access_token, data.refresh_token);
    message.textContent = 'Login successful. Redirecting...';
    message.className = 'alert';
    setTimeout(() => window.location.href = '/dashboard.html', 800);
  });
}

async function handleRegister() {
  const form = document.getElementById('registerForm');
  const message = document.getElementById('registerMessage');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    message.textContent = '';
    const payload = {
      email: form.email.value,
      password: form.password.value,
    };
    const res = await fetch('/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) {
      message.textContent = data.detail || 'Registration failed';
      message.className = 'alert error';
      return;
    }
    setTokens(data.access_token, data.refresh_token);
    message.textContent = 'Account created. Redirecting...';
    message.className = 'alert';
    setTimeout(() => window.location.href = '/dashboard.html', 800);
  });
}

export function initAuthPages() {
  const loginForm = document.getElementById('loginForm');
  if (loginForm) handleLogin();
  const registerForm = document.getElementById('registerForm');
  if (registerForm) handleRegister();
}

document.addEventListener('DOMContentLoaded', initAuthPages);
