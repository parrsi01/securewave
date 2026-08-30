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
    fetch('/api/auth/session', { credentials: 'include' })
      .then((res) => res.ok ? res.json() : null)
      .then((session) => {
        if (!session?.authenticated) return;
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

  /* ── Live deployed version ── */
  const footerBottom = document.querySelector('.footer-bottom');
  if (footerBottom && !footerBottom.querySelector('[data-site-version]')) {
    fetch('/version', { cache: 'no-store' })
      .then((res) => res.ok ? res.json() : null)
      .then((release) => {
        if (!release || typeof release.version !== 'string' || !release.version.trim()) return;
        const commit = typeof release.commit === 'string' && /^[0-9a-f]{7,40}$/i.test(release.commit)
          ? ` · build ${release.commit.slice(0, 7)}`
          : '';
        const version = document.createElement('span');
        version.dataset.siteVersion = 'true';
        version.textContent = `v${release.version}${commit}`;
        version.setAttribute('aria-label', `Deployed version ${release.version}`);
        footerBottom.append(document.createTextNode(' · '), version);
      })
      .catch(() => {});
  }

  /* ── Scroll reveal animations ── */
  const revealEls = document.querySelectorAll('.reveal');
  if (revealEls.length > 0 && 'IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            revealObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
    );
    revealEls.forEach((el) => revealObserver.observe(el));
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

  /* ── Homepage: hero reveal kick + stagger ── */
  const heroLeft = document.querySelector('.hero-left');
  if (heroLeft) {
    document.querySelectorAll('.reveal').forEach((el, i) => {
      if (!el.style.transitionDelay) el.style.transitionDelay = (i % 3) * 0.1 + 's';
    });
    setTimeout(() => heroLeft.classList.add('in'), 80);
  }

  /* ── Homepage: animated network diagram (CSP-safe external script) ── */
  const netviz = document.getElementById('netviz');
  if (netviz) {
    const A = '#00b4ff', G = '#00e5a0', M = '#1a3055', S = '#4a72a8', B2 = '#1a3060';

    const node = (x, y, label, color, status, statusColor) =>
      '<g>' +
      '<circle cx="' + x + '" cy="' + y + '" r="28" fill="none" stroke="' + B2 + '" stroke-width="1"/>' +
      '<circle cx="' + x + '" cy="' + y + '" r="20" fill="#060c18" stroke="' + color + '" stroke-width="1.2"/>' +
      '<text x="' + x + '" y="' + (y + 3) + '" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="9" fill="' + color + '">' + label + '</text>' +
      '<text x="' + x + '" y="' + (y + 44) + '" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="8" fill="' + statusColor + '">' + status + '</text>' +
      '</g>';

    const protoLabel = (x, y, text, color) => {
      const w = text.length * 6 + 12;
      return '<g>' +
        '<rect x="' + (x - w / 2) + '" y="' + (y - 9) + '" width="' + w + '" height="18" fill="#060c18" stroke="' + color + '" stroke-width="1"/>' +
        '<text x="' + x + '" y="' + (y + 3) + '" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="8" fill="' + color + '">' + text + '</text>' +
        '</g>';
    };

    netviz.innerHTML =
      '<svg viewBox="0 0 600 560" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid slice">' +
      '<defs>' +
      '<pattern id="nvgrid" width="32" height="32" patternUnits="userSpaceOnUse">' +
      '<path d="M32 0H0V32" fill="none" stroke="#0f1e3a" stroke-width="0.5"/>' +
      '</pattern>' +
      '<filter id="nvglow" x="-50%" y="-50%" width="200%" height="200%">' +
      '<feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>' +
      '</filter>' +
      '</defs>' +
      '<rect width="600" height="560" fill="#060c18"/>' +
      '<rect width="600" height="560" fill="url(#nvgrid)"/>' +
      '<path d="M300,280 L300,90" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path d="M300,280 L465,185" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path d="M300,280 L465,375" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path d="M300,280 L300,470" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path d="M300,280 L135,375" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path d="M300,280 L135,185" stroke="' + B2 + '" stroke-width="1"/>' +
      '<path id="nv-client" d="M135,185 L300,280" stroke="' + A + '" stroke-width="1.5" opacity="0.6"/>' +
      '<path id="nv-dns" d="M300,280 L300,90" stroke="' + G + '" stroke-width="1.5" opacity="0.6"/>' +
      '<path id="nv-client-r" d="M300,280 L135,185" fill="none" stroke="none"/>' +
      '<path id="nv-srv" d="M300,280 L465,185" fill="none" stroke="none"/>' +
      '<circle cx="300" cy="280" r="52" fill="none" stroke="' + A + '" stroke-width="1">' +
      '<animate attributeName="r" from="52" to="90" dur="3s" repeatCount="indefinite"/>' +
      '<animate attributeName="opacity" from="0.4" to="0" dur="3s" repeatCount="indefinite"/>' +
      '</circle>' +
      '<circle cx="300" cy="280" r="52" fill="none" stroke="' + A + '" stroke-width="1">' +
      '<animate attributeName="r" from="52" to="90" dur="3s" begin="1.5s" repeatCount="indefinite"/>' +
      '<animate attributeName="opacity" from="0.4" to="0" dur="3s" begin="1.5s" repeatCount="indefinite"/>' +
      '</circle>' +
      '<circle cx="300" cy="280" r="52" fill="#060c18" stroke="' + M + '" stroke-width="1"/>' +
      '<circle cx="300" cy="280" r="40" fill="none" stroke="' + A + '" stroke-width="1.5"/>' +
      '<g transform="translate(285,248)">' +
      '<path d="M15 4L23.3 9V15.7C23.3 20.3 15 24 15 24C15 24 6.7 20.3 6.7 15.7V9L15 4Z" fill="#060c18" stroke="' + A + '" stroke-width="1"/>' +
      '<path d="M7.5 15 Q9.6 10.8 11.7 15 Q13.8 19.2 15.8 15 Q17.9 10.8 20 15 Q21.2 17.5 22.5 15" stroke="' + A + '" stroke-width="1.2" stroke-linecap="round" fill="none"/>' +
      '</g>' +
      '<text x="300" y="292" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="9" fill="#d0e8ff">SECURE</text>' +
      '<text x="300" y="304" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="9" fill="' + A + '">WAVE</text>' +
      node(300, 90, 'DNS', G, 'verified', G) +
      node(465, 185, 'SRV', S, 'standby', M) +
      node(465, 375, 'SRV', M, 'offline', M) +
      node(300, 470, 'DEVICE', M, 'unregistered', M) +
      node(135, 375, 'AUTH', M, 'pending', M) +
      node(135, 185, 'CLIENT', A, 'active', A) +
      protoLabel(217, 232, 'WG', A) +
      protoLabel(300, 185, 'DNS', G) +
      protoLabel(382, 232, 'LOCKED', M) +
      '<circle r="4" fill="' + A + '" filter="url(#nvglow)"><animateMotion dur="2.4s" repeatCount="indefinite"><mpath href="#nv-client"/></animateMotion></circle>' +
      '<circle r="3.5" fill="' + G + '" filter="url(#nvglow)"><animateMotion dur="2s" begin="0.8s" repeatCount="indefinite"><mpath href="#nv-dns"/></animateMotion></circle>' +
      '<circle r="3" fill="' + A + '" opacity="0.6"><animateMotion dur="2.4s" begin="1.4s" repeatCount="indefinite"><mpath href="#nv-client-r"/></animateMotion></circle>' +
      '</svg>';
  }

  /* ── Load assistant widget ── */
  const ensureAssistant = () => {
    if (window.SecureWaveAssistant && typeof window.SecureWaveAssistant.init === 'function') {
      window.SecureWaveAssistant.init({});
      return;
    }
    if (document.querySelector('script[data-sw-assistant]')) return;
    const script = document.createElement('script');
    script.src = '/js/chat_assistant.js';
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
