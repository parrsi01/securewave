// SecureWave Dashboard - App-first control plane

class DashboardUI {
  constructor() {
    this.accessToken = localStorage.getItem('access_token');
    this.userName = document.getElementById('userName');
    this.userEmail = document.getElementById('userEmail');
    this.accountStatus = document.getElementById('accountStatus');
    this.subscriptionStatus = document.getElementById('subscriptionStatus');
    this.deviceCount = document.getElementById('deviceCount');
    this.deviceList = document.getElementById('deviceList');
    this.vpnReadiness = document.getElementById('vpnReadiness');
    this.vpnReadinessDetail = document.getElementById('vpnReadinessDetail');
    this.logoutBtn = document.getElementById('logoutBtn');

    this.init();
  }

  async init() {
    if (!this.accessToken) {
      window.location.href = '/login.html?redirect=/dashboard.html';
      return;
    }

    const isValidToken = await this.validateToken();
    if (!isValidToken) {
      return;
    }

    await Promise.all([
      this.loadUserInfo(),
      this.loadSubscriptionInfo(),
      this.loadDevices(),
      this.loadVpnStatus()
    ]);
    this.bindEvents();
  }

  async validateToken() {
    try {
      const response = await fetch('/api/auth/me', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        this.clearSession();
        window.location.href = '/login.html?redirect=/dashboard.html';
        return false;
      }

      return true;
    } catch (error) {
      console.error('Token validation failed:', error);
      window.location.href = '/login.html?redirect=/dashboard.html';
      return false;
    }
  }

  bindEvents() {
    if (!this.logoutBtn) return;
    this.logoutBtn.addEventListener('click', async () => {
      try {
        await fetch('/api/auth/logout', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${this.accessToken}`
          }
        });
      } catch (error) {
        console.error('Logout failed:', error);
      } finally {
        this.clearSession();
        window.location.href = '/home.html';
      }
    });
  }

  clearSession() {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
  }

  async loadUserInfo() {
    if (this.userEmail) {
      this.userEmail.textContent = 'Loading...';
    }

    try {
      const response = await fetch('/api/auth/me', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        throw new Error('Failed to load user info');
      }

      const data = await response.json();
      if (this.userEmail) {
        this.userEmail.textContent = data.email || 'N/A';
      }
      if (this.userName) {
        const emailName = data.email ? data.email.split('@')[0] : 'User';
        this.userName.textContent = emailName.charAt(0).toUpperCase() + emailName.slice(1);
      }
      if (this.accountStatus) {
        this.setBadge(
          this.accountStatus,
          data.is_active ? 'Active' : 'Inactive',
          data.is_active ? 'success' : 'error'
        );
      }
    } catch (error) {
      console.error('Failed to load user info:', error);
      if (this.userEmail) {
        this.userEmail.textContent = 'Error loading';
      }
      if (this.accountStatus) {
        this.setBadge(this.accountStatus, 'Error', 'error');
      }
    }
  }

  async loadSubscriptionInfo() {
    if (!this.subscriptionStatus) return;
    this.setBadge(this.subscriptionStatus, 'Loading...', 'info');

    try {
      const response = await fetch('/api/billing/subscriptions/current', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        this.setBadge(this.subscriptionStatus, 'Free Plan', 'info');
        return;
      }

      const data = await response.json();
      if (!data.subscription) {
        this.setBadge(this.subscriptionStatus, 'Free Plan', 'info');
        return;
      }

      const status = data.subscription.status || 'active';
      const planName = data.subscription.plan_name || 'Premium';
      const badgeType = ['active', 'trialing'].includes(status)
        ? 'success'
        : ['past_due'].includes(status)
          ? 'warning'
          : ['canceled', 'expired', 'inactive'].includes(status)
            ? 'error'
            : 'info';

      this.setBadge(this.subscriptionStatus, `${planName} • ${status}`, badgeType);
    } catch (error) {
      console.error('Failed to load subscription info:', error);
      this.setBadge(this.subscriptionStatus, 'Free Plan', 'info');
    }
  }

  async loadDevices() {
    if (!this.deviceList || !this.deviceCount) return;
    this.deviceList.innerHTML = '<li>Loading devices...</li>';
    this.deviceCount.textContent = '--';

    try {
      const response = await fetch('/api/vpn/devices', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        throw new Error('Failed to load devices');
      }

      const data = await response.json();
      const devices = data.devices || [];
      this.deviceCount.textContent = devices.length.toString();

      if (!devices.length) {
        this.deviceList.innerHTML = '<li>No devices yet. Add one in Settings.</li>';
        return;
      }

      const maxItems = 4;
      this.deviceList.innerHTML = '';
      devices.slice(0, maxItems).forEach((device) => {
        const name = device.name || device.device_name || 'Unnamed device';
        const item = document.createElement('li');
        item.textContent = name;
        this.deviceList.appendChild(item);
      });

      if (devices.length > maxItems) {
        const item = document.createElement('li');
        item.textContent = `+${devices.length - maxItems} more devices`;
        this.deviceList.appendChild(item);
      }
    } catch (error) {
      console.error('Failed to load devices:', error);
      this.deviceList.innerHTML = '<li>Unable to load devices right now.</li>';
      this.deviceCount.textContent = '--';
    }
  }

  async loadVpnStatus() {
    if (!this.vpnReadiness) return;
    this.setBadge(this.vpnReadiness, 'Checking...', 'info');
    if (this.vpnReadinessDetail) {
      this.vpnReadinessDetail.textContent = '';
    }

    try {
      const response = await fetch('/api/vpn/status', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        throw new Error('Unable to load VPN status');
      }

      const data = await response.json();
      const status = data.status || 'DISCONNECTED';
      const isConnected = status === 'CONNECTED';
      const badgeType = isConnected ? 'success' : 'info';
      const readiness = isConnected ? 'Active' : 'Ready';
      this.setBadge(this.vpnReadiness, readiness, badgeType);

      if (this.vpnReadinessDetail) {
        const location = data.server_location || 'Auto-select region';
        this.vpnReadinessDetail.textContent = isConnected
          ? `Connected via ${location}`
          : 'Download the app to connect.';
      }
    } catch (error) {
      console.error('Failed to load VPN status:', error);
      this.setBadge(this.vpnReadiness, 'Unavailable', 'warning');
      if (this.vpnReadinessDetail) {
        this.vpnReadinessDetail.textContent = 'Try again in a moment.';
      }
    }
  }

  setBadge(element, text, type) {
    if (!element) return;
    element.textContent = text;
    element.classList.remove('badge-success', 'badge-warning', 'badge-error', 'badge-info');
    if (type) {
      element.classList.add(`badge-${type}`);
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  new DashboardUI();
});
