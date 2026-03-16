/* SecureWave Assistant (local-only, no network calls)
 * - Floating button + panel
 * - Guided plan chooser (use-case, device count, region)
 * - Stores state in localStorage
 */
(function () {
  'use strict';

  const STORAGE_KEY = 'sw_assistant_v1';

  function safeJsonParse(value, fallback) {
    try {
      return JSON.parse(value);
    } catch {
      return fallback;
    }
  }

  function loadState() {
    const raw = localStorage.getItem(STORAGE_KEY);
    const state = safeJsonParse(raw, null);
    if (!state || typeof state !== 'object') return null;
    if (!Array.isArray(state.messages)) return null;
    return state;
  }

  function saveState(state) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch {
      // Ignore storage quota / privacy mode issues.
    }
  }

  function defaultState(intent) {
    return {
      version: 1,
      intent: intent || 'general',
      step: 0,
      answers: {
        useCase: null,
        devices: null,
        region: null,
      },
      messages: [],
    };
  }

  function computeRecommendation(answers) {
    const use = answers.useCase;
    const devices = answers.devices;
    const region = answers.region;

    const deviceCount = devices === '1' ? 1 : devices === '2-3' ? 3 : devices === '4+' ? 4 : 0;
    const travelHeavy = region === 'multiple' || region === 'travel';
    const heavyUse = use === 'streaming' || use === 'work' || use === 'travel';
    const lightUse = use === 'browsing' || use === 'other';

    // Conservative: recommend Pro if anything suggests sustained usage.
    const recommendPro = heavyUse || travelHeavy || deviceCount >= 2;

    if (recommendPro) {
      return {
        plan: 'Pro',
        price: '$9',
        summary: 'Unlimited data with priority routing for everyday use.',
        bullets: [
          'Unlimited data (no monthly cap)',
          'Better fit for multiple devices or travel',
          'Best choice for streaming and daily work',
        ],
        cta: { label: 'Get Pro', href: '/register.html' },
      };
    }

    return {
      plan: 'Free Starter',
      price: '$0',
      summary: 'Max 5 GB / month for light browsing and occasional use.',
      bullets: [
        'Max 5 GB / month data',
        'Good fit for one device and light use',
        'Upgrade anytime if you hit the cap',
      ],
      cta: { label: 'Start Free', href: '/register.html' },
    };
  }

  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (k === 'class') node.className = v;
        else if (k === 'text') node.textContent = v;
        else if (k === 'html') node.innerHTML = v;
        else if (k.startsWith('data-')) node.setAttribute(k, v);
        else if (k === 'disabled') node.disabled = Boolean(v);
        else node.setAttribute(k, v);
      }
    }
    if (children) {
      for (const child of children) {
        node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
      }
    }
    return node;
  }

  function buildUi() {
    const fab = el('button', {
      class: 'sw-chat-fab',
      type: 'button',
      'aria-label': 'Open SecureWave Assistant',
      'aria-expanded': 'false',
    }, [
      el('span', { class: 'sw-chat-fab-dot', 'aria-hidden': 'true' }),
      el('span', { class: 'sw-chat-fab-label', text: 'Help' }),
    ]);

    const panel = el('section', {
      class: 'sw-chat-panel',
      role: 'dialog',
      'aria-label': 'SecureWave Assistant',
      'aria-modal': 'false',
    });

    const header = el('div', { class: 'sw-chat-header' });
    const title = el('div', { class: 'sw-chat-title' }, [
      el('div', { class: 'sw-chat-title-name', text: 'SecureWave Assistant' }),
      el('div', { class: 'sw-chat-title-sub', text: 'Help choosing a plan, locally.' }),
    ]);

    const close = el('button', {
      class: 'sw-chat-close',
      type: 'button',
      'aria-label': 'Close assistant',
    }, [el('span', { 'aria-hidden': 'true', text: '\u00D7' })]);

    // Direct onclick as primary close mechanism.
    close.onclick = function (e) {
      e.preventDefault();
      e.stopPropagation();
      panel.classList.remove('open');
      fab.setAttribute('aria-expanded', 'false');
    };

    header.appendChild(title);
    header.appendChild(close);

    const body = el('div', { class: 'sw-chat-body' });
    const messages = el('div', { class: 'sw-chat-messages', 'data-sw-chat-messages': '1' });
    const quick = el('div', { class: 'sw-chat-quick', 'data-sw-chat-quick': '1' });
    body.appendChild(messages);
    body.appendChild(quick);

    const footer = el('div', { class: 'sw-chat-footer' });
    const input = el('input', {
      class: 'sw-chat-input',
      type: 'text',
      placeholder: 'Type a question (optional)',
      autocomplete: 'off',
      'aria-label': 'Message',
    });
    const send = el('button', { class: 'btn btn-secondary sw-chat-send', type: 'button', text: 'Send' });
    footer.appendChild(input);
    footer.appendChild(send);

    panel.appendChild(header);
    panel.appendChild(body);
    panel.appendChild(footer);

    return { fab, panel, messages, quick, close, input, send };
  }

  var _instance = null;

  function assistantInit(options) {
    // Prevent duplicate panels — return existing instance if already initialized.
    if (_instance) return _instance;

    const intent = (options && options.intent) || null;
    let state = loadState() || defaultState(intent);
    if (intent && state.intent !== intent) state.intent = intent;

    const ui = buildUi();
    document.body.appendChild(ui.fab);
    document.body.appendChild(ui.panel);

    function renderMessages() {
      ui.messages.innerHTML = '';
      for (const msg of state.messages) {
        const isUser = msg.role === 'user';
        ui.messages.appendChild(el('div', { class: isUser ? 'sw-chat-msg sw-chat-msg-user' : 'sw-chat-msg sw-chat-msg-bot' }, [
          el('div', { class: 'sw-chat-bubble', text: msg.text }),
        ]));
      }
      ui.messages.scrollTop = ui.messages.scrollHeight;
    }

    function setQuickReplies(replies) {
      ui.quick.innerHTML = '';
      if (!replies || replies.length === 0) return;
      for (const r of replies) {
        const b = el('button', { class: 'sw-chat-chip', type: 'button', text: r.label, 'data-value': r.value });
        b.addEventListener('click', () => onQuickReply(r.value, r.label));
        ui.quick.appendChild(b);
      }
    }

    function push(role, text) {
      state.messages.push({ role, text, ts: Date.now() });
      saveState(state);
      renderMessages();
    }

    function restart(intentOverride) {
      const nextIntent = intentOverride || state.intent || 'general';
      state = defaultState(nextIntent);
      saveState(state);
      push('bot', "Hi. I can help you pick a plan. What's your main use-case?");
      state.step = 0;
      saveState(state);
      setQuickReplies([
        { label: 'Browsing / email', value: 'use:browsing' },
        { label: 'Work / remote access', value: 'use:work' },
        { label: 'Streaming / gaming', value: 'use:streaming' },
        { label: 'Travel / public Wi-Fi', value: 'use:travel' },
        { label: 'Other', value: 'use:other' },
      ]);
    }

    function showRecommendation() {
      const rec = computeRecommendation(state.answers);
      push('bot', `Recommendation: ${rec.plan} (${rec.price}/mo). ${rec.summary}`);
      for (const b of rec.bullets) push('bot', `• ${b}`);
      push('bot', 'Next steps: create an account, then download the app to connect.');

      setQuickReplies([
        { label: 'Create account', value: `go:${rec.cta.href}` },
        { label: 'Download', value: 'go:/home.html#download' },
        { label: 'Compare plans', value: 'go:/subscription.html' },
        { label: 'Start over', value: 'restart' },
      ]);
    }

    function advance() {
      if (state.step === 0) {
        push('bot', 'How many devices do you want to protect?');
        state.step = 1;
        saveState(state);
        setQuickReplies([
          { label: '1 device', value: 'devices:1' },
          { label: '2-3 devices', value: 'devices:2-3' },
          { label: '4+ devices', value: 'devices:4+' },
        ]);
        return;
      }

      if (state.step === 1) {
        push('bot', 'Where do you use SecureWave most often?');
        state.step = 2;
        saveState(state);
        setQuickReplies([
          { label: 'North America', value: 'region:na' },
          { label: 'Europe', value: 'region:eu' },
          { label: 'Asia-Pacific', value: 'region:apac' },
          { label: 'Multiple regions', value: 'region:multiple' },
          { label: 'Mostly traveling', value: 'region:travel' },
        ]);
        return;
      }

      if (state.step === 2) {
        state.step = 3;
        saveState(state);
        showRecommendation();
      }
    }

    function onQuickReply(value, label) {
      if (value === 'restart') {
        restart(state.intent);
        return;
      }

      if (value.startsWith('go:')) {
        const href = value.slice('go:'.length);
        window.location.href = href;
        return;
      }

      push('user', label);

      const [k, v] = value.split(':', 2);
      if (k === 'use') state.answers.useCase = v;
      if (k === 'devices') state.answers.devices = v;
      if (k === 'region') state.answers.region = v;
      saveState(state);

      advance();
    }

    function open() {
      ui.panel.classList.add('open');
      ui.fab.setAttribute('aria-expanded', 'true');
      ui.input.focus({ preventScroll: true });
    }

    function closePanel() {
      ui.panel.classList.remove('open');
      ui.fab.setAttribute('aria-expanded', 'false');
    }

    function toggle() {
      if (ui.panel.classList.contains('open')) closePanel();
      else open();
    }

    ui.fab.addEventListener('click', toggle);
    ui.close.addEventListener('click', closePanel);

    function sendFreeform() {
      const text = (ui.input.value || '').trim();
      if (!text) return;
      ui.input.value = '';
      push('user', text);

      // Minimal offline behavior: steer back to the guided flow.
      if (state.step < 3) {
        push('bot', "For the best recommendation, use the quick questions below.");
        return;
      }

      push('bot', 'I can help you restart the plan chooser, or you can compare plans.');
      setQuickReplies([
        { label: 'Start over', value: 'restart' },
        { label: 'Compare plans', value: 'go:/subscription.html' },
        { label: 'Download', value: 'go:/home.html#download' },
      ]);
    }

    ui.send.addEventListener('click', sendFreeform);
    ui.input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        sendFreeform();
      } else if (e.key === 'Escape') {
        closePanel();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && ui.panel.classList.contains('open')) closePanel();
    });

    // External triggers: any element with data-open-assistant opens the panel.
    document.addEventListener('click', (e) => {
      const target = e.target && e.target.closest ? e.target.closest('[data-open-assistant]') : null;
      if (!target) return;
      e.preventDefault();
      open();
      if (state.messages.length === 0) restart(target.getAttribute('data-assistant-intent') || state.intent);
    });

    if (state.messages.length === 0) {
      restart(state.intent);
    } else {
      renderMessages();
      // Rebuild quick replies based on step.
      if (state.step === 0) {
        setQuickReplies([
          { label: 'Browsing / email', value: 'use:browsing' },
          { label: 'Work / remote access', value: 'use:work' },
          { label: 'Streaming / gaming', value: 'use:streaming' },
          { label: 'Travel / public Wi-Fi', value: 'use:travel' },
          { label: 'Other', value: 'use:other' },
        ]);
      } else if (state.step === 1) {
        setQuickReplies([
          { label: '1 device', value: 'devices:1' },
          { label: '2-3 devices', value: 'devices:2-3' },
          { label: '4+ devices', value: 'devices:4+' },
        ]);
      } else if (state.step === 2) {
        setQuickReplies([
          { label: 'North America', value: 'region:na' },
          { label: 'Europe', value: 'region:eu' },
          { label: 'Asia-Pacific', value: 'region:apac' },
          { label: 'Multiple regions', value: 'region:multiple' },
          { label: 'Mostly traveling', value: 'region:travel' },
        ]);
      } else {
        setQuickReplies([
          { label: 'Compare plans', value: 'go:/subscription.html' },
          { label: 'Download', value: 'go:/home.html#download' },
          { label: 'Start over', value: 'restart' },
        ]);
      }
    }

    _instance = { open, close: closePanel, restart };
    return _instance;
  }

  window.SecureWaveAssistant = {
    init: assistantInit,
  };
})();

