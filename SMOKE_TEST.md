# Frontend Smoke Test Checklist

1) Load `/home.html` → CSS/JS loads, hero displays.
2) Load `/login.html` → no errors shown before typing.
3) Register new user → redirect to `/dashboard.html`.
4) Refresh `/dashboard` → page loads (no 404).
5) On dashboard, connect demo VPN → status shows "Connected (Demo)".
6) Download config from dashboard → file downloads.
7) Visit `/vpn` → connect/disconnect works, status updates.
8) Visit `/settings` and `/subscription` → page loads and nav works.
9) Visit `/diagnostics` → health + events load (requires auth).
