"""
SecureWave XGBoost Risk Scoring Module (Day 8)

Scores user/connection risk based on behavioral signals.
Higher score = higher risk (0.0 to 1.0)

Inputs:
- login_failures: int (failed login attempts in last 24h)
- reconnect_frequency: int (reconnects per hour)
- unusual_hours: bool (connecting at unusual times)
- ip_reputation: float (0=bad, 1=good)
- geo_anomaly: bool (connecting from unusual location)
- data_exfil_indicator: float (unusual upload/download ratio)

Output:
- risk_score: float (0-1)
- risk_level: str ("low", "medium", "high", "critical")
- risk_factors: List[str]
"""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

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
class RiskInput:
    """Input features for risk scoring"""
    login_failures: int = 0
    reconnect_frequency: int = 0  # reconnects per hour
    unusual_hours: bool = False
    ip_reputation: float = 1.0  # 0=bad, 1=good
    geo_anomaly: bool = False
    data_exfil_indicator: float = 0.0  # ratio deviation from normal
    session_duration_anomaly: float = 0.0  # deviation from user's typical session


@dataclass
class RiskResult:
    """Risk scoring result"""
    score: float  # 0.0 to 1.0
    level: str  # "low", "medium", "high", "critical"
    factors: List[str] = field(default_factory=list)
    method: str = "rule_based"


class XGBRiskScorer:
    """
    XGBoost-based risk scorer.
    Falls back to rule-based scoring if ML dependencies unavailable.
    """

    LEVELS = ["low", "medium", "high", "critical"]

    def __init__(self, model_path: Optional[str] = None):
        self.model: Optional[xgb.XGBRegressor] = None
        self.use_ml = ML_AVAILABLE
        self.is_trained = False

        if self.use_ml and model_path and Path(model_path).exists():
            self._load_model(model_path)

    def _load_model(self, path: str) -> None:
        """Load pre-trained model from disk"""
        try:
            self.model = xgb.XGBRegressor()
            self.model.load_model(path)
            self.is_trained = True
        except Exception:
            self.model = None
            self.is_trained = False

    def save_model(self, path: str) -> None:
        """Save trained model to disk"""
        if self.model and self.is_trained:
            self.model.save_model(path)

    def _extract_features(self, inp: RiskInput) -> List[float]:
        """Extract feature vector from input"""
        return [
            float(inp.login_failures),
            float(inp.reconnect_frequency),
            1.0 if inp.unusual_hours else 0.0,
            inp.ip_reputation,
            1.0 if inp.geo_anomaly else 0.0,
            inp.data_exfil_indicator,
            inp.session_duration_anomaly,
        ]

    def _identify_risk_factors(self, inp: RiskInput) -> List[str]:
        """Identify which factors contribute to risk"""
        factors = []

        if inp.login_failures >= 3:
            factors.append(f"multiple_login_failures ({inp.login_failures})")
        if inp.reconnect_frequency >= 5:
            factors.append(f"high_reconnect_frequency ({inp.reconnect_frequency}/hr)")
        if inp.unusual_hours:
            factors.append("unusual_access_time")
        if inp.ip_reputation < 0.5:
            factors.append(f"low_ip_reputation ({inp.ip_reputation:.2f})")
        if inp.geo_anomaly:
            factors.append("geographic_anomaly")
        if inp.data_exfil_indicator > 0.5:
            factors.append(f"unusual_data_pattern ({inp.data_exfil_indicator:.2f})")
        if inp.session_duration_anomaly > 2.0:
            factors.append("abnormal_session_duration")

        return factors

    def _rule_based_score(self, inp: RiskInput) -> RiskResult:
        """
        Rule-based risk scoring (fallback when ML unavailable).
        Uses weighted sum of risk indicators.
        """
        factors = self._identify_risk_factors(inp)

        # Calculate risk score from each factor
        score = 0.0

        # Login failures: each failure adds risk
        score += min(0.3, inp.login_failures * 0.1)

        # Reconnect frequency: high frequency is suspicious
        score += min(0.2, inp.reconnect_frequency * 0.04)

        # Unusual hours
        if inp.unusual_hours:
            score += 0.1

        # IP reputation (inverted - low reputation = high risk)
        score += (1.0 - inp.ip_reputation) * 0.2

        # Geo anomaly
        if inp.geo_anomaly:
            score += 0.15

        # Data exfiltration indicator
        score += min(0.2, inp.data_exfil_indicator * 0.2)

        # Session duration anomaly
        score += min(0.1, inp.session_duration_anomaly * 0.05)

        # Clamp to 0-1
        score = max(0.0, min(1.0, score))

        # Map score to level
        if score >= 0.75:
            level = "critical"
        elif score >= 0.5:
            level = "high"
        elif score >= 0.25:
            level = "medium"
        else:
            level = "low"

        return RiskResult(
            score=round(score, 3),
            level=level,
            factors=factors,
            method="rule_based"
        )

    def train(self, X: List[List[float]], y: List[float]) -> None:
        """
        Train the XGBoost regressor for risk scoring.

        Args:
            X: List of feature vectors
            y: List of risk scores (0.0 to 1.0)
        """
        if not self.use_ml:
            return

        X_arr = np.array(X, dtype=np.float32)
        y_arr = np.array(y, dtype=np.float32)

        self.model = xgb.XGBRegressor(
            n_estimators=100,
            max_depth=6,
            learning_rate=0.1,
            objective='reg:squarederror',
            random_state=42,
            n_jobs=1,
        )
        self.model.fit(X_arr, y_arr)
        self.is_trained = True

    def predict(self, inp: RiskInput) -> RiskResult:
        """
        Predict risk score for input metrics.

        Returns:
            RiskResult with score, level, factors, and method
        """
        factors = self._identify_risk_factors(inp)

        # Fallback to rule-based if ML not available or not trained
        if not self.use_ml or not self.is_trained or self.model is None:
            return self._rule_based_score(inp)

        try:
            features = self._extract_features(inp)
            X = np.array([features], dtype=np.float32)

            # Predict risk score
            score = float(self.model.predict(X)[0])
            score = max(0.0, min(1.0, score))  # Clamp

            # Map score to level
            if score >= 0.75:
                level = "critical"
            elif score >= 0.5:
                level = "high"
            elif score >= 0.25:
                level = "medium"
            else:
                level = "low"

            return RiskResult(
                score=round(score, 3),
                level=level,
                factors=factors,
                method="xgboost"
            )
        except Exception:
            return self._rule_based_score(inp)

    def predict_batch(self, inputs: List[RiskInput]) -> List[RiskResult]:
        """Predict risk for multiple inputs"""
        return [self.predict(inp) for inp in inputs]


# Singleton instance
_risk_scorer: Optional[XGBRiskScorer] = None


def get_risk_scorer() -> XGBRiskScorer:
    """Get or create singleton risk scorer"""
    global _risk_scorer
    if _risk_scorer is None:
        model_path = os.getenv("RISK_MODEL_PATH", "data/models/risk_model.json")
        _risk_scorer = XGBRiskScorer(model_path=model_path)
    return _risk_scorer


def score_risk(
    login_failures: int = 0,
    reconnect_frequency: int = 0,
    unusual_hours: bool = False,
    ip_reputation: float = 1.0,
    geo_anomaly: bool = False,
    data_exfil_indicator: float = 0.0,
    session_duration_anomaly: float = 0.0
) -> Dict:
    """
    Convenience function to score risk.

    Returns:
        {"score": float, "level": str, "factors": List[str], "method": str}
    """
    scorer = get_risk_scorer()
    inp = RiskInput(
        login_failures=login_failures,
        reconnect_frequency=reconnect_frequency,
        unusual_hours=unusual_hours,
        ip_reputation=ip_reputation,
        geo_anomaly=geo_anomaly,
        data_exfil_indicator=data_exfil_indicator,
        session_duration_anomaly=session_duration_anomaly,
    )
    result = scorer.predict(inp)
    return {
        "score": result.score,
        "level": result.level,
        "factors": result.factors,
        "method": result.method,
    }
