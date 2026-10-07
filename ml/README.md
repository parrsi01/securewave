# Offline MARL + XGBoost routing adaptation

This experiment adapts Simon Parris's decentralized anomaly-detection research
to VPN server selection. It does not restore an anomaly detector, train on
production traffic, or establish that a VPN connection is working.

The research reference is revision
`a2a95da72e0cb930857fb3db26d80d7a0a6808e0` of
[Decentralized Federated Detection of Network Anomalies](https://github.com/parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks).
The original code provides local XGBoost agents, network topology experiments
and trust ideas. This adaptation implements routing actions and Bellman learning
explicitly; it does not imply the original scripts learned routing policies.

## Data and model

Three independent simulated client agents share four simulated server slots.
Assignments increase congestion; background load, capacity and seasonal demand
affect the next observation. Slot indices exist only inside this experiment.
Runtime recommendations must use eligible real server inventory.

The single feature order used for collection and inference is:

| Feature | Units |
| --- | --- |
| `latency_ms` | milliseconds |
| `packet_loss` | fraction, 0 to 1 |
| `jitter_ms` | milliseconds |
| `load_ratio` | normalized load, 0 to 1 |

The CPU-only XGBoost regressor predicts post-assignment utility from the chosen
server's pre-assignment observation. All three assignments are applied before
reward measurement, so the target reflects contention rather than a formula
computed from the same feature row. Utility weights latency, loss, jitter and
available capacity. These synthetic quantities are not measured VPN throughput.

## Learning and inference

Agents choose among three actions: the highest predicted utility, the lowest
load, or the caller's existing baseline. Context buckets encode relative
prediction differences and the quality winner's load; they contain no user or
server identifiers. Ties resolve to the lowest candidate or action index.

Each agent updates its own table:

`Q(s,a) <- Q(s,a) + 0.18 * [r + 0.9 * max Q(s',a') - Q(s,a)]`.

Terminal transitions omit the continuation term. Reward includes a 0.03 switch
penalty. Exploration decreases during offline training and remains at least
0.1 to sample each action. There is no exploration during inference. Independent
tables are merged using action visit counts to produce one shadow policy.
The learner is a research implementation of independent multi-agent Q-learning;
it does not assert convergence in the shared, nonstationary environment.

## Evaluation and artifacts

Train, validation and test have disjoint episode seeds and demand-regime group
identifiers. Training uses only training episodes; neither holdout is an early
stopping set or a policy-update source. Validation and final test compare the
frozen baseline, XGBoost-only and combined policies on paired environment seeds.
The random stream is independent of chosen assignments. Reports preserve each
episode's mean reward, switches and decision reasons. They do not claim a
production speed or reliability improvement.

```bash
python -m ml.train_routing --output /private/path/routing-candidate --seed 42 --episodes 80
python -m pytest -q tests/test_routing_training.py
```

Install the separate ML development dependencies before training. Production
request handling imports only `routing_policy.py`, which uses the standard
library. The trainer exports `model.json`, `policy.json` and `manifest.json`.
The manifest records the exact feature order, both artifact hashes, dependency
versions, research provenance, split identifiers, agent update counts and
holdout metrics. All outputs are labelled `synthetic_simulator`.

The pure recommendation helper falls back to the XGBoost quality action for an
unseen policy context. Runtime shadow handling separately falls back to the
unchanged product baseline for missing artifacts or invalid/stale telemetry.
Even a valid shadow recommendation does not change the selected server.
