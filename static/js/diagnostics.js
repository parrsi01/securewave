document.addEventListener('DOMContentLoaded', async () => {
  const healthStatus = document.getElementById('healthStatus');
  const envStatus = document.getElementById('envStatus');
  const eventsList = document.getElementById('eventsList');

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
