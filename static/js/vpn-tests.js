/**
 * SecureWave VPN Test Suite - Frontend Integration
 *
 * Provides UI controls for running VPN performance tests
 * and displaying results on the dashboard.
 */

const VPNTests = {
    // State
    isRunning: false,
    pollInterval: null,

    // API endpoints
    endpoints: {
        status: '/api/vpn/tests/status',
        latest: '/api/vpn/tests/latest',
        run: '/api/vpn/tests/run',
        runSync: '/api/vpn/tests/run/sync'
    },

    /**
     * Initialize the VPN test module
     */
    init() {
        this.bindEvents();
        this.checkStatus();
    },

    /**
     * Bind event listeners
     */
    bindEvents() {
        const runBtn = document.getElementById('run-vpn-test-btn');
        if (runBtn) {
            runBtn.addEventListener('click', () => this.runTests());
        }

        const quickBtn = document.getElementById('run-vpn-test-quick-btn');
        if (quickBtn) {
            quickBtn.addEventListener('click', () => this.runTests(true));
        }
    },

    /**
     * Get auth token from storage
     */
    getToken() {
        return localStorage.getItem('access_token') || sessionStorage.getItem('access_token');
    },

    /**
     * Make authenticated API request
     */
    async apiRequest(endpoint, options = {}) {
        const token = this.getToken();
        const headers = {
            'Content-Type': 'application/json',
            ...options.headers
        };

        if (token) {
            headers['Authorization'] = `Bearer ${token}`;
        }

        const response = await fetch(endpoint, {
            ...options,
            headers
        });

        if (!response.ok) {
            const error = await response.json().catch(() => ({ detail: 'Request failed' }));
            throw new Error(error.detail || `HTTP ${response.status}`);
        }

        return response.json();
    },

    /**
     * Check current test status
     */
    async checkStatus() {
        try {
            const status = await this.apiRequest(this.endpoints.status);

            this.isRunning = status.running;
            this.updateUI(status);

            if (status.has_results) {
                await this.loadLatestResults();
            }

            if (status.running) {
                this.startPolling();
            }
        } catch (error) {
            console.error('Failed to check test status:', error);
        }
    },

    /**
     * Load and display latest results
     */
    async loadLatestResults() {
        try {
            const results = await this.apiRequest(this.endpoints.latest);
            this.displayResults(results);
        } catch (error) {
            console.error('Failed to load test results:', error);
        }
    },

    /**
     * Run VPN tests
     */
    async runTests(quick = false) {
        if (this.isRunning) {
            this.showNotification('Tests are already running', 'warning');
            return;
        }

        const container = document.getElementById('vpn-test-results');
        if (container) {
            container.innerHTML = this.renderLoading(quick);
        }

        this.setButtonState(true);

        try {
            const response = await this.apiRequest(this.endpoints.run, {
                method: 'POST',
                body: JSON.stringify({
                    quick: quick,
                    skip_baseline: false,
                    stability_duration: quick ? 10 : 30
                })
            });

            if (response.status === 'started') {
                this.isRunning = true;
                this.startPolling();
                this.showNotification('VPN tests started. This may take 1-2 minutes.', 'info');
            } else if (response.status === 'running') {
                this.startPolling();
                this.showNotification('Tests already running. Please wait.', 'warning');
            }
        } catch (error) {
            console.error('Failed to start tests:', error);
            this.showNotification(`Failed to start tests: ${error.message}`, 'error');
            this.setButtonState(false);
        }
    },

    /**
     * Start polling for test completion
     */
    startPolling() {
        if (this.pollInterval) return;

        this.pollInterval = setInterval(async () => {
            try {
                const status = await this.apiRequest(this.endpoints.status);

                if (!status.running) {
                    this.stopPolling();
                    this.isRunning = false;
                    this.setButtonState(false);
                    await this.loadLatestResults();
                    this.showNotification('VPN tests completed!', 'success');
                }
            } catch (error) {
                console.error('Polling error:', error);
            }
        }, 3000);
    },

    /**
     * Stop polling
     */
    stopPolling() {
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
        }
    },

    /**
     * Update UI based on status
     */
    updateUI(status) {
        this.setButtonState(status.running);

        const lastRunEl = document.getElementById('vpn-test-last-run');
        if (lastRunEl && status.last_run) {
            const date = new Date(status.last_run);
            lastRunEl.textContent = `Last run: ${date.toLocaleString()}`;
        }
    },

    /**
     * Set button loading state
     */
    setButtonState(loading) {
        const runBtn = document.getElementById('run-vpn-test-btn');
        const quickBtn = document.getElementById('run-vpn-test-quick-btn');

        if (runBtn) {
            runBtn.disabled = loading;
            runBtn.innerHTML = loading
                ? '<span class="spinner"></span> Running...'
                : 'Run Full Test';
        }

        if (quickBtn) {
            quickBtn.disabled = loading;
        }
    },

    /**
     * Display test results
     */
    displayResults(results) {
        const container = document.getElementById('vpn-test-results');
        if (!container) return;

        container.innerHTML = this.renderResults(results);
    },

    /**
     * Render loading state
     */
    renderLoading(quick) {
        const duration = quick ? '30-60 seconds' : '1-2 minutes';
        return `
            <div class="test-loading">
                <div class="spinner-large"></div>
                <p>Running VPN performance tests...</p>
                <p class="text-muted">This may take ${duration}</p>
                <div class="test-progress">
                    <div class="progress-steps">
                        <span class="step active">Latency</span>
                        <span class="step">Throughput</span>
                        <span class="step">DNS Leak</span>
                        <span class="step">IPv6 Leak</span>
                        <span class="step">Ad Blocking</span>
                        <span class="step">Stability</span>
                    </div>
                </div>
            </div>
        `;
    },

    /**
     * Render test results
     */
    renderResults(results) {
        const statusClass = results.status === 'PASSED' ? 'success' : 'danger';
        const scoreClass = results.overall_score >= 70 ? 'success' :
                          results.overall_score >= 50 ? 'warning' : 'danger';

        return `
            <div class="test-results">
                <div class="test-header">
                    <div class="test-score ${scoreClass}">
                        <span class="score-value">${Math.round(results.overall_score)}</span>
                        <span class="score-label">/100</span>
                    </div>
                    <div class="test-status ${statusClass}">
                        ${results.status}
                    </div>
                </div>

                ${results.message ? `<div class="config-status warning">${results.message}</div>` : ''}

                <div class="test-vpn-info">
                    ${results.vpn_detected
                        ? `<span class="badge badge-success">VPN Active: ${results.vpn_interface}</span>`
                        : '<span class="badge badge-warning">No VPN Detected</span>'
                    }
                </div>

                <div class="test-metrics">
                    <div class="metric">
                        <div class="metric-label">Latency</div>
                        <div class="metric-value">${results.latency_ms.toFixed(1)} ms</div>
                        ${results.latency_increase_ms != null
                            ? `<div class="metric-change ${results.latency_increase_ms > 30 ? 'bad' : 'good'}">
                                 +${results.latency_increase_ms.toFixed(1)} ms
                               </div>`
                            : ''
                        }
                    </div>

                    <div class="metric">
                        <div class="metric-label">Download</div>
                        <div class="metric-value">${results.throughput_mbps.toFixed(1)} Mbps</div>
                        ${results.throughput_retained_percent != null
                            ? `<div class="metric-change ${results.throughput_retained_percent < 70 ? 'bad' : 'good'}">
                                 ${results.throughput_retained_percent.toFixed(0)}% retained
                               </div>`
                            : ''
                        }
                    </div>

                    <div class="metric">
                        <div class="metric-label">DNS Leak</div>
                        <div class="metric-value ${results.dns_leak_detected ? 'text-danger' : 'text-success'}">
                            ${results.dns_leak_detected ? 'DETECTED' : 'NONE'}
                        </div>
                    </div>

                    <div class="metric">
                        <div class="metric-label">IPv6 Leak</div>
                        <div class="metric-value ${results.ipv6_leak_detected ? 'text-danger' : 'text-success'}">
                            ${results.ipv6_leak_detected ? 'DETECTED' : 'NONE'}
                        </div>
                    </div>

                    <div class="metric">
                        <div class="metric-label">Ads Blocked</div>
                        <div class="metric-value">${results.ads_blocked_percent.toFixed(0)}%</div>
                    </div>

                    <div class="metric">
                        <div class="metric-label">Trackers Blocked</div>
                        <div class="metric-value">${results.trackers_blocked_percent.toFixed(0)}%</div>
                    </div>

                    <div class="metric">
                        <div class="metric-label">Tunnel Stability</div>
                        <div class="metric-value">${results.uptime_percent.toFixed(1)}%</div>
                        <div class="metric-change">
                            ${results.tunnel_drops} drops
                        </div>
                    </div>
                </div>

                <div class="test-footer">
                    <span class="test-duration">
                        Test completed in ${results.test_duration_seconds.toFixed(0)}s
                    </span>
                    <span class="test-timestamp">
                        ${new Date(results.timestamp).toLocaleString()}
                    </span>
                </div>
            </div>
        `;
    },

    /**
     * Show notification
     */
    showNotification(message, type = 'info') {
        // Try to use existing notification system
        if (typeof showToast === 'function') {
            showToast(message, type);
            return;
        }

        // Fallback: console log
        console.log(`[${type.toUpperCase()}] ${message}`);

        // Fallback: alert for errors
        if (type === 'error') {
            alert(message);
        }
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Only initialize on pages with the test container
    if (document.getElementById('vpn-test-results') ||
        document.getElementById('run-vpn-test-btn')) {
        VPNTests.init();
    }
});

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = VPNTests;
}
