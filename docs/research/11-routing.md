# 11. Experimental routing policy and validity

## 11.1 Objective and deployment contract

The optional extension studies whether predicted future utility and learned
action values can improve server selection. It adapts the author's multi-agent
XGBoost motivation [9] to a new task. It does not reuse anomaly labels or the
paper's accuracy results. The original reward/trust and ensemble scripts do
not contain the Bellman Q-learning implemented in this experiment.

Let C be the account's current eligible server set and b(C) the established
selector. The deployed contract is:

```text
selected(C) = b(C), independently of any shadow recommendation h(C)
```

Thus failures or differences in h cannot change provisioning authority. No
activation flag exists in this version. Explicit choices retain their normal
eligibility checks; zero candidates return unavailable and one candidate skips
the experiment. The inference worker is separate from the API request process.

## 11.2 Learning specification

Three simulated clients maintain independent Q tables while sharing four
congested server resources. The feature vector is ordered latency, loss,
jitter and normalized load. An XGBoost regressor estimates post-action utility
from pre-action features generated under randomized offline actions.

The simulator utility weights are 0.45 exp(-latency/180), 0.25(1-loss),
0.15 exp(-jitter/35) and 0.15(1-load), bounded in [0,1]. Switching subtracts
0.03 from an agent's reward. Independent Q updates use learning rate 0.18,
discount 0.9 and zero continuation at terminal transitions. Three actions
represent highest predicted utility, lowest load and the baseline. Quantized
context captures quality/load relationships rather than identities.

Visit-weighted aggregation forms one advisory table from the independent
learners. Unknown contexts use explicitly labelled XGBoost-only ranking.
Training with four candidates does not validate other fleet sizes; those
sizes have unseen context. The deployed single-host fleet therefore supplies
no evidence of learned alternative-server selection.

For n candidates, T trees of depth d and k visited states, offline prediction
costs approximately O(nTd); deterministic ranking costs O(n). The tabular
update costs O(1) for three actions, and policy storage is O(k). API observation
is bounded by candidate count and fixed file-size limits; it imports no native
ML library. These bounds do not promise a wall-clock deadline for filesystem
I/O, which remains an operator-controlled dependency in shadow mode.

## 11.3 Experimental controls and outcomes

Episode seeds and regime groups are disjoint across train, validation and test.
All model fitting and policy updates occur on training episodes. Both holdouts
use the frozen artifacts and paired random streams; neither is an early-stopping
set. The manifest records the split, dependencies, feature order and hashes.

The seed-42, 80-training-episode run produced 5,760 XGBoost observations and
1,920 updates per agent. Over 20 frozen test episodes, mean utility was 0.525263
for the simulator latency baseline, 0.545234 for XGBoost alone and 0.533659 for
the combined policy. The combined method trails the simpler ablation. No
statistical significance or real-world routing benefit is inferred. Production
also uses a different baseline ordering, so these values are not its uplift.

## 11.4 Construct validity and required future evidence

Real collection measures collector-to-server ICMP mean RTT, loss fraction and
RTT standard deviation, together with load average per CPU. These have the
same numeric shape as simulator features but different semantics. Five ICMP
probes give coarse loss resolution; load average includes blocked/runnable
work rather than simulator congestion. The legacy monitor's estimated jitter
and simulated load are explicitly excluded from measured evidence.

An external probe on 7 October received no ICMP replies. No missing RTT was
filled with a default and no measured snapshot was fabricated. Freshness,
measurement method, perspective, normalized predictions and artifact hashes
are checked before advisory evaluation. None establishes model calibration.

Activation would require independent physical nodes, measured future outcome
targets, calibration, time-separated evaluation, baseline/ablation comparison,
uncertainty estimates and bounded switching/failure experiments. A new review
would also need to specify privacy, retention and authority changes. The current
extension remains an implementation experiment with fail-open shadow behavior.

The [operator and reproducibility guide](../development/routing-optimizer.md)
provides commands, schemas and data provenance. App lifecycle evidence remains
separate from this model's validity.
