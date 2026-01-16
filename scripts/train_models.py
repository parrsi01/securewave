#!/usr/bin/env python3
"""
SecureWave XGBoost Model Training Script (Day 7-9)

Trains QoS and Risk models from synthetic telemetry data.

Usage:
    python scripts/train_models.py
"""

import os
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

import csv
from typing import List, Tuple


def load_data(csv_path: str) -> Tuple[List[dict], List[str]]:
    """Load telemetry data from CSV"""
    records = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            records.append({
                'latency_ms': float(row['latency_ms']),
                'packet_loss': float(row['packet_loss']),
                'jitter_ms': float(row['jitter_ms']),
                'bandwidth_mbps': float(row['bandwidth_mbps']),
                'connection_stability': float(row['connection_stability']),
                'disconnect_count': int(row['disconnect_count']),
                'qos_label': row['qos_label'],
                'risk_score': float(row['risk_score']),
            })
    return records


def train_qos_model(records: List[dict], output_path: str) -> dict:
    """Train QoS classification model"""
    from services.xgb_qos import get_qos_classifier

    print(f"\n{'='*50}")
    print("Training QoS Classification Model")
    print('='*50)

    # Prepare training data
    X = []
    y = []
    for r in records:
        X.append([
            r['latency_ms'],
            r['packet_loss'],
            r['jitter_ms'],
            r['bandwidth_mbps'],
            r['connection_stability'],
        ])
        y.append(r['qos_label'])

    print(f"Training samples: {len(X)}")
    print(f"Features: latency_ms, packet_loss, jitter_ms, bandwidth_mbps, connection_stability")

    # Label distribution
    label_counts = {}
    for label in y:
        label_counts[label] = label_counts.get(label, 0) + 1
    print(f"Label distribution: {label_counts}")

    # Train
    classifier = get_qos_classifier()
    classifier.train(X, y)

    # Save model
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    classifier.save_model(output_path)
    print(f"Model saved to: {output_path}")

    # Test predictions
    from services.xgb_qos import QoSInput
    test_cases = [
        QoSInput(latency_ms=30, packet_loss=0.005, jitter_ms=2, bandwidth_mbps=100, connection_stability=0.98),
        QoSInput(latency_ms=150, packet_loss=0.05, jitter_ms=20, bandwidth_mbps=50, connection_stability=0.7),
        QoSInput(latency_ms=400, packet_loss=0.15, jitter_ms=50, bandwidth_mbps=20, connection_stability=0.3),
    ]

    print("\nTest predictions:")
    for tc in test_cases:
        result = classifier.predict(tc)
        print(f"  Latency={tc.latency_ms}ms, Loss={tc.packet_loss*100:.1f}% → {result.label} (score={result.score:.3f}, method={result.method})")

    return {
        "samples": len(X),
        "labels": label_counts,
        "model_path": output_path,
        "is_trained": classifier.is_trained,
    }


def train_risk_model(records: List[dict], output_path: str) -> dict:
    """Train Risk scoring model"""
    from services.xgb_risk import get_risk_scorer

    print(f"\n{'='*50}")
    print("Training Risk Scoring Model")
    print('='*50)

    # Prepare training data
    # Features: login_failures, reconnect_frequency, unusual_hours, ip_reputation,
    #           geo_anomaly, data_exfil_indicator, session_duration_anomaly
    X = []
    y = []
    for r in records:
        # Simulate risk features from available data
        login_failures = 0 if r['risk_score'] < 0.3 else int(r['risk_score'] * 5)
        reconnect_freq = r['disconnect_count']
        unusual_hours = 1.0 if r['risk_score'] > 0.4 else 0.0
        ip_reputation = max(0.3, 1.0 - r['risk_score'])
        geo_anomaly = 1.0 if r['risk_score'] > 0.5 else 0.0
        data_exfil = r['risk_score'] * 0.5 if r['risk_score'] > 0.3 else 0.0
        session_anomaly = r['risk_score'] * 2 if r['risk_score'] > 0.2 else 0.0

        X.append([
            float(login_failures),
            float(reconnect_freq),
            unusual_hours,
            ip_reputation,
            geo_anomaly,
            data_exfil,
            session_anomaly,
        ])
        y.append(r['risk_score'])

    print(f"Training samples: {len(X)}")
    print(f"Features: login_failures, reconnect_freq, unusual_hours, ip_reputation, geo_anomaly, data_exfil, session_anomaly")

    # Risk score distribution
    low = sum(1 for s in y if s < 0.25)
    medium = sum(1 for s in y if 0.25 <= s < 0.5)
    high = sum(1 for s in y if 0.5 <= s < 0.75)
    critical = sum(1 for s in y if s >= 0.75)
    print(f"Risk distribution: low={low}, medium={medium}, high={high}, critical={critical}")

    # Train
    scorer = get_risk_scorer()
    scorer.train(X, y)

    # Save model
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    scorer.save_model(output_path)
    print(f"Model saved to: {output_path}")

    # Test predictions
    from services.xgb_risk import RiskInput
    test_cases = [
        RiskInput(login_failures=0, reconnect_frequency=0, ip_reputation=1.0),
        RiskInput(login_failures=3, reconnect_frequency=5, unusual_hours=True, ip_reputation=0.6),
        RiskInput(login_failures=5, reconnect_frequency=10, unusual_hours=True, ip_reputation=0.3, geo_anomaly=True),
    ]

    print("\nTest predictions:")
    for tc in test_cases:
        result = scorer.predict(tc)
        print(f"  Failures={tc.login_failures}, Reconnects={tc.reconnect_frequency} → {result.level} (score={result.score:.3f}, method={result.method})")

    return {
        "samples": len(X),
        "distribution": {"low": low, "medium": medium, "high": high, "critical": critical},
        "model_path": output_path,
        "is_trained": scorer.is_trained,
    }


def main():
    print("SecureWave XGBoost Model Training")
    print("="*50)

    # Paths
    data_path = "data/vpn_telemetry.csv"
    qos_model_path = "data/models/qos_model.json"
    risk_model_path = "data/models/risk_model.json"

    # Check data exists
    if not Path(data_path).exists():
        print(f"ERROR: Training data not found at {data_path}")
        print("Run: python scripts/generate_synthetic_data.py first")
        sys.exit(1)

    # Load data
    print(f"Loading data from {data_path}...")
    records = load_data(data_path)
    print(f"Loaded {len(records)} records")

    # Train models
    qos_stats = train_qos_model(records, qos_model_path)
    risk_stats = train_risk_model(records, risk_model_path)

    # Summary
    print(f"\n{'='*50}")
    print("TRAINING COMPLETE")
    print('='*50)
    print(f"QoS Model: {qos_model_path} (trained={qos_stats['is_trained']})")
    print(f"Risk Model: {risk_model_path} (trained={risk_stats['is_trained']})")


if __name__ == "__main__":
    main()
