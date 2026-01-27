(() => {
  const script = document.createElement('script');
  const parts = ['flutter_', 'boot', 'strap', '.js'];
  script.src = parts.join('');
  script.async = true;
  document.body.appendChild(script);
})();
