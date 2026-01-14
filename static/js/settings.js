// SecureWave Settings - local preference persistence

const SETTINGS_KEY = 'securewave_settings';

const DEFAULT_SETTINGS = {
  preferred_country: 'auto',
  preferred_region: 'auto',
  auto_connect: false,
  always_on: false,
  kill_switch: true,
  split_tunneling: false,
  protocol: 'wireguard',
  dns_provider: 'cloudflare'
};

function loadSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch (error) {
    console.error('Failed to load settings:', error);
    return { ...DEFAULT_SETTINGS };
  }
}

function saveSettings(settings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}

function applySettingsToUI(settings) {
  const inputs = document.querySelectorAll('[data-setting]');
  inputs.forEach(input => {
    const key = input.dataset.setting;
    if (!(key in settings)) return;
    if (input.type === 'checkbox') {
      input.checked = Boolean(settings[key]);
    } else {
      input.value = settings[key];
    }
  });
}

function collectSettingsFromUI() {
  const settings = loadSettings();
  const inputs = document.querySelectorAll('[data-setting]');
  inputs.forEach(input => {
    const key = input.dataset.setting;
    if (input.type === 'checkbox') {
      settings[key] = input.checked;
    } else {
      settings[key] = input.value;
    }
  });
  return settings;
}

function showSettingsToast(message, type = 'success') {
  if (typeof showToast === 'function') {
    showToast(message, type === 'success' ? 'success' : 'info');
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const settings = loadSettings();
  applySettingsToUI(settings);

  const accountEmail = document.getElementById('accountEmail');
  if (accountEmail) {
    fetch('/api/auth/me', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('access_token')}`
      }
    }).then(response => response.json()).then(data => {
      if (data.email) {
        accountEmail.textContent = data.email;
      }
    }).catch(() => {
      accountEmail.textContent = 'Unavailable';
    });
  }

  const inputs = document.querySelectorAll('[data-setting]');
  inputs.forEach(input => {
    input.addEventListener('change', () => {
      const updated = collectSettingsFromUI();
      saveSettings(updated);
      showSettingsToast('Settings updated');
    });
  });

  const resetBtn = document.getElementById('resetSettings');
  if (resetBtn) {
    resetBtn.addEventListener('click', () => {
      saveSettings(DEFAULT_SETTINGS);
      applySettingsToUI(DEFAULT_SETTINGS);
      showSettingsToast('Settings reset');
    });
  }

  const settingsLogout = document.getElementById('settingsLogout');
  if (settingsLogout) {
    settingsLogout.addEventListener('click', async () => {
      try {
        await fetch('/api/auth/logout', { method: 'POST' });
      } catch (error) {
        // no-op
      } finally {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        window.location.href = '/login.html';
      }
    });
  }
});
