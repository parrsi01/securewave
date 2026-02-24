"""
SecureWave Active Security Monitor

Integrates the MARL policy engine and XGBoost risk/QoS scorers into a
unified, thread-safe security monitoring layer.  All public methods are
safe to call from concurrent FastAPI request handlers.

Responsibilities:
- Per-connection security evaluation (QoS + Risk -> MARL decision)
- Batch anomaly detection across multiple connections
- AI/automated-agent attack detection (rapid requests, unusual headers)
- Threat summary reporting with alert history
"""

import logging
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

from services.marl_policy import (
    MARLPolicyEngine,
    PolicyAction,
    StateVector,
    get_policy_engine,
)
from services.xgb_qos import classify_qos
from services.xgb_risk import score_risk

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class ThreatLevel(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class AlertSeverity(Enum):
    INFO = "info"
    WARNING = "warning"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class SecurityAlert:
    """A single recorded security alert."""
    timestamp: float
    severity: AlertSeverity
    category: str
    message: str
    user_id: Optional[int] = None
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "severity": self.severity.value,
            "category": self.category,
            "message": self.message,
            "user_id": self.user_id,
            "details": self.details,
        }


@dataclass
class ConnectionMetrics:
    """Metrics submitted for a single VPN connection evaluation."""
    latency_ms: float = 50.0
    packet_loss: float = 0.0
    jitter_ms: float = 2.0
    bandwidth_mbps: float = 100.0
    server_load: float = 0.3
    server_id: str = "unknown"
    login_failures: int = 0
    reconnect_count: int = 0
    unusual_hours: bool = False
    ip_reputation: float = 1.0
    geo_anomaly: bool = False
    data_exfil_indicator: float = 0.0
    user_priority: int = 0


# ---------------------------------------------------------------------------
# Thresholds for AI-agent / automated attack detection
# ---------------------------------------------------------------------------

_AI_AGENT_DEFAULTS = {
    "rapid_request_window_seconds": 60,
    "rapid_request_threshold": 100,
    "unique_endpoint_threshold": 30,
    "sequential_scan_threshold": 20,
    "payload_size_anomaly_bytes": 50_000,
}

# ---------------------------------------------------------------------------
# SecurityMonitor (thread-safe singleton)
# ---------------------------------------------------------------------------

class SecurityMonitor:
    """
    Central security monitor that combines MARL, XGBoost QoS, and XGBoost
    Risk into a single evaluation pipeline.

    Thread-safety is guaranteed via a ``threading.Lock`` around all mutable
    state (alert list, threat-level cache, request-tracking counters).
    """

    _MAX_ALERTS = 5000  # ring-buffer cap

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._alerts: deque[SecurityAlert] = deque(maxlen=self._MAX_ALERTS)
        self._current_threat_level: ThreatLevel = ThreatLevel.LOW
        self._threat_level_updated_at: float = time.time()

        # Per-user request tracking for AI-agent detection
        # Mapping: user_id -> list of request timestamps
        self._request_tracker: Dict[int, deque] = {}

        # Reference to shared MARL engine
        self._policy_engine: MARLPolicyEngine = get_policy_engine()

        logger.info("SecurityMonitor initialised")

    # ------------------------------------------------------------------
    # evaluate_connection
    # ------------------------------------------------------------------

    def evaluate_connection(
        self,
        user_id: int,
        connection_metrics: ConnectionMetrics,
    ) -> Dict[str, Any]:
        """
        Run XGBoost QoS + Risk scoring and feed into the MARL policy
        engine.  Returns a combined evaluation dict.

        This is the primary integration point for per-request security
        checks on an active VPN connection.
        """
        # 1. QoS classification
        qos_result = classify_qos(
            latency_ms=connection_metrics.latency_ms,
            packet_loss=connection_metrics.packet_loss,
            jitter_ms=connection_metrics.jitter_ms,
            bandwidth_mbps=connection_metrics.bandwidth_mbps,
        )

        # 2. Risk scoring
        risk_result = score_risk(
            login_failures=connection_metrics.login_failures,
            reconnect_frequency=connection_metrics.reconnect_count,
            unusual_hours=connection_metrics.unusual_hours,
            ip_reputation=connection_metrics.ip_reputation,
            geo_anomaly=connection_metrics.geo_anomaly,
            data_exfil_indicator=connection_metrics.data_exfil_indicator,
        )

        # 3. Build MARL state vector
        state = StateVector(
            user_id=user_id,
            server_id=connection_metrics.server_id,
            qos_score=qos_result.get("score", 0.8),
            risk_score=risk_result.get("score", 0.1),
            server_load=connection_metrics.server_load,
            latency_ms=connection_metrics.latency_ms,
            packet_loss=connection_metrics.packet_loss,
            jitter_ms=connection_metrics.jitter_ms,
            user_priority=connection_metrics.user_priority,
            reconnect_count=connection_metrics.reconnect_count,
        )

        # 4. MARL policy decision
        decision = self._policy_engine.decide(state)

        # 5. Record alert if action is non-trivial
        if decision.action not in (PolicyAction.NO_ACTION,):
            severity = self._action_to_severity(decision.action)
            self._record_alert(
                severity=severity,
                category="policy_action",
                message=f"MARL policy triggered {decision.action.value}: {decision.reason}",
                user_id=user_id,
                details={
                    "action": decision.action.value,
                    "target_server": decision.target_server,
                    "qos": qos_result,
                    "risk": risk_result,
                },
            )

        # 6. Possibly escalate global threat level
        self._maybe_update_threat_level(risk_result.get("score", 0.0))

        return {
            "user_id": user_id,
            "qos": qos_result,
            "risk": risk_result,
            "policy_action": decision.action.value,
            "policy_reason": decision.reason,
            "policy_confidence": decision.confidence,
            "policy_safety_override": decision.safety_override,
            "policy_optimization_hints": dict(decision.optimization_hints or {}),
            "target_server": decision.target_server,
            "threat_level": self._current_threat_level.value,
        }

    # ------------------------------------------------------------------
    # detect_anomalies (batch)
    # ------------------------------------------------------------------

    def detect_anomalies(
        self,
        metrics_batch: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        """
        Batch anomaly detection across multiple connections.

        Accepts a list of dicts, each containing at minimum:
          - user_id: int
          - latency_ms, packet_loss, jitter_ms, bandwidth_mbps, server_load,
            server_id  (matching ``ConnectionMetrics`` fields)

        Returns a summary with per-connection verdicts and an aggregate
        anomaly count.
        """
        results: List[Dict[str, Any]] = []
        anomaly_count = 0

        for entry in metrics_batch:
            user_id = entry.get("user_id", 0)
            metrics = ConnectionMetrics(
                latency_ms=entry.get("latency_ms", 50.0),
                packet_loss=entry.get("packet_loss", 0.0),
                jitter_ms=entry.get("jitter_ms", 2.0),
                bandwidth_mbps=entry.get("bandwidth_mbps", 100.0),
                server_load=entry.get("server_load", 0.3),
                server_id=entry.get("server_id", "unknown"),
                login_failures=entry.get("login_failures", 0),
                reconnect_count=entry.get("reconnect_count", 0),
                unusual_hours=entry.get("unusual_hours", False),
                ip_reputation=entry.get("ip_reputation", 1.0),
                geo_anomaly=entry.get("geo_anomaly", False),
                data_exfil_indicator=entry.get("data_exfil_indicator", 0.0),
                user_priority=entry.get("user_priority", 0),
            )
            evaluation = self.evaluate_connection(user_id, metrics)
            is_anomaly = evaluation["policy_action"] != PolicyAction.NO_ACTION.value
            if is_anomaly:
                anomaly_count += 1
            results.append({
                "user_id": user_id,
                "is_anomaly": is_anomaly,
                "action": evaluation["policy_action"],
                "reason": evaluation["policy_reason"],
                "risk_score": evaluation["risk"].get("score", 0.0),
                "qos_label": evaluation["qos"].get("label", "unknown"),
            })

        return {
            "total": len(metrics_batch),
            "anomalies": anomaly_count,
            "threat_level": self._current_threat_level.value,
            "results": results,
        }

    # ------------------------------------------------------------------
    # check_ai_agent_attack
    # ------------------------------------------------------------------

    def check_ai_agent_attack(
        self,
        request_patterns: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Detect automated / AI-agent attack patterns.

        Expected keys in ``request_patterns``:
          - user_id: int
          - request_count: int          (requests in the last window)
          - unique_endpoints: int       (distinct endpoints hit)
          - avg_payload_size_bytes: int
          - has_unusual_headers: bool
          - sequential_ids_probed: int  (e.g. /api/users/1, /api/users/2, ...)
          - timestamp: float            (optional, defaults to now)

        Returns a verdict dict with ``is_attack``, ``confidence``, and
        ``reasons``.
        """
        now = request_patterns.get("timestamp", time.time())
        user_id = request_patterns.get("user_id", 0)
        request_count = request_patterns.get("request_count", 0)
        unique_endpoints = request_patterns.get("unique_endpoints", 0)
        avg_payload = request_patterns.get("avg_payload_size_bytes", 0)
        unusual_headers = request_patterns.get("has_unusual_headers", False)
        sequential_ids = request_patterns.get("sequential_ids_probed", 0)

        reasons: List[str] = []
        score = 0.0

        # Rapid-fire requests
        threshold = _AI_AGENT_DEFAULTS["rapid_request_threshold"]
        if request_count > threshold:
            reasons.append(
                f"Rapid requests: {request_count} in window "
                f"(threshold {threshold})"
            )
            score += min(0.35, (request_count - threshold) / threshold * 0.35)

        # Endpoint enumeration
        ep_threshold = _AI_AGENT_DEFAULTS["unique_endpoint_threshold"]
        if unique_endpoints > ep_threshold:
            reasons.append(
                f"Endpoint enumeration: {unique_endpoints} unique endpoints "
                f"(threshold {ep_threshold})"
            )
            score += 0.20

        # Sequential ID probing (classic scraper/fuzzer)
        seq_threshold = _AI_AGENT_DEFAULTS["sequential_scan_threshold"]
        if sequential_ids > seq_threshold:
            reasons.append(
                f"Sequential ID probing: {sequential_ids} sequential IDs "
                f"(threshold {seq_threshold})"
            )
            score += 0.25

        # Unusually large payloads (prompt-injection / LLM-style attacks)
        payload_threshold = _AI_AGENT_DEFAULTS["payload_size_anomaly_bytes"]
        if avg_payload > payload_threshold:
            reasons.append(
                f"Large payloads: avg {avg_payload} bytes "
                f"(threshold {payload_threshold})"
            )
            score += 0.10

        # Unusual headers (e.g. missing Accept, odd User-Agent patterns)
        if unusual_headers:
            reasons.append("Unusual or missing standard HTTP headers")
            score += 0.10

        score = min(1.0, score)
        is_attack = score >= 0.40

        if is_attack:
            severity = AlertSeverity.CRITICAL if score >= 0.70 else AlertSeverity.HIGH
            self._record_alert(
                severity=severity,
                category="ai_agent_attack",
                message=f"Possible AI-agent attack detected (score {score:.2f})",
                user_id=user_id,
                details={
                    "score": round(score, 3),
                    "reasons": reasons,
                    "request_count": request_count,
                    "unique_endpoints": unique_endpoints,
                },
            )

        # Track request timestamps for user
        with self._lock:
            if user_id not in self._request_tracker:
                self._request_tracker[user_id] = deque(maxlen=500)
            self._request_tracker[user_id].append(now)

        return {
            "is_attack": is_attack,
            "score": round(score, 3),
            "reasons": reasons,
            "user_id": user_id,
            "threat_level": self._current_threat_level.value,
        }

    # ------------------------------------------------------------------
    # get_threat_summary
    # ------------------------------------------------------------------

    def get_threat_summary(self) -> Dict[str, Any]:
        """
        Return the current threat level, recent alert counts by severity,
        and the last N alerts.
        """
        with self._lock:
            alerts_list = list(self._alerts)

        now = time.time()
        one_hour_ago = now - 3600

        recent = [a for a in alerts_list if a.timestamp >= one_hour_ago]
        severity_counts: Dict[str, int] = {s.value: 0 for s in AlertSeverity}
        for alert in recent:
            severity_counts[alert.severity.value] += 1

        last_20 = [a.to_dict() for a in alerts_list[-20:]]

        return {
            "threat_level": self._current_threat_level.value,
            "threat_level_updated_at": self._threat_level_updated_at,
            "alerts_last_hour": len(recent),
            "severity_counts": severity_counts,
            "recent_alerts": last_20,
            "total_alerts_stored": len(alerts_list),
        }

    # ------------------------------------------------------------------
    # get_recent_alerts
    # ------------------------------------------------------------------

    def get_recent_alerts(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Return the most recent ``limit`` alerts as dicts."""
        with self._lock:
            tail = list(self._alerts)[-limit:]
        return [a.to_dict() for a in tail]

    # ------------------------------------------------------------------
    # report_suspicious_activity (manual reports from users/endpoints)
    # ------------------------------------------------------------------

    def report_suspicious_activity(
        self,
        user_id: int,
        category: str,
        description: str,
        details: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Accept a user-submitted or system-submitted suspicious activity
        report and store it as an alert.
        """
        alert = self._record_alert(
            severity=AlertSeverity.WARNING,
            category=category,
            message=description,
            user_id=user_id,
            details=details or {},
        )
        logger.info(
            "Suspicious activity reported by user %d: %s",
            user_id,
            description,
        )
        return {
            "accepted": True,
            "alert_id": id(alert),
            "timestamp": alert.timestamp,
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _record_alert(
        self,
        severity: AlertSeverity,
        category: str,
        message: str,
        user_id: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None,
    ) -> SecurityAlert:
        alert = SecurityAlert(
            timestamp=time.time(),
            severity=severity,
            category=category,
            message=message,
            user_id=user_id,
            details=details or {},
        )
        with self._lock:
            self._alerts.append(alert)

        logger.warning(
            "SECURITY ALERT [%s] %s: %s",
            severity.value,
            category,
            message,
        )
        return alert

    def _action_to_severity(self, action: PolicyAction) -> AlertSeverity:
        mapping = {
            PolicyAction.REROUTE: AlertSeverity.HIGH,
            PolicyAction.THROTTLE: AlertSeverity.WARNING,
            PolicyAction.ROTATE_SERVER: AlertSeverity.INFO,
            PolicyAction.ALERT: AlertSeverity.CRITICAL,
        }
        return mapping.get(action, AlertSeverity.INFO)

    def _maybe_update_threat_level(self, latest_risk_score: float) -> None:
        """
        Heuristic: if recent alerts are accumulating or risk scores are
        climbing, escalate the global threat level.
        """
        with self._lock:
            now = time.time()
            one_hour_ago = now - 3600
            recent_critical = sum(
                1
                for a in self._alerts
                if a.timestamp >= one_hour_ago
                and a.severity in (AlertSeverity.HIGH, AlertSeverity.CRITICAL)
            )

            if recent_critical >= 10 or latest_risk_score >= 0.85:
                new_level = ThreatLevel.CRITICAL
            elif recent_critical >= 5 or latest_risk_score >= 0.65:
                new_level = ThreatLevel.HIGH
            elif recent_critical >= 2 or latest_risk_score >= 0.40:
                new_level = ThreatLevel.MEDIUM
            else:
                new_level = ThreatLevel.LOW

            if new_level != self._current_threat_level:
                logger.warning(
                    "Threat level changed: %s -> %s",
                    self._current_threat_level.value,
                    new_level.value,
                )
                self._current_threat_level = new_level
                self._threat_level_updated_at = now


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------

_security_monitor: Optional[SecurityMonitor] = None
_singleton_lock = threading.Lock()


def get_security_monitor() -> SecurityMonitor:
    """Return the process-wide SecurityMonitor singleton (thread-safe)."""
    global _security_monitor
    if _security_monitor is None:
        with _singleton_lock:
            # Double-checked locking
            if _security_monitor is None:
                _security_monitor = SecurityMonitor()
    return _security_monitor
