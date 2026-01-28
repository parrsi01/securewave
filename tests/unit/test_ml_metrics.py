from ml.metrics import aggregate_policy_actions


def test_aggregate_policy_actions_trust_weighted():
    actions = ["reroute", "reroute", "alert"]
    counts = aggregate_policy_actions(actions, trust_weight=1.5)
    assert counts["reroute"] == 3.0
    assert counts["alert"] == 1.5
