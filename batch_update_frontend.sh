#!/bin/bash
echo "Updating all frontend files with modern design and working functionality..."

cd frontend

# Update remaining critical pages
# (Due to constraints, updating key pages with functional JavaScript routes)

# Update main.js with working API routes
cat > js/main.js << 'JSEOF'
// SecureWave VPN - Main JavaScript with Working API Routes

const API_BASE = '/api';

// Mobile menu toggle
document.addEventListener('DOMContentLoaded', () => {
  const navToggle = document.getElementById('navToggle');
  const navMenu = document.getElementById('navMenu');
  
  if (navToggle && navMenu) {
    navToggle.addEventListener('click', () => {
      navMenu.classList.toggle('active');
    });
  }

  // Check auth state and update UI
  checkAuthState();
});

function checkAuthState() {
  const token = localStorage.getItem('access_token');
  const loginBtn = document.getElementById('loginBtn');
  const registerBtn = document.getElementById('registerBtn');
  const logoutBtn = document.getElementById('logoutBtn');
  const dashLink = document.getElementById('dashLink');

  if (token) {
    // User is logged in
    if (loginBtn) loginBtn.classList.add('d-none');
    if (registerBtn) registerBtn.classList.add('d-none');
    if (logoutBtn) {
      logoutBtn.classList.remove('d-none');
      logoutBtn.addEventListener('click', logout);
    }
    if (dashLink) dashLink.classList.remove('d-none');
  } else {
    // User is not logged in
    if (loginBtn) loginBtn.classList.remove('d-none');
    if (registerBtn) registerBtn.classList.remove('d-none');
    if (logoutBtn) logoutBtn.classList.add('d-none');
    if (dashLink) dashLink.classList.add('d-none');
  }
}

function logout() {
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  window.location.href = '/home.html';
}

async function apiCall(endpoint, options = {}) {
  const token = localStorage.getItem('access_token');
  const headers = {
    'Content-Type': 'application/json',
    ...(token && { 'Authorization': `Bearer ${token}` }),
    ...options.headers
  };

  try {
    const response = await fetch(`${API_BASE}${endpoint}`, {
      ...options,
      headers
    });

    if (response.status === 401) {
      // Token expired
      localStorage.removeItem('access_token');
      window.location.href = '/login.html';
      return null;
    }

    return response;
  } catch (error) {
    console.error('API Error:', error);
    return null;
  }
}

function showAlert(message, type = 'info') {
  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.textContent = message;
  
  const container = document.querySelector('.container') || document.body;
  container.insertBefore(alert, container.firstChild);
  
  setTimeout(() => alert.remove(), 5000);
}
JSEOF

echo "✅ main.js updated with working API routes"

# Update auth.js
cat > js/auth.js << 'AUTHJS'
// Authentication handlers with correct API routes

document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('loginForm');
  const registerForm = document.getElementById('registerForm');

  if (loginForm) {
    loginForm.addEventListener('submit', handleLogin);
  }

  if (registerForm) {
    registerForm.addEventListener('submit', handleRegister);
  }
});

async function handleLogin(e) {
  e.preventDefault();
  
  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const submitBtn = e.target.querySelector('button[type="submit"]');
  
  submitBtn.disabled = true;
  submitBtn.textContent = 'Logging in...';

  try {
    const formData = new FormData();
    formData.append('username', email);
    formData.append('password', password);

    const response = await fetch('/api/auth/login', {
      method: 'POST',
      body: formData
    });

    const data = await response.json();

    if (response.ok && data.access_token) {
      localStorage.setItem('access_token', data.access_token);
      if (data.refresh_token) {
        localStorage.setItem('refresh_token', data.refresh_token);
      }
      window.location.href = '/dashboard.html';
    } else {
      showAlert(data.detail || 'Login failed. Please check your credentials.', 'error');
    }
  } catch (error) {
    showAlert('Login failed. Please try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Login';
  }
}

async function handleRegister(e) {
  e.preventDefault();
  
  const email = document.getElementById('email').value;
  const password = document.getElementById('password').value;
  const submitBtn = e.target.querySelector('button[type="submit"]');
  
  submitBtn.disabled = true;
  submitBtn.textContent = 'Creating account...';

  try {
    const response = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    const data = await response.json();

    if (response.ok) {
      showAlert('Account created successfully! Redirecting to login...', 'success');
      setTimeout(() => window.location.href = '/login.html', 2000);
    } else {
      showAlert(data.detail || 'Registration failed.', 'error');
    }
  } catch (error) {
    showAlert('Registration failed. Please try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Create Account';
  }
}

function showAlert(message, type = 'info') {
  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.textContent = message;
  
  const container = document.querySelector('.container-sm') || document.querySelector('.container');
  container.insertBefore(alert, container.firstChild);
  
  setTimeout(() => alert.remove(), 5000);
}
AUTHJS

echo "✅ auth.js updated with correct routes"

# Update dashboard.js
cat > js/dashboard.js << 'DASHJS'
// Dashboard functionality with working VPN actions

document.addEventListener('DOMContentLoaded', () => {
  const token = localStorage.getItem('access_token');
  if (!token) {
    window.location.href = '/login.html';
    return;
  }

  loadDashboardData();

  const generateBtn = document.getElementById('generateConfig');
  const downloadBtn = document.getElementById('downloadConfig');
  const showQRBtn = document.getElementById('showQR');

  if (generateBtn) generateBtn.addEventListener('click', generateVPNConfig);
  if (downloadBtn) downloadBtn.addEventListener('click', downloadConfig);
  if (showQRBtn) showQRBtn.addEventListener('click', showQRCode);
});

async function loadDashboardData() {
  const token = localStorage.getItem('access_token');
  
  try {
    const response = await fetch('/api/dashboard/info', {
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (!response.ok) {
      if (response.status === 401) {
        localStorage.removeItem('access_token');
        window.location.href = '/login.html';
      }
      return;
    }

    const data = await response.json();
    
    if (document.getElementById('userEmail')) {
      document.getElementById('userEmail').textContent = data.email || 'User';
    }
    
    if (document.getElementById('subscriptionStatus')) {
      const status = data.subscription?.is_active ? 'Active' : 'Inactive';
      document.getElementById('subscriptionStatus').textContent = status;
      document.getElementById('subscriptionStatus').className = 
        `badge badge-${data.subscription?.is_active ? 'success' : 'error'}`;
    }
  } catch (error) {
    console.error('Failed to load dashboard data:', error);
  }
}

async function generateVPNConfig() {
  const token = localStorage.getItem('access_token');
  const btn = document.getElementById('generateConfig');
  
  btn.disabled = true;
  btn.textContent = 'Generating...';

  try {
    const response = await fetch('/api/vpn/generate', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` }
    });

    const data = await response.json();

    if (response.ok) {
      showAlert('VPN config generated successfully!', 'success');
      document.getElementById('downloadConfig').classList.remove('d-none');
      document.getElementById('showQR').classList.remove('d-none');
    } else {
      showAlert(data.detail || 'Failed to generate config', 'error');
    }
  } catch (error) {
    showAlert('Failed to generate config', 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Generate New Config';
  }
}

async function downloadConfig() {
  const token = localStorage.getItem('access_token');
  
  try {
    const response = await fetch('/api/vpn/config/download', {
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (response.ok) {
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'securewave.conf';
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      a.remove();
    } else {
      showAlert('Failed to download config', 'error');
    }
  } catch (error) {
    showAlert('Failed to download config', 'error');
  }
}

async function showQRCode() {
  const token = localStorage.getItem('access_token');
  
  try {
    const response = await fetch('/api/vpn/config/qr', {
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (response.ok) {
      const data = await response.json();
      const qrDiv = document.getElementById('qrCodeDisplay') || document.createElement('div');
      qrDiv.id = 'qrCodeDisplay';
      qrDiv.innerHTML = `<img src="data:image/png;base64,${data.qr_base64}" alt="QR Code" style="max-width: 300px; margin: 1rem auto; display: block;">`;
      
      const container = document.querySelector('.container');
      if (!document.getElementById('qrCodeDisplay')) {
        container.appendChild(qrDiv);
      }
    } else {
      showAlert('Failed to generate QR code', 'error');
    }
  } catch (error) {
    showAlert('Failed to generate QR code', 'error');
  }
}

function showAlert(message, type = 'info') {
  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.textContent = message;
  
  const container = document.querySelector('.container');
  container.insertBefore(alert, container.firstChild);
  
  setTimeout(() => alert.remove(), 5000);
}
DASHJS

echo "✅ dashboard.js updated with working actions"
echo "✅ All JavaScript files updated"

