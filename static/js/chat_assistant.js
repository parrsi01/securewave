/* SecureWave Assistant (local-only, no network calls)
 * - Floating button + panel
 * - Guided plan chooser (use-case, device count, region)
 * - Stores state in localStorage
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'sw_assistant_v1';
  var _instance = null;
  var _panelEl = null;
  var _fabEl = null;

  function safeJsonParse(value, fallback) {
    try { return JSON.parse(value); } catch (e) { return fallback; }
  }

  function loadState() {
    var raw = localStorage.getItem(STORAGE_KEY);
    var state = safeJsonParse(raw, null);
    if (!state || typeof state !== 'object') return null;
    if (!Array.isArray(state.messages)) return null;
    return state;
  }

  function saveState(state) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) {}
  }

  function defaultState(intent) {
    return { version: 1, intent: intent || 'general', step: 0, answers: { useCase: null, devices: null, region: null }, messages: [] };
  }

  function computeRecommendation(answers) {
    var use = answers.useCase;
    var devices = answers.devices;
    var region = answers.region;
    var deviceCount = devices === '1' ? 1 : devices === '2-3' ? 3 : devices === '4+' ? 4 : 0;
    var travelHeavy = region === 'multiple' || region === 'travel';
    var heavyUse = use === 'streaming' || use === 'work' || use === 'travel';
    var recommendPro = heavyUse || travelHeavy || deviceCount >= 2;

    if (recommendPro) {
      return { plan: 'Pro', price: '$9', summary: 'Unlimited data with priority routing for everyday use.',
        bullets: ['Unlimited data (no monthly cap)', 'Better fit for multiple devices or travel', 'Best choice for streaming and daily work'],
        cta: { label: 'Get Pro', href: '/register.html' } };
    }
    return { plan: 'Free Starter', price: '$0', summary: 'Max 5 GB / month for light browsing and occasional use.',
      bullets: ['Max 5 GB / month data', 'Good fit for one device and light use', 'Upgrade anytime if you hit the cap'],
      cta: { label: 'Start Free', href: '/register.html' } };
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      var keys = Object.keys(attrs);
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i], v = attrs[k];
        if (k === 'class') node.className = v;
        else if (k === 'text') node.textContent = v;
        else if (k === 'html') node.innerHTML = v;
        else if (k === 'disabled') node.disabled = Boolean(v);
        else node.setAttribute(k, v);
      }
    }
    if (children) {
      for (var j = 0; j < children.length; j++) {
        node.appendChild(typeof children[j] === 'string' ? document.createTextNode(children[j]) : children[j]);
      }
    }
    return node;
  }

  // === CORE OPEN / CLOSE — single source of truth ===
  function openPanel() {
    if (!_panelEl || !_fabEl) return;
    _panelEl.classList.add('open');
    _fabEl.setAttribute('aria-expanded', 'true');
  }

  function closePanel() {
    if (!_panelEl || !_fabEl) return;
    _panelEl.classList.remove('open');
    _fabEl.setAttribute('aria-expanded', 'false');
  }

  function togglePanel() {
    if (!_panelEl) return;
    if (_panelEl.classList.contains('open')) closePanel();
    else openPanel();
  }

  function buildUi() {
    var fab = el('button', { class: 'sw-chat-fab', type: 'button', 'aria-label': 'Open SecureWave Assistant', 'aria-expanded': 'false' }, [
      el('span', { class: 'sw-chat-fab-dot', 'aria-hidden': 'true' }),
      el('span', { class: 'sw-chat-fab-label', text: 'Help' }),
    ]);

    var panel = el('section', { class: 'sw-chat-panel', role: 'dialog', 'aria-label': 'SecureWave Assistant', 'aria-modal': 'false' });

    var header = el('div', { class: 'sw-chat-header' });
    var title = el('div', { class: 'sw-chat-title' }, [
      el('div', { class: 'sw-chat-title-name', text: 'SecureWave Assistant' }),
      el('div', { class: 'sw-chat-title-sub', text: 'Help choosing a plan, locally.' }),
    ]);

    var closeBtn = el('button', { class: 'sw-chat-close', type: 'button', 'aria-label': 'Close assistant' }, [
      el('span', { 'aria-hidden': 'true', text: '\u00D7' }),
    ]);

    header.appendChild(title);
    header.appendChild(closeBtn);

    var body = el('div', { class: 'sw-chat-body' });
    var messages = el('div', { class: 'sw-chat-messages', 'data-sw-chat-messages': '1' });
    var quick = el('div', { class: 'sw-chat-quick', 'data-sw-chat-quick': '1' });
    body.appendChild(messages);
    body.appendChild(quick);

    var footer = el('div', { class: 'sw-chat-footer' });
    var input = el('input', { class: 'sw-chat-input', type: 'text', placeholder: 'Type a question (optional)', autocomplete: 'off', 'aria-label': 'Message' });
    var send = el('button', { class: 'btn btn-secondary sw-chat-send', type: 'button', text: 'Send' });
    footer.appendChild(input);
    footer.appendChild(send);

    panel.appendChild(header);
    panel.appendChild(body);
    panel.appendChild(footer);

    // Store refs globally for open/close functions
    _panelEl = panel;
    _fabEl = fab;

    // === CLOSE BUTTON: three redundant mechanisms to guarantee it works ===

    // 1. Direct onclick (highest priority, works on all browsers)
    closeBtn.onclick = function (e) {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      closePanel();
      return false;
    };

    // 2. Touchend for mobile (fires before click, more reliable on iOS Safari)
    closeBtn.addEventListener('touchend', function (e) {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      closePanel();
    }, { passive: false });

    // 3. Event delegation on panel — catches clicks on any .sw-chat-close
    //    even if the direct handler somehow fails
    panel.addEventListener('click', function (e) {
      var target = e.target;
      // Walk up from target to find .sw-chat-close
      while (target && target !== panel) {
        if (target.classList && target.classList.contains('sw-chat-close')) {
          e.preventDefault();
          e.stopPropagation();
          closePanel();
          return;
        }
        target = target.parentElement;
      }
    }, true); // capture phase — fires before bubble

    // FAB toggle
    fab.addEventListener('click', function (e) {
      e.stopPropagation();
      togglePanel();
    });

    return { fab: fab, panel: panel, messages: messages, quick: quick, input: input, send: send };
  }

  function assistantInit(options) {
    if (_instance) return _instance;

    var intent = (options && options.intent) || null;
    var state = loadState() || defaultState(intent);
    if (intent && state.intent !== intent) state.intent = intent;

    var ui = buildUi();
    document.body.appendChild(ui.fab);
    document.body.appendChild(ui.panel);

    function renderMessages() {
      ui.messages.innerHTML = '';
      for (var i = 0; i < state.messages.length; i++) {
        var msg = state.messages[i];
        var isUser = msg.role === 'user';
        ui.messages.appendChild(el('div', { class: isUser ? 'sw-chat-msg sw-chat-msg-user' : 'sw-chat-msg sw-chat-msg-bot' }, [
          el('div', { class: 'sw-chat-bubble', text: msg.text }),
        ]));
      }
      ui.messages.scrollTop = ui.messages.scrollHeight;
    }

    function setQuickReplies(replies) {
      ui.quick.innerHTML = '';
      if (!replies || replies.length === 0) return;
      for (var i = 0; i < replies.length; i++) {
        (function (r) {
          var b = el('button', { class: 'sw-chat-chip', type: 'button', text: r.label, 'data-value': r.value });
          b.addEventListener('click', function () { onQuickReply(r.value, r.label); });
          ui.quick.appendChild(b);
        })(replies[i]);
      }
    }

    function push(role, text) {
      state.messages.push({ role: role, text: text, ts: Date.now() });
      saveState(state);
      renderMessages();
    }

    function restart(intentOverride) {
      var nextIntent = intentOverride || state.intent || 'general';
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
      var rec = computeRecommendation(state.answers);
      push('bot', 'Recommendation: ' + rec.plan + ' (' + rec.price + '/mo). ' + rec.summary);
      for (var i = 0; i < rec.bullets.length; i++) push('bot', '\u2022 ' + rec.bullets[i]);
      push('bot', 'Next steps: create an account, then download the app to connect.');
      setQuickReplies([
        { label: 'Create account', value: 'go:' + rec.cta.href },
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
      if (value === 'restart') { restart(state.intent); return; }
      if (value.indexOf('go:') === 0) { window.location.href = value.slice(3); return; }
      push('user', label);
      var parts = value.split(':');
      var k = parts[0], v = parts[1];
      if (k === 'use') state.answers.useCase = v;
      if (k === 'devices') state.answers.devices = v;
      if (k === 'region') state.answers.region = v;
      saveState(state);
      advance();
    }

    function sendFreeform() {
      var text = (ui.input.value || '').trim();
      if (!text) return;
      ui.input.value = '';
      push('user', text);
      if (state.step < 3) {
        push('bot', 'For the best recommendation, use the quick questions below.');
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
    ui.input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); sendFreeform(); }
      else if (e.key === 'Escape') { closePanel(); }
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && _panelEl && _panelEl.classList.contains('open')) closePanel();
    });

    // External triggers: data-open-assistant buttons
    document.addEventListener('click', function (e) {
      if (!e.target || !e.target.closest) return;
      var trigger = e.target.closest('[data-open-assistant]');
      if (!trigger) return;
      e.preventDefault();
      openPanel();
      if (state.messages.length === 0) restart(trigger.getAttribute('data-assistant-intent') || state.intent);
    });

    if (state.messages.length === 0) {
      restart(state.intent);
    } else {
      renderMessages();
      if (state.step === 0) {
        setQuickReplies([ { label: 'Browsing / email', value: 'use:browsing' }, { label: 'Work / remote access', value: 'use:work' }, { label: 'Streaming / gaming', value: 'use:streaming' }, { label: 'Travel / public Wi-Fi', value: 'use:travel' }, { label: 'Other', value: 'use:other' } ]);
      } else if (state.step === 1) {
        setQuickReplies([ { label: '1 device', value: 'devices:1' }, { label: '2-3 devices', value: 'devices:2-3' }, { label: '4+ devices', value: 'devices:4+' } ]);
      } else if (state.step === 2) {
        setQuickReplies([ { label: 'North America', value: 'region:na' }, { label: 'Europe', value: 'region:eu' }, { label: 'Asia-Pacific', value: 'region:apac' }, { label: 'Multiple regions', value: 'region:multiple' }, { label: 'Mostly traveling', value: 'region:travel' } ]);
      } else {
        setQuickReplies([ { label: 'Compare plans', value: 'go:/subscription.html' }, { label: 'Download', value: 'go:/home.html#download' }, { label: 'Start over', value: 'restart' } ]);
      }
    }

    _instance = { open: openPanel, close: closePanel, restart: restart };
    return _instance;
  }

  window.SecureWaveAssistant = { init: assistantInit };
})();
