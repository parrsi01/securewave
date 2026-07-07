# External Load Test Authorization Status

Status: not run

Reason: this evidence run is explicitly read-only and does not authorize external load testing.

Command shape that would be needed after explicit authorization:

```bash
python3 scripts/linux_enterprise_vpn_certification.py \
  --cohorts 100 250 500 1000 \
  --workers 16 \
  --include-live-proofs \
  --external-target <authorized SecureWave-owned API base> \
  --output-dir artifacts/post-merge-enterprise-release/load-test
```

Required authorization:
- Written approval naming the target host/API base.
- Confirmed load limits, stop conditions, and maintenance window.
- Confirmation that WireGuard/OpenVPN/IKEv2 profile fetch and usage reporting traffic is allowed.

Expected target:
- SecureWave-owned production or staging infrastructure only.

Safety limits:
- Stop on elevated error rate, 5xx responses, database saturation, host CPU/memory pressure, or operator request.
- Do not include real user credentials in logs or artifacts.
