/* SecureWave Assistant (local-only, no network calls)
 * - Floating button + panel
 * - Guided plan chooser (use-case, device count, region)
 * - Stores plan preferences only; conversation text stays in memory
 */
(function () {
  'use strict';

  const STORAGE_KEY = 'sw_assistant_v1';
  let instance;

  function safeJsonParse(value, fallback) {
    try {
      return JSON.parse(value);
    } catch {
      return fallback;
    }
  }

  function loadState() {
    let raw;
    try { raw = localStorage.getItem(STORAGE_KEY); } catch { return null; }
    const state = safeJsonParse(raw, null);
    if (!state || typeof state !== 'object') return null;
    if (!Array.isArray(state.messages)) return null;
    if (state.version !== 1 || !Number.isInteger(state.step) || state.step < 0 || state.step > 3) return null;
    if (!state.answers || typeof state.answers !== 'object') return null;
    if (!state.messages.every(msg => msg && typeof msg.text === 'string' && ['bot', 'user'].includes(msg.role))) return null;
    state.messages = state.messages.slice(-40);
    return state;
  }

  function saveState(state) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...state, messages: [] }));
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

    // Conservative: recommend Pro if anything suggests sustained usage.
    const recommendPro = heavyUse || travelHeavy || deviceCount >= 2;

    if (recommendPro) {
      return {
        plan: 'Pro',
        summary: 'Compare the current paid plans and their limits on the plans page.',
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
      'aria-controls': 'sw-support-panel',
    }, [
      el('span', { class: 'sw-chat-fab-dot', 'aria-hidden': 'true' }),
      el('span', { class: 'sw-chat-fab-label', text: 'Help' }),
    ]);

    const panel = el('section', {
      class: 'sw-chat-panel',
      id: 'sw-support-panel',
      role: 'dialog',
      'aria-label': 'SecureWave Assistant',
      'aria-modal': 'false',
      hidden: 'hidden',
    });

    const header = el('div', { class: 'sw-chat-header' });
    const title = el('div', { class: 'sw-chat-title' }, [
      el('div', { class: 'sw-chat-title-name', text: 'SecureWave Assistant' }),
      el('div', { class: 'sw-chat-title-sub', text: 'Automated local guide — not live chat. Do not enter passwords or keys.' }),
    ]);

    const close = el('button', {
      class: 'sw-chat-close',
      type: 'button',
      'aria-label': 'Close assistant',
    }, [el('span', { 'aria-hidden': 'true', text: '×' })]);

    header.appendChild(title);
    header.appendChild(close);

    const body = el('div', { class: 'sw-chat-body' });
    const messages = el('div', { class: 'sw-chat-messages', 'data-sw-chat-messages': '1', role: 'log', 'aria-live': 'polite', 'aria-label': 'Support conversation' });
    const quick = el('div', { class: 'sw-chat-quick', 'data-sw-chat-quick': '1' });
    body.appendChild(messages);
    body.appendChild(quick);

    const footer = el('div', { class: 'sw-chat-footer' });
    const input = el('input', {
      class: 'sw-chat-input',
      type: 'text',
      placeholder: 'Type a question (optional)',
      autocomplete: 'off',
      maxlength: '1000',
      'aria-label': 'Message',
    });
    const send = el('button', { class: 'btn btn-secondary sw-chat-send', type: 'button', text: 'Send' });
    footer.appendChild(input);
    footer.appendChild(send);

    panel.appendChild(header);
    const support = el('div', { class: 'sw-chat-support' }, [
      el('a', { href: '/contact.html', text: 'Support center' }),
    ]);
    const topics = el('button', { type: 'button', class: 'sw-chat-chip', text: 'Help topics' });
    support.appendChild(topics);
    panel.appendChild(support);
    panel.appendChild(body);
    panel.appendChild(footer);

    return { fab, panel, body, messages, quick, close, input, send, topics };
  }

  function assistantInit(options) {
    if (instance) return instance;
    const intent = (options && options.intent) || null;
    let state = loadState() || defaultState(intent);
    state.messages = [];
    saveState(state);
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
      ui.body.scrollTop = ui.body.scrollHeight;
    }

    function setQuickReplies(replies) {
      ui.quick.innerHTML = '';
      if (!replies || replies.length === 0) return;
      for (const r of replies) {
        const b = el('button', { class: 'sw-chat-chip', type: 'button', text: r.label, 'data-value': r.value });
        b.addEventListener('click', () => onQuickReply(r.value, r.label));
        ui.quick.appendChild(b);
      }
      ui.body.scrollTop = ui.body.scrollHeight;
    }

    function push(role, text) {
      state.messages.push({ role, text, ts: Date.now() });
      state.messages = state.messages.slice(-40);
      // Free-form support text stays in memory, never in persistent storage.
      renderMessages();
    }

    const helpTopics = {
      download: ['Download and installation', 'Use the downloads page for available builds, checksums, and installation notes. Availability differs by platform.', '/download.html'],
      account: ['Sign-in and verification', 'Check your email address and verification email, including spam. If sign-in or verification still fails, contact support. Never share passwords or verification links here.', '/login.html'],
      connection: ['Connection troubleshooting', 'Open the installed app and check its connection status. Review diagnostics before retrying. WireGuard is the release path; do not switch to an unavailable protocol.', '/diagnostics.html'],
      billing: ['Plans and billing', 'Review current prices and limits on the plans page. Contact support for payment or invoice problems; do not enter card details here.', '/subscription.html'],
    };

    function showHelp() {
      setQuickReplies(Object.entries(helpTopics).map(([key, topic]) => ({ label: topic[0], value: `help:${key}` })).concat([
        { label: 'Choose a plan', value: 'restart' },
        { label: 'Support center', value: 'go:/contact.html' },
      ]));
    }

    function answerTopic(key) {
      const topic = helpTopics[key];
      if (!topic) return;
      push('bot', topic[1]);
      setQuickReplies([
        { label: topic[0], value: `go:${topic[2]}` },
        { label: 'Support center', value: 'go:/contact.html' },
        { label: 'Help topics', value: 'help' },
      ]);
    }
    ui.topics.addEventListener('click', showHelp);

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
      push('bot', `Recommendation: ${rec.plan}. ${rec.summary}`);
      for (const b of rec.bullets) push('bot', `• ${b}`);
      push('bot', 'Next steps: create an account, then download the app to connect.');

      setQuickReplies([
        { label: 'Create account', value: `go:${rec.cta.href}` },
        { label: 'Download', value: 'go:/download.html' },
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
      if (value === 'help') { showHelp(); return; }
      if (value.startsWith('help:')) { answerTopic(value.slice(5)); return; }
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
      ui.panel.hidden = false;
      ui.fab.setAttribute('aria-expanded', 'true');
      ui.panel.classList.add('open');
      ui.close.focus({ preventScroll: true });
    }

    function close() {
      ui.panel.classList.remove('open');
      ui.fab.setAttribute('aria-expanded', 'false');
      ui.panel.hidden = true;
      ui.fab.focus({ preventScroll: true });
    }

    function toggle() {
      if (ui.panel.hidden) open();
      else close();
    }

    ui.fab.addEventListener('click', toggle);
    ui.close.addEventListener('click', close);

    function sendFreeform() {
      const text = (ui.input.value || '').trim();
      if (!text) return;
      ui.input.value = '';
      push('user', text);

      if (/login|log in|sign.?in|password|account|verif|email/i.test(text)) answerTopic('account');
      else if (/connect|tunnel|wireguard|vpn|dns|leak/i.test(text)) answerTopic('connection');
      else if (/bill|pay|invoice|price|plan|refund/i.test(text)) answerTopic('billing');
      else if (/download|install|mac|windows|linux|android|ios/i.test(text)) answerTopic('download');
      else {
        push('bot', 'I can offer general guidance, but cannot inspect your account or open a ticket here. Choose a topic or visit the Support center.');
        showHelp();
      }
    }

    ui.send.addEventListener('click', sendFreeform);
    ui.input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        sendFreeform();
      } else if (e.key === 'Escape') {
        close();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !ui.panel.hidden) close();
    });

    // External triggers: any element with data-open-assistant opens the panel.
    document.addEventListener('click', (e) => {
      const target = e.target && e.target.closest ? e.target.closest('[data-open-assistant]') : null;
      if (!target) return;
      e.preventDefault();
      open();
      if (state.messages.length === 0) restart(target.getAttribute('data-assistant-intent') || state.intent);
    });

    push('bot', 'How can I help? Choose a topic or describe the issue. Messages are not sent to support.');
    showHelp();

    instance = { open, close, restart };
    return instance;
  }

  window.SecureWaveAssistant = {
    init: assistantInit,
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => assistantInit({}), { once: true });
  } else {
    assistantInit({});
  }
})();
