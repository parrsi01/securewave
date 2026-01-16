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

function setMessageVisibility(id, visible) {
  const el = document.getElementById(id);
  if (el) {
    el.classList.toggle('hidden', !visible);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const settings = loadSettings();
  applySettingsToUI(settings);
  const accessToken = localStorage.getItem('access_token');

  // CRITICAL: Immediate auth guard - redirect if no token exists
  if (!accessToken) {
    window.location.href = '/login.html?redirect=/settings.html';
    return;
  }

  const accountEmail = document.getElementById('accountEmail');
  if (accountEmail) {
    fetch('/api/auth/me', {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    }).then(response => {
      if (!response.ok) {
        if (response.status === 401) {
          // Token invalid - clear and redirect
          localStorage.removeItem('access_token');
          localStorage.removeItem('refresh_token');
          window.location.href = '/login.html?redirect=/settings.html';
        }
        return null;
      }
      return response.json();
    }).then(data => {
      if (data && data.email) {
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
  let resetArmed = false;
  if (resetBtn) {
    resetBtn.addEventListener('click', () => {
      if (!resetArmed) {
        resetArmed = true;
        showSettingsToast('Click reset again to confirm', 'info');
        setTimeout(() => {
          resetArmed = false;
        }, 4000);
        return;
      }
      resetArmed = false;
      saveSettings(DEFAULT_SETTINGS);
      applySettingsToUI(DEFAULT_SETTINGS);
      showSettingsToast('Settings reset');
    });
  }

  const emailUpdateForm = document.getElementById('emailUpdateForm');
  if (emailUpdateForm) {
    emailUpdateForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      setMessageVisibility('emailUpdateSuccess', false);
      setMessageVisibility('emailUpdateError', false);
      const newEmail = document.getElementById('newEmail').value.trim();
      const password = document.getElementById('emailPassword').value;
      const updateEmailBtn = document.getElementById('updateEmailBtn');

      if (!accessToken) {
        window.location.href = '/login.html?redirect=/settings.html';
        return;
      }

      if (!newEmail || !password) {
        setMessageVisibility('emailUpdateError', true);
        return;
      }

      updateEmailBtn.disabled = true;
      updateEmailBtn.textContent = 'Updating...';

      try {
        const response = await fetch('/api/auth/update-email', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`
          },
          body: JSON.stringify({ new_email: newEmail, password })
        });

        const data = await response.json();
        if (!response.ok) {
          setMessageVisibility('emailUpdateError', true);
          showSettingsToast(data.detail || 'Unable to update email', 'info');
          return;
        }

        if (data.access_token) {
          localStorage.setItem('access_token', data.access_token);
        }
        if (data.refresh_token) {
          localStorage.setItem('refresh_token', data.refresh_token);
        }
        if (accountEmail) {
          accountEmail.textContent = newEmail;
        }
        emailUpdateForm.reset();
        setMessageVisibility('emailUpdateSuccess', true);
        showSettingsToast('Email updated');
      } catch (error) {
        setMessageVisibility('emailUpdateError', true);
        showSettingsToast('Unable to update email', 'info');
      } finally {
        updateEmailBtn.disabled = false;
        updateEmailBtn.textContent = 'Update Email';
      }
    });
  }

  const passwordUpdateForm = document.getElementById('passwordUpdateForm');
  if (passwordUpdateForm) {
    passwordUpdateForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      setMessageVisibility('passwordUpdateSuccess', false);
      setMessageVisibility('passwordUpdateError', false);
      setMessageVisibility('passwordMismatchError', false);

      const currentPassword = document.getElementById('currentPassword').value;
      const newPassword = document.getElementById('newPassword').value;
      const confirmPassword = document.getElementById('confirmPassword').value;
      const updatePasswordBtn = document.getElementById('updatePasswordBtn');

      if (!accessToken) {
        window.location.href = '/login.html?redirect=/settings.html';
        return;
      }

      if (newPassword.length < 8 || !currentPassword) {
        setMessageVisibility('passwordUpdateError', true);
        return;
      }

      if (newPassword !== confirmPassword) {
        setMessageVisibility('passwordMismatchError', true);
        return;
      }

      updatePasswordBtn.disabled = true;
      updatePasswordBtn.textContent = 'Updating...';

      try {
        const response = await fetch('/api/auth/update-password', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`
          },
          body: JSON.stringify({ current_password: currentPassword, new_password: newPassword })
        });

        const data = await response.json();
        if (!response.ok) {
          setMessageVisibility('passwordUpdateError', true);
          showSettingsToast(data.detail || 'Unable to update password', 'info');
          return;
        }

        passwordUpdateForm.reset();
        setMessageVisibility('passwordUpdateSuccess', true);
        showSettingsToast('Password updated');
      } catch (error) {
        setMessageVisibility('passwordUpdateError', true);
        showSettingsToast('Unable to update password', 'info');
      } finally {
        updatePasswordBtn.disabled = false;
        updatePasswordBtn.textContent = 'Update Password';
      }
    });
  }

  const logoutAllBtn = document.getElementById('logoutAllBtn');
  let logoutAllArmed = false;
  if (logoutAllBtn) {
    logoutAllBtn.addEventListener('click', async () => {
      if (!logoutAllArmed) {
        logoutAllArmed = true;
        showSettingsToast('Click again to confirm logout all sessions', 'info');
        setTimeout(() => {
          logoutAllArmed = false;
        }, 4000);
        return;
      }

      logoutAllArmed = false;
      try {
        // Include auth header so server knows which user's sessions to invalidate
        await fetch('/api/auth/logout-all', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`
          }
        });
      } catch (error) {
        // no-op - continue with local logout
      } finally {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        window.location.href = '/login.html';
      }
    });
  }

  const settingsLogout = document.getElementById('settingsLogout');
  if (settingsLogout) {
    settingsLogout.addEventListener('click', async () => {
      try {
        // Include auth header for proper session invalidation
        await fetch('/api/auth/logout', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`
          }
        });
      } catch (error) {
        // no-op - continue with local logout
      } finally {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        window.location.href = '/login.html';
      }
    });
  }
});
