#!/bin/bash
cd /home/sp/cyber-course/projects/securewave/frontend

# Create modern home.html
cat > home.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SecureWave VPN - Enterprise-Grade Privacy & Security</title>
  <link rel="stylesheet" href="/static/css/global.css">
</head>
<body>
  <nav class="navbar">
    <div class="navbar-container">
      <a href="/home.html" class="navbar-brand">
        <img src="/static/assets/logo.svg" alt="SecureWave VPN">
        <span>SecureWave</span>
      </a>
      <button class="navbar-toggle" id="navToggle">☰</button>
      <ul class="navbar-menu" id="navMenu">
        <li><a href="/home.html" class="active">Home</a></li>
        <li><a href="/services.html">Features</a></li>
        <li><a href="/vpn.html">VPN Config</a></li>
        <li><a href="/subscription.html">Pricing</a></li>
        <li><a href="/dashboard.html" class="d-none" id="dashLink">Dashboard</a></li>
        <li><a href="/login.html" class="btn btn-secondary btn-sm" id="loginBtn">Login</a></li>
        <li><a href="/register.html" class="btn btn-primary btn-sm" id="registerBtn">Get Started</a></li>
        <li><button class="btn btn-outline btn-sm d-none" id="logoutBtn">Logout</button></li>
      </ul>
    </div>
  </nav>

  <main>
    <section class="hero">
      <div class="container">
        <div class="badge mb-4">🔒 Enterprise-Grade VPN • Powered by WireGuard</div>
        <h1 class="hero-title">Secure Your Digital Life with SecureWave VPN</h1>
        <p class="hero-subtitle">
          Military-grade encryption, blazing-fast speeds, and intelligent server selection powered by AI.
          Experience true online privacy across all your devices.
        </p>
        <div class="hero-actions">
          <a href="/register.html" class="btn btn-primary btn-lg">Start Free Trial</a>
          <a href="/vpn.html" class="btn btn-outline btn-lg">Get VPN Config</a>
        </div>
      </div>
    </section>

    <section class="container" style="padding: 4rem 0;">
      <h2 class="text-center mb-4">Why Choose SecureWave?</h2>
      <div class="grid grid-3">
        <div class="card fade-in">
          <h3>🚀 Lightning Fast</h3>
          <p>AI-powered server selection using MARL + XGBoost algorithms ensures you always connect to the fastest server.</p>
        </div>
        <div class="card fade-in">
          <h3>🔐 Military Encryption</h3>
          <p>WireGuard protocol with ChaCha20 encryption keeps your data secure from hackers and surveillance.</p>
        </div>
        <div class="card fade-in">
          <h3>🌍 Global Network</h3>
          <p>Connect to servers in 50+ countries with unlimited bandwidth and zero logging policy.</p>
        </div>
        <div class="card fade-in">
          <h3>💳 Secure Payments</h3>
          <p>Integrated Stripe & PayPal checkout with subscription management and instant activation.</p>
        </div>
        <div class="card fade-in">
          <h3>📱 All Devices</h3>
          <p>Works seamlessly on Windows, Mac, Linux, iOS, Android, and routers. One subscription, unlimited devices.</p>
        </div>
        <div class="card fade-in">
          <h3>⚡ Instant Setup</h3>
          <p>Generate your WireGuard config in seconds with QR code support for mobile devices.</p>
        </div>
      </div>
    </section>

    <section class="container" style="padding: 4rem 0;">
      <div class="grid grid-2">
        <div class="card">
          <h2>Real-Time Dashboard</h2>
          <p>Monitor your VPN usage, manage subscriptions, and download configs from your personal dashboard.</p>
          <ul style="list-style: none; padding: 0;">
            <li class="badge badge-success" style="margin: 0.5rem 0;">✓ One-click config download</li>
            <li class="badge badge-success" style="margin: 0.5rem 0;">✓ QR code for mobile</li>
            <li class="badge badge-success" style="margin: 0.5rem 0;">✓ Subscription management</li>
            <li class="badge badge-success" style="margin: 0.5rem 0;">✓ Usage analytics</li>
          </ul>
          <a href="/dashboard.html" class="btn btn-primary mt-4">Open Dashboard</a>
        </div>
        <div class="card">
          <h2>Developer Friendly</h2>
          <p>Built with modern technologies for developers who care about security and performance.</p>
          <div style="display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 1rem 0;">
            <span class="badge">FastAPI</span>
            <span class="badge">WireGuard</span>
            <span class="badge">XGBoost AI</span>
            <span class="badge">Azure</span>
            <span class="badge">Docker</span>
          </div>
          <a href="/api/docs" class="btn btn-outline mt-4">API Documentation</a>
        </div>
      </div>
    </section>
  </main>

  <footer class="footer">
    <div class="container">
      <p>© 2025 SecureWave VPN. Enterprise-grade security for everyone.</p>
    </div>
  </footer>

  <script src="/static/js/main.js"></script>
</body>
</html>
EOF

echo "✅ home.html created"
