"""
SecureWave VPN Routing Optimizer
Multi-Agent Reinforcement Learning (MARL) + XGBoost for intelligent server selection
Optimizes for latency, bandwidth, security, and load balancing
"""
import json
import time
from collections import deque
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np
import xgboost as xgb
from sklearn.preprocessing import StandardScaler


@dataclass
class ServerMetrics:
    """Real-time server performance metrics"""
    server_id: str
    location: str
    latency_ms: float
    bandwidth_mbps: float
    cpu_load: float
    active_connections: int
    packet_loss: float
    jitter_ms: float
    security_score: float
    timestamp: float


@dataclass
class ConnectionState:
    """User connection state for MARL agent"""
    user_id: int
    current_server: Optional[str]
    avg_throughput: float
    connection_stability: float
    preferred_location: Optional[str]
    priority_level: int  # 0=free, 1=premium


class VPNOptimizer:
    """
    Advanced VPN routing optimizer combining:
    - Multi-Agent Reinforcement Learning (MARL) for adaptive decision-making
    - XGBoost for predictive server performance modeling
    - Real-time metrics analysis
    - Load balancing across server fleet
    """

    def __init__(self, model_path: Optional[str] = None):
        self.servers: Dict[str, ServerMetrics] = {}
        self.connection_states: Dict[int, ConnectionState] = {}
        self.metrics_history = deque(maxlen=10000)
        self.scaler = StandardScaler()

        # MARL parameters
        self.learning_rate = 0.001
        self.discount_factor = 0.95
        self.exploration_rate = 0.1
        self.q_table: Dict[Tuple, float] = {}

        # XGBoost model for server performance prediction
        self.xgb_model = self._initialize_xgboost_model(model_path)

        # Performance tracking
        self.reward_history = deque(maxlen=1000)
        self.prediction_accuracy = 0.0

    def _initialize_xgboost_model(self, model_path: Optional[str] = None) -> xgb.XGBRegressor:
        """Initialize XGBoost model for server performance prediction"""
        if model_path:
            try:
                model = xgb.XGBRegressor()
                model.load_model(model_path)
                return model
            except Exception:
                pass

        # Create new model with optimized hyperparameters
        return xgb.XGBRegressor(
            n_estimators=200,
            max_depth=8,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            objective='reg:squarederror',
            tree_method='hist',
            random_state=42
        )

    def add_server(self, server_id: str, location: str, initial_metrics: Optional[Dict] = None):
        """Register a new VPN server in the optimizer"""
        metrics = initial_metrics or {}
        self.servers[server_id] = ServerMetrics(
            server_id=server_id,
            location=location,
            latency_ms=metrics.get('latency_ms', 50.0),
            bandwidth_mbps=metrics.get('bandwidth_mbps', 1000.0),
            cpu_load=metrics.get('cpu_load', 0.3),
            active_connections=metrics.get('active_connections', 0),
            packet_loss=metrics.get('packet_loss', 0.0),
            jitter_ms=metrics.get('jitter_ms', 2.0),
            security_score=metrics.get('security_score', 0.95),
            timestamp=time.time()
        )

    def update_server_metrics(self, server_id: str, metrics: Dict):
        """Update real-time server metrics"""
        if server_id not in self.servers:
            return

        server = self.servers[server_id]
        server.latency_ms = metrics.get('latency_ms', server.latency_ms)
        server.bandwidth_mbps = metrics.get('bandwidth_mbps', server.bandwidth_mbps)
        server.cpu_load = metrics.get('cpu_load', server.cpu_load)
        server.active_connections = metrics.get('active_connections', server.active_connections)
        server.packet_loss = metrics.get('packet_loss', server.packet_loss)
        server.jitter_ms = metrics.get('jitter_ms', server.jitter_ms)
        server.security_score = metrics.get('security_score', server.security_score)
        server.timestamp = time.time()

        # Store in history for model training
        self.metrics_history.append({
            'server_id': server_id,
            'timestamp': server.timestamp,
            **metrics
        })

    def _extract_features(self, server: ServerMetrics, user_state: ConnectionState) -> np.ndarray:
        """Extract feature vector for ML model"""
        features = [
            server.latency_ms,
            server.bandwidth_mbps,
            server.cpu_load,
            server.active_connections,
            server.packet_loss,
            server.jitter_ms,
            server.security_score,
            user_state.avg_throughput,
            user_state.connection_stability,
            user_state.priority_level,
            # Geographic preference (1 if matches, 0 otherwise)
            1.0 if user_state.preferred_location == server.location else 0.0,
            # Time-based features
            np.sin(2 * np.pi * (time.time() % 86400) / 86400),  # Time of day
            np.cos(2 * np.pi * (time.time() % 86400) / 86400),
        ]
        return np.array(features).reshape(1, -1)

    def _calculate_reward(self, server: ServerMetrics, user_state: ConnectionState,
                         actual_performance: Optional[float] = None) -> float:
        """
        Calculate reward for MARL agent
        Reward based on: latency, bandwidth, stability, security
        """
        # Base rewards
        latency_reward = max(0, (200 - server.latency_ms) / 200)  # Lower is better
        bandwidth_reward = min(1, server.bandwidth_mbps / 1000)  # Higher is better
        load_reward = max(0, (1 - server.cpu_load))  # Lower load is better
        stability_reward = max(0, (1 - server.packet_loss) * (1 - server.jitter_ms / 100))
        security_reward = server.security_score

        # Weighted combination (optimized for VPN performance)
        if user_state.priority_level == 0:  # Free tier
            # Free users: prioritize latency and basic stability
            reward = (
                0.4 * latency_reward +
                0.2 * bandwidth_reward +
                0.2 * load_reward +
                0.2 * stability_reward
            )
        else:  # Premium tier
            # Premium users: balanced optimization with security
            reward = (
                0.25 * latency_reward +
                0.25 * bandwidth_reward +
                0.15 * load_reward +
                0.20 * stability_reward +
                0.15 * security_reward
            )

        # Bonus for location preference
        if user_state.preferred_location == server.location:
            reward *= 1.1

        # Penalty for overloaded servers
        if server.active_connections > 100:
            reward *= 0.8

        return reward

    def _select_server_marl(self, user_id: int) -> str:
        """
        Select optimal server using MARL (Multi-Agent Reinforcement Learning)
        Each user is treated as an agent making decisions
        """
        if user_id not in self.connection_states:
            # Initialize new user state
            self.connection_states[user_id] = ConnectionState(
                user_id=user_id,
                current_server=None,
                avg_throughput=0.0,
                connection_stability=1.0,
                preferred_location=None,
                priority_level=0
            )

        user_state = self.connection_states[user_id]

        # Epsilon-greedy exploration
        if np.random.random() < self.exploration_rate:
            # Explore: random server
            return np.random.choice(list(self.servers.keys()))

        # Exploit: choose best server based on Q-values
        best_server = None
        best_value = float('-inf')

        for server_id, server in self.servers.items():
            # State-action pair for Q-table
            state = (user_id, server.location, int(server.cpu_load * 10))
            action = server_id

            # Get Q-value (default 0 for new state-action pairs)
            q_value = self.q_table.get((state, action), 0.0)

            # Use XGBoost prediction to enhance Q-value
            features = self._extract_features(server, user_state)
            predicted_performance = self.xgb_model.predict(features)[0] if len(self.metrics_history) > 100 else 0.5

            # Combined value
            combined_value = 0.7 * q_value + 0.3 * predicted_performance

            if combined_value > best_value:
                best_value = combined_value
                best_server = server_id

        return best_server or list(self.servers.keys())[0]

    def update_q_table(self, user_id: int, server_id: str, reward: float):
        """Update Q-table based on observed reward (MARL learning step)"""
        if user_id not in self.connection_states:
            return

        user_state = self.connection_states[user_id]
        server = self.servers.get(server_id)
        if not server:
            return

        # Current state-action
        state = (user_id, server.location, int(server.cpu_load * 10))
        action = server_id

        # Get current Q-value
        current_q = self.q_table.get((state, action), 0.0)

        # Get max Q-value for next state (for all possible servers)
        max_next_q = max([
            self.q_table.get((state, sid), 0.0)
            for sid in self.servers.keys()
        ], default=0.0)

        # Q-learning update rule
        new_q = current_q + self.learning_rate * (
            reward + self.discount_factor * max_next_q - current_q
        )

        self.q_table[(state, action)] = new_q
        self.reward_history.append(reward)

    def select_optimal_server(self, user_id: int, user_location: Optional[str] = None,
                             is_premium: bool = False) -> Dict:
        """
        Main entry point: Select optimal VPN server for user
        Returns server details and confidence score
        """
        if not self.servers:
            return {"error": "No servers available"}

        # Update user state
        if user_id in self.connection_states:
            self.connection_states[user_id].priority_level = 1 if is_premium else 0
            if user_location:
                self.connection_states[user_id].preferred_location = user_location
        else:
            self.connection_states[user_id] = ConnectionState(
                user_id=user_id,
                current_server=None,
                avg_throughput=0.0,
                connection_stability=1.0,
                preferred_location=user_location,
                priority_level=1 if is_premium else 0
            )

        # Select server using MARL
        selected_server_id = self._select_server_marl(user_id)
        server = self.servers[selected_server_id]

        # Calculate confidence score
        user_state = self.connection_states[user_id]
        reward = self._calculate_reward(server, user_state)
        confidence = min(1.0, reward * 1.2)  # Scale to 0-1

        return {
            "server_id": server.server_id,
            "location": server.location,
            "estimated_latency_ms": round(server.latency_ms, 2),
            "estimated_bandwidth_mbps": round(server.bandwidth_mbps, 2),
            "confidence_score": round(confidence, 3),
            "server_load": round(server.cpu_load, 2),
            "active_connections": server.active_connections,
            "security_score": round(server.security_score, 2),
            "optimization_method": "MARL+XGBoost"
        }

    def report_connection_quality(self, user_id: int, server_id: str,
                                  actual_latency: float, actual_throughput: float):
        """
        Report actual connection quality for model improvement
        This enables continuous learning and model refinement
        """
        if user_id not in self.connection_states or server_id not in self.servers:
            return

        server = self.servers[server_id]
        user_state = self.connection_states[user_id]

        # Update user state
        user_state.avg_throughput = 0.9 * user_state.avg_throughput + 0.1 * actual_throughput
        user_state.current_server = server_id

        # Calculate actual performance reward
        performance_score = min(1.0, actual_throughput / 100)  # Normalize to 0-1
        latency_score = max(0, (200 - actual_latency) / 200)
        actual_reward = (performance_score + latency_score) / 2

        # Update Q-table with actual reward
        self.update_q_table(user_id, server_id, actual_reward)

        # Train XGBoost model periodically
        if len(self.metrics_history) > 100 and len(self.metrics_history) % 50 == 0:
            self._train_xgboost_model()

    def _train_xgboost_model(self):
        """Train XGBoost model on historical metrics"""
        if len(self.metrics_history) < 100:
            return

        # Prepare training data from historical metrics
        X_data = []
        y_data = []

        for i, record in enumerate(list(self.metrics_history)[-500:]):
            # Features
            features = [
                record.get('latency_ms', 50),
                record.get('bandwidth_mbps', 1000),
                record.get('cpu_load', 0.5),
                record.get('active_connections', 0),
                record.get('packet_loss', 0),
                record.get('jitter_ms', 2),
                record.get('security_score', 0.95),
            ]

            # Target: normalized performance score
            latency_score = max(0, (200 - record.get('latency_ms', 50)) / 200)
            bandwidth_score = min(1, record.get('bandwidth_mbps', 1000) / 1000)
            target = (latency_score + bandwidth_score) / 2

            X_data.append(features)
            y_data.append(target)

        # Train model
        X = np.array(X_data)
        y = np.array(y_data)

        self.xgb_model.fit(X[:, :7], y)  # Use first 7 features for base model

        # Update prediction accuracy
        predictions = self.xgb_model.predict(X[:, :7])
        self.prediction_accuracy = 1 - np.mean(np.abs(predictions - y))

    def get_stats(self) -> Dict:
        """Get optimizer performance statistics"""
        avg_reward = np.mean(list(self.reward_history)) if self.reward_history else 0.0

        return {
            "total_servers": len(self.servers),
            "active_users": len(self.connection_states),
            "q_table_size": len(self.q_table),
            "metrics_history_size": len(self.metrics_history),
            "avg_reward": round(avg_reward, 3),
            "prediction_accuracy": round(self.prediction_accuracy, 3),
            "exploration_rate": self.exploration_rate,
            "model_type": "MARL + XGBoost"
        }


# Global optimizer instance (singleton pattern for production use)
_optimizer_instance: Optional[VPNOptimizer] = None


def get_vpn_optimizer() -> VPNOptimizer:
    """Get or create global VPN optimizer instance"""
    global _optimizer_instance
    if _optimizer_instance is None:
        _optimizer_instance = VPNOptimizer()
        # Initialize with demo servers
        _initialize_demo_servers(_optimizer_instance)
    return _optimizer_instance


def load_servers_from_database(optimizer: VPNOptimizer, db):
    """Load VPN servers from database into optimizer"""
    from models.vpn_server import VPNServer

    servers = db.query(VPNServer).filter(
        VPNServer.status.in_(["active", "demo"])
    ).all()

    loaded_count = 0
    for server in servers:
        optimizer.add_server(
            server_id=server.server_id,
            location=server.location,
            initial_metrics={
                "latency_ms": server.latency_ms or 50.0,
                "bandwidth_mbps": server.bandwidth_in_mbps or 1000.0,
                "cpu_load": server.cpu_load or 0.3,
                "active_connections": server.current_connections or 0,
                "packet_loss": server.packet_loss or 0.0,
                "jitter_ms": server.jitter_ms or 2.0,
                "security_score": 0.95,  # Could be calculated from server config
            }
        )
        loaded_count += 1

    return loaded_count


def _initialize_demo_servers(optimizer: VPNOptimizer):
    """Initialize demo servers for testing (deprecated - use load_servers_from_database)"""
    demo_servers = [
        {"id": "us-east-1", "location": "New York", "latency": 25, "bandwidth": 1000},
        {"id": "us-west-1", "location": "San Francisco", "latency": 30, "bandwidth": 1000},
        {"id": "eu-west-1", "location": "London", "latency": 40, "bandwidth": 800},
        {"id": "eu-central-1", "location": "Frankfurt", "latency": 45, "bandwidth": 900},
        {"id": "ap-southeast-1", "location": "Singapore", "latency": 80, "bandwidth": 700},
        {"id": "ap-northeast-1", "location": "Tokyo", "latency": 85, "bandwidth": 750},
    ]

    for server in demo_servers:
        optimizer.add_server(
            server_id=server["id"],
            location=server["location"],
            initial_metrics={
                "latency_ms": server["latency"],
                "bandwidth_mbps": server["bandwidth"],
                "cpu_load": np.random.uniform(0.2, 0.6),
                "active_connections": np.random.randint(10, 50),
                "packet_loss": np.random.uniform(0, 0.01),
                "jitter_ms": np.random.uniform(1, 5),
                "security_score": np.random.uniform(0.9, 0.99),
            }
        )
