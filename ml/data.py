import csv
import hashlib
import random
from datetime import datetime
from typing import Any, Dict, List, Tuple


def _stable_fraction(key: str) -> float:
    """Return a stable pseudo-random float in [0, 1] for a given key.

    Used to generate deterministic synthetic features without relying on the
    process-global RNG (and without leaking labels).
    """
    digest = hashlib.blake2b(key.encode("utf-8"), digest_size=8).digest()
    value = int.from_bytes(digest, "big", signed=False)
    return value / float((1 << 64) - 1)


def _parse_iso_hour(ts: str) -> int:
    try:
        return datetime.fromisoformat(ts).hour
    except Exception:
        return 12


def extract_risk_features(record: Dict[str, Any]) -> Dict[str, Any]:
    """Derive causal/pre-decision risk features from telemetry (no label leakage).

    IMPORTANT: This must never use `risk_score` to construct input features.
    """
    disconnects = int(record.get("disconnect_count", 0))
    stability = float(record.get("connection_stability", 1.0))
    duration_minutes = int(record.get("session_duration_minutes", 60))
    bandwidth_mbps = float(record.get("bandwidth_mbps", 80.0))
    timestamp = str(record.get("timestamp", ""))
    user_id = int(record.get("user_id", 0))
    server_id = str(record.get("server_id", ""))

    hour = _parse_iso_hour(timestamp)
    # Treat "night hours" as more likely unusual, but cap frequency using a stable hash.
    night = hour < 6 or hour >= 23
    unusual_hours = bool(night and _stable_fraction(f"unusual:{user_id}:{timestamp}") < 0.2)

    # Reconnect frequency is derived from observed disconnects normalized by session duration.
    duration_hours = max(1.0 / 60.0, duration_minutes / 60.0)
    reconnect_frequency = int(round(disconnects / duration_hours))
    reconnect_frequency = max(0, min(50, reconnect_frequency))

    # "Login failures" is a synthetic proxy derived from stability/disconnect history only.
    login_failures = int(round(max(0.0, (1.0 - stability) * 4.0 + disconnects * 0.8)))
    if unusual_hours:
        login_failures += 1
    login_failures = max(0, min(10, login_failures))

    # Stable, server-based reputation prior in [0.3, 1.0] (independent of labels).
    ip_reputation = 0.3 + _stable_fraction(f"iprep:{server_id}") * 0.7

    # Rare geo anomaly flag to avoid dominating the feature space.
    geo_anomaly = bool(
        server_id
        and _stable_fraction(f"geo:{user_id}:{server_id}:{timestamp}") < 0.05
    )

    # Data exfil indicator based on unusually high estimated volume.
    # (bandwidth * duration) is a proxy; clamped to [0, 1].
    volume_proxy = bandwidth_mbps * float(duration_minutes)
    baseline_proxy = 80.0 * 60.0  # ~1h at 80 Mbps
    data_exfil_indicator = max(0.0, min(1.0, (volume_proxy / baseline_proxy - 1.0) * 0.5))

    # Session duration anomaly relative to a 1-hour baseline.
    session_duration_anomaly = max(0.0, (duration_minutes / 60.0) - 1.0)

    return {
        "login_failures": login_failures,
        "reconnect_frequency": reconnect_frequency,
        "unusual_hours": unusual_hours,
        "ip_reputation": ip_reputation,
        "geo_anomaly": geo_anomaly,
        "data_exfil_indicator": data_exfil_indicator,
        "session_duration_anomaly": session_duration_anomaly,
    }


def load_telemetry_csv(path: str) -> List[Dict[str, Any]]:
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            records.append(
                {
                    "timestamp": row.get("timestamp", ""),
                    "user_id": int(row.get("user_id", 0) or 0),
                    "server_id": row.get("server_id", ""),
                    "latency_ms": float(row["latency_ms"]),
                    "packet_loss": float(row["packet_loss"]),
                    "jitter_ms": float(row["jitter_ms"]),
                    "bandwidth_mbps": float(row["bandwidth_mbps"]),
                    "connection_stability": float(row["connection_stability"]),
                    "disconnect_count": int(row["disconnect_count"]),
                    "session_duration_minutes": int(row.get("session_duration_minutes", 0) or 0),
                    "qos_label": row["qos_label"],
                    "risk_score": float(row["risk_score"]),
                }
            )
    return records


def split_records(
    records: List[Dict[str, float]],
    train_ratio: float,
    seed: int,
) -> Tuple[List[Dict[str, float]], List[Dict[str, float]]]:
    rng = random.Random(seed)
    shuffled = records[:]
    rng.shuffle(shuffled)
    split_idx = int(len(shuffled) * train_ratio)
    return shuffled[:split_idx], shuffled[split_idx:]


def apply_feature_decay(features: List[List[float]], decay: float) -> List[List[float]]:
    if decay >= 1.0:
        return features
    decayed = []
    for row in features:
        decayed.append([value * (decay ** idx) for idx, value in enumerate(row)])
    return decayed


def build_qos_dataset(records: List[Dict[str, float]]) -> Tuple[List[List[float]], List[str]]:
    X = []
    y = []
    for record in records:
        X.append(
            [
                record["latency_ms"],
                record["packet_loss"],
                record["jitter_ms"],
                record["bandwidth_mbps"],
                record["connection_stability"],
            ]
        )
        y.append(record["qos_label"])
    return X, y


def build_risk_dataset(records: List[Dict[str, float]]) -> Tuple[List[List[float]], List[float]]:
    X = []
    y = []
    for record in records:
        risk_score = float(record["risk_score"])
        features = extract_risk_features(record)
        X.append(
            [
                float(features["login_failures"]),
                float(features["reconnect_frequency"]),
                1.0 if features["unusual_hours"] else 0.0,
                float(features["ip_reputation"]),
                1.0 if features["geo_anomaly"] else 0.0,
                float(features["data_exfil_indicator"]),
                float(features["session_duration_anomaly"]),
            ]
        )
        y.append(risk_score)
    return X, y
