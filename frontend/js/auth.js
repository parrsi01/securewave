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
      const errorMessage = getErrorMessage(data);
      showAlert(errorMessage, 'error');
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
      const errorMessage = getErrorMessage(data);
      showAlert(errorMessage, 'error');
    }
  } catch (error) {
    showAlert('Registration failed. Please try again.', 'error');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Create Account';
  }
}

function getErrorMessage(data) {
  // Handle different error response formats from FastAPI
  if (typeof data.detail === 'string') {
    return data.detail;
  }

  // Handle validation errors (array of error objects)
  if (Array.isArray(data.detail)) {
    return data.detail.map(err => err.msg || JSON.stringify(err)).join(', ');
  }

  // Handle object error details
  if (typeof data.detail === 'object') {
    if (data.detail.msg) {
      return data.detail.msg;
    }
    return JSON.stringify(data.detail);
  }

  // Fallback error messages
  if (data.message) {
    return data.message;
  }

  return 'An error occurred. Please try again.';
}

function showAlert(message, type = 'info') {
  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.textContent = message;

  const container = document.querySelector('.container-sm') || document.querySelector('.container');
  container.insertBefore(alert, container.firstChild);

  setTimeout(() => alert.remove(), 5000);
}
