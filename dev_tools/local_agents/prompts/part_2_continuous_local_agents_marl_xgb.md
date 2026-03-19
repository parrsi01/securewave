MODE: LOCAL AGENTS + MARL/XGB

OBJECTIVE:
Continuously simulate Linux VM VPN failures, detect the likely root cause locally, evaluate recovery strategies, and persist the results so later patches are trained against real local evidence.

REPO CONTEXT:
- Agent runner: `dev_tools/local_agents/run_securewave_vpn_agents.py`
- Fault lab agent: `dev_tools/local_agents/vpn_fault_lab_agent.py`
- Recovery ML agent: `dev_tools/local_agents/vpn_recovery_ml_agent.py`
- Raw telemetry: `artifacts/local_agents/runtime/`
- Consolidated persistence bundle: `vpn_diagnostics/`

MINIMUM AGENT SET
1. `FaultLabAgent`
   - probes connectivity state
   - runs safe or destructive fault simulations
   - writes telemetry compatible with the existing `ml/` pipeline

2. `RecoveryMlAgent`
   - trains or updates local QoS and risk models
   - uses the MARL policy engine to rank recovery actions
   - emits patch recommendations for repeated failure signatures

If more specialized agents are added later, keep them subordinate to these two persisted pipelines rather than creating isolated logs.

STEP 1 — CONTINUOUS SIMULATION LOOP
Run:

```bash
.venv/bin/python dev_tools/local_agents/run_securewave_vpn_agents.py \
  --agent all \
  --cycles 0 \
  --interval-seconds 30 \
  --api-base-url https://138.199.204.139.nip.io/api \
  --interface sw-wg \
  --diagnostics-dir vpn_diagnostics
```

For active fault injection, add:
- `--execute-destructive`
- `--execute-recovery`
- `--allow-vpn-bounce`
- `--preferred-wifi-connection "<wifi profile name>"`

STEP 2 — DETECTION
Each cycle must detect and persist:
- current connectivity snapshot
- simulated fault scenarios
- proposed recovery actions
- actual recovery results
- repeated failure signatures

STEP 3 — LEARNING
Use the existing SecureWave MARL + XGBoost stack:
- `services/marl_policy.py`
- `services/xgb_qos.py`
- `services/xgb_risk.py`
- `ml/data.py`

The goal is not blind auto-patching. The goal is:
- rank likely fixes faster on the next failure
- identify repeated failure signatures
- produce evidence-backed patch recommendations

STEP 4 — PERSISTENCE
Save everything under `vpn_diagnostics/`:
- `vpn_diagnostics/logs/logs.json`
- `vpn_diagnostics/simulations/simulations.json`
- `vpn_diagnostics/test_results/fixes.json`
- `vpn_diagnostics/test_results/failures.json`
- `vpn_diagnostics/model/model_stats.json`

Retain the raw low-level artifacts in `artifacts/local_agents/runtime/` for deeper inspection.

STEP 5 — FEEDBACK LOOP
At the end of each cycle:
- compare successful and failed recoveries
- update model stats if enough records exist
- rewrite patch recommendations if the same signatures repeat
- leave the saved data intact for the next prompt run

STEP 6 — OUTPUT
Return:
1. simulation results summary
2. most common failure signature
3. best-performing recovery action
4. latest model training status
5. patch recommendations generated from repeated evidence
