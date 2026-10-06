/* Shared automated support. Runs locally, stores no messages, makes no account changes. */
(function () {
  'use strict';
  let instance;
  const topics = {
    download: {
      label: 'Download & install',
      text: 'SecureWave v.1.0.0 is available as a DEB file for Ubuntu 24.04 ARM64. Download it, open the DEB in your software installer, then launch SecureWave. Windows, macOS, iOS, Android and Linux x64 downloads are not currently available.',
      links: [['Download v.1.0.0', '/download.html']],
    },
    account: {
      label: 'Sign-in & account',
      text: 'Create an account, follow any email-verification prompt, then sign in with the same account in the app. If verification mail is missing, check spam. For a forgotten password or a persistent sign-in error, contact support. Never share your password or verification code in chat.',
      links: [['Sign in', '/login.html'], ['Create an account', '/register.html'], ['Contact support', '/contact.html']],
    },
    plans: {
      label: 'Plans & billing',
      text: 'Free includes 5 GB of VPN traffic per month and one device. Premium includes unlimited transfer and up to five devices: USD $9.99 monthly or $99.99 paid yearly (about $8.33 per month). Review your account for billing and renewal details. This assistant cannot charge, cancel or refund a subscription.',
      links: [['Compare plans', '/subscription.html'], ['Account dashboard', '/dashboard.html'], ['Billing support', '/contact.html']],
    },
    connection: {
      label: 'VPN connection',
      text: 'Connect inside the installed SecureWave app; the website does not start a VPN. First check your normal internet connection, sign in, then select Connect. If connection fails, disconnect and try again. If it still fails, contact support with your operating system and the exact error message, without passwords or keys.',
      links: [['Connection diagnostics', '/diagnostics.html'], ['Contact support', '/contact.html']],
    },
    usage: {
      label: 'Data & devices',
      text: 'Your dashboard shows your plan, usage and registered devices. Free has a 5 GB monthly allowance and one device; Premium supports up to five devices and unlimited transfer. If you reach a limit, check your account plan and registered devices before reconnecting.',
      links: [['View dashboard', '/dashboard.html'], ['Compare plans', '/subscription.html']],
    },
    privacy: {
      label: 'Privacy & safety',
      text: 'SecureWave uses WireGuard in the available app. Check connection status in the app and use the leak-test page for additional checks. This assistant gives general help and cannot inspect your tunnel or account. Your chat messages stay on this page and are not saved or sent to a server.',
      links: [['Privacy policy', '/privacy.html'], ['Leak test', '/leak_test.html']],
    },
    contact: {
      label: 'Contact support',
      text: 'For account-specific help, payment questions or unresolved errors, open the support page and use its contact form. Include your operating system, app version and the error you see. This chat is automated guidance, not a live support agent; it does not submit a ticket.',
      links: [['Open support page', '/contact.html']],
    },
  };
  function findTopic(text) {
    const q = text.toLowerCase();
    if (/refund|cancel|payment|bill|price|pricing|plan|premium|subscription|cost/.test(q)) return 'plans';
    if (/log.?in|sign.?in|password|verify|verification|email|register|account/.test(q)) return 'account';
    if (/install|download|deb\b|ubuntu|linux|arm64|windows|macos|iphone|ipad|ios\b|android|version/.test(q)) return 'download';
    if (/connect|tunnel|wireguard|vpn|offline|internet|network|error|fail/.test(q)) return 'connection';
    if (/usage|allowance|limit|device|data|bandwidth|transfer/.test(q)) return 'usage';
    if (/privacy|safe|security|leak|dns|store|save|messages/.test(q)) return 'privacy';
    if (/contact|support|human|agent|ticket|help/.test(q)) return 'contact';
    return null;
  }
  function element(tag, attributes, text) {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attributes || {})) node.setAttribute(name, value);
    if (text) node.textContent = text;
    return node;
  }
  function init() {
    if (instance) return instance;
    const fab = element('button', {class: 'sw-chat-fab', type: 'button', 'aria-label': 'Open support chat', 'aria-expanded': 'false', 'aria-controls': 'sw-support-panel'}, 'Help');
    const panel = element('section', {id: 'sw-support-panel', class: 'sw-chat-panel', role: 'dialog', 'aria-labelledby': 'sw-support-title'});
    panel.hidden = true;
    const header = element('div', {class: 'sw-chat-header'});
    const heading = element('div');
    heading.appendChild(element('h2', {id: 'sw-support-title', class: 'sw-chat-title'}, 'SecureWave support'));
    heading.appendChild(element('p', {class: 'sw-chat-subtitle'}, 'Automated help · not a live agent'));
    const closeButton = element('button', {type: 'button', class: 'sw-chat-close', 'aria-label': 'Close support chat'}, '×');
    header.appendChild(heading); header.appendChild(closeButton);
    const messages = element('div', {class: 'sw-chat-messages', role: 'log', 'aria-live': 'polite', 'aria-relevant': 'additions', 'aria-label': 'Support conversation', tabindex: '0'});
    const quick = element('div', {class: 'sw-chat-quick', 'aria-label': 'Support topics'});
    const form = element('form', {class: 'sw-chat-footer'});
    const input = element('input', {class: 'sw-chat-input', type: 'text', maxlength: '500', placeholder: 'Ask a support question', autocomplete: 'off', 'aria-label': 'Your support question'});
    const send = element('button', {class: 'btn btn-secondary sw-chat-send', type: 'submit'}, 'Send');
    form.appendChild(input); form.appendChild(send);
    panel.appendChild(header); panel.appendChild(messages); panel.appendChild(quick); panel.appendChild(form);
    document.body.appendChild(fab); document.body.appendChild(panel);
    function push(text, isUser, links) {
      const bubble = element('div', {class: isUser ? 'sw-chat-bubble sw-chat-bubble-user' : 'sw-chat-bubble'});
      bubble.appendChild(element('p', {}, text));
      if (links && links.length) {
        const actions = element('div', {class: 'sw-chat-links'});
        for (const [label, href] of links) actions.appendChild(element('a', {href}, label));
        bubble.appendChild(actions);
      }
      messages.appendChild(bubble);
      while (messages.children.length > 40) messages.removeChild(messages.firstChild);
      messages.scrollTop = messages.scrollHeight;
    }
    function reply(key) { const topic = topics[key]; push(topic.text, false, topic.links); }
    for (const [key, topic] of Object.entries(topics)) {
      const button = element('button', {class: 'sw-chat-chip', type: 'button'}, topic.label);
      button.addEventListener('click', () => { push(topic.label, true); reply(key); });
      quick.appendChild(button);
    }
    let returnFocus = fab;
    function open() {
      if (panel.hidden) returnFocus = document.activeElement || fab;
      panel.hidden = false; fab.setAttribute('aria-expanded', 'true');
      input.focus({preventScroll: true});
    }
    function close() {
      panel.hidden = true; fab.setAttribute('aria-expanded', 'false');
      if (returnFocus && typeof returnFocus.focus === 'function') returnFocus.focus({preventScroll: true});
    }
    fab.addEventListener('click', () => panel.hidden ? open() : close());
    closeButton.addEventListener('click', close);
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const text = (input.value || '').trim().slice(0, 500);
      if (!text) return;
      input.value = ''; push(text, true);
      const key = findTopic(text);
      if (key) reply(key);
      else if (/^(hi|hello|hey|thanks|thank you)[.!\s]*$/i.test(text)) push('Hello! Choose a topic below, or ask about installation, sign-in, plans or your VPN connection.', false);
      else push('I do not have a specific answer for that question. Choose a support topic below, or contact support for help with your situation.', false, topics.contact.links);
      input.focus({preventScroll: true});
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !panel.hidden) { event.preventDefault(); close(); }
    });
    document.addEventListener('click', (event) => {
      const trigger = event.target && event.target.closest ? event.target.closest('[data-open-assistant]') : null;
      if (trigger) { event.preventDefault(); open(); }
    });
    push('Hi! I can help with downloads, account access, plans and connection problems. Choose a topic or type a question. Please do not share passwords, payment details or verification codes.', false);
    instance = {open, close};
    return instance;
  }
  window.SecureWaveAssistant = {init};
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, {once: true});
  else init();
})();
