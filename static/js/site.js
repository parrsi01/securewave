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
