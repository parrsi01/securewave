"""
ML pipeline unit tests for SecureWave.

Covers:
- XGBoost QoS classifier returns valid classes
- XGBoost Risk scorer returns scores in 0-1 range
- MARL policy engine returns valid actions
- VPN optimizer selects servers correctly
- Graceful degradation when ML libraries unavailable
- Rule-based fallbacks produce deterministic results
"""

import pytest


# ---------------------------------------------------------------------------
# XGBoost QoS Classifier
# ---------------------------------------------------------------------------

class TestXGBQoSClassifier:
    """Test the QoS classification module."""

    def test_rule_based_excellent_connection(self):
        """Low latency, zero loss should classify as excellent."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        result = classifier.predict(QoSInput(
            latency_ms=10.0,
            packet_loss=0.0,
            jitter_ms=1.0,
            bandwidth_mbps=200.0,
            connection_stability=1.0,
        ))

        assert result.label == "excellent"
        assert 0.0 <= result.score <= 1.0
        assert result.method == "rule_based"
        assert result.confidence == 0.8

    def test_rule_based_poor_connection(self):
        """High latency, high loss should classify as poor."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        result = classifier.predict(QoSInput(
            latency_ms=300.0,
            packet_loss=0.15,
            jitter_ms=80.0,
            bandwidth_mbps=5.0,
            connection_stability=0.2,
        ))

        assert result.label == "poor"
        assert 0.0 <= result.score <= 1.0

    def test_rule_based_fair_connection(self):
        """Moderate metrics should classify as fair or good."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        result = classifier.predict(QoSInput(
            latency_ms=120.0,
            packet_loss=0.03,
            jitter_ms=20.0,
            bandwidth_mbps=50.0,
            connection_stability=0.7,
        ))

        assert result.label in ("fair", "good")
        assert 0.0 <= result.score <= 1.0

    def test_classify_qos_convenience_function(self):
        """The classify_qos() convenience wrapper must return a dict."""
        from services.xgb_qos import classify_qos

        result = classify_qos(
            latency_ms=50.0,
            packet_loss=0.01,
            jitter_ms=5.0,
            bandwidth_mbps=100.0,
            connection_stability=0.95,
        )

        assert isinstance(result, dict)
        assert result["label"] in ("excellent", "good", "fair", "poor")
        assert 0.0 <= result["score"] <= 1.0
        assert "confidence" in result
        assert "method" in result

    def test_batch_prediction(self):
        """predict_batch must return one result per input."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        inputs = [
            QoSInput(latency_ms=10, packet_loss=0, jitter_ms=1),
            QoSInput(latency_ms=200, packet_loss=0.1, jitter_ms=50),
        ]
        results = classifier.predict_batch(inputs)
        assert len(results) == 2
        assert all(0.0 <= r.score <= 1.0 for r in results)

    def test_labels_are_valid(self):
        """All returned labels must be from the known set."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        valid_labels = {"excellent", "good", "fair", "poor"}

        for latency in [10, 50, 100, 150, 200, 300]:
            result = classifier.predict(QoSInput(
                latency_ms=latency, packet_loss=0.01, jitter_ms=5.0
            ))
            assert result.label in valid_labels


# ---------------------------------------------------------------------------
# XGBoost Risk Scorer
# ---------------------------------------------------------------------------

class TestXGBRiskScorer:
    """Test the risk scoring module."""

    def test_low_risk_normal_user(self):
        """A normal user with no anomalies should have low risk."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()
        result = scorer.predict(RiskInput(
            login_failures=0,
            reconnect_frequency=0,
            unusual_hours=False,
            ip_reputation=1.0,
            geo_anomaly=False,
            data_exfil_indicator=0.0,
        ))

        assert result.level == "low"
        assert 0.0 <= result.score <= 1.0
        assert result.score < 0.25

    def test_high_risk_suspicious_user(self):
        """Many anomalies should produce a high or critical risk score."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()
        result = scorer.predict(RiskInput(
            login_failures=5,
            reconnect_frequency=10,
            unusual_hours=True,
            ip_reputation=0.1,
            geo_anomaly=True,
            data_exfil_indicator=0.8,
            session_duration_anomaly=3.0,
        ))

        assert result.level in ("high", "critical")
        assert result.score >= 0.5
        assert len(result.factors) > 0

    def test_risk_score_clamped_to_0_1(self):
        """Risk score must always be in [0, 1]."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()

        # Extreme inputs
        result = scorer.predict(RiskInput(
            login_failures=100,
            reconnect_frequency=100,
            unusual_hours=True,
            ip_reputation=0.0,
            geo_anomaly=True,
            data_exfil_indicator=10.0,
            session_duration_anomaly=100.0,
        ))

        assert 0.0 <= result.score <= 1.0

    def test_risk_factors_identified(self):
        """Specific risk conditions should produce named factors."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()
        result = scorer.predict(RiskInput(
            login_failures=5,
            ip_reputation=0.2,
            geo_anomaly=True,
        ))

        factor_texts = " ".join(result.factors)
        assert "login_failures" in factor_texts
        assert "ip_reputation" in factor_texts
        assert "geographic_anomaly" in factor_texts

    def test_score_risk_convenience_function(self):
        """The score_risk() convenience wrapper must return a dict."""
        from services.xgb_risk import score_risk

        result = score_risk(
            login_failures=1,
            reconnect_frequency=2,
            ip_reputation=0.8,
        )

        assert isinstance(result, dict)
        assert result["level"] in ("low", "medium", "high", "critical")
        assert 0.0 <= result["score"] <= 1.0
        assert isinstance(result["factors"], list)

    def test_batch_prediction(self):
        """predict_batch must return one result per input."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()
        inputs = [
            RiskInput(login_failures=0),
            RiskInput(login_failures=10, geo_anomaly=True),
        ]
        results = scorer.predict_batch(inputs)
        assert len(results) == 2
        assert results[0].score < results[1].score


# ---------------------------------------------------------------------------
# MARL Policy Engine
# ---------------------------------------------------------------------------

class TestMARLPolicyEngine:
    """Test the MARL policy engine decision-making."""

    def test_safety_override_critical_packet_loss(self):
        """Critical packet loss must trigger immediate REROUTE."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        state = StateVector(
            user_id=1,
            server_id="us-east-1",
            packet_loss=0.15,  # above 10% threshold
            latency_ms=50.0,
        )
        decision = engine.decide(state)

        assert decision.action == PolicyAction.REROUTE
        assert decision.safety_override is True
        assert decision.confidence == 1.0

    def test_safety_override_critical_latency(self):
        """Critical latency must trigger immediate REROUTE."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        state = StateVector(
            user_id=1,
            server_id="us-east-1",
            latency_ms=600.0,  # above 500ms threshold
        )
        decision = engine.decide(state)

        assert decision.action == PolicyAction.REROUTE
        assert decision.safety_override is True

    def test_safety_override_high_risk(self):
        """High risk score must trigger ALERT."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        state = StateVector(
            user_id=1,
            server_id="us-east-1",
            risk_score=0.85,  # above 0.75 threshold
        )
        decision = engine.decide(state)

        assert decision.action == PolicyAction.ALERT
        assert decision.safety_override is True

    def test_safety_override_server_overload(self):
        """Server overload must trigger ROTATE_SERVER."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        state = StateVector(
            user_id=1,
            server_id="us-east-1",
            server_load=0.95,  # above 0.90 threshold
        )
        decision = engine.decide(state)

        assert decision.action == PolicyAction.ROTATE_SERVER
        assert decision.safety_override is True

    def test_normal_state_returns_valid_action(self):
        """Normal connection state should return a valid policy action."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        # Force exploitation (no exploration)
        engine.exploration_rate = 0.0

        state = StateVector(
            user_id=1,
            server_id="us-east-1",
            qos_score=0.9,
            risk_score=0.1,
            server_load=0.3,
            latency_ms=30.0,
            packet_loss=0.0,
        )
        decision = engine.decide(state)

        valid_actions = {a for a in PolicyAction}
        assert decision.action in valid_actions
        assert decision.safety_override is False

    def test_reward_calculation(self):
        """Reward function must return values in [-1, 1]."""
        from services.marl_policy import MARLPolicyEngine

        engine = MARLPolicyEngine()

        # Perfect conditions
        reward = engine.calculate_reward(
            uptime=1.0, packet_loss=0.0, reconnects=0, throughput_mbps=100.0
        )
        assert -1.0 <= reward <= 1.0
        assert reward > 0.5  # should be positive for good conditions

        # Terrible conditions
        reward_bad = engine.calculate_reward(
            uptime=0.1, packet_loss=0.5, reconnects=10, throughput_mbps=1.0
        )
        assert -1.0 <= reward_bad <= 1.0
        assert reward_bad < reward  # worse conditions -> lower reward

    def test_q_learning_update(self):
        """Q-table should update after learn() call."""
        from services.marl_policy import MARLPolicyEngine, StateVector, PolicyAction

        engine = MARLPolicyEngine()
        state = StateVector(user_id=1, server_id="s1")
        next_state = StateVector(user_id=1, server_id="s1", qos_score=0.95)

        engine.learn(state, PolicyAction.NO_ACTION, 0.8, next_state)

        assert len(engine.q_table) > 0
        assert len(engine.reward_history) == 1

    def test_get_stats(self):
        """get_stats() must return expected keys."""
        from services.marl_policy import MARLPolicyEngine

        engine = MARLPolicyEngine()
        stats = engine.get_stats()

        assert "q_table_size" in stats
        assert "avg_reward" in stats
        assert "total_decisions" in stats
        assert "available_servers" in stats

    def test_evaluate_connection_convenience(self):
        """evaluate_connection() convenience function returns a valid dict."""
        from services.marl_policy import evaluate_connection

        result = evaluate_connection(
            user_id=1,
            server_id="us-east-1",
            latency_ms=30.0,
            packet_loss=0.01,
            jitter_ms=2.0,
        )

        assert isinstance(result, dict)
        assert result["action"] in (
            "no_action", "reroute", "throttle", "rotate_server", "alert"
        )
        assert "qos" in result
        assert "risk" in result

    def test_custom_config(self):
        """MARLPolicyEngine should accept custom MARLPolicyConfig."""
        from services.marl_policy import MARLPolicyEngine, MARLPolicyConfig, StateVector, PolicyAction

        config = MARLPolicyConfig(
            critical_packet_loss=0.20,
            critical_latency=1000.0,
        )
        engine = MARLPolicyEngine(config=config)

        # 15% packet loss is below the custom 20% threshold
        state = StateVector(user_id=1, server_id="s1", packet_loss=0.15)
        decision = engine.decide(state)
        # Should NOT trigger safety override with the relaxed threshold
        assert decision.safety_override is False


# ---------------------------------------------------------------------------
# VPN Optimizer
# ---------------------------------------------------------------------------

class TestVPNOptimizer:
    """Test the OptimizedVPNOptimizer server selection."""

    def test_add_and_select_server(self):
        """Adding servers and selecting one must return a valid result."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York", {"latency_ms": 20, "bandwidth_mbps": 1000})
        optimizer.add_server("s2", "London", {"latency_ms": 80, "bandwidth_mbps": 800})

        result = optimizer.select_optimal_server(user_id=1)

        assert "server_id" in result
        assert result["server_id"] in ("s1", "s2")
        assert "location" in result
        assert "estimated_latency_ms" in result
        assert "confidence_score" in result

    def test_no_servers_returns_error(self):
        """With no servers registered, selection must return an error."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        result = optimizer.select_optimal_server(user_id=1)
        assert "error" in result

    def test_report_connection_quality(self):
        """Reporting quality should update Q-table and user state."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York", {"latency_ms": 20})

        # Select first to create user state
        optimizer.select_optimal_server(user_id=1)

        # Report quality
        optimizer.report_connection_quality(
            user_id=1, server_id="s1",
            actual_latency=25.0, actual_throughput=90.0,
        )

        assert len(optimizer.reward_history) > 0

    def test_get_stats(self):
        """get_stats() must return expected structure."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York")

        stats = optimizer.get_stats()
        assert stats["total_servers"] == 1
        assert "ml_enabled" in stats
        assert "avg_reward" in stats

    def test_premium_user_preference(self):
        """Premium users should receive different reward weighting."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York", {
            "latency_ms": 20, "bandwidth_mbps": 1000, "security_score": 0.99
        })

        # Free user selection
        free_result = optimizer.select_optimal_server(user_id=1, is_premium=False)
        # Premium user selection
        premium_result = optimizer.select_optimal_server(user_id=2, is_premium=True)

        # Both should succeed
        assert "server_id" in free_result
        assert "server_id" in premium_result

    def test_update_server_metrics(self):
        """Updating server metrics should reflect in the optimizer."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York", {"latency_ms": 20})

        optimizer.update_server_metrics("s1", {"latency_ms": 100, "cpu_load": 0.8})

        assert optimizer.servers["s1"].latency_ms == 100
        assert optimizer.servers["s1"].cpu_load == 0.8


# ---------------------------------------------------------------------------
# Graceful Degradation
# ---------------------------------------------------------------------------

class TestGracefulDegradation:
    """ML components must degrade gracefully when libraries are missing."""

    def test_optional_ml_modules_do_not_import_xgboost_at_module_import(self):
        """Core imports must not load optional native ML extensions."""
        import os
        import subprocess
        import sys
        from pathlib import Path

        repo_root = Path(__file__).resolve().parents[2]
        script = (
            "import sys; "
            "import services.xgb_qos, services.xgb_risk, services.vpn_optimizer; "
            "assert 'xgboost' not in sys.modules"
        )
        result = subprocess.run(
            [sys.executable, "-c", script],
            cwd=repo_root,
            env={**os.environ, "PYTHONPATH": str(repo_root)},
            capture_output=True,
            text=True,
            check=False,
        )

        assert result.returncode == 0, result.stderr

    def test_qos_without_trained_model(self):
        """QoS classifier without training should use rule-based fallback."""
        from services.xgb_qos import XGBQoSClassifier, QoSInput

        classifier = XGBQoSClassifier()
        # Not trained, should fall back to rules
        result = classifier.predict(QoSInput(
            latency_ms=50, packet_loss=0.01, jitter_ms=5.0
        ))

        assert result.method == "rule_based"
        assert result.label in ("excellent", "good", "fair", "poor")

    def test_risk_without_trained_model(self):
        """Risk scorer without training should use rule-based fallback."""
        from services.xgb_risk import XGBRiskScorer, RiskInput

        scorer = XGBRiskScorer()
        result = scorer.predict(RiskInput(login_failures=2))

        assert result.method == "rule_based"
        assert result.level in ("low", "medium", "high", "critical")

    def test_optimizer_without_ml(self):
        """Optimizer with use_ml=False should still select servers."""
        from services.vpn_optimizer import OptimizedVPNOptimizer

        optimizer = OptimizedVPNOptimizer(use_ml=False)
        optimizer.add_server("s1", "New York")

        result = optimizer.select_optimal_server(user_id=1)
        assert result["server_id"] == "s1"
        assert result["optimization_method"] == "MARL-only"

    def test_marl_engine_no_scorers(self):
        """MARL engine should work even without QoS/Risk scorer imports."""
        from services.marl_policy import MARLPolicyEngine, StateVector

        engine = MARLPolicyEngine()
        state = StateVector(
            user_id=1, server_id="s1",
            qos_score=0.9, risk_score=0.1,
        )
        decision = engine.decide(state)

        assert decision is not None
        assert decision.action is not None
