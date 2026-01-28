import argparse
import json
import logging
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from ml.config import ExperimentConfig, load_config
from ml.data import (
    apply_feature_decay,
    build_qos_dataset,
    build_risk_dataset,
    load_telemetry_csv,
    split_records,
)
from ml.metrics import accuracy_score, aggregate_policy_actions, mean_absolute_error
from ml.seed import seed_everything
from services.marl_policy import StateVector, create_policy_engine
from services.xgb_qos import QoSInput, XGBQoSClassifier
from services.xgb_risk import RiskInput, XGBRiskScorer

LOGGER = logging.getLogger("securewave.ml")


def _setup_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")


def _run_policy(engine, records: List[Dict[str, float]]) -> List[str]:
    actions = []
    for record in records:
        state = StateVector(
            user_id=1,
            server_id="baseline",
            qos_score=record.get("qos_score", 0.8),
            risk_score=record.get("risk_score", 0.1),
            server_load=0.3,
            latency_ms=record["latency_ms"],
            packet_loss=record["packet_loss"],
            jitter_ms=record["jitter_ms"],
            user_priority=0,
            reconnect_count=int(record["disconnect_count"]),
        )
        decision = engine.decide(state)
        actions.append(decision.action.value)
    return actions


def run_experiment(
    config: ExperimentConfig,
    data_path: str,
    output_dir: Optional[str] = None,
    run_id: Optional[str] = None,
) -> Path:
    seed_everything(config.seed, config.split.seed)

    records = load_telemetry_csv(data_path)
    train_records, test_records = split_records(records, config.split.train_ratio, config.split.seed)

    X_qos_train, y_qos_train = build_qos_dataset(train_records)
    X_qos_test, y_qos_test = build_qos_dataset(test_records)

    X_risk_train, y_risk_train = build_risk_dataset(train_records)
    X_risk_test, y_risk_test = build_risk_dataset(test_records)

    if config.aggregation.feature_decay < 1.0:
        X_qos_train = apply_feature_decay(X_qos_train, config.aggregation.feature_decay)
        X_qos_test = apply_feature_decay(X_qos_test, config.aggregation.feature_decay)
        X_risk_train = apply_feature_decay(X_risk_train, config.aggregation.feature_decay)
        X_risk_test = apply_feature_decay(X_risk_test, config.aggregation.feature_decay)

    qos_classifier = XGBQoSClassifier(model_path=None)
    qos_classifier.train_with_config(
        X_qos_train,
        y_qos_train,
        config=config.xgb_qos,
        eval_set=(X_qos_test, y_qos_test) if X_qos_test else None,
    )

    risk_scorer = XGBRiskScorer(model_path=None)
    risk_scorer.train_with_config(
        X_risk_train,
        y_risk_train,
        config=config.xgb_risk,
        eval_set=(X_risk_test, y_risk_test) if X_risk_test else None,
    )

    qos_preds = []
    for record in test_records:
        inp = QoSInput(
            latency_ms=record["latency_ms"],
            packet_loss=record["packet_loss"],
            jitter_ms=record["jitter_ms"],
            bandwidth_mbps=record["bandwidth_mbps"],
            connection_stability=record["connection_stability"],
        )
        qos_preds.append(qos_classifier.predict(inp).label)

    risk_preds = []
    for record in test_records:
        inp = RiskInput(
            login_failures=0 if record["risk_score"] < 0.3 else int(record["risk_score"] * 5),
            reconnect_frequency=int(record["disconnect_count"]),
            unusual_hours=record["risk_score"] > 0.4,
            ip_reputation=max(0.3, 1.0 - record["risk_score"]),
            geo_anomaly=record["risk_score"] > 0.5,
            data_exfil_indicator=record["risk_score"] * 0.5 if record["risk_score"] > 0.3 else 0.0,
            session_duration_anomaly=record["risk_score"] * 2 if record["risk_score"] > 0.2 else 0.0,
        )
        risk_preds.append(risk_scorer.predict(inp).score)

    qos_accuracy = accuracy_score(y_qos_test, qos_preds)
    risk_mae = mean_absolute_error(y_risk_test, risk_preds)

    policy_engine = create_policy_engine(config.marl)
    policy_actions = _run_policy(policy_engine, test_records)
    action_counts = aggregate_policy_actions(policy_actions, trust_weight=config.aggregation.trust_weight)

    metrics = {
        "profile": config.profile,
        "records": len(records),
        "train_records": len(train_records),
        "test_records": len(test_records),
        "qos_accuracy": round(qos_accuracy, 4),
        "risk_mae": round(risk_mae, 4),
        "policy_action_counts": action_counts,
        "ml_available": qos_classifier.use_ml and risk_scorer.use_ml,
    }

    output_root = Path(output_dir or config.output_dir)
    run_stamp = run_id or f"{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}-{config.profile}"
    run_dir = output_root / run_stamp
    run_dir.mkdir(parents=True, exist_ok=True)

    with (run_dir / "config.json").open("w", encoding="utf-8") as handle:
        json.dump(asdict(config), handle, indent=2, sort_keys=True)

    with (run_dir / "metrics.json").open("w", encoding="utf-8") as handle:
        json.dump(metrics, handle, indent=2, sort_keys=True)

    with (run_dir / "metrics.csv").open("w", encoding="utf-8") as handle:
        handle.write("metric,value\n")
        handle.write(f"qos_accuracy,{metrics['qos_accuracy']}\n")
        handle.write(f"risk_mae,{metrics['risk_mae']}\n")

    LOGGER.info("Experiment complete: %s", run_dir)
    return run_dir


def main() -> None:
    _setup_logging()
    parser = argparse.ArgumentParser(description="SecureWave MARL + XGBoost experiment runner")
    parser.add_argument("--config", required=True, help="Path to experiment config JSON")
    parser.add_argument("--data", default="data/vpn_telemetry.csv", help="Path to telemetry CSV")
    parser.add_argument("--output", default=None, help="Override output directory")
    parser.add_argument("--run-id", default=None, help="Optional run identifier")
    args = parser.parse_args()

    config = load_config(args.config)
    run_experiment(config, data_path=args.data, output_dir=args.output, run_id=args.run_id)


if __name__ == "__main__":
    main()
