(function () {
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
        return 'your device';
    }
  }

  function detectPlatformLocally() {
    const ua = String(navigator.userAgent || '').toLowerCase();

    if (ua.includes('windows')) {
      return { platform: 'windows', arch: (ua.includes('arm64') || ua.includes('aarch64')) ? 'arm64' : 'x64' };
    }
    if (ua.includes('iphone') || ua.includes('ipad') || ua.includes('ipod')) {
      return { platform: 'ios', arch: 'arm64' };
    }
    if (ua.includes('macintosh') || ua.includes('mac os')) {
      return { platform: 'macos', arch: ua.includes('arm64') ? 'arm64' : 'x64' };
    }
    if (ua.includes('android')) {
      return { platform: 'android', arch: ua.includes('arm64') ? 'arm64' : 'universal' };
    }
    if (ua.includes('linux')) {
      return { platform: 'linux', arch: (ua.includes('aarch64') || ua.includes('arm64')) ? 'arm64' : 'x64' };
    }
    return { platform: 'unknown', arch: 'unknown' };
  }

  function applyResolvedLinks(links, href, label) {
    links.forEach((el) => {
      try {
        el.setAttribute('href', href);
        if (!el.hasAttribute('data-os-download-keep-label')) {
          el.textContent = label;
        }
      } catch (_) {
        // ignore DOM update failures for individual elements
      }
    });
  }

  async function fetchRecommendation() {
    const res = await fetch('/api/downloads/detect');
    if (!res.ok) {
      return null;
    }
    const data = await res.json().catch(() => null);
    if (!data || !data.recommended_download) {
      return null;
    }

    const platform = data.platform || 'unknown';
    return {
      href: data.recommended_download,
      label: `Download for ${platformLabel(platform)}`,
    };
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const links = document.querySelectorAll('[data-os-download]');
    if (!links || links.length === 0) {
      return;
    }

    const local = detectPlatformLocally();
    applyResolvedLinks(links, '/download', `Download for ${platformLabel(local.platform)}`);

    try {
      const recommended = await fetchRecommendation();
      if (recommended && recommended.href) {
        applyResolvedLinks(links, recommended.href, recommended.label);
      }
    } catch (_) {
      // Keep /download fallback.
    }
  });
})();
