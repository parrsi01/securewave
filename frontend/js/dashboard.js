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
      const errorMessage = getErrorMessage(data);
      showAlert(errorMessage, 'error');
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

  const container = document.querySelector('.container');
  container.insertBefore(alert, container.firstChild);

  setTimeout(() => alert.remove(), 5000);
}
