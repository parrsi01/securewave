# Experimental MARL + XGBoost routing

SecureWave 1.0.0 includes a backend-only routing experiment. It records an
advisory recommendation while the established selector continues to choose
every VPN connection. Default mode is off; there is no live exploration or
automatic activation. Authentication, Flutter, WireGuard keys and the Linux
helper remain independent of native ML packages.

## Research lineage

The reference is Simon Parris's
[network-anomaly research repository](https://github.com/parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks)
at `a2a95da72e0cb930857fb3db26d80d7a0a6808e0`, specifically
`Code/marl_xgb.py` and `Code/enhanced_marl_xgb.py`. The original scripts use
neighbor aggregation and reward/trust updates; the enhanced variant uses
weighted ensembles and feature search. Neither provides the tabular Bellman
policy-learning loop used here. Their anomaly classifiers cannot serve as
VPN-routing models without a new specification.

This is an attributed adaptation with a new objective, simulator, feature
contract and evaluation. It claims neither the paper's classifier accuracy
nor federated privacy, distributed production agents or attack detection.
Local development agents audited the research, historical data and acceptance
prerequisites before implementation.

## Architecture and authority

```text
Approved inventory -> read-only collector -> private measured telemetry
Synthetic episodes -> XGBoost + three Q-learning agents -> frozen artifacts
Artifacts + telemetry -> offline CPU worker -> private prediction snapshot
Eligible servers + existing baseline -> shadow observer -> advisory log
Existing baseline -------------------------------------> VPN provisioning
```

Only the collector probes hosts; only the worker imports XGBoost. The API
reads bounded regular files and a standard-library policy helper. It performs
no ML training, native inference, network probe or database write for this
experiment. `routes/vpn.py::_select_server` always returns its original server
object, even when the observer recommends another or raises an exception.

## Feature contract and algorithms

The exact ordered feature vector is
`[latency_ms, packet_loss, jitter_ms, load_ratio]`: milliseconds, fraction,
milliseconds and normalized load. Allowed ranges are [0,5000], [0,1],
[0,5000], [0,1]. Invalid, missing, stale or nonfinite inputs are rejected.

Three independent client agents interact through four simulated servers with
evolving congestion. XGBoost regresses **post-action utility** from pre-action
observations collected under randomized offline actions. The bounded [0,1]
utility combines latency, loss, jitter and congestion; switching costs 0.03.
It is a simulator reward, not an established commercial VPN quality metric.

Each agent maintains its own Q table and performs:

```text
Q_i(s,a) <- Q_i(s,a) + alpha * [r_i + gamma * max_b Q_i(s',b) - Q_i(s,a)]
```

Alpha is 0.18, gamma 0.9; terminal transitions have zero continuation.
Actions choose highest predicted utility, least load, or the baseline. State
encodes quantized quality/load relationships without identities. Exploration
is offline only. Visit-weighted agent tables form the exported policy. Unseen
states explicitly fall back to XGBoost ranking. A fleet size other than the
four training candidates has unseen context, so it does not demonstrate
generalized learned multi-agent routing.

The simulator baseline minimizes latency. Production retains its established
health/performance/latency ordering. These are different comparators; the
synthetic experiment cannot estimate production uplift.

## Data quality and evaluation

The historical 10,000-row VPN CSV is synthetic. Its same-row QoS formula and
repeated user/server groups make it unsuitable as real generalization evidence.
It is neither committed nor silently used to train this model.

New simulator episodes have disjoint seeds and regime groups across training,
validation and test. Every episode stays wholly within one split. Neither
holdout is used for fitting, early stopping or policy updates. Evaluation uses
paired random streams with a frozen model and policy. The manifest records
seeds, groups, library versions, rows, update counts, feature order and digests.
No parameter was tuned after inspecting the final test.

| Frozen seed-42 test: 20 paired episodes | Mean utility |
| --- | ---: |
| Simulator latency baseline | 0.525263 |
| XGBoost alone | 0.545234 |
| MARL + XGBoost | 0.533659 |

The combined policy does **not** beat XGBoost alone. These results justify
continued experimentation, not activation. Training produces 5,760 observations,
1,920 Bellman updates per agent and 13 learned contexts.

Measured inputs come from five ICMP probes (mean RTT, packet-loss fraction,
RTT standard deviation) and read-only SSH (one-minute load average and CPU
count). `load_ratio=min(1,loadavg/cores)` is normalized run-queue load, not CPU
utilization. ICMP deviation is a jitter surrogate, and five probes yield coarse
20% loss increments. The collector perspective is explicitly
`collector_host_to_server`, not client application QoS. Snapshot metadata must
carry the exact measurement method; fresh timestamps alone are insufficient.

The deployed legacy health monitor estimates jitter/load and substitutes
defaults on some failures. Those database values are excluded from measured
inputs. Actual ICMP/load observations also differ semantically from simulator
congestion; they are not automatically converted into training data. Real
future-outcome targets, time-separated validation and calibration remain
required before retraining or activation.

On 7 October 2026, read-only inventory inspection found five registry entries
sharing one physical IP, with one eligible candidate for both tiers. Duplicate
normalized endpoint addresses are rejected by the collector; distinct addresses
alone do not establish independent physical hosts. No real multi-server
performance improvement is claimed.

## Reproduce and operate

Use Python 3.12, `requirements-dev.txt` and optional `requirements-ml.txt`.
The tested CPU stack is NumPy 1.26.4, SciPy 1.16.3, scikit-learn 1.5.2
and XGBoost 2.1.3. Scikit-learn supplies the offline regressor wrapper.

```sh
python -m pip install -r requirements-dev.txt -r requirements-ml.txt
python -m ml.train_routing --output /var/tmp/securewave-routing-model \
  --seed 42 --episodes 80
python -m pytest --confcutdir=tests -q tests/test_routing_training.py \
  tests/test_routing_shadow.py tests/test_routing_worker.py \
  tests/test_routing_collection.py tests/test_routing_integration.py
```

Create an owned mode-0700 output directory and a mode-0600 inventory containing
`schema_version:1`, `servers:[{server_id,address}]` for approved registered
nodes. Supply an existing host-verified SSH key, never source credentials.

```sh
python scripts/collect_routing_telemetry.py --inventory /private/fleet.json \
  --ssh-key /private/operator-key --output /private/telemetry.json
python scripts/routing_shadow_worker.py --artifacts /private/model \
  --telemetry /private/telemetry.json --output /private/snapshot.json
```

The worker verifies exact feature order and model/policy digests, infers on CPU
outside the API, and atomically writes mode-0600 output. Generated artifacts
and telemetry stay outside Git and public downloads. No packet contents,
account identifiers, passwords, keys or browsing history are collected.

The API accepts optional environment settings:

```text
SECUREWAVE_ROUTING_SHADOW=shadow
SECUREWAVE_ROUTING_SNAPSHOT=/private/snapshot.json
SECUREWAVE_ROUTING_POLICY=/private/model/policy.json
```

The snapshot must be owned by the API identity and private. Coordinate file
ownership as an operator; never weaken permissions to make a probe succeed.
Snapshots expire after 120 seconds, with five seconds future tolerance.
Collection/worker scheduling belongs outside requests; this first version
does not install a telemetry daemon. Explicit choices and a single candidate
skip observation. All eligible candidates need measured coverage.

Malformed artifacts, missing optional packages, stale samples, unavailable
probes and logging errors fail open to normal routing. Mode `off` performs zero
artifact reads. CI independently checks the research pipeline and app layers.
Actual GUI acceptance remains tied to its exact public package and deployed API;
it does not by itself prove local ML code was deployed.
