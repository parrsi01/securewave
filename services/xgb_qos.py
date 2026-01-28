"""
SecureWave XGBoost QoS Scoring Module (Day 7)

Classifies VPN connection quality based on telemetry metrics.
Labels: "excellent", "good", "fair", "poor"

Inputs:
- latency_ms
- packet_loss (0-1)
- jitter_ms
- bandwidth_mbps
- connection_stability (0-1)

Output:
- qos_label: str
- qos_score: float (0-1)
- confidence: float
"""

import os
from dataclasses import dataclass
from collections import Counter
from pathlib import Path
from typing import Dict, Optional, Tuple, List

# Lazy ML imports
try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False

try:
    import xgboost as xgb
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False

ML_AVAILABLE = NUMPY_AVAILABLE and XGBOOST_AVAILABLE


@dataclass
class QoSInput:
    """Input features for QoS classification"""
    latency_ms: float
    packet_loss: float
    jitter_ms: float
    bandwidth_mbps: float = 100.0
    connection_stability: float = 1.0


@dataclass
class QoSResult:
    """QoS classification result"""
    label: str  # "excellent", "good", "fair", "poor"
    score: float  # 0.0 to 1.0
    confidence: float
    method: str  # "xgboost" or "rule_based"


@dataclass
class XGBQoSConfig:
    """Training configuration for QoS classifier."""
    n_estimators: int = 100
    max_depth: int = 6
    learning_rate: float = 0.1
    subsample: float = 1.0
    colsample_bytree: float = 1.0
    random_state: int = 42
    n_jobs: int = 1
    early_stopping_rounds: Optional[int] = None
    class_weight_strategy: Optional[str] = None  # "balanced"


class XGBQoSClassifier:
    """
    XGBoost-based QoS classifier.
    Falls back to rule-based scoring if ML dependencies unavailable.
    """

    # Class label mapping
    LABELS = ["poor", "fair", "good", "excellent"]
    LABEL_TO_INT = {label: i for i, label in enumerate(LABELS)}

    def __init__(self, model_path: Optional[str] = None):
        self.model: Optional[xgb.XGBClassifier] = None
        self.use_ml = ML_AVAILABLE
        self.is_trained = False

        if self.use_ml and model_path and Path(model_path).exists():
            self._load_model(model_path)

    def _load_model(self, path: str) -> None:
        """Load pre-trained model from disk"""
        try:
            self.model = xgb.XGBClassifier()
            self.model.load_model(path)
            self.is_trained = True
        except Exception:
            self.model = None
            self.is_trained = False

    def save_model(self, path: str) -> None:
        """Save trained model to disk"""
        if self.model and self.is_trained:
            self.model.save_model(path)

    def _extract_features(self, inp: QoSInput) -> List[float]:
        """Extract feature vector from input"""
        return [
            inp.latency_ms,
            inp.packet_loss,
            inp.jitter_ms,
            inp.bandwidth_mbps,
            inp.connection_stability,
        ]

    def _rule_based_score(self, inp: QoSInput) -> QoSResult:
        """
        Rule-based QoS scoring (fallback when ML unavailable).
        Deterministic and interpretable.
        """
        # Normalize each metric to 0-1 (higher is better)
        latency_score = max(0.0, min(1.0, (200 - inp.latency_ms) / 200))
        loss_score = max(0.0, 1.0 - inp.packet_loss * 10)  # 10% loss = 0 score
        jitter_score = max(0.0, min(1.0, (50 - inp.jitter_ms) / 50))
        bandwidth_score = min(1.0, inp.bandwidth_mbps / 100)
        stability_score = inp.connection_stability

        # Weighted combination
        score = (
            0.35 * latency_score +
            0.25 * loss_score +
            0.15 * jitter_score +
            0.15 * bandwidth_score +
            0.10 * stability_score
        )

        # Map score to label
        if score >= 0.85:
            label = "excellent"
        elif score >= 0.65:
            label = "good"
        elif score >= 0.40:
            label = "fair"
        else:
            label = "poor"

        return QoSResult(
            label=label,
            score=round(score, 3),
            confidence=0.8,  # Rule-based has fixed confidence
            method="rule_based"
        )

    def train(self, X: List[List[float]], y: List[str]) -> None:
        """
        Train the XGBoost classifier.

        Args:
            X: List of feature vectors [latency, loss, jitter, bandwidth, stability]
            y: List of labels ["excellent", "good", "fair", "poor"]
        """
        return self.train_with_config(X, y, config=None, eval_set=None)

    def train_with_config(
        self,
        X: List[List[float]],
        y: List[str],
        config: Optional[XGBQoSConfig] = None,
        eval_set: Optional[Tuple[List[List[float]], List[str]]] = None,
    ) -> None:
        if not self.use_ml:
            return

        cfg = config or XGBQoSConfig()
        y_int = [self.LABEL_TO_INT[label] for label in y]
        X_arr = np.array(X, dtype=np.float32)
        y_arr = np.array(y_int, dtype=np.int32)

        sample_weight = None
        if cfg.class_weight_strategy == "balanced":
            counts = Counter(y_int)
            total = len(y_int)
            weights = {label: total / (len(counts) * count) for label, count in counts.items()}
            sample_weight = np.array([weights[label] for label in y_int], dtype=np.float32)

        self.model = xgb.XGBClassifier(
            n_estimators=cfg.n_estimators,
            max_depth=cfg.max_depth,
            learning_rate=cfg.learning_rate,
            subsample=cfg.subsample,
            colsample_bytree=cfg.colsample_bytree,
            objective='multi:softprob',
            num_class=4,
            use_label_encoder=False,
            eval_metric='mlogloss',
            random_state=cfg.random_state,
            n_jobs=cfg.n_jobs,
        )
        fit_kwargs = {}
        if cfg.early_stopping_rounds and eval_set:
            X_eval, y_eval = eval_set
            y_eval_int = [self.LABEL_TO_INT[label] for label in y_eval]
            fit_kwargs["eval_set"] = [(np.array(X_eval, dtype=np.float32), np.array(y_eval_int, dtype=np.int32))]
            fit_kwargs["early_stopping_rounds"] = cfg.early_stopping_rounds
        if sample_weight is not None:
            fit_kwargs["sample_weight"] = sample_weight
        self.model.fit(X_arr, y_arr, **fit_kwargs)
        self.is_trained = True

    def predict(self, inp: QoSInput) -> QoSResult:
        """
        Predict QoS label for input metrics.

        Returns:
            QoSResult with label, score, confidence, and method
        """
        # Fallback to rule-based if ML not available or not trained
        if not self.use_ml or not self.is_trained or self.model is None:
            return self._rule_based_score(inp)

        try:
            features = self._extract_features(inp)
            X = np.array([features], dtype=np.float32)

            # Get class probabilities
            probs = self.model.predict_proba(X)[0]
            predicted_class = int(np.argmax(probs))
            confidence = float(probs[predicted_class])
            label = self.LABELS[predicted_class]

            # Calculate continuous score from weighted probabilities
            score = sum(p * (i / 3) for i, p in enumerate(probs))

            return QoSResult(
                label=label,
                score=round(score, 3),
                confidence=round(confidence, 3),
                method="xgboost"
            )
        except Exception:
            return self._rule_based_score(inp)

    def predict_batch(self, inputs: List[QoSInput]) -> List[QoSResult]:
        """Predict QoS for multiple inputs"""
        return [self.predict(inp) for inp in inputs]


# Singleton instance
_qos_classifier: Optional[XGBQoSClassifier] = None


def get_qos_classifier() -> XGBQoSClassifier:
    """Get or create singleton QoS classifier"""
    global _qos_classifier
    if _qos_classifier is None:
        model_path = os.getenv("QOS_MODEL_PATH", "data/models/qos_model.json")
        _qos_classifier = XGBQoSClassifier(model_path=model_path)
    return _qos_classifier


def classify_qos(
    latency_ms: float,
    packet_loss: float,
    jitter_ms: float,
    bandwidth_mbps: float = 100.0,
    connection_stability: float = 1.0
) -> Dict:
    """
    Convenience function to classify QoS.

    Returns:
        {"label": str, "score": float, "confidence": float, "method": str}
    """
    classifier = get_qos_classifier()
    inp = QoSInput(
        latency_ms=latency_ms,
        packet_loss=packet_loss,
        jitter_ms=jitter_ms,
        bandwidth_mbps=bandwidth_mbps,
        connection_stability=connection_stability,
    )
    result = classifier.predict(inp)
    return {
        "label": result.label,
        "score": result.score,
        "confidence": result.confidence,
        "method": result.method,
    }
