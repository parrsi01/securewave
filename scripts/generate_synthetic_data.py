#!/usr/bin/env python3
"""
SecureWave Synthetic VPN Telemetry Dataset Generator (Day 6)

Generates realistic synthetic VPN telemetry data for training XGBoost models.
Includes:
- Latency (ms)
- Packet loss (%)
- Jitter (ms)
- Bandwidth (Mbps)
- Connection stability
- Disconnects
- Labels for QoS classification

Usage:
    python scripts/generate_synthetic_data.py --output data/vpn_telemetry.csv --samples 10000
"""

import argparse
import csv
import os
import random
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple


@dataclass
class TelemetryRecord:
    """Single telemetry record"""
    timestamp: str
    user_id: int
    server_id: str
    latency_ms: float
    packet_loss: float
    jitter_ms: float
    bandwidth_mbps: float
    connection_stability: float
    disconnect_count: int
    session_duration_minutes: int
    qos_label: str  # "excellent", "good", "fair", "poor"
    risk_score: float


def classify_qos(latency: float, loss: float, jitter: float, bandwidth: float) -> str:
    """Rule-based QoS classification for training labels"""
    score = (
        0.35 * max(0, min(1, (200 - latency) / 200)) +
        0.25 * max(0, 1 - loss * 10) +
        0.15 * max(0, min(1, (50 - jitter) / 50)) +
        0.25 * min(1, bandwidth / 100)
    )

    if score >= 0.85:
        return "excellent"
    elif score >= 0.65:
        return "good"
    elif score >= 0.40:
        return "fair"
    else:
        return "poor"


def generate_normal_session() -> Tuple[float, float, float, float, float, int]:
    """Generate metrics for a normal, healthy connection"""
    latency = random.gauss(45, 15)  # Mean 45ms, std 15
    latency = max(10, min(150, latency))

    packet_loss = random.uniform(0, 0.02)  # 0-2%

    jitter = random.gauss(3, 2)
    jitter = max(0.5, min(15, jitter))

    bandwidth = random.gauss(80, 20)
    bandwidth = max(20, min(150, bandwidth))

    stability = random.uniform(0.85, 1.0)
    disconnects = random.choices([0, 1], weights=[0.9, 0.1])[0]

    return latency, packet_loss, jitter, bandwidth, stability, disconnects


def generate_degraded_session() -> Tuple[float, float, float, float, float, int]:
    """Generate metrics for a degraded connection"""
    latency = random.gauss(150, 50)
    latency = max(80, min(400, latency))

    packet_loss = random.uniform(0.02, 0.08)  # 2-8%

    jitter = random.gauss(25, 10)
    jitter = max(10, min(60, jitter))

    bandwidth = random.gauss(40, 15)
    bandwidth = max(10, min(80, bandwidth))

    stability = random.uniform(0.5, 0.85)
    disconnects = random.choices([0, 1, 2, 3], weights=[0.4, 0.3, 0.2, 0.1])[0]

    return latency, packet_loss, jitter, bandwidth, stability, disconnects


def generate_poor_session() -> Tuple[float, float, float, float, float, int]:
    """Generate metrics for a poor connection"""
    latency = random.gauss(350, 100)
    latency = max(200, min(800, latency))

    packet_loss = random.uniform(0.08, 0.25)  # 8-25%

    jitter = random.gauss(50, 20)
    jitter = max(30, min(100, jitter))

    bandwidth = random.gauss(15, 10)
    bandwidth = max(1, min(40, bandwidth))

    stability = random.uniform(0.2, 0.5)
    disconnects = random.choices([1, 2, 3, 4, 5], weights=[0.2, 0.25, 0.25, 0.2, 0.1])[0]

    return latency, packet_loss, jitter, bandwidth, stability, disconnects


def generate_risk_score(disconnects: int, stability: float, unusual: bool = False) -> float:
    """Generate risk score based on behavioral signals"""
    base_risk = 0.05

    # Disconnects increase risk
    base_risk += disconnects * 0.08

    # Low stability increases risk
    base_risk += (1 - stability) * 0.2

    # Unusual patterns
    if unusual:
        base_risk += random.uniform(0.1, 0.3)

    return max(0, min(1, base_risk))


def generate_dataset(num_samples: int, seed: int = 42) -> List[TelemetryRecord]:
    """Generate synthetic telemetry dataset"""
    random.seed(seed)

    records = []
    servers = ["us-east-1", "us-west-1", "eu-west-1", "eu-central-1", "ap-southeast-1", "ap-northeast-1"]

    # Distribution: 60% normal, 25% degraded, 15% poor
    session_types = (
        ["normal"] * 60 +
        ["degraded"] * 25 +
        ["poor"] * 15
    )

    start_time = datetime.now() - timedelta(days=30)

    for i in range(num_samples):
        session_type = random.choice(session_types)

        if session_type == "normal":
            latency, loss, jitter, bandwidth, stability, disconnects = generate_normal_session()
        elif session_type == "degraded":
            latency, loss, jitter, bandwidth, stability, disconnects = generate_degraded_session()
        else:
            latency, loss, jitter, bandwidth, stability, disconnects = generate_poor_session()

        # Random user and server
        user_id = random.randint(1, 500)
        server_id = random.choice(servers)

        # Random timestamp over 30 days
        timestamp = start_time + timedelta(
            days=random.uniform(0, 30),
            hours=random.uniform(0, 24)
        )

        # Session duration (5 min to 8 hours)
        duration = random.randint(5, 480)

        # Classify QoS
        qos_label = classify_qos(latency, loss, jitter, bandwidth)

        # Risk score
        unusual = random.random() < 0.05  # 5% unusual behavior
        risk = generate_risk_score(disconnects, stability, unusual)

        record = TelemetryRecord(
            timestamp=timestamp.isoformat(),
            user_id=user_id,
            server_id=server_id,
            latency_ms=round(latency, 2),
            packet_loss=round(loss, 4),
            jitter_ms=round(jitter, 2),
            bandwidth_mbps=round(bandwidth, 2),
            connection_stability=round(stability, 3),
            disconnect_count=disconnects,
            session_duration_minutes=duration,
            qos_label=qos_label,
            risk_score=round(risk, 3),
        )
        records.append(record)

    return records


def save_to_csv(records: List[TelemetryRecord], output_path: str) -> None:
    """Save records to CSV file"""
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "timestamp", "user_id", "server_id", "latency_ms", "packet_loss",
        "jitter_ms", "bandwidth_mbps", "connection_stability", "disconnect_count",
        "session_duration_minutes", "qos_label", "risk_score"
    ]

    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            writer.writerow({
                "timestamp": record.timestamp,
                "user_id": record.user_id,
                "server_id": record.server_id,
                "latency_ms": record.latency_ms,
                "packet_loss": record.packet_loss,
                "jitter_ms": record.jitter_ms,
                "bandwidth_mbps": record.bandwidth_mbps,
                "connection_stability": record.connection_stability,
                "disconnect_count": record.disconnect_count,
                "session_duration_minutes": record.session_duration_minutes,
                "qos_label": record.qos_label,
                "risk_score": record.risk_score,
            })


def print_stats(records: List[TelemetryRecord]) -> None:
    """Print dataset statistics"""
    print("\n=== Dataset Statistics ===")
    print(f"Total records: {len(records)}")

    # QoS distribution
    qos_counts = {}
    for r in records:
        qos_counts[r.qos_label] = qos_counts.get(r.qos_label, 0) + 1

    print("\nQoS Label Distribution:")
    for label in ["excellent", "good", "fair", "poor"]:
        count = qos_counts.get(label, 0)
        pct = count / len(records) * 100
        print(f"  {label}: {count} ({pct:.1f}%)")

    # Average metrics
    avg_latency = sum(r.latency_ms for r in records) / len(records)
    avg_loss = sum(r.packet_loss for r in records) / len(records)
    avg_risk = sum(r.risk_score for r in records) / len(records)

    print(f"\nAverage Latency: {avg_latency:.1f}ms")
    print(f"Average Packet Loss: {avg_loss*100:.2f}%")
    print(f"Average Risk Score: {avg_risk:.3f}")


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic VPN telemetry dataset")
    parser.add_argument("--output", "-o", default="data/vpn_telemetry.csv", help="Output CSV file path")
    parser.add_argument("--samples", "-n", type=int, default=10000, help="Number of samples to generate")
    parser.add_argument("--seed", "-s", type=int, default=42, help="Random seed for reproducibility")
    args = parser.parse_args()

    print(f"Generating {args.samples} synthetic telemetry records...")
    records = generate_dataset(args.samples, args.seed)

    print(f"Saving to {args.output}...")
    save_to_csv(records, args.output)

    print_stats(records)
    print(f"\nDataset saved to: {args.output}")


if __name__ == "__main__":
    main()
