// Dashboard VPN Control - Professional Implementation
// Handles VPN toggle, server selection, config generation, and state management

class VPNDashboard {
  constructor() {
    this.vpnToggle = document.getElementById('vpnToggle');
    this.serverSelect = document.getElementById('serverSelect');
    this.connectionStatus = document.getElementById('connectionStatus');
    this.connectionDetails = document.getElementById('connectionDetails');
    this.selectedServer = document.getElementById('selectedServer');

    // Statistics elements
    this.statLatency = document.getElementById('statLatency');
    this.statBandwidth = document.getElementById('statBandwidth');
    this.statLocation = document.getElementById('statLocation');
    this.statEncryption = document.getElementById('statEncryption');

    // Account info elements
    this.userEmail = document.getElementById('userEmail');
    this.accountStatus = document.getElementById('accountStatus');
    this.joinDate = document.getElementById('joinDate');
    this.subscriptionStatus = document.getElementById('subscriptionStatus');

    // State
    this.isConnected = false;
    this.connectionState = 'DISCONNECTED';
    this.currentServer = null;
    this.accessToken = localStorage.getItem('access_token');
    this.vpnConfig = null;
    this.connectionId = null;

    // Connection tracking (Phase 4 enhancements)
    this.connectionStartTime = null;
    this.connectionTimer = null;
    this.usageInterval = null;
    this.statusInterval = null;

    this.init();
  }

  async init() {
    // CRITICAL: Immediate auth guard - redirect if no token exists
    if (!this.accessToken) {
      window.location.href = '/login.html?redirect=/dashboard.html';
      return;
    }

    // Validate token BEFORE making any other API calls
    const isValidToken = await this.validateToken();
    if (!isValidToken) {
      // Token invalid - already redirected by validateToken
      return;
    }

    // Token is valid - now load initial data
    await Promise.all([
      this.loadUserInfo(),
      this.loadSubscriptionInfo(),
      this.loadServers(),
      this.initializeVPNStatus()
    ]);

    // Set up event listeners
    this.setupEventListeners();

    // Initialize UI
    this.updateUI();
  }

  async validateToken() {
    try {
      const response = await fetch('/api/auth/me', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (!response.ok) {
        // Token invalid - clear and redirect
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
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

  setupEventListeners() {
    // VPN Toggle
    this.vpnToggle.addEventListener('change', () => this.handleVPNToggle());

    // Server Selection
    this.serverSelect.addEventListener('change', () => this.handleServerChange());

    // Download Config Button
    // Logout button
    const logoutBtn = document.getElementById('logoutBtn');
    if (logoutBtn) {
      logoutBtn.addEventListener('click', () => this.handleLogout());
    }
  }

  async initializeVPNStatus() {
    try {
      const response = await fetch('/api/vpn/status', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });
      if (!response.ok) return;
      const data = await response.json();
      if (data.status) {
        this.setConnectionState(data.status);
        if (data.status === 'CONNECTED' && data.connected_since) {
          this.connectionStartTime = new Date(data.connected_since).getTime();
          this.startConnectionTracking();
        }
        if (['CONNECTED', 'CONNECTING', 'DISCONNECTING'].includes(data.status)) {
          this.updateConnectionDetails({
            location: data.region || (this.currentServer ? this.currentServer.location : 'Auto'),
            public_ip: data.client_ip || '10.8.0.10'
          });
        }
        this.ensureStatusPolling();
        this.updateUI();
      }
    } catch (error) {
      console.error('Failed to initialize VPN status:', error);
    }
  }

  async loadUserInfo() {
    // Show loading state
    if (this.userEmail) this.userEmail.textContent = 'Loading...';
    if (this.accountStatus) this.setBadge(this.accountStatus, 'Loading...', 'info');

    try {
      const response = await fetch('/api/auth/me', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        this.userEmail.textContent = data.email || 'N/A';
        this.setBadge(
          this.accountStatus,
          data.is_active ? 'Active' : 'Inactive',
          data.is_active ? 'success' : 'error'
        );

        // Update user name in header
        const userNameElement = document.getElementById('userName');
        if (userNameElement) {
          const emailName = data.email ? data.email.split('@')[0] : 'User';
          userNameElement.textContent = emailName.charAt(0).toUpperCase() + emailName.slice(1);
        }

        // Format join date
        if (data.created_at && this.joinDate) {
          const date = new Date(data.created_at);
          this.joinDate.textContent = date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
          });
        }
      } else if (response.status === 401) {
        // Token expired
        this.handleLogout();
      } else {
        throw new Error('Failed to load user info');
      }
    } catch (error) {
      console.error('Failed to load user info:', error);
      if (this.userEmail) this.userEmail.textContent = 'Error loading';
      if (this.accountStatus) this.setBadge(this.accountStatus, 'Error', 'error');
      this.showAlert('Failed to load account information', 'error');
    }
  }

  async loadSubscriptionInfo() {
    if (!this.subscriptionStatus) return;

    // Show loading state
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
      this.setBadge(this.subscriptionStatus, 'Free Plan', 'info');
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

  async loadServers() {
    try {
      const response = await fetch('/api/vpn/servers', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (response.status === 401) {
        this.handleLogout();
        return;
      }

      if (response.status === 402) {
        this.showAlert('Plan limit reached. Upgrade to Premium to continue.', 'warning');
        this.serverSelect.innerHTML = '<option value="">Subscription required</option>';
        return;
      }

      if (!response.ok) {
        throw new Error('Failed to load server list');
      }

      const data = await response.json();
      const servers = (data.servers || []).map(server => ({
        server_id: server.server_id,
        location: `${server.city}, ${server.country}`,
        latency_ms: server.latency_ms || 0,
        bandwidth_mbps: 1000,
        health_status: server.health_status || 'unknown'
      }));
      this.populateServerDropdown(servers);
    } catch (error) {
      console.error('Failed to load servers:', error);
      this.showAlert('Failed to load server list', 'error');

      // Fallback server list
      this.serverSelect.innerHTML = '<option value="">Select a server location</option>';
    }
  }

  populateServerDropdown(servers) {
    // Sort servers by latency (best first)
    const sortedServers = servers.sort((a, b) => a.latency_ms - b.latency_ms);

    // Clear existing options
    this.serverSelect.innerHTML = '<option value="">Select a server location</option>';

    // Add server options
    sortedServers.forEach(server => {
      const option = document.createElement('option');
      option.value = server.server_id;
      const latencyText = server.latency_ms ? `${server.latency_ms.toFixed(0)}ms` : 'n/a';
      option.textContent = `${server.location} (${latencyText}, ${server.bandwidth_mbps}Mbps)`;
      option.dataset.server = JSON.stringify(server);
      this.serverSelect.appendChild(option);
    });

    // Auto-select best server (first in sorted list)
    if (sortedServers.length > 0) {
      this.serverSelect.selectedIndex = 1; // Index 1 because 0 is "Select..."
      this.handleServerChange();
    }
  }

  handleServerChange() {
    const selectedOption = this.serverSelect.options[this.serverSelect.selectedIndex];

    if (selectedOption.value) {
      this.currentServer = JSON.parse(selectedOption.dataset.server);
      this.updateServerStats();

      if (['CONNECTED', 'CONNECTING', 'DISCONNECTING'].includes(this.connectionState)) {
        this.updateConnectionDetails({
          location: this.currentServer.location,
          public_ip: '10.8.0.10'
        });
      }
    } else {
      this.currentServer = null;
      this.clearServerStats();
    }
  }

  updateServerStats() {
    if (this.currentServer) {
      this.statLatency.textContent = `${this.currentServer.latency_ms.toFixed(1)}ms`;
      this.statBandwidth.textContent = `${this.currentServer.bandwidth_mbps.toFixed(0)}Mbps`;
      this.statLocation.textContent = this.currentServer.location;
      this.statEncryption.textContent = 'ChaCha20';

      if (this.selectedServer) {
        this.selectedServer.textContent = this.currentServer.location;
      }
    }
  }

  clearServerStats() {
    this.statLatency.textContent = '--';
    this.statBandwidth.textContent = '--';
    this.statLocation.textContent = '--';
    this.statEncryption.textContent = '--';
  }

  async handleVPNToggle() {
    const isChecked = this.vpnToggle.checked;

    if (isChecked) {
      // Turning VPN ON
      if (!this.currentServer) {
        this.showAlert('Please select a server location first', 'warning');
        this.vpnToggle.checked = false;
        return;
      }

      await this.connectVPN();
    } else {
      // Turning VPN OFF
      await this.disconnectVPN();
    }
  }

  async connectVPN() {
    try {
      this.setConnectionState('CONNECTING');
      this.connectionStatus.textContent = 'Preparing...';
      this.connectionStatus.className = 'connection-status connecting';

      const response = await fetch('/api/vpn/allocate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          server_id: this.currentServer ? this.currentServer.server_id : null,
          device_name: 'Dashboard Device'
        })
      });

      if (response.status === 402) {
        this.showAlert('Plan limit reached. Upgrade to Premium to continue.', 'warning');
        this.vpnToggle.checked = false;
        this.setConnectionState('DISCONNECTED');
        this.updateUI();
        return;
      }

      if (response.ok) {
        const data = await response.json();
        this.setConnectionState('READY');
        this.connectionStatus.textContent = 'Ready to connect';
        this.connectionStatus.className = 'connection-status connected';
        this.startConnectionTracking();
        this.updateConnectionDetails({
          location: data.server_location || (this.currentServer ? this.currentServer.location : 'Auto'),
          public_ip: data.client_ip || '10.8.0.10',
          mode: 'live'
        });
        this.updateUI();
        this.showAlert('VPN is ready. Open WireGuard to connect.', 'success');
      } else if (response.status === 401) {
        this.handleLogout();
      } else {
        throw new Error('Failed to connect VPN');
      }
    } catch (error) {
      console.error('Failed to connect VPN:', error);
      this.showAlert('Failed to connect VPN. Please try again.', 'error');
      this.vpnToggle.checked = false;
      this.setConnectionState('DISCONNECTED');
      this.updateUI();
    }
  }

  async disconnectVPN() {
    try {
      this.setConnectionState('DISCONNECTING');
      this.connectionStatus.textContent = 'Disconnecting...';
      this.connectionStatus.className = 'connection-status disconnecting';

      // Stop connection tracking (Phase 4 enhancements)
      this.stopConnectionTracking();

      // Update state
      this.setConnectionState('DISCONNECTED');
      this.updateUI();

      this.showAlert('VPN setup cleared', 'info');
    } catch (error) {
      console.error('Failed to disconnect VPN:', error);
      this.showAlert('Failed to disconnect VPN', 'error');
    }
  }

  // Phase 4 Enhancement: Connection tracking
  startConnectionTracking() {
    if (!this.connectionStartTime) {
      this.connectionStartTime = Date.now();
    }

    // Update connection duration every second
    this.connectionTimer = setInterval(() => {
      this.updateConnectionDuration();
    }, 1000);

    this.fetchUsage();
    this.usageInterval = setInterval(() => {
      this.fetchUsage();
    }, 30000);
  }

  stopConnectionTracking() {
    if (this.connectionTimer) {
      clearInterval(this.connectionTimer);
      this.connectionTimer = null;
    }
    if (this.usageInterval) {
      clearInterval(this.usageInterval);
      this.usageInterval = null;
    }
    this.connectionStartTime = null;
  }

  updateConnectionDuration() {
    if (!this.connectionStartTime) return;

    const duration = Math.floor((Date.now() - this.connectionStartTime) / 1000);
    const hours = Math.floor(duration / 3600);
    const minutes = Math.floor((duration % 3600) / 60);
    const seconds = duration % 60;

    const durationText = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;

    // Update duration display if element exists
    const durationElement = document.getElementById('connectionDuration');
    if (durationElement) {
      durationElement.textContent = durationText;
    }
  }

  async fetchUsage() {
    try {
      const response = await fetch('/api/vpn/usage', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });
      if (!response.ok) return;
      const data = await response.json();
      const downloadElement = document.getElementById('dataDownload');
      const uploadElement = document.getElementById('dataUpload');
      if (downloadElement) {
        downloadElement.textContent = `${data.total_data_received_mb || 0} MB`;
      }
      if (uploadElement) {
        uploadElement.textContent = `${data.total_data_sent_mb || 0} MB`;
      }
    } catch (error) {
      console.error('Failed to fetch usage:', error);
    }
  }

  ensureStatusPolling() {
    if (this.statusInterval) return;
    this.statusInterval = setInterval(() => {
      this.fetchStatus();
    }, 5000);
  }

  updateConnectionDetails(serverInfo) {
    if (this.connectionDetails) {
      const location = serverInfo.location || (this.currentServer ? this.currentServer.location : 'Auto');
      const publicIp = serverInfo.public_ip || '10.8.0.10';
      const mode = 'Control Plane';
      const detailsHTML = `
        <p><strong>Server:</strong> ${location}</p>
        <p><strong>IP Address:</strong> ${publicIp}</p>
        <p><strong>Protocol:</strong> WireGuard</p>
        <p><strong>Mode:</strong> ${mode}</p>
        <p><strong>Session:</strong> <span id="connectionDuration">00:00:00</span></p>
        <p><strong>Data:</strong> <span id="dataDownload">0 MB</span> down / <span id="dataUpload">0 MB</span> up</p>
        <p><strong>Next step:</strong> Open WireGuard and connect your SecureWave tunnel.</p>
      `;
      this.connectionDetails.innerHTML = detailsHTML;
    }
  }

  updateUI() {
    const isActive = ['READY', 'CONNECTING', 'DISCONNECTING', 'CONNECTED'].includes(this.connectionState);
    const isReady = this.connectionState === 'READY';

    this.vpnToggle.checked = isActive;

    if (isReady) {
      this.connectionStatus.textContent = 'Ready to connect';
      this.connectionStatus.className = 'connection-status connected';
      this.connectionDetails.style.display = 'block';
      this.serverSelect.disabled = false;
    } else if (this.connectionState === 'CONNECTING') {
      this.connectionStatus.textContent = 'Preparing...';
      this.connectionStatus.className = 'connection-status connecting';
      this.connectionDetails.style.display = 'block';
      this.serverSelect.disabled = false;
    } else if (this.connectionState === 'DISCONNECTING') {
      this.connectionStatus.textContent = 'Disconnecting...';
      this.connectionStatus.className = 'connection-status disconnecting';
      this.connectionDetails.style.display = 'block';
      this.serverSelect.disabled = false;
    } else {
      // Disconnected state
      this.connectionStatus.textContent = 'Disconnected';
      this.connectionStatus.className = 'connection-status disconnected';
      this.connectionDetails.style.display = 'none';
      this.serverSelect.disabled = false;
    }
  }

  async fetchStatus() {
    try {
      const response = await fetch('/api/vpn/status', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });
      if (!response.ok) return;
      const data = await response.json();
      if (data.status === 'CONNECTED') {
        this.setConnectionState('READY');
        if (!this.connectionStartTime && data.connected_since) {
          this.connectionStartTime = new Date(data.connected_since).getTime();
        }
        if (!this.connectionTimer) {
          this.startConnectionTracking();
        }
        this.updateConnectionDetails({
          location: data.region || (this.currentServer ? this.currentServer.location : 'Auto'),
          public_ip: data.client_ip || '10.8.0.10'
        });
      }
      if (data.status === 'CONNECTING') {
        this.setConnectionState('CONNECTING');
      }
      if (data.status === 'DISCONNECTING') {
        this.setConnectionState('DISCONNECTING');
      }
      if (data.status === 'DISCONNECTED') {
        this.setConnectionState('DISCONNECTED');
        this.stopConnectionTracking();
      }
      this.updateUI();
    } catch (error) {
      console.error('Status check failed:', error);
    }
  }

  setConnectionState(state) {
    this.connectionState = state;
    this.isConnected = state === 'CONNECTED';
  }


  handleLogout() {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    window.location.href = '/login.html';
  }

  showAlert(message, type = 'info') {
    // Remove existing alerts
    const existingAlerts = document.querySelectorAll('.dashboard-alert');
    existingAlerts.forEach(alert => alert.remove());

    const alert = document.createElement('div');
    alert.className = `dashboard-alert alert-${type}`;
    alert.textContent = message;

    // Insert at top of main content
    const mainContent = document.querySelector('.dashboard-content') || document.querySelector('main');
    if (mainContent) {
      mainContent.insertBefore(alert, mainContent.firstChild);

      // Auto-remove after 5 seconds
      setTimeout(() => alert.remove(), 5000);
    }
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  new VPNDashboard();
});
