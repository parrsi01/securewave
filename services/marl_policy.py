"""
SecureWave MARL Policy Engine (Day 11-13)

Multi-Agent Reinforcement Learning policy engine for VPN optimization.
Combines XGBoost scores + rules with hard safety constraints.

Actions:
- NO_ACTION: Keep current state
- REROUTE: Redirect user to different server
- THROTTLE: Reduce bandwidth allocation
- ROTATE_SERVER: Proactively rotate to prevent issues
- ALERT: Flag for manual review

State Vector:
- qos_score: float (from xgb_qos)
- risk_score: float (from xgb_risk)
- server_load: float (0-1)
- latency_ms: float
- packet_loss: float
- connection_duration_minutes: float
- user_priority: int (0=free, 1=premium)

Reward Function:
  reward = uptime - packet_loss - reconnects + (0.1 * throughput_normalized)
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple
import time

# Lazy imports for QoS and Risk scorers
try:
    from services.xgb_qos import classify_qos
    from services.xgb_risk import score_risk
    SCORERS_AVAILABLE = True
except ImportError:
    SCORERS_AVAILABLE = False


class PolicyAction(Enum):
    """Available policy actions"""
    NO_ACTION = "no_action"
    REROUTE = "reroute"
    THROTTLE = "throttle"
    ROTATE_SERVER = "rotate_server"
    ALERT = "alert"


@dataclass
class StateVector:
    """MARL state representation (Day 11)"""
    user_id: int
    server_id: str
    qos_score: float = 1.0
    risk_score: float = 0.0
    server_load: float = 0.3
    latency_ms: float = 50.0
    packet_loss: float = 0.0
    jitter_ms: float = 2.0
    connection_duration_minutes: float = 0.0
    user_priority: int = 0  # 0=free, 1=premium
    reconnect_count: int = 0
    throughput_mbps: float = 100.0


@dataclass
class PolicyDecision:
    """Policy engine decision output"""
    action: PolicyAction
    target_server: Optional[str] = None
    reason: str = ""
    confidence: float = 1.0
    safety_override: bool = False
    optimization_hints: Dict[str, Any] = field(default_factory=dict)


@dataclass
class MARLPolicyConfig:
    """Configuration for MARL policy behavior."""
    critical_packet_loss: float = 0.10
    critical_latency: float = 500.0
    high_risk_threshold: float = 0.75
    max_server_load: float = 0.90
    learning_rate: float = 0.1
    discount_factor: float = 0.9
    exploration_rate: float = 0.05


class MARLPolicyEngine:
    """
    MARL Policy Engine for VPN optimization decisions.

    Combines:
    - XGBoost QoS and Risk scores
    - Rule-based safety constraints
    - Q-learning for adaptive decisions
    """

    # Safety thresholds (hard constraints)
    CRITICAL_PACKET_LOSS = 0.10  # 10% packet loss triggers immediate reroute
    CRITICAL_LATENCY = 500.0  # 500ms latency triggers reroute
    HIGH_RISK_THRESHOLD = 0.75  # Risk score for alert
    MAX_SERVER_LOAD = 0.90  # 90% load triggers rotation

    # Q-learning parameters
    LEARNING_RATE = 0.1
    DISCOUNT_FACTOR = 0.9
    EXPLORATION_RATE = 0.05

    def __init__(self, config: Optional[MARLPolicyConfig] = None):
        cfg = config or MARLPolicyConfig()
        self.critical_packet_loss = cfg.critical_packet_loss
        self.critical_latency = cfg.critical_latency
        self.high_risk_threshold = cfg.high_risk_threshold
        self.max_server_load = cfg.max_server_load
        self.learning_rate = cfg.learning_rate
        self.discount_factor = cfg.discount_factor
        self.exploration_rate = cfg.exploration_rate

        # Q-table: (state_hash, action) -> value
        self.q_table: Dict[Tuple, float] = {}

        # Reward history for tracking
        self.reward_history: List[float] = []

        # Available servers (populated from optimizer)
        self.available_servers: List[str] = []
        # Short rolling load history used for predictive balancing.
        self._server_load_samples: Dict[str, List[Tuple[float, float]]] = {}
        self._max_load_samples = 48

    def set_available_servers(self, servers: List[str]) -> None:
        """Update list of available servers"""
        self.available_servers = servers

    @staticmethod
    def _clamp(value: float, low: float, high: float) -> float:
        return max(low, min(high, value))

    def _latency_weight(self, state: StateVector) -> float:
        """
        Dynamic latency weighting:
        - Premium users are more latency-sensitive.
        - Loss/jitter amplify effective latency.
        - Lower QoS score increases weighting.
        """
        base = 1.25 if state.user_priority > 0 else 1.0
        loss_amp = 1.0 + min(0.35, max(0.0, float(state.packet_loss)) * 1.5)
        jitter_amp = 1.0 + min(0.25, max(0.0, float(state.jitter_ms)) / 200.0)
        qos_amp = 1.0 + max(0.0, (0.75 - float(state.qos_score))) * 0.6
        return round(self._clamp(base * loss_amp * jitter_amp * qos_amp, 0.85, 2.2), 4)

    def _weighted_latency_ms(self, state: StateVector) -> float:
        return float(state.latency_ms) * self._latency_weight(state)

    def _record_server_load_sample(self, state: StateVector) -> None:
        now = time.time()
        series = self._server_load_samples.setdefault(state.server_id, [])
        series.append((now, self._clamp(float(state.server_load), 0.0, 1.5)))
        if len(series) > self._max_load_samples:
            del series[: len(series) - self._max_load_samples]

    def _predict_server_load(self, state: StateVector) -> float:
        """
        Predict near-future server load from recent trend + connection risk.
        """
        series = self._server_load_samples.get(state.server_id, [])
        current = self._clamp(float(state.server_load), 0.0, 1.5)
        if len(series) < 2:
            return current

        recent = series[-8:] if len(series) >= 8 else series
        start_load = recent[0][1]
        end_load = recent[-1][1]
        upward_delta = max(0.0, end_load - start_load)

        projected = end_load + (upward_delta * 0.65)
        projected += min(0.08, max(0, int(state.reconnect_count)) * 0.01)
        projected += min(0.06, max(0.0, float(state.packet_loss)) * 0.5)
        if state.user_priority > 0:
            projected += 0.02

        return round(self._clamp(projected, 0.0, 1.5), 4)

    def preclassify_server_health(self, state: StateVector, *, predicted_load: Optional[float] = None) -> str:
        """
        Fast pre-classification before heavier health pipelines run.
        """
        predicted = self._predict_server_load(state) if predicted_load is None else float(predicted_load)
        weighted_latency = self._weighted_latency_ms(state)
        packet_loss = max(0.0, float(state.packet_loss))
        jitter = max(0.0, float(state.jitter_ms))

        if packet_loss >= 0.20 or weighted_latency >= 650.0 or predicted >= 0.97 or jitter >= 120.0:
            return "unstable"
        if packet_loss >= 0.08 or weighted_latency >= 320.0 or predicted >= 0.82 or jitter >= 45.0:
            return "degraded"
        return "healthy"

    def suggest_adaptive_mtu(self, state: StateVector, *, preclassified_health: Optional[str] = None) -> int:
        """
        MTU hint consumed by profile/tunnel orchestration.
        """
        health = (preclassified_health or self.preclassify_server_health(state)).strip().lower()
        if health == "unstable" or state.packet_loss >= 0.12:
            return 1320
        if health == "degraded" or state.jitter_ms >= 40.0:
            return 1360
        if self._weighted_latency_ms(state) >= 220.0:
            return 1380
        if state.user_priority > 0 and state.packet_loss < 0.02 and state.jitter_ms < 8.0:
            return 1420
        return 1400

    def _hash_state(self, state: StateVector) -> Tuple:
        """Create hashable state representation for Q-table"""
        return (
            int(state.qos_score * 10),
            int(state.risk_score * 10),
            int(state.server_load * 10),
            int(state.latency_ms / 50),  # 50ms buckets
            int(state.packet_loss * 100),
            state.user_priority,
        )

    def calculate_reward(
        self,
        uptime: float,  # 0-1, fraction of time connected
        packet_loss: float,  # 0-1
        reconnects: int,  # count
        throughput_mbps: float = 100.0
    ) -> float:
        """
        Calculate reward for MARL agent (Day 12).

        Formula: reward = uptime - packet_loss - (reconnects * 0.1) + (0.1 * throughput_normalized)
        """
        throughput_normalized = min(1.0, throughput_mbps / 100)

        reward = (
            uptime
            - packet_loss
            - (reconnects * 0.1)
            + (0.1 * throughput_normalized)
        )

        # Clamp to reasonable range
        return max(-1.0, min(1.0, reward))

    def _check_safety_constraints(
        self,
        state: StateVector,
        *,
        weighted_latency_ms: float,
        predicted_server_load: float,
        server_health_preclassification: str,
    ) -> Optional[PolicyDecision]:
        """
        Check hard safety constraints (Day 13).
        Returns immediate decision if constraint violated.
        """
        # Critical packet loss -> immediate reroute
        if state.packet_loss >= self.critical_packet_loss:
            return PolicyDecision(
                action=PolicyAction.REROUTE,
                reason=f"Critical packet loss: {state.packet_loss*100:.1f}%",
                confidence=1.0,
                safety_override=True,
            )

        # Critical latency -> immediate reroute
        if weighted_latency_ms >= self.critical_latency:
            return PolicyDecision(
                action=PolicyAction.REROUTE,
                reason=(
                    f"Critical weighted latency: {weighted_latency_ms:.0f}ms "
                    f"(raw={state.latency_ms:.0f}ms)"
                ),
                confidence=1.0,
                safety_override=True,
            )

        # Pre-classified instability -> immediate reroute before tunnel degrades further.
        if server_health_preclassification == "unstable":
            return PolicyDecision(
                action=PolicyAction.REROUTE,
                reason="Server pre-classified as unstable",
                confidence=0.95,
                safety_override=True,
            )

        # High risk -> alert
        if state.risk_score >= self.high_risk_threshold:
            return PolicyDecision(
                action=PolicyAction.ALERT,
                reason=f"High risk score: {state.risk_score:.2f}",
                confidence=1.0,
                safety_override=True,
            )

        # Server overloaded -> rotate
        if predicted_server_load >= self.max_server_load:
            return PolicyDecision(
                action=PolicyAction.ROTATE_SERVER,
                reason=(
                    f"Predicted server overload: {predicted_server_load*100:.0f}% "
                    f"(current={state.server_load*100:.0f}%)"
                ),
                confidence=0.9,
                safety_override=True,
            )

        return None

    def _select_best_server(self, current_server: str) -> Optional[str]:
        """Select best alternative server"""
        if len(self.available_servers) <= 1:
            return None

        # Simple selection: pick first server that's not current
        for server in self.available_servers:
            if server != current_server:
                return server

        return None

    def _get_q_value(self, state_hash: Tuple, action: PolicyAction) -> float:
        """Get Q-value for state-action pair"""
        return self.q_table.get((state_hash, action.value), 0.0)

    def _update_q_value(
        self,
        state_hash: Tuple,
        action: PolicyAction,
        reward: float,
        next_state_hash: Tuple
    ) -> None:
        """Update Q-value using Q-learning update rule"""
        current_q = self._get_q_value(state_hash, action)

        # Max Q-value for next state
        max_next_q = max(
            self._get_q_value(next_state_hash, a)
            for a in PolicyAction
        )

        # Q-learning update
        new_q = current_q + self.learning_rate * (
            reward + self.discount_factor * max_next_q - current_q
        )

        self.q_table[(state_hash, action.value)] = new_q
        self.reward_history.append(reward)

        # Keep history bounded
        if len(self.reward_history) > 1000:
            self.reward_history = self.reward_history[-1000:]

    def decide(self, state: StateVector) -> PolicyDecision:
        """
        Make policy decision for given state (Day 13).

        Combines:
        1. Hard safety constraints (override everything)
        2. Q-learning exploration/exploitation
        3. XGBoost-informed decisions
        """
        self._record_server_load_sample(state)
        weighted_latency_ms = self._weighted_latency_ms(state)
        predicted_server_load = self._predict_server_load(state)
        server_health_preclassification = self.preclassify_server_health(
            state,
            predicted_load=predicted_server_load,
        )
        adaptive_mtu = self.suggest_adaptive_mtu(
            state,
            preclassified_health=server_health_preclassification,
        )
        hints = {
            "latency_weight": self._latency_weight(state),
            "weighted_latency_ms": round(weighted_latency_ms, 2),
            "predicted_server_load": round(predicted_server_load, 4),
            "server_health_preclassification": server_health_preclassification,
            "adaptive_mtu": int(adaptive_mtu),
        }

        # Check safety constraints first
        safety_decision = self._check_safety_constraints(
            state,
            weighted_latency_ms=weighted_latency_ms,
            predicted_server_load=predicted_server_load,
            server_health_preclassification=server_health_preclassification,
        )
        if safety_decision:
            # Find target server for reroute/rotate actions
            if safety_decision.action in (PolicyAction.REROUTE, PolicyAction.ROTATE_SERVER):
                safety_decision.target_server = self._select_best_server(state.server_id)
            safety_decision.optimization_hints = hints
            return safety_decision

        state_hash = self._hash_state(state)

        # Exploration: random action
        import secrets
        rng = secrets.SystemRandom()
        if rng.random() < self.exploration_rate:
            action = rng.choice(list(PolicyAction))
        else:
            # Exploitation: best Q-value action
            best_action = PolicyAction.NO_ACTION
            best_value = float('-inf')

            for action in PolicyAction:
                value = self._get_q_value(state_hash, action)
                if value > best_value:
                    best_value = value
                    best_action = action

            action = best_action

        # Build decision
        decision = PolicyDecision(
            action=action,
            confidence=0.8,
            safety_override=False,
            optimization_hints=hints,
        )

        # Set target server if needed
        if action in (PolicyAction.REROUTE, PolicyAction.ROTATE_SERVER):
            decision.target_server = self._select_best_server(state.server_id)
            decision.reason = (
                f"Q-learning selected {action.value} "
                f"(health={server_health_preclassification})"
            )
        elif action == PolicyAction.THROTTLE:
            decision.reason = f"QoS degradation detected ({server_health_preclassification})"
        elif action == PolicyAction.ALERT:
            decision.reason = "Anomaly detected by policy"
        else:
            decision.reason = f"Connection stable ({server_health_preclassification})"

        return decision

    def learn(
        self,
        state: StateVector,
        action: PolicyAction,
        reward: float,
        next_state: StateVector
    ) -> None:
        """Update Q-table based on observed reward"""
        state_hash = self._hash_state(state)
        next_state_hash = self._hash_state(next_state)
        self._update_q_value(state_hash, action, reward, next_state_hash)

    def get_stats(self) -> Dict:
        """Get policy engine statistics"""
        avg_reward = 0.0
        if self.reward_history:
            avg_reward = sum(self.reward_history) / len(self.reward_history)

        return {
            "q_table_size": len(self.q_table),
            "avg_reward": round(avg_reward, 3),
            "total_decisions": len(self.reward_history),
            "available_servers": len(self.available_servers),
            "exploration_rate": self.exploration_rate,
            "tracked_servers": len(self._server_load_samples),
        }


# Singleton instance
_policy_engine: Optional[MARLPolicyEngine] = None


def get_policy_engine() -> MARLPolicyEngine:
    """Get or create singleton policy engine"""
    global _policy_engine
    if _policy_engine is None:
        _policy_engine = MARLPolicyEngine()
    return _policy_engine


def create_policy_engine(config: Optional[MARLPolicyConfig] = None) -> MARLPolicyEngine:
    """Create a policy engine instance with optional configuration."""
    return MARLPolicyEngine(config=config)


def evaluate_connection(
    user_id: int,
    server_id: str,
    latency_ms: float,
    packet_loss: float,
    jitter_ms: float,
    bandwidth_mbps: float = 100.0,
    server_load: float = 0.3,
    user_priority: int = 0,
    reconnect_count: int = 0,
    login_failures: int = 0,
) -> Dict:
    """
    Convenience function to evaluate a connection and get policy decision.

    Returns:
        {
            "action": str,
            "target_server": str or None,
            "reason": str,
            "confidence": float,
            "qos": {...},
            "risk": {...}
        }
    """
    engine = get_policy_engine()

    # Get QoS score
    qos_result = {"score": 0.8, "label": "good", "method": "fallback"}
    if SCORERS_AVAILABLE:
        qos_result = classify_qos(
            latency_ms=latency_ms,
            packet_loss=packet_loss,
            jitter_ms=jitter_ms,
            bandwidth_mbps=bandwidth_mbps,
        )

    # Get risk score
    risk_result = {"score": 0.1, "level": "low", "method": "fallback"}
    if SCORERS_AVAILABLE:
        risk_result = score_risk(
            login_failures=login_failures,
            reconnect_frequency=reconnect_count,
        )

    # Build state vector
    state = StateVector(
        user_id=user_id,
        server_id=server_id,
        qos_score=qos_result.get("score", 0.8),
        risk_score=risk_result.get("score", 0.1),
        server_load=server_load,
        latency_ms=latency_ms,
        packet_loss=packet_loss,
        jitter_ms=jitter_ms,
        user_priority=user_priority,
        reconnect_count=reconnect_count,
    )

    # Get policy decision
    decision = engine.decide(state)

    return {
        "action": decision.action.value,
        "target_server": decision.target_server,
        "reason": decision.reason,
        "confidence": decision.confidence,
        "safety_override": decision.safety_override,
        "optimization_hints": decision.optimization_hints,
        "qos": qos_result,
        "risk": risk_result,
    }
