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

function escapeHtml(input) {
  return String(input || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

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

  // Plan label
  const planEl = document.querySelector('[data-plan-label]');
  try {
    const res = await fetch('/api/dashboard/info', { credentials: 'include' });
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

  // Device count & sessions
  const csrfToken = getCookie('csrf_token');
  try {
    const devRes = await fetch('/api/vpn/devices', {
      credentials: 'include',
      headers: { 'X-CSRF-Token': csrfToken },
    });
    if (devRes.ok) {
      const devData = await devRes.json().catch(() => ({ devices: [] }));
      const devices = Array.isArray(devData.devices) ? devData.devices : [];
      const countEl = document.querySelector('[data-metric="device-count"]');
      if (countEl) countEl.textContent = devices.length;

      const sessionCountEl = document.querySelector('[data-session-count]');
      const sessionsBody = document.querySelector('[data-sessions-body]');
      const activeSessions = devices.filter(d => {
        if (!d.last_handshake) return false;
        const handshakeAge = (Date.now() / 1000) - new Date(d.last_handshake).getTime() / 1000;
        return handshakeAge < 300;
      });

      const activeCountEl = document.querySelector('[data-metric="active-sessions"]');
      if (activeCountEl) activeCountEl.textContent = activeSessions.length;
      if (sessionCountEl) sessionCountEl.textContent = `${devices.length} device${devices.length !== 1 ? 's' : ''}`;

      if (sessionsBody) {
        if (devices.length === 0) {
          sessionsBody.innerHTML = '<tr><td colspan="4">No devices registered. <a href="/download">Download the app</a> to get started.</td></tr>';
        } else {
          sessionsBody.innerHTML = devices.map(d => {
            const isOnline = d.last_handshake && ((Date.now() / 1000) - new Date(d.last_handshake).getTime() / 1000 < 300);
            const statusBadge = isOnline
              ? '<span class="badge badge-success">Online</span>'
              : '<span class="badge badge-muted">Offline</span>';
            const lastSeen = d.last_handshake
              ? new Date(d.last_handshake).toLocaleString()
              : 'Never';
            return `<tr>
              <td>${escapeHtml(d.name || d.device_name || 'Unknown')}</td>
              <td>${escapeHtml(d.device_type || d.type || '--')}</td>
              <td>${statusBadge}</td>
              <td>${escapeHtml(lastSeen)}</td>
            </tr>`;
          }).join('');
        }
      }
    }
  } catch (error) {
    const countEl = document.querySelector('[data-metric="device-count"]');
    if (countEl) countEl.textContent = '--';
  }

  // Backend health
  async function checkBackend(url, el) {
    if (!el) return;
    try {
      const res = await fetch(url, { credentials: 'include' });
      el.textContent = res.ok ? 'Online' : 'Degraded';
      el.style.color = res.ok ? 'var(--success)' : 'var(--warning)';
    } catch {
      el.textContent = 'Unreachable';
      el.style.color = 'var(--danger)';
    }
  }

  checkBackend('/api/health', document.querySelector('[data-backend-api]'));
  checkBackend('/api/health', document.querySelector('[data-backend-db]'));
  checkBackend('/api/vpn/servers', document.querySelector('[data-backend-fleet]'));
});
