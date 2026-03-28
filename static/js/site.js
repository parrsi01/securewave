document.addEventListener('DOMContentLoaded', () => {
  /* ── Navigation toggle (mobile) ── */
  const nav = document.querySelector('.nav');
  const toggle = document.querySelector('[data-nav-toggle]');
  if (nav && toggle) {
    toggle.setAttribute('aria-expanded', 'false');
    toggle.addEventListener('click', () => {
      const isOpen = nav.classList.toggle('nav-open');
      toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });
    // Close mobile menu when a link is clicked
    nav.querySelectorAll('.nav-mobile a:not(.btn)').forEach((link) => {
      link.addEventListener('click', () => {
        nav.classList.remove('nav-open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  /* ── Navbar scroll shadow ── */
  const onScroll = () => {
    if (!nav) return;
    if (window.scrollY > 10) nav.classList.add('scrolled');
    else nav.classList.remove('scrolled');
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* ── Auth state: swap nav actions ── */
  const navActions = document.querySelector('.nav-actions');
  const getCookie = (name) => {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return '';
  };

  if (navActions) {
    fetch('/api/auth/me', { credentials: 'include' })
      .then((res) => {
        if (!res.ok) return;
        navActions.innerHTML =
          '<a class="btn btn-ghost btn-sm" href="/dashboard">Dashboard</a>' +
          '<button class="btn btn-secondary btn-sm" type="button" data-logout>Sign out</button>';
        const logoutBtn = navActions.querySelector('[data-logout]');
        if (!logoutBtn) return;
        logoutBtn.addEventListener('click', async () => {
          const csrfToken = getCookie('csrf_token');
          try {
            await fetch('/api/auth/logout', {
              method: 'POST',
              headers: { 'X-CSRF-Token': csrfToken },
              credentials: 'include',
            });
          } finally {
            localStorage.removeItem('user_email');
            window.location.href = '/login';
          }
        });
      })
      .catch(() => {});
  }

  // Also bind any pre-rendered data-logout buttons (authenticated pages)
  document.querySelectorAll('[data-logout]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const csrfToken = getCookie('csrf_token');
      try {
        await fetch('/api/auth/logout', {
          method: 'POST',
          headers: { 'X-CSRF-Token': csrfToken },
          credentials: 'include',
        });
      } finally {
        localStorage.removeItem('user_email');
        window.location.href = '/login';
      }
    });
  });

  /* ── Footer year ── */
  const yearEl = document.querySelector('[data-year]');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* ── Scroll reveal animations ── */
  const revealEls = document.querySelectorAll('.reveal');
  if (revealEls.length > 0 && 'IntersectionObserver' in window) {
    const makeVisible = (el) => el.classList.add('visible');
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            makeVisible(entry.target);
            revealObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
    );
    revealEls.forEach((el) => {
      if (el.getBoundingClientRect().top <= window.innerHeight * 0.95) {
        makeVisible(el);
        return;
      }
      revealObserver.observe(el);
    });
  } else if (revealEls.length > 0) {
    revealEls.forEach((el) => el.classList.add('visible'));
  }

  /* ── Accordion ── */
  document.querySelectorAll('.accordion-trigger').forEach((trigger) => {
    trigger.addEventListener('click', () => {
      const item = trigger.closest('.accordion-item');
      if (!item) return;
      const wasOpen = item.classList.contains('open');
      // Close all siblings
      const parent = item.parentElement;
      if (parent) {
        parent.querySelectorAll('.accordion-item.open').forEach((openItem) => {
          openItem.classList.remove('open');
        });
      }
      // Toggle clicked
      if (!wasOpen) item.classList.add('open');
    });
  });

  /* ── Tabs ── */
  document.querySelectorAll('.tabs').forEach((tabBar) => {
    const tabs = tabBar.querySelectorAll('.tab');
    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        const target = tab.getAttribute('data-tab');
        if (!target) return;
        // Update active tab
        tabs.forEach((t) => t.classList.remove('active'));
        tab.classList.add('active');
        // Update panels
        const container = tabBar.parentElement;
        if (!container) return;
        container.querySelectorAll('.tab-panel').forEach((panel) => {
          panel.classList.toggle('active', panel.id === target);
        });
      });
    });
  });

  /* ── Smooth scroll for anchor links ── */
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener('click', (e) => {
      const id = link.getAttribute('href');
      if (!id || id === '#') return;
      const target = document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  /* ── Performance benchmark card ── */
  const benchmarkCard = document.querySelector('[data-performance-benchmark]');
  if (benchmarkCard) {
    const formatMbps = (value) =>
      typeof value === 'number' && Number.isFinite(value) ? `${value.toFixed(1)} Mbps` : 'Not measured';
    const formatMs = (value) =>
      typeof value === 'number' && Number.isFinite(value) ? `${value.toFixed(1)} ms` : 'Not measured';
    const formatRetention = (value) =>
      typeof value === 'number' && Number.isFinite(value) ? `${value.toFixed(1)}% retained` : 'Not measured';
    const protocolSummary = (row) => {
      if (!row) return 'No data';
      if (row.status === 'unavailable') return row.reason || 'Unavailable';
      if (row.status === 'fail') return row.reason || 'Benchmark failed';
      const parts = [];
      if (typeof row.download_mbps === 'number') parts.push(`${row.download_mbps.toFixed(1)} Mbps down`);
      if (typeof row.upload_mbps === 'number') parts.push(`${row.upload_mbps.toFixed(1)} Mbps up`);
      if (typeof row.latency_ms === 'number') parts.push(`${row.latency_ms.toFixed(1)} ms`);
      if (typeof row.download_retention_pct === 'number') parts.push(`${row.download_retention_pct.toFixed(1)}% retained`);
      return parts.length > 0 ? parts.join(' • ') : (row.reason || row.status);
    };

    fetch('/data/performance_benchmarks.json?v=20260327a', { cache: 'no-store' })
      .then((res) => {
        if (!res.ok) throw new Error(`http_${res.status}`);
        return res.json();
      })
      .then((payload) => {
        const baseline = payload.baseline || {};
        const protocols = payload.protocols || {};
        const generated = payload.generated_at ? new Date(payload.generated_at) : null;
        const generatedText =
          generated && !Number.isNaN(generated.getTime()) ? generated.toISOString().replace('T', ' ').replace('.000Z', ' UTC') : 'Unknown';

        const hostEl = benchmarkCard.querySelector('[data-benchmark-host]');
        if (hostEl) hostEl.textContent = payload.host_platform || 'Unknown';
        const generatedEl = benchmarkCard.querySelector('[data-benchmark-generated]');
        if (generatedEl) generatedEl.textContent = generatedText;
        const baseDownloadEl = benchmarkCard.querySelector('[data-benchmark-baseline-download]');
        if (baseDownloadEl) baseDownloadEl.textContent = formatMbps(baseline.download_mbps);
        const baseUploadEl = benchmarkCard.querySelector('[data-benchmark-baseline-upload]');
        if (baseUploadEl) baseUploadEl.textContent = formatMbps(baseline.upload_mbps);
        const baseLatencyEl = benchmarkCard.querySelector('[data-benchmark-baseline-latency]');
        if (baseLatencyEl) baseLatencyEl.textContent = formatMs(baseline.latency_ms);

        const list = benchmarkCard.querySelector('[data-benchmark-protocols]');
        if (list) {
          list.innerHTML = ['wireguard', 'openvpn', 'ikev2']
            .map((protocol) => {
              const row = protocols[protocol] || {};
              const label = row.label || protocol;
              return (
                `<div class="flex justify-between gap-3">` +
                `<span class="text-muted">${label}</span>` +
                `<span class="text-primary font-semibold">${protocolSummary(row)}</span>` +
                `</div>`
              );
            })
            .join('');
        }
      })
      .catch(() => {
        const generatedEl = benchmarkCard.querySelector('[data-benchmark-generated]');
        if (generatedEl) generatedEl.textContent = 'Unavailable';
        const baseDownloadEl = benchmarkCard.querySelector('[data-benchmark-baseline-download]');
        if (baseDownloadEl) baseDownloadEl.textContent = 'No benchmark artifact';
        const list = benchmarkCard.querySelector('[data-benchmark-protocols]');
        if (list) {
          list.innerHTML =
            '<div class="flex justify-between gap-3"><span class="text-muted">Benchmark status</span><span class="text-primary font-semibold">No published benchmark artifact</span></div>';
        }
      });
  }

  /* ── Load assistant widget ── */
  const ensureAssistant = () => {
    if (window.SecureWaveAssistant && typeof window.SecureWaveAssistant.init === 'function') {
      window.SecureWaveAssistant.init({});
      return;
    }
    if (document.querySelector('script[data-sw-assistant]')) return;
    const script = document.createElement('script');
    script.src = '/js/chat_assistant.js?v=20260318';
    script.defer = true;
    script.setAttribute('data-sw-assistant', '1');
    script.addEventListener('load', () => {
      try {
        if (window.SecureWaveAssistant && typeof window.SecureWaveAssistant.init === 'function') {
          window.SecureWaveAssistant.init({});
        }
      } catch { /* ignore */ }
    });
    document.head.appendChild(script);
  };
  ensureAssistant();
});
