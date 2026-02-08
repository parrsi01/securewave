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

function safeJson(res) {
  return res.json().catch(() => ({}));
}

function formatBytesFromMb(mb) {
  const n = Number(mb || 0);
  if (Number.isNaN(n)) return '--';
  if (n < 1024) return `${n.toFixed(0)} MB`;
  return `${(n / 1024).toFixed(2)} GB`;
}

function relativeTime(iso) {
  if (!iso) return 'Never';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return 'Unknown';
  const diffMs = Date.now() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'Just now';
  if (diffMin < 60) return `${diffMin} min ago`;
  const diffH = Math.floor(diffMin / 60);
  if (diffH < 24) return `${diffH} hr ago`;
  const diffD = Math.floor(diffH / 24);
  return `${diffD} d ago`;
}

function isOnline(lastHandshakeIso) {
  if (!lastHandshakeIso) return false;
  const date = new Date(lastHandshakeIso);
  if (Number.isNaN(date.getTime())) return false;
  return Date.now() - date.getTime() < 5 * 60 * 1000; // 5 minutes
}

async function fetchJson(url, opts = {}) {
  const res = await fetch(url, { credentials: 'include', ...opts });
  if (!res.ok) throw new Error(`${url} -> ${res.status}`);
  return safeJson(res);
}

function setText(sel, text) {
  const el = document.querySelector(sel);
  if (el) el.textContent = text;
}

function buildServerOptions(servers, selectedId) {
  const options = [];
  options.push(`<option value="auto"${selectedId ? '' : ' selected'}>Auto (fastest)</option>`);
  (servers || []).forEach((s) => {
    const id = s.server_id || s.id;
    const label = s.location || s.name || id;
    const selected = selectedId && id === selectedId ? ' selected' : '';
    if (!id) return;
    options.push(`<option value="${id}"${selected}>${label}</option>`);
  });
  return options.join('');
}

async function updateDeviceServer(deviceId, serverId) {
  const csrf = getCookie('csrf_token');
  return fetchJson(`/api/vpn/devices/${deviceId}/server`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
    body: JSON.stringify({ server_id: serverId }),
  });
}

async function revokeDevice(deviceId) {
  const csrf = getCookie('csrf_token');
  const res = await fetch(`/api/vpn/devices/${deviceId}`, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': csrf },
    credentials: 'include',
  });
  if (!res.ok) throw new Error(`revoke -> ${res.status}`);
}

function renderDevices({ devices = [], servers = [] }) {
  const tbody = document.querySelector('[data-devices-body]');
  if (!tbody) return;

  if (!Array.isArray(devices) || devices.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="6">No devices registered yet. Install the app and connect once to register this device automatically.</td></tr>';
    return;
  }

  tbody.innerHTML = devices
    .map((d) => {
      const name = d.name || `Device #${d.id}`;
      const type = d.device_type || '--';
      const last = d.last_handshake || null;
      const status = isOnline(last) ? 'Online' : (last ? 'Offline' : 'Not connected yet');
      const statusBadge = isOnline(last) ? 'badge-primary' : 'badge-muted';
      const serverId = d.server_id || null;
      const optionsHtml = buildServerOptions(servers, serverId);
      return `
        <tr data-device-row="${d.id}">
          <td><strong>${name}</strong><br><span class="muted">${d.ip_address || ''}</span></td>
          <td>${type}</td>
          <td><span class="badge ${statusBadge}">${status}</span></td>
          <td>${relativeTime(last)}</td>
          <td>
            <select class="form-select" data-device-server="${d.id}">
              ${optionsHtml}
            </select>
          </td>
          <td style="text-align:right">
            <button class="btn btn-ghost btn-sm" type="button" data-device-revoke="${d.id}">Revoke</button>
          </td>
        </tr>
      `;
    })
    .join('');

  // Bind server preference updates
  tbody.querySelectorAll('[data-device-server]').forEach((selectEl) => {
    selectEl.addEventListener('change', async (e) => {
      const el = e.currentTarget;
      const id = el.getAttribute('data-device-server');
      if (!id) return;
      const next = el.value === 'auto' ? null : el.value;
      el.disabled = true;
      try {
        await updateDeviceServer(id, next);
      } catch (_) {
        // Revert on failure
        el.value = 'auto';
      } finally {
        el.disabled = false;
      }
    });
  });

  // Bind revocation
  tbody.querySelectorAll('[data-device-revoke]').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      const el = e.currentTarget;
      const id = el.getAttribute('data-device-revoke');
      if (!id) return;
      const ok = window.confirm('Revoke this device? It will no longer be able to connect.');
      if (!ok) return;
      el.disabled = true;
      try {
        await revokeDevice(id);
        const row = tbody.querySelector(`[data-device-row="${id}"]`);
        if (row) row.remove();
      } catch (_) {
        el.disabled = false;
      }
    });
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  // Enforce auth on this page (cookie session).
  const meRes = await fetch('/api/auth/me', { credentials: 'include' });
  if (!meRes.ok) {
    window.location.href = '/login';
    return;
  }
  const me = await safeJson(meRes);
  if (me?.email) {
    setText('[data-user-email]', me.email);
  }

  // Fetch all dashboard data in parallel.
  const results = await Promise.allSettled([
    fetchJson('/api/dashboard/info'),
    fetchJson('/api/vpn/devices'),
    fetchJson('/api/vpn/usage'),
    fetchJson('/api/vpn/servers'),
    fetchJson('/api/health'),
    fetchJson('/api/ready'),
    fetchJson('/api/vpn/health'),
  ]);

  const dashInfo = results[0].status === 'fulfilled' ? results[0].value : {};
  const devicesResp = results[1].status === 'fulfilled' ? results[1].value : {};
  const usageResp = results[2].status === 'fulfilled' ? results[2].value : {};
  const serversResp = results[3].status === 'fulfilled' ? results[3].value : {};
  const apiHealth = results[4].status === 'fulfilled' ? results[4].value : null;
  const ready = results[5].status === 'fulfilled' ? results[5].value : null;
  const fleet = results[6].status === 'fulfilled' ? results[6].value : null;

  const planLabel = formatPlanLabel(dashInfo.subscription_status, dashInfo.subscription);
  setText('[data-metric="plan"]', planLabel);

  const devices = Array.isArray(devicesResp.devices) ? devicesResp.devices : [];
  setText('[data-metric="devices"]', `${devices.length}`);
  setText('[data-device-count]', `${devices.length} device${devices.length === 1 ? '' : 's'}`);

  const sent = Number(usageResp.total_data_sent_mb || 0);
  const recv = Number(usageResp.total_data_received_mb || 0);
  setText('[data-metric="data-used"]', formatBytesFromMb(sent + recv));

  const servers = Array.isArray(serversResp.servers) ? serversResp.servers : (Array.isArray(serversResp) ? serversResp : []);
  renderDevices({ devices, servers });

  // Backend status widgets
  setText('[data-backend-api]', apiHealth?.status === 'ok' ? 'OK' : 'Unavailable');
  setText('[data-backend-db]', ready?.status === 'ready' ? 'Connected' : 'Unavailable');
  if (fleet?.summary) {
    const s = fleet.summary;
    const ok = typeof fleet.status === 'string' ? fleet.status : 'unknown';
    setText('[data-backend-fleet]', `${ok.toUpperCase()} (${s.healthy || 0} healthy)`);
  } else if (servers && servers.length > 0) {
    setText('[data-backend-fleet]', `OK (${servers.length} servers)`);
  } else {
    setText('[data-backend-fleet]', 'No servers');
  }
});

