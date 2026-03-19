# Local SecureWave VPN Agents

This package adds two local agents that reuse the existing SecureWave MARL/XGBoost stack and the existing Linux fault-injection harnesses. It also ships a two-part prompt pack for:

- live Codex 5.4 `xhigh` debugging with preplanned failure tests
- continuous local simulation and patch-learning during later prompt runs

Agents:

- `FaultLabAgent`
  - Continuously probes the Linux VM/network/VPN state.
  - Reuses `dev_tools/sandbox/chaos_tests/network_drop.py`.
  - Reuses `dev_tools/sandbox/live_validation/network_failure_cases.py`.
  - Writes telemetry compatible with the existing `ml/` pipeline.

- `RecoveryMlAgent`
  - Trains/updates local QoS and risk models from the collected telemetry.
  - Uses the existing MARL policy engine to decide recovery actions.
  - Can safely recover Wi-Fi/networking locally and optionally bounce the VPN interface.
  - Emits patch recommendations for repeated failure signatures.

Run both agents together:

```bash
python3 dev_tools/local_agents/run_securewave_vpn_agents.py \
  --agent all \
  --cycles 0 \
  --interval-seconds 30 \
  --api-base-url https://138.199.204.139.nip.io/api \
  --interface sw-wg \
  --diagnostics-dir vpn_diagnostics
```

Enable safe local recovery actions:

```bash
python3 dev_tools/local_agents/run_securewave_vpn_agents.py \
  --agent all \
  --cycles 0 \
  --execute-recovery \
  --preferred-wifi-connection "Your WiFi SSID" \
  --diagnostics-dir vpn_diagnostics
```

Enable destructive fault injection only when you explicitly want to simulate real Linux VM outages:

```bash
sudo python3 dev_tools/local_agents/run_securewave_vpn_agents.py \
  --agent all \
  --cycles 5 \
  --execute-destructive \
  --execute-recovery \
  --allow-vpn-bounce \
  --preferred-wifi-connection "Your WiFi SSID" \
  --diagnostics-dir vpn_diagnostics
```

Artifacts:

- `artifacts/local_agents/runtime/fault_lab/fault_lab_events.jsonl`
- `artifacts/local_agents/runtime/vpn_fault_lab_telemetry.csv`
- `artifacts/local_agents/runtime/recovery_ml/latest_recovery_cycle.json`
- `artifacts/local_agents/runtime/recovery_ml/patch_recommendations.md`
- `vpn_diagnostics/logs/logs.json`
- `vpn_diagnostics/simulations/simulations.json`
- `vpn_diagnostics/test_results/fixes.json`
- `vpn_diagnostics/test_results/failures.json`
- `vpn_diagnostics/model/model_stats.json`

Notes:

- The agents use MARL + XGBoost when the optional ML dependencies are installed. If not, they fall back to MARL + rule-based scoring.
- Recovery is dry-run by default.
- The agents do not auto-edit application source files. They emit patch recommendations tied to repeated failure signatures so code fixes can be applied deliberately.
- The preplanned unit-test playbook for the common Linux VM failure classes is in `dev_tools/local_agents/vpn_failure_playbook.py` and `tests/test_vpn_connectivity.py`.
- Prompt templates are in `dev_tools/local_agents/prompts/`.
