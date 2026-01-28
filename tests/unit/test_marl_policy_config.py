from services.marl_policy import MARLPolicyConfig, create_policy_engine


def test_marl_config_overrides_defaults():
    config = MARLPolicyConfig(exploration_rate=0.2, learning_rate=0.05)
    engine = create_policy_engine(config)
    assert engine.exploration_rate == 0.2
    assert engine.learning_rate == 0.05
