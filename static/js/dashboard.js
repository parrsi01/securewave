function formatPlanLabel(status, subscription) {
  if (subscription?.is_active || status === 'active') return 'Premium';
  if (status === 'basic') return 'Starter (Free)';
  if (status === 'inactive') return 'Inactive';
  return 'Starter (Free)';
}

function getCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
  return '';
}

/* ── Anomaly Detection Client ── */
const AnomalyDetector = {
  _indicator: null,

  init() {
    this._indicator = document.querySelector('.anomaly-indicator');
    this.check();
    // Re-check every 60 seconds
    setInterval(() => this.check(), 60000);
  },

  async check() {
    if (!this._indicator) return;
    try {
      const csrfToken = getCookie('csrf_token');
      const res = await fetch('/api/optimizer/stats', {
        credentials: 'include',
        headers: { 'X-CSRF-Token': csrfToken },
      });
      if (!res.ok) {
        this.setStatus('safe', 'Network Monitored');
        return;
      }
      const data = await res.json();
      const stats = data.optimizer_stats || {};

      // Evaluate risk based on optimizer metrics
      if (stats.ml_enabled) {
        const avgLoss = stats.avg_packet_loss || 0;
        const avgLatency = stats.avg_latency_ms || 0;
        if (avgLoss > 0.1 || avgLatency > 500) {
          this.setStatus('critical', 'Anomaly Detected');
        } else if (avgLoss > 0.05 || avgLatency > 300) {
          this.setStatus('warning', 'Elevated Risk');
        } else {
          this.setStatus('safe', 'Network Safe');
        }
      } else {
        this.setStatus('safe', 'Network Monitored');
      }
    } catch {
      this.setStatus('safe', 'Network Monitored');
    }
  },

  setStatus(level, text) {
    if (!this._indicator) return;
    this._indicator.classList.remove('safe', 'warning', 'critical');
    this._indicator.classList.add(level);
    const label = this._indicator.querySelector('.anomaly-text');
    if (label) label.textContent = text;
  },
};

document.addEventListener('DOMContentLoaded', async () => {
  let sessionEmail = localStorage.getItem('user_email') || 'you@example.com';
  try {
    const sessionRes = await fetch('/api/auth/me', { credentials: 'include' });
    if (!sessionRes.ok) {
      window.location.href = '/login';
      return;
    }
    const sessionData = await sessionRes.json().catch(() => ({}));
    if (sessionData.email) {
      sessionEmail = sessionData.email;
    }
  } catch (error) {
    window.location.href = '/login';
    return;
  }

  const emailEl = document.querySelector('[data-user-email]');
  if (emailEl) {
    emailEl.textContent = sessionEmail;
  }

  const planEl = document.querySelector('[data-plan-label]');
  try {
    const res = await fetch('/api/dashboard/info', {
      credentials: 'include',
    });
    if (res.ok) {
      const data = await res.json().catch(() => ({}));
      if (planEl) {
        planEl.textContent = formatPlanLabel(data.subscription_status, data.subscription);
      }
    }
  } catch (error) {
    if (planEl) {
      planEl.textContent = formatPlanLabel('basic', null);
    }
  }

  // Initialize anomaly detection
  AnomalyDetector.init();
});
