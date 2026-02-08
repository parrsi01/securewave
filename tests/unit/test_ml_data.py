from ml.data import apply_feature_decay, build_risk_dataset, split_records


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


def test_risk_features_do_not_use_label():
    base = {
        "timestamp": "2026-01-01T02:00:00",
        "user_id": 123,
        "server_id": "us-east-1",
        "latency_ms": 50.0,
        "packet_loss": 0.01,
        "jitter_ms": 5.0,
        "bandwidth_mbps": 100.0,
        "connection_stability": 0.9,
        "disconnect_count": 1,
        "session_duration_minutes": 60,
        "qos_label": "good",
    }
    rec_low = dict(base, risk_score=0.1)
    rec_high = dict(base, risk_score=0.9)

    X, y = build_risk_dataset([rec_low, rec_high])
    assert X[0] == X[1]
    assert y == [0.1, 0.9]
