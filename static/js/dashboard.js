// Dashboard VPN Control - Professional Implementation
// Handles VPN toggle, server selection, config generation, and state management

class VPNDashboard {
  constructor() {
    this.vpnToggle = document.getElementById('vpnToggle');
    this.serverSelect = document.getElementById('serverSelect');
    this.downloadBtn = document.getElementById('downloadConfigBtn');
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
    this.dataTransferred = { upload: 0, download: 0 };
    this.dataTransferInterval = null;
    this.statusInterval = null;

    this.init();
  }

  async init() {
    // Check authentication
    if (!this.accessToken) {
      this.showAlert('Please login to access the dashboard', 'error');
      setTimeout(() => window.location.href = '/login.html', 2000);
      return;
    }

    // Load initial data
    await this.loadUserInfo();
    await this.loadServers();
    await this.initializeVPNStatus();

    // Set up event listeners
    this.setupEventListeners();

    // Initialize UI
    this.updateUI();
  }

  setupEventListeners() {
    // VPN Toggle
    this.vpnToggle.addEventListener('change', () => this.handleVPNToggle());

    // Server Selection
    this.serverSelect.addEventListener('change', () => this.handleServerChange());

    // Download Config Button
    this.downloadBtn.addEventListener('click', () => this.downloadConfig());

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
            public_ip: data.mock_ip || '10.8.0.10'
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
    try {
      const response = await fetch('/api/auth/me', {
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        this.userEmail.textContent = data.email || 'N/A';
        this.accountStatus.textContent = data.subscription_active ? 'Premium Active' : 'Free Trial';

        // Format join date
        if (data.created_at) {
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
      }
    } catch (error) {
      console.error('Failed to load user info:', error);
      this.showAlert('Failed to load account information', 'error');
    }
  }

  async loadServers() {
    try {
      const servers = [
        { server_id: 'us-east', location: 'US East', latency_ms: 42, bandwidth_mbps: 900 },
        { server_id: 'us-west', location: 'US West', latency_ms: 55, bandwidth_mbps: 800 },
        { server_id: 'eu-central', location: 'EU Central', latency_ms: 80, bandwidth_mbps: 750 },
        { server_id: 'ap-southeast', location: 'AP Southeast', latency_ms: 110, bandwidth_mbps: 650 }
      ];
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
      option.textContent = `${server.location} (${server.latency_ms}ms, ${server.bandwidth_mbps}Mbps)`;
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
      this.connectionStatus.textContent = 'Connecting...';
      this.connectionStatus.className = 'connection-status connecting';

      const response = await fetch('/api/vpn/connect', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          region: this.currentServer ? this.currentServer.server_id : null
        })
      });

      if (response.ok) {
        const data = await response.json();
        this.setConnectionState(data.status || 'CONNECTING');
        this.connectionId = data.session_id || null;
        this.connectionStatus.textContent = data.status === 'CONNECTING' ? 'Connecting...' : 'Connected (Demo)';
        this.connectionStatus.className = data.status === 'CONNECTING' ? 'connection-status connecting' : 'connection-status connected';
        if (data.status === 'CONNECTED') {
          this.startConnectionTracking();
        }
        this.ensureStatusPolling();
        this.updateConnectionDetails({
          location: data.region || (this.currentServer ? this.currentServer.location : 'Auto'),
          public_ip: data.mock_ip || '10.8.0.10'
        });
        this.updateUI();
        this.showAlert('VPN connecting (Demo Mode)', 'success');
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

      await fetch('/api/vpn/disconnect', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          reason: 'user'
        })
      });

      // Stop connection tracking (Phase 4 enhancements)
      this.stopConnectionTracking();

      // Clear config
      this.vpnConfig = null;
      this.connectionId = null;

      // Update state
      this.setConnectionState('DISCONNECTING');
      this.updateUI();

      this.showAlert('VPN disconnecting (Demo Mode)', 'info');
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
    this.dataTransferred = { upload: 0, download: 0 };

    // Update connection duration every second
    this.connectionTimer = setInterval(() => {
      this.updateConnectionDuration();
    }, 1000);

    // Simulate data transfer (increment every 2 seconds)
    this.dataTransferInterval = setInterval(() => {
      // Simulate realistic VPN data transfer (random but believable)
      this.dataTransferred.download += Math.random() * 50 + 10; // 10-60 KB/s
      this.dataTransferred.upload += Math.random() * 20 + 5;    // 5-25 KB/s
      this.updateDataTransfer();
    }, 2000);

  }

  stopConnectionTracking() {
    if (this.connectionTimer) {
      clearInterval(this.connectionTimer);
      this.connectionTimer = null;
    }
    if (this.dataTransferInterval) {
      clearInterval(this.dataTransferInterval);
      this.dataTransferInterval = null;
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

  updateDataTransfer() {
    const formatBytes = (kb) => {
      if (kb < 1024) return `${kb.toFixed(1)} KB`;
      const mb = kb / 1024;
      if (mb < 1024) return `${mb.toFixed(2)} MB`;
      const gb = mb / 1024;
      return `${gb.toFixed(2)} GB`;
    };

    const downloadElement = document.getElementById('dataDownload');
    const uploadElement = document.getElementById('dataUpload');

    if (downloadElement) {
      downloadElement.textContent = formatBytes(this.dataTransferred.download);
    }
    if (uploadElement) {
      uploadElement.textContent = formatBytes(this.dataTransferred.upload);
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
      const detailsHTML = `
        <p><strong>Server:</strong> ${serverInfo.location || this.currentServer.location}</p>
        <p><strong>IP Address:</strong> ${serverInfo.public_ip || '10.8.0.10'}</p>
        <p><strong>Protocol:</strong> WireGuard (Demo)</p>
        <p><strong>Mode:</strong> Control Plane Demo</p>
      `;
      this.connectionDetails.innerHTML = detailsHTML;
    }
  }

  updateUI() {
    const isActive = ['CONNECTED', 'CONNECTING', 'DISCONNECTING'].includes(this.connectionState);
    const isConnected = this.connectionState === 'CONNECTED';

    this.vpnToggle.checked = isActive;

    if (isConnected) {
      // Connected state
      this.connectionStatus.textContent = 'Connected (Demo)';
      this.connectionStatus.className = 'connection-status connected';
      this.connectionDetails.style.display = 'block';
      this.downloadBtn.style.display = 'inline-flex';
      this.serverSelect.disabled = false; // Allow changing servers while connected
    } else if (this.connectionState === 'CONNECTING') {
      this.connectionStatus.textContent = 'Connecting...';
      this.connectionStatus.className = 'connection-status connecting';
      this.connectionDetails.style.display = 'block';
      this.downloadBtn.style.display = 'none';
      this.serverSelect.disabled = false;
    } else if (this.connectionState === 'DISCONNECTING') {
      this.connectionStatus.textContent = 'Disconnecting...';
      this.connectionStatus.className = 'connection-status disconnecting';
      this.connectionDetails.style.display = 'block';
      this.downloadBtn.style.display = 'none';
      this.serverSelect.disabled = false;
    } else {
      // Disconnected state
      this.connectionStatus.textContent = 'Disconnected';
      this.connectionStatus.className = 'connection-status disconnected';
      this.connectionDetails.style.display = 'none';
      this.downloadBtn.style.display = 'none';
      this.serverSelect.disabled = false;
    }
  }

  async downloadConfig() {
    try {
      const response = await fetch('/api/vpn/config', {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.accessToken}`
        }
      });
      if (!response.ok) {
        throw new Error('Failed to fetch config');
      }
      const data = await response.json();
      this.vpnConfig = data.config;
      const filename = `securewave-demo-${this.currentServer.location.toLowerCase().replace(/\s+/g, '-')}.conf`;
      this.downloadConfigFromText(this.vpnConfig, filename, true);
    } catch (error) {
      console.error('Failed to download config:', error);
      this.showAlert('Failed to download configuration file', 'error');
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
        this.setConnectionState('CONNECTED');
        if (!this.connectionStartTime && data.connected_since) {
          this.connectionStartTime = new Date(data.connected_since).getTime();
        }
        if (!this.connectionTimer) {
          this.startConnectionTracking();
        }
        this.updateConnectionDetails({
          location: data.region || (this.currentServer ? this.currentServer.location : 'Auto'),
          public_ip: data.mock_ip || '10.8.0.10'
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
        this.vpnConfig = null;
        this.connectionId = null;
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

  downloadConfigFromText(configText, filename, showAlert = true) {
    const blob = new Blob([configText], { type: 'text/plain' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);

    if (showAlert) {
      this.showAlert('VPN configuration downloaded successfully!', 'success');
    }
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
