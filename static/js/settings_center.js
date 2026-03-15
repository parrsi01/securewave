(function () {
  /* ── Helpers (same pattern as billing_center.js) ── */

  function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return '';
  }

  function safeJson(res) {
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('application/json')) return res.json().catch(() => ({}));
    return Promise.resolve({});
  }

  async function fetchJson(url, opts = {}) {
    const res = await fetch(url, { credentials: 'include', ...opts });
    const data = await safeJson(res);
    return { ok: res.ok, status: res.status, data };
  }

  function escapeHtml(value) {
    return String(value || '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function csrfHeaders(extra = {}) {
    return {
      'Content-Type': 'application/json',
      'X-CSRF-Token': getCookie('csrf_token'),
      ...extra,
    };
  }

  /* ── Toast notifications ── */

  function showToast(message, variant) {
    let container = document.querySelector('.toast-container');
    if (!container) {
      container = document.createElement('div');
      container.className = 'toast-container';
      document.body.appendChild(container);
    }
    const toast = document.createElement('div');
    toast.className = `toast ${variant || 'success'}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => { toast.remove(); }, 4000);
  }

  /* ── Inline form messages ── */

  function showFormMsg(form, message, isError) {
    let msg = form.querySelector('.form-message');
    if (!msg) {
      msg = document.createElement('div');
      msg.className = 'form-message';
      const actions = form.querySelector('.form-actions');
      if (actions) {
        form.insertBefore(msg, actions);
      } else {
        form.appendChild(msg);
      }
    }
    msg.textContent = message;
    msg.classList.toggle('error', !!isError);
    msg.classList.add('visible');
    setTimeout(() => { msg.classList.remove('visible'); }, 6000);
  }

  /* ── Modal helper (uses CSS .modal-overlay / .modal) ── */

  function openModal(title, bodyHtml) {
    closeModal();
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay open';
    overlay.innerHTML = `
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">${escapeHtml(title)}</span>
          <button class="modal-close" type="button" aria-label="Close">&times;</button>
        </div>
        <div class="modal-body">${bodyHtml}</div>
      </div>`;
    document.body.appendChild(overlay);
    overlay.querySelector('.modal-close').addEventListener('click', closeModal);
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) closeModal();
    });
    return overlay;
  }

  function closeModal() {
    const existing = document.querySelector('.modal-overlay');
    if (existing) existing.remove();
  }

  /* ── LocalStorage helpers ── */

  const LS_PREFIX = 'sw_settings_';

  function lsGet(key, fallback) {
    try {
      const v = localStorage.getItem(LS_PREFIX + key);
      if (v === null) return fallback;
      return JSON.parse(v);
    } catch { return fallback; }
  }

  function lsSet(key, value) {
    try { localStorage.setItem(LS_PREFIX + key, JSON.stringify(value)); } catch {}
  }

  /* ── Auth gate ── */

  async function ensureAuth() {
    const res = await fetch('/api/auth/me', { credentials: 'include' });
    if (!res.ok) {
      window.location.href = '/login';
      return null;
    }
    return res.json().catch(() => null);
  }

  /* ───────────────────────────────────────────────────
     Section: Profile
     ─────────────────────────────────────────────────── */

  function initProfile(user) {
    const emailEl = document.querySelector('[data-user-email]');
    if (emailEl) emailEl.value = user.email || '';

    const nameInput = document.getElementById('display-name');
    if (nameInput) nameInput.value = lsGet('display_name', '');

    const form = document.querySelector('[data-profile-form]');
    if (!form) return;

    form.addEventListener('submit', (e) => {
      e.preventDefault();
      if (nameInput) lsSet('display_name', nameInput.value);
      showToast('Profile saved.', 'success');
    });
  }

  /* ───────────────────────────────────────────────────
     Section: Password
     ─────────────────────────────────────────────────── */

  function initPassword() {
    const form = document.querySelector('[data-password-form]');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = form.querySelector('button[type="submit"]');

      const currentPassword = form.querySelector('#current-password').value;
      const newPassword = form.querySelector('#new-password').value;
      const confirmPassword = form.querySelector('#confirm-password').value;

      if (!currentPassword || !newPassword || !confirmPassword) {
        showFormMsg(form, 'All fields are required.', true);
        return;
      }

      if (newPassword !== confirmPassword) {
        showFormMsg(form, 'New passwords do not match.', true);
        return;
      }

      if (btn) btn.disabled = true;
      try {
        const resp = await fetchJson('/api/auth/update-password', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({
            current_password: currentPassword,
            new_password: newPassword,
          }),
        });

        if (resp.ok) {
          showFormMsg(form, resp.data.message || 'Password updated successfully.', false);
          form.reset();
        } else {
          showFormMsg(form, resp.data.detail || 'Failed to update password.', true);
        }
      } catch {
        showFormMsg(form, 'Network error. Please try again.', true);
      } finally {
        if (btn) btn.disabled = false;
      }
    });
  }

  /* ───────────────────────────────────────────────────
     Section: 2FA
     ─────────────────────────────────────────────────── */

  async function init2FA() {
    const toggle = document.querySelector('[data-toggle="2fa"]');
    if (!toggle) return;

    // Load current status
    try {
      const resp = await fetchJson('/api/auth/2fa/status');
      if (resp.ok) {
        toggle.checked = !!resp.data.enabled;
      }
    } catch {}

    toggle.addEventListener('change', async () => {
      if (toggle.checked) {
        await enable2FA(toggle);
      } else {
        await disable2FA(toggle);
      }
    });
  }

  async function enable2FA(toggle) {
    // Step 1: POST /2fa/setup
    const setupResp = await fetchJson('/api/auth/2fa/setup', {
      method: 'POST',
      headers: csrfHeaders(),
    });

    if (!setupResp.ok) {
      toggle.checked = false;
      showToast(setupResp.data.detail || 'Failed to start 2FA setup.', 'error');
      return;
    }

    const { secret, backup_codes, qr_code_url } = setupResp.data;

    // Step 2: Show modal with QR + verification input
    const backupList = (backup_codes || []).map((c) => `<code>${escapeHtml(c)}</code>`).join(' ');
    const bodyHtml = `
      <p style="margin-bottom:var(--sw-space-3)">Scan the QR code with your authenticator app:</p>
      <div style="text-align:center;margin-bottom:var(--sw-space-4)">
        <img src="${escapeHtml(qr_code_url)}" alt="2FA QR Code" width="200" height="200" style="border-radius:var(--sw-radius-md);background:#fff;padding:8px">
      </div>
      <p style="font-size:.85rem;margin-bottom:var(--sw-space-2)">Or enter manually: <code>${escapeHtml(secret)}</code></p>
      <div style="margin-bottom:var(--sw-space-4)">
        <p style="font-size:.85rem;margin-bottom:var(--sw-space-2)"><strong>Backup codes</strong> (save these):</p>
        <div style="font-size:.8rem;line-height:1.8;word-break:break-all">${backupList}</div>
      </div>
      <form data-2fa-verify-form>
        <div class="form-group">
          <label class="form-label" for="totp-code">Enter the 6-digit code from your app</label>
          <input class="form-input" type="text" id="totp-code" name="totp_code" autocomplete="one-time-code" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" required>
        </div>
        <div class="form-message"></div>
        <div class="form-actions">
          <button class="btn btn-primary" type="submit">Verify &amp; Enable</button>
          <button class="btn btn-ghost" type="button" data-2fa-cancel>Cancel</button>
        </div>
      </form>`;

    const overlay = openModal('Set up Two-Factor Authentication', bodyHtml);

    const verifyForm = overlay.querySelector('[data-2fa-verify-form]');
    const cancelBtn = overlay.querySelector('[data-2fa-cancel]');

    cancelBtn.addEventListener('click', () => {
      toggle.checked = false;
      closeModal();
    });

    // If modal closed via overlay/X, revert toggle
    overlay.querySelector('.modal-close').addEventListener('click', () => {
      toggle.checked = false;
    });

    verifyForm.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const code = verifyForm.querySelector('#totp-code').value.trim();
      if (!code) return;

      const submitBtn = verifyForm.querySelector('button[type="submit"]');
      if (submitBtn) submitBtn.disabled = true;

      try {
        const resp = await fetchJson('/api/auth/2fa/verify', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ totp_code: code }),
        });

        if (resp.ok) {
          closeModal();
          showToast('Two-factor authentication enabled.', 'success');
          // toggle stays checked
        } else {
          showFormMsg(verifyForm, resp.data.detail || 'Invalid code. Try again.', true);
          toggle.checked = false;
        }
      } catch {
        showFormMsg(verifyForm, 'Network error. Please try again.', true);
        toggle.checked = false;
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  async function disable2FA(toggle) {
    // Prompt for current TOTP code before disabling
    const bodyHtml = `
      <p style="margin-bottom:var(--sw-space-3)">Enter your current authenticator code or a backup code to disable 2FA.</p>
      <form data-2fa-disable-form>
        <div class="form-group">
          <label class="form-label" for="totp-disable-code">Verification code</label>
          <input class="form-input" type="text" id="totp-disable-code" name="totp_code" autocomplete="one-time-code" inputmode="numeric" maxlength="10" required>
        </div>
        <div class="form-message"></div>
        <div class="form-actions">
          <button class="btn btn-danger" type="submit">Disable 2FA</button>
          <button class="btn btn-ghost" type="button" data-2fa-disable-cancel>Cancel</button>
        </div>
      </form>`;

    const overlay = openModal('Disable Two-Factor Authentication', bodyHtml);

    const disableForm = overlay.querySelector('[data-2fa-disable-form]');
    const cancelBtn = overlay.querySelector('[data-2fa-disable-cancel]');

    cancelBtn.addEventListener('click', () => {
      toggle.checked = true;
      closeModal();
    });

    overlay.querySelector('.modal-close').addEventListener('click', () => {
      toggle.checked = true;
    });

    disableForm.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const code = disableForm.querySelector('#totp-disable-code').value.trim();
      if (!code) return;

      const submitBtn = disableForm.querySelector('button[type="submit"]');
      if (submitBtn) submitBtn.disabled = true;

      try {
        const resp = await fetchJson('/api/auth/2fa/disable', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ totp_code: code }),
        });

        if (resp.ok) {
          closeModal();
          showToast('Two-factor authentication disabled.', 'success');
          // toggle stays unchecked
        } else {
          showFormMsg(disableForm, resp.data.detail || 'Invalid code.', true);
          toggle.checked = true;
        }
      } catch {
        showFormMsg(disableForm, 'Network error. Please try again.', true);
        toggle.checked = true;
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  /* ───────────────────────────────────────────────────
     Section: Settings nav (smooth scroll + active highlight)
     ─────────────────────────────────────────────────── */

  function initSettingsNav() {
    const nav = document.querySelector('.settings-nav');
    if (!nav) return;

    const links = nav.querySelectorAll('a[href^="#"]');
    const sections = [];
    links.forEach((link) => {
      const id = link.getAttribute('href').slice(1);
      const section = document.getElementById(id);
      if (section) sections.push({ link, section });
    });

    // Scroll spy
    function updateActive() {
      const scrollY = window.scrollY + 120;
      let current = sections[0];
      for (const entry of sections) {
        if (entry.section.offsetTop <= scrollY) current = entry;
      }
      links.forEach((l) => l.classList.remove('active'));
      if (current) current.link.classList.add('active');
    }

    window.addEventListener('scroll', updateActive, { passive: true });
    updateActive();
  }

  /* ───────────────────────────────────────────────────
     Section: Connection settings (localStorage)
     ─────────────────────────────────────────────────── */

  function initConnectionSettings() {
    // Select-based settings
    const selects = document.querySelectorAll('[data-setting]');
    selects.forEach((sel) => {
      const key = sel.getAttribute('data-setting');
      const saved = lsGet(key, null);
      if (saved !== null) sel.value = saved;

      sel.addEventListener('change', () => {
        lsSet(key, sel.value);
        showToast('Setting saved.', 'success');
      });
    });

    // Toggle-based connection settings
    const connectionToggles = ['auto-connect', 'kill-switch'];
    connectionToggles.forEach((name) => {
      const input = document.querySelector(`[data-toggle="${name}"]`);
      if (!input) return;
      input.checked = lsGet(name, false);
      input.addEventListener('change', () => {
        lsSet(name, input.checked);
        showToast('Setting saved.', 'success');
      });
    });
  }

  /* ───────────────────────────────────────────────────
     Section: Notification toggles (localStorage)
     ─────────────────────────────────────────────────── */

  function initNotifications() {
    const notifToggles = ['email-notifications', 'security-alerts', 'marketing-emails'];
    const defaults = { 'email-notifications': true, 'security-alerts': true, 'marketing-emails': false };

    notifToggles.forEach((name) => {
      const input = document.querySelector(`[data-toggle="${name}"]`);
      if (!input) return;
      input.checked = lsGet(name, defaults[name]);
      input.addEventListener('change', () => {
        lsSet(name, input.checked);
        showToast('Notification preference saved.', 'success');
      });
    });
  }

  /* ───────────────────────────────────────────────────
     Section: Delete account
     ─────────────────────────────────────────────────── */

  function initDeleteAccount() {
    const btn = document.querySelector('[data-delete-account]');
    if (!btn) return;

    btn.addEventListener('click', async () => {
      const confirmed = window.confirm(
        'Are you sure you want to delete your account? This action cannot be undone.'
      );
      if (!confirmed) return;

      btn.disabled = true;
      try {
        const resp = await fetchJson('/api/auth/delete-account', {
          method: 'DELETE',
          headers: csrfHeaders(),
        });

        if (resp.ok) {
          showToast('Account deletion requested. You will be logged out.', 'success');
          setTimeout(() => { window.location.href = '/login'; }, 2000);
        } else if (resp.status === 404 || resp.status === 405) {
          // Endpoint does not exist yet
          showToast('Please contact support to delete your account: support@securewaveapp.com', 'error');
        } else {
          showToast(resp.data.detail || 'Failed to delete account.', 'error');
        }
      } catch {
        showToast('Please contact support to delete your account: support@securewaveapp.com', 'error');
      } finally {
        btn.disabled = false;
      }
    });
  }

  /* ───────────────────────────────────────────────────
     Init
     ─────────────────────────────────────────────────── */

  document.addEventListener('DOMContentLoaded', async () => {
    const user = await ensureAuth();
    if (!user) return;

    initProfile(user);
    initPassword();
    await init2FA();
    initSettingsNav();
    initConnectionSettings();
    initNotifications();
    initDeleteAccount();
  });
}());
