# SecureWave Linux App

This Flutter app is Linux + WireGuard only.

The app expects a live backend at `SECUREWAVE_API_BASE_URL`, a registered WireGuard server in the database, and the local SecureWave helper service installed on the VM.

```bash
make linux-runtime-install
SECUREWAVE_API_BASE_URL=http://localhost:8000/api make flutter-run
```

The app is intentionally scoped to the live Linux WireGuard path.
