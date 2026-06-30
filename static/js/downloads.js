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

function renderCard(entry) {
  const title = `${platformLabel(entry.platform)}${entry.architecture ? ` (${entry.architecture})` : ''}`;
  const status = entry.status === 'available' ? 'Available' : 'Coming soon';
  const badgeClass = entry.status === 'available' ? 'badge-primary' : 'badge-muted';
  const size = entry.size_display ? ` • ${entry.size_display}` : '';
  const notes = entry.notes ? `<p class="muted">${escapeHtml(entry.notes)}</p>` : '';

  const action = entry.status === 'available' && entry.url && entry.url !== '#'
    ? `<a class="btn btn-primary btn-block" href="${escapeHtml(entry.url)}" rel="nofollow">Download</a>`
    : `<button class="btn btn-secondary btn-block" type="button" disabled>Coming soon</button>`;

  return `
    <div class="card card-elevated">
      <div class="card-body">
        <div style="display:flex; align-items:center; justify-content:space-between; gap: var(--space-3)">
          <h4 style="margin:0">${escapeHtml(title)}</h4>
          <span class="badge ${badgeClass}">${escapeHtml(status)}</span>
        </div>
        <p class="muted" style="margin-top: var(--space-2); margin-bottom: 0">
          v${escapeHtml(entry.version || '--')}${escapeHtml(size)}
        </p>
        <div style="margin-top: var(--space-3)">${notes}</div>
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

async function fetchDownloadData() {
  const apiRes = await fetch('/api/downloads');
  const apiData = await safeJson(apiRes);
  if (apiRes.ok && Array.isArray(apiData.downloads)) return apiData;

  const staticRes = await fetch('/downloads/manifest.json', { cache: 'no-store' });
  const staticData = await safeJson(staticRes);
  if (staticRes.ok && Array.isArray(staticData.downloads)) return staticData;

  return { downloads: [] };
}

function bestDownloadForPlatform(downloads, platform) {
  const matches = downloads.filter((entry) => entry.platform === platform);
  return matches.find((entry) => entry.status === 'available' && entry.url && entry.url !== '#') || null;
}

document.addEventListener('DOMContentLoaded', async () => {
  const recoCard = document.getElementById('recommendation-card');
  const grid = document.querySelector('[data-download-grid]');
  let downloadData = null;

  // Recommendation (best-effort)
  try {
    const res = await fetch('/api/downloads/detect');
    const data = await safeJson(res);
    if (res.ok && data.recommended_download) {
      if (recoCard) recoCard.style.display = '';
      const link = document.querySelector('[data-reco-link]');
      const platformEl = document.querySelector('[data-reco-platform]');
      const notesEl = document.querySelector('[data-reco-notes]');
      if (platformEl) platformEl.textContent = platformLabel(data.platform);
      if (notesEl) notesEl.textContent = 'Fastest path to getting connected on this device.';
      if (link) link.setAttribute('href', data.recommended_download);
    }
  } catch (_) {
    // fallback below once the manifest loads
  }

  // Full list
  try {
    const data = downloadData || await fetchDownloadData();
    downloadData = data;
    const downloads = Array.isArray(data.downloads) ? data.downloads : [];
    if (!grid) return;

    if (recoCard && recoCard.style.display === 'none') {
      const platform = /Mac|iPhone|iPad/.test(navigator.userAgent)
        ? (/iPhone|iPad/.test(navigator.userAgent) ? 'ios' : 'macos')
        : (/Android/.test(navigator.userAgent) ? 'android' : (/Win/.test(navigator.userAgent) ? 'windows' : 'linux'));
      const recommended = bestDownloadForPlatform(downloads, platform);
      if (recommended) {
        recoCard.style.display = '';
        const link = document.querySelector('[data-reco-link]');
        const platformEl = document.querySelector('[data-reco-platform]');
        const notesEl = document.querySelector('[data-reco-notes]');
        if (platformEl) platformEl.textContent = platformLabel(recommended.platform);
        if (notesEl) notesEl.textContent = recommended.notes || 'Recommended for this device.';
        if (link) link.setAttribute('href', recommended.url);
      }
    }

    if (downloads.length === 0) {
      grid.innerHTML = `
        <div class="card card-elevated">
          <div class="card-body">
            <h4>No downloads published yet</h4>
            <p class="muted">Build artifacts were not found on the server. Check back soon.</p>
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
            <p class="muted">Unable to fetch the download list from the backend.</p>
          </div>
        </div>
      `;
    }
  }
});
