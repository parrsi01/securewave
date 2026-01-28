from ml.data import apply_feature_decay, split_records


def test_split_records_deterministic():
    records = [{"latency_ms": i} for i in range(10)]
    train_a, test_a = split_records(records, train_ratio=0.7, seed=123)
    train_b, test_b = split_records(records, train_ratio=0.7, seed=123)
    assert train_a == train_b
    assert test_a == test_b


def test_feature_decay_applies():
    features = [[1.0, 1.0, 1.0]]
    decayed = apply_feature_decay(features, decay=0.9)
    assert decayed[0][0] == 1.0
    assert decayed[0][1] < decayed[0][0]
