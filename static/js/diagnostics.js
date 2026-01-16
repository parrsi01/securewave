document.addEventListener('DOMContentLoaded', async () => {
  const healthStatus = document.getElementById('healthStatus');
  const envStatus = document.getElementById('envStatus');
  const eventsList = document.getElementById('eventsList');
  const sessionStatus = document.getElementById('sessionStatus');

  try {
    const health = await fetch('/health');
    if (health.ok) {
      const data = await health.json();
      healthStatus.textContent = `${data.status} (${data.service})`;
    } else {
      healthStatus.textContent = 'Health check failed';
    }
  } catch (error) {
    healthStatus.textContent = 'Health check failed';
  }

  try {
    const response = await fetch('/api/diagnostics/summary', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('access_token')}`
      }
    });
    if (response.ok) {
      const data = await response.json();
      envStatus.innerHTML = `
        <div><strong>Environment:</strong> ${data.environment}</div>
        <div><strong>Demo Mode:</strong> ${data.demo_mode ? 'enabled' : 'disabled'}</div>
        <div><strong>Database:</strong> ${data.database}</div>
      `;
    } else if (response.status === 401) {
      window.location.href = '/login.html?redirect=/diagnostics.html';
    } else {
      envStatus.textContent = 'Failed to load diagnostics.';
    }
  } catch (error) {
    envStatus.textContent = 'Failed to load diagnostics.';
  }

  try {
    const response = await fetch('/api/diagnostics/debug/session', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('access_token')}`
      }
    });
    if (response.ok) {
      const data = await response.json();
      const vpn = data.vpn_session || {};
      const optimizer = data.optimizer || {};
      sessionStatus.innerHTML = `
        <div><strong>User:</strong> ${data.user?.email || 'Unknown'}</div>
        <div><strong>VPN Status:</strong> ${vpn.status || 'unknown'}</div>
        <div><strong>Region:</strong> ${vpn.region || 'n/a'}</div>
        <div><strong>Assigned Node:</strong> ${vpn.assigned_node || 'n/a'}</div>
        <div><strong>Optimizer:</strong> ${optimizer.error ? 'Unavailable' : 'Active'}</div>
      `;
    } else if (response.status === 401) {
      window.location.href = '/login.html?redirect=/diagnostics.html';
    } else {
      sessionStatus.textContent = 'Failed to load session snapshot.';
    }
  } catch (error) {
    if (sessionStatus) {
      sessionStatus.textContent = 'Failed to load session snapshot.';
    }
  }

  try {
    const response = await fetch('/api/diagnostics/events', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('access_token')}`
      }
    });
    if (response.ok) {
      const data = await response.json();
      if (!data.length) {
        eventsList.textContent = 'No recent events.';
        return;
      }
      const list = document.createElement('ul');
      list.style.paddingLeft = '1rem';
      data.forEach(event => {
        const li = document.createElement('li');
        li.textContent = `${event.created_at || 'now'} · ${event.event_type} · ${event.description}`;
        list.appendChild(li);
      });
      eventsList.innerHTML = '';
      eventsList.appendChild(list);
    } else if (response.status === 401) {
      window.location.href = '/login.html?redirect=/diagnostics.html';
    } else {
      eventsList.textContent = 'Failed to load events.';
    }
  } catch (error) {
    eventsList.textContent = 'Failed to load events.';
  }
});
