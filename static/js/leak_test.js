async function safeJson(res) {
  return res.json().catch(() => ({}));
}

function setText(sel, text) {
  const el = document.querySelector(sel);
  if (el) el.textContent = text;
}

document.addEventListener('DOMContentLoaded', async () => {
  try {
    const res = await fetch('/api/tools/ip');
    const data = await safeJson(res);
    if (res.ok && data.ip) {
      setText('[data-client-ip]', data.ip);
      setText('[data-ip-status]', 'OK');
    } else {
      setText('[data-client-ip]', '--');
      setText('[data-ip-status]', 'Unavailable');
    }
  } catch (_) {
    setText('[data-client-ip]', '--');
    setText('[data-ip-status]', 'Unavailable');
  }
});

