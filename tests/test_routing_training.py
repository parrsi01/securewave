"""Research correctness tests; these do not substitute for real VPN acceptance."""

import hashlib
import json
import math

import pytest

from ml.routing_policy import FEATURES, action_indices, recommend_index, state_key
from ml.train_routing import Agent, GAMMA, LEARNING_RATE, Simulation, episode_specs


def test_policy_actions_are_stable_and_use_learned_values():
    predictions, loads = [0.8, 0.9, 0.6], [0.8, 0.6, 0.1]
    key = state_key(predictions, loads)
    assert action_indices(predictions, loads, 0) == (1, 2, 0)
    assert recommend_index(predictions, loads, 0, {}) == (1, "xgboost_only_unseen_state")
    assert recommend_index(predictions, loads, 0, {key: [0.1, 0.7, 0.2]}) == (2, "marl_xgboost_load")
    assert recommend_index(predictions, loads, 0, {key: [0.1, 0.2, 0.7]}) == (0, "marl_xgboost_baseline")
    assert action_indices([0.8, 0.8], [0.2, 0.2], 1) == (0, 0, 1)
    assert recommend_index([0.8, 0.8], [0.2, 0.2], 1,
                           {state_key([0.8, 0.8], [0.2, 0.2]): [1, 1, 1]})[0] == 0


@pytest.mark.parametrize("predictions,loads,baseline", [([], [], 0), ([math.nan], [0.5], 0),
                         ([math.inf], [0.5], 0), ([0.8], [-0.1], 0), ([0.8], [1.1], 0),
                         ([0.8], [0.5, 0.6], 0), ([0.8], [0.5], -1), ([0.8], [0.5], True)])
def test_policy_rejects_invalid_inputs(predictions, loads, baseline):
    with pytest.raises(ValueError):
        recommend_index(predictions, loads, baseline, {})


def test_policy_rejects_invalid_table_values():
    key = state_key([0.8], [0.1])
    with pytest.raises(ValueError):
        recommend_index([0.8], [0.1], 0, {key: [0, math.nan, 0]})


def test_state_encoding_caps_large_finite_differences_before_conversion():
    assert state_key([1e308, -1e308], [0.2, 0.1]).endswith(":2:2")


def test_bellman_update_uses_next_state_and_terminal_mask():
    agent = Agent(q_table={"current": [0, 0, 0], "next": [4, 2, 1]})
    agent.update("current", 1, 0.5, "next", terminal=False)
    assert agent.q_table["current"][1] == pytest.approx(LEARNING_RATE * (0.5 + GAMMA * 4))
    agent.update("terminal", 0, 0.5, "next", terminal=True)
    assert agent.q_table["terminal"][0] == pytest.approx(LEARNING_RATE * 0.5)
    assert agent.visits["current"] == [0, 1, 0]


def test_independent_agents_really_learn_preferences():
    first, second = Agent(), Agent()
    for _ in range(40):
        first.update("state", 0, 0.2, "terminal", True)
        first.update("state", 1, 0.8, "terminal", True)
        second.update("state", 0, 0.9, "terminal", True)
        second.update("state", 1, 0.1, "terminal", True)
    assert max(range(3), key=lambda a: first.q_table["state"][a]) == 1
    assert max(range(3), key=lambda a: second.q_table["state"][a]) == 0
    assert first.q_table is not second.q_table


def test_splits_have_disjoint_episode_seeds_and_regime_groups():
    specs = episode_specs(42, 20)
    for first, second in (("train", "validation"), ("train", "test"), ("validation", "test")):
        assert {s for s, _ in specs[first]}.isdisjoint({s for s, _ in specs[second]})
        assert {g for _, g in specs[first]}.isdisjoint({g for _, g in specs[second]})
    with pytest.raises(ValueError):
        episode_specs(42, 0)


def test_shared_congestion_changes_observations_and_outcome():
    np = pytest.importorskip("numpy")
    together, spread = Simulation(42, 0), Simulation(42, 0)
    before = together.observations().copy()
    together.advance([0, 0, 0])
    spread.advance([0, 1, 2])
    assert together.load[0] > spread.load[0]
    assert not np.array_equal(before, together.observations())
    assert together.observations().shape[1] == len(FEATURES)


def test_training_exports_valid_reproducible_frozen_artifacts(tmp_path):
    np = pytest.importorskip("numpy")
    xgb = pytest.importorskip("xgboost")
    from ml.train_routing import collect_training_rows, train

    first, second = tmp_path / "first", tmp_path / "second"
    a, b = train(first, episodes=8), train(second, episodes=8)
    assert a == b
    assert a["model_origin"] == "synthetic_simulator"
    assert a["feature_names"] == list(FEATURES)
    assert a["data"]["evaluation_frozen"] is True
    assert a["data"]["agent_update_counts"] == [8 * 24] * 3
    for name, digest in a["sha256"].items():
        assert hashlib.sha256((first / name).read_bytes()).hexdigest() == digest
        assert (first / name).read_bytes() == (second / name).read_bytes()
    policy = json.loads((first / "policy.json").read_text())
    assert policy["schema_version"] == 1
    assert policy["q_table"]
    assert all(len(q) == 3 and all(math.isfinite(v) for v in q) for q in policy["q_table"].values())
    model = xgb.XGBRegressor()
    model.load_model(first / "model.json")
    assert model.n_features_in_ == len(FEATURES)
    observations = Simulation(111, 5).observations()
    assert np.isfinite(model.predict(observations)).all()
    x, y, episodes = collect_training_rows(episode_specs(42, 8)["train"])
    assert x.shape == (8 * 24 * 3, len(FEATURES))
    assert len(episodes) == len(y)
    # The target is a post-action outcome, not a duplicate of same-row utility.
    from ml.train_routing import utility
    assert any(abs(utility(row) - target) > 0.001 for row, target in zip(x, y))
    for split in ("validation", "test"):
        assert set(a["metrics"][split]) == {"baseline", "xgboost_only", "marl_xgboost"}
