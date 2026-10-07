"""Seeded CPU-only multi-agent simulator and XGBoost training.

Synthetic data tests the implementation, not real VPN performance. Independent
client policies interact through shared evolving server congestion. No client,
WireGuard, account or production traffic is collected by this module.
"""

import argparse
import hashlib
import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from ml.routing_policy import FEATURES, action_indices, recommend_index, state_key

RESEARCH_SHA = "a2a95da72e0cb930857fb3db26d80d7a0a6808e0"
SPLIT_GROUPS = {"train": (0, 1, 2), "validation": (3, 4), "test": (5, 6)}
N_AGENTS = 3
N_SERVERS = 4
STEPS = 24
GAMMA = 0.9
LEARNING_RATE = 0.18


def episode_specs(seed: int, episodes: int) -> dict[str, list[tuple[int, int]]]:
    if seed < 0 or seed >= 2**32 or episodes <= 0:
        raise ValueError("Seed must be a uint32 and episodes must be positive")
    counts = {"train": episodes, "validation": max(4, episodes // 4), "test": max(4, episodes // 4)}
    span = max(counts.values()) + 1
    return {name: [(seed + split * span + i, groups[i % len(groups)])
                   for i in range(counts[name])]
            for split, (name, groups) in enumerate(SPLIT_GROUPS.items())}


def utility(features) -> float:
    latency, loss, jitter, load = features
    return max(0.0, min(1.0, 0.45 * math.exp(-latency / 180)
                        + 0.25 * (1 - loss) + 0.15 * math.exp(-jitter / 35)
                        + 0.15 * (1 - load)))


class Simulation:
    def __init__(self, seed: int, group: int):
        import numpy as np
        self.rng = np.random.default_rng(seed)
        # Held-out group identifiers are disjoint; physical ranges overlap so
        # evaluation tests generalization rather than an impossible extrapolation.
        self.base_latency = self.rng.uniform(20, 120, N_SERVERS)
        self.capacity = self.rng.uniform(0.75, 1.3, N_SERVERS)
        self.background = self.rng.uniform(0.05, 0.4, N_SERVERS)
        self.load = self.background.copy()
        self.phase = group * math.pi / 7
        self.step = 0

    def observations(self):
        import numpy as np
        latency = self.base_latency + 100 * self.load**2
        loss = np.clip(0.005 + 0.10 * self.load**3, 0, 1)
        jitter = 2 + 28 * self.load**2
        return np.column_stack((latency, loss, jitter, self.load))

    def advance(self, selected):
        import numpy as np
        counts = np.bincount(selected, minlength=N_SERVERS)
        seasonal = 0.06 * math.sin(self.step / 4 + self.phase)
        noise = self.rng.normal(0, 0.015, N_SERVERS)
        self.load = np.clip(0.55 * self.load + 0.45 * self.background
                            + 0.17 * counts / self.capacity + seasonal + noise, 0, 1)
        outcome = self.observations()
        # Generate noise for every server regardless of decisions, making the
        # environment random stream identical across paired evaluation policies.
        outcome[:, 0] = np.maximum(1, outcome[:, 0] + self.rng.normal(0, 3, N_SERVERS))
        outcome[:, 2] = np.maximum(0, outcome[:, 2] + self.rng.normal(0, 1, N_SERVERS))
        self.step += 1
        return [utility(outcome[index]) for index in selected]


@dataclass
class Agent:
    q_table: dict[str, list[float]] = field(default_factory=dict)
    visits: dict[str, list[int]] = field(default_factory=dict)
    updates: int = 0

    def update(self, state: str, action: int, reward: float, next_state: str, terminal: bool):
        values = self.q_table.setdefault(state, [0.0, 0.0, 0.0])
        visits = self.visits.setdefault(state, [0, 0, 0])
        continuation = 0.0 if terminal else max(self.q_table.get(next_state, [0.0, 0.0, 0.0]))
        values[action] += LEARNING_RATE * (reward + GAMMA * continuation - values[action])
        visits[action] += 1
        self.updates += 1


def collect_training_rows(specs):
    import numpy as np
    features, targets, row_episodes = [], [], []
    for seed, group in specs:
        sim = Simulation(seed, group)
        choices_rng = np.random.default_rng(seed ^ 0xC011EC7)
        for _ in range(STEPS):
            before = sim.observations().copy()
            chosen = choices_rng.integers(0, N_SERVERS, N_AGENTS).tolist()
            after_utility = sim.advance(chosen)
            for index, reward in zip(chosen, after_utility):
                features.append(before[index].tolist())
                targets.append(reward)
                row_episodes.append(seed)
    return np.asarray(features, dtype=float), np.asarray(targets, dtype=float), row_episodes


def learn_policy(model, specs):
    import numpy as np
    agents = [Agent() for _ in range(N_AGENTS)]
    for episode, (seed, group) in enumerate(specs):
        sim = Simulation(seed, group)
        rng = np.random.default_rng(seed ^ 0xAC710)
        previous = [None] * N_AGENTS
        epsilon = max(0.1, 0.8 * (1 - episode / max(1, len(specs))))
        for step in range(STEPS):
            obs = sim.observations()
            prediction = model.predict(obs).tolist()
            loads = obs[:, 3].tolist()
            baseline = int(np.argmin(obs[:, 0]))
            indices = action_indices(prediction, loads, baseline)
            key = state_key(prediction, loads)
            actions = [int(rng.integers(0, 3)) if rng.random() < epsilon else
                       max(range(3), key=lambda action: agent.q_table.get(key, [0.0] * 3)[action])
                       for agent in agents]
            selected = [indices[action] for action in actions]
            rewards = sim.advance(selected)
            next_obs = sim.observations()
            next_key = state_key(model.predict(next_obs).tolist(), next_obs[:, 3].tolist())
            for i, agent in enumerate(agents):
                penalty = 0.03 if previous[i] is not None and previous[i] != selected[i] else 0.0
                agent.update(key, actions[i], rewards[i] - penalty, next_key, step == STEPS - 1)
            previous = selected
    merged = {}
    for state in sorted({state for agent in agents for state in agent.q_table}):
        merged[state] = []
        for action in range(3):
            count = sum(agent.visits.get(state, [0] * 3)[action] for agent in agents)
            value = sum(agent.q_table.get(state, [0.0] * 3)[action]
                        * agent.visits.get(state, [0] * 3)[action] for agent in agents)
            merged[state].append(value / count if count else 0.0)
    return merged, [agent.updates for agent in agents]


def evaluate(model, policy, specs):
    import numpy as np
    results = {}
    for method in ("baseline", "xgboost_only", "marl_xgboost"):
        episode_returns, switches, reasons = [], 0, {}
        for seed, group in specs:
            sim = Simulation(seed, group)
            previous, rewards = [None] * N_AGENTS, []
            for _ in range(STEPS):
                obs = sim.observations()
                predicted = model.predict(obs).tolist()
                loads = obs[:, 3].tolist()
                baseline = int(np.argmin(obs[:, 0]))
                if method == "baseline":
                    chosen, reason = baseline, "baseline"
                elif method == "xgboost_only":
                    chosen, reason = action_indices(predicted, loads, baseline)[0], "xgboost_only"
                else:
                    chosen, reason = recommend_index(predicted, loads, baseline, policy)
                selected = [chosen] * N_AGENTS
                actual = sim.advance(selected)
                reasons[reason] = reasons.get(reason, 0) + N_AGENTS
                for agent, value in enumerate(actual):
                    switched = previous[agent] is not None and previous[agent] != chosen
                    switches += int(switched)
                    rewards.append(value - (0.03 if switched else 0.0))
                previous = selected
            episode_returns.append(float(np.mean(rewards)))
        results[method] = {"mean_utility": float(np.mean(episode_returns)),
                           "std_episode_utility": float(np.std(episode_returns)),
                           "episode_utilities": episode_returns, "switches": switches,
                           "decision_reasons": reasons, "episodes": len(specs)}
    return results


def train(output: Path, seed: int = 42, episodes: int = 80):
    import numpy as np
    import sklearn
    import xgboost as xgb
    specs = episode_specs(seed, episodes)
    x_train, y_train, row_episodes = collect_training_rows(specs["train"])
    model = xgb.XGBRegressor(n_estimators=60, max_depth=3, learning_rate=0.08,
                             objective="reg:squarederror", tree_method="hist", n_jobs=1,
                             random_state=seed, subsample=1.0, colsample_bytree=1.0)
    # Neither holdout is passed as eval_set, used for early stopping, or used to
    # select hyperparameters. The complete policy is frozen before evaluation.
    model.fit(x_train, y_train)
    q_table, updates = learn_policy(model, specs["train"])
    frozen_policy = json.dumps(q_table, sort_keys=True)
    metrics = {name: evaluate(model, q_table, specs[name]) for name in ("validation", "test")}
    assert json.dumps(q_table, sort_keys=True) == frozen_policy
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.chmod(0o700)
    model.save_model(output / "model.json")
    policy = {"schema_version": 1, "q_table": q_table}
    (output / "policy.json").write_text(json.dumps(policy, indent=2, sort_keys=True, allow_nan=False) + "\n")
    for name in ("model.json", "policy.json"):
        (output / name).chmod(0o600)
    hashes = {name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in ("model.json", "policy.json")}
    manifest = {"schema_version": 1, "feature_names": list(FEATURES),
                "model_origin": "synthetic_simulator", "model_version": f"routing-simulator-v1-seed{seed}-episodes{episodes}",
                "sha256": hashes, "provenance": {"research_sha": RESEARCH_SHA,
                "research_repository": "parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks",
                "adaptation": "Independent tabular routing agents and XGBoost utility regression; no anomaly classifier restoration",
                "xgboost_version": xgb.__version__, "numpy_version": np.__version__,
                "scikit_learn_version": sklearn.__version__},
                "data": {"source": "synthetic_simulator", "seed": seed, "agents": N_AGENTS,
                "servers": N_SERVERS, "steps_per_episode": STEPS, "training_rows": len(y_train),
                "training_row_episode_ids": sorted(set(row_episodes)),
                "splits": {name: {"episode_seeds": [s for s, _ in rows], "regime_groups": sorted({g for _, g in rows})}
                           for name, rows in specs.items()}, "agent_update_counts": updates,
                "evaluation_frozen": True}, "metrics": metrics,
                "limitations": ["Synthetic utility is not evidence of production VPN performance.",
                                "No production traffic, training data or account identifiers are used.",
                                "Independent learned Q tables are merged by action visit count for shadow evaluation."]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True, allow_nan=False) + "\n")
    (output / "manifest.json").chmod(0o600)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--episodes", type=int, default=80)
    args = parser.parse_args()
    if args.episodes <= 0 or not 0 <= args.seed < 2**32:
        parser.error("--episodes must be positive and --seed must be a uint32")
    manifest = train(args.output, args.seed, args.episodes)
    print(json.dumps({"model_version": manifest["model_version"], "origin": manifest["model_origin"],
                      "training_rows": manifest["data"]["training_rows"], "metrics": manifest["metrics"]}, sort_keys=True))


if __name__ == "__main__":
    main()
