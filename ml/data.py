import csv
import random
from typing import Dict, List, Tuple


def load_telemetry_csv(path: str) -> List[Dict[str, float]]:
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            records.append(
                {
                    "latency_ms": float(row["latency_ms"]),
                    "packet_loss": float(row["packet_loss"]),
                    "jitter_ms": float(row["jitter_ms"]),
                    "bandwidth_mbps": float(row["bandwidth_mbps"]),
                    "connection_stability": float(row["connection_stability"]),
                    "disconnect_count": int(row["disconnect_count"]),
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
        login_failures = 0 if risk_score < 0.3 else int(risk_score * 5)
        reconnect_freq = int(record["disconnect_count"])
        unusual_hours = 1.0 if risk_score > 0.4 else 0.0
        ip_reputation = max(0.3, 1.0 - risk_score)
        geo_anomaly = 1.0 if risk_score > 0.5 else 0.0
        data_exfil = risk_score * 0.5 if risk_score > 0.3 else 0.0
        session_anomaly = risk_score * 2 if risk_score > 0.2 else 0.0
        X.append(
            [
                float(login_failures),
                float(reconnect_freq),
                unusual_hours,
                ip_reputation,
                geo_anomaly,
                data_exfil,
                session_anomaly,
            ]
        )
        y.append(risk_score)
    return X, y
