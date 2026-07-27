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
  const statusMap = {
    available: ['Beta available', 'badge-primary'],
    beta: ['Beta build', 'badge-muted'],
    coming_soon: ['Coming soon', 'badge-muted'],
  };
  const [status, badgeClass] = statusMap[entry.status] || statusMap.coming_soon;
  const size = entry.size_display ? ` • ${entry.size_display}` : '';
  const notes = entry.notes ? `<p class="muted">${escapeHtml(entry.notes)}</p>` : '';
  const checksum = entry.checksum_sha256
    ? `<p class="muted" style="word-break: break-all">SHA256 ${escapeHtml(entry.checksum_sha256)}</p>`
    : '';
  const evidence = entry.evidence_url
    ? `<a class="btn btn-secondary btn-block" href="${escapeHtml(entry.evidence_url)}" rel="nofollow noopener">View ${escapeHtml(entry.evidence_label || 'build evidence')}</a>`
    : '';

  const action = entry.status === 'available' && entry.url && entry.url !== '#'
    ? `<a class="btn btn-primary btn-block" href="${escapeHtml(entry.url)}" rel="nofollow">Download beta</a>`
    : entry.status === 'beta' && evidence
      ? evidence
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
        <div style="margin-top: var(--space-3)">${notes}${checksum}</div>
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

function detectClientPlatform() {
  const userAgent = navigator.userAgent;
  if (/iPhone|iPad/.test(userAgent)) return { platform: 'ios', architecture: 'arm64' };
  if (/Mac/.test(userAgent)) return { platform: 'macos', architecture: /arm64|aarch64/i.test(userAgent) ? 'arm64' : 'x64' };
  if (/Android/.test(userAgent)) return { platform: 'android', architecture: /arm64|aarch64/i.test(userAgent) ? 'arm64' : 'universal' };
  if (/Win/.test(userAgent)) return { platform: 'windows', architecture: /arm64|aarch64/i.test(userAgent) ? 'arm64' : 'x64' };
  return { platform: 'linux', architecture: /arm64|aarch64/i.test(userAgent) ? 'arm64' : 'x64' };
}

function bestDownloadForPlatform(downloads, platform, architecture) {
  const matches = downloads.filter((entry) => (
    entry.platform === platform
    && entry.status === 'available'
    && entry.url
    && entry.url !== '#'
  ));
  return matches.find((entry) => entry.architecture === architecture)
    || matches.find((entry) => entry.architecture === 'universal')
    || matches[0]
    || null;
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
      const detected = detectClientPlatform();
      const recommended = bestDownloadForPlatform(downloads, detected.platform, detected.architecture);
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
    grid.innerHTML = downloads
      .map((entry) => renderCard({
        ...entry,
        version: entry.version || data.version,
      }))
      .join('');
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
