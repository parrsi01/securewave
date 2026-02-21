function escapeHtml(input) {
  return String(input || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function platformLabel(platform) {
  switch ((platform || '').toLowerCase()) {
    case 'windows':
      return 'Windows';
    case 'macos':
      return 'macOS';
    case 'linux':
      return 'Linux';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iOS';
    default:
      return platform || 'Unknown';
  }
}

function formatLabel(entry) {
  const platform = platformLabel(entry.platform);
  const arch = entry.architecture ? ` (${entry.architecture})` : '';
  const format = entry.format ? ` • ${String(entry.format).toUpperCase()}` : '';
  return `${platform}${arch}${format}`;
}

function renderDetails(entry) {
  const details = [];

  if (entry.size_display) {
    details.push(`Size: ${escapeHtml(entry.size_display)}`);
  }

  if (entry.build_date) {
    details.push(`Built: ${escapeHtml(entry.build_date)}`);
  }

  if (entry.checksum_sha256) {
    details.push(`SHA256: <code>${escapeHtml(entry.checksum_sha256)}</code>`);
  }

  if (typeof entry.signed === 'boolean') {
    details.push(`Signed: ${entry.signed ? 'Yes' : 'No'}`);
  }

  if (entry.signing_notes) {
    details.push(escapeHtml(entry.signing_notes));
  }

  if (details.length === 0) {
    return '';
  }

  return `<p class="muted" style="margin-top: var(--space-2); margin-bottom: 0">${details.join('<br>')}</p>`;
}

function renderCard(entry) {
  const title = formatLabel(entry);
  const status = entry.status === 'available' ? 'Available' : 'Unavailable';
  const badgeClass = entry.status === 'available' ? 'badge-primary' : 'badge-muted';
  const notes = entry.notes ? `<p class="muted" style="margin-top: var(--space-2)">${escapeHtml(entry.notes)}</p>` : '';

  const action = entry.status === 'available' && entry.url
    ? `<a class="btn btn-primary btn-block" href="${escapeHtml(entry.url)}" rel="nofollow">Download</a>`
    : `<button class="btn btn-secondary btn-block" type="button" disabled>Unavailable</button>`;

  return `
    <div class="card card-elevated">
      <div class="card-body">
        <div style="display:flex; align-items:center; justify-content:space-between; gap: var(--space-3)">
          <h4 style="margin:0">${escapeHtml(title)}</h4>
          <span class="badge ${badgeClass}">${escapeHtml(status)}</span>
        </div>
        <p class="muted" style="margin-top: var(--space-2); margin-bottom: 0">
          v${escapeHtml(entry.version || '--')}
        </p>
        ${renderDetails(entry)}
        ${notes}
        <div style="margin-top: var(--space-3)">
          ${action}
        </div>
      </div>
    </div>
  `;
}

async function safeJson(res) {
  return res.json().catch(() => ({}));
}

document.addEventListener('DOMContentLoaded', async () => {
  const recoCard = document.getElementById('recommendation-card');
  const grid = document.querySelector('[data-download-grid]');

  try {
    const res = await fetch('/api/downloads/detect');
    const data = await safeJson(res);
    if (res.ok && data.recommended_download) {
      if (recoCard) {
        recoCard.style.display = '';
      }
      const link = document.querySelector('[data-reco-link]');
      const platformEl = document.querySelector('[data-reco-platform]');
      const notesEl = document.querySelector('[data-reco-notes]');
      if (platformEl) {
        platformEl.textContent = platformLabel(data.platform);
      }
      if (notesEl) {
        notesEl.textContent = 'Best available installer for this device.';
      }
      if (link) {
        link.setAttribute('href', data.recommended_download);
      }
    }
  } catch (_) {
    // Recommendation stays hidden if detection API fails.
  }

  try {
    const res = await fetch('/api/downloads');
    const data = await safeJson(res);
    const downloads = Array.isArray(data.downloads) ? data.downloads : [];

    if (!grid) {
      return;
    }

    if (downloads.length === 0) {
      grid.innerHTML = `
        <div class="card card-elevated">
          <div class="card-body">
            <h4>No downloads published yet</h4>
            <p class="muted">Release manifest not found or no artifacts are currently published.</p>
          </div>
        </div>
      `;
      return;
    }

    grid.innerHTML = downloads.map(renderCard).join('');
  } catch (_) {
    if (grid) {
      grid.innerHTML = `
        <div class="card card-elevated">
          <div class="card-body">
            <h4>Downloads unavailable</h4>
            <p class="muted">Unable to load release metadata from the backend.</p>
          </div>
        </div>
      `;
    }
  }
});
