"""
SecureWave VPN Routing Optimizer (Optimized ML Version)
Multi-Agent Reinforcement Learning (MARL) + XGBoost for intelligent server selection
OPTIMIZED: Memory-efficient, lazy-loaded dependencies, production-ready

Key Optimizations:
- Lazy import of ML dependencies (app works without them)
- Efficient Q-table with LRU eviction
- Incremental XGBoost training
- Reduced memory footprint
- Model persistence for faster startup
"""
import time
from collections import deque, OrderedDict
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Any

# Lazy imports - only load if available
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

try:
    from sklearn.preprocessing import StandardScaler
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False

ML_AVAILABLE = NUMPY_AVAILABLE and XGBOOST_AVAILABLE and SKLEARN_AVAILABLE


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


class LRUCache(OrderedDict):
    """Memory-efficient LRU cache for Q-table"""
    def __init__(self, maxsize=10000):
        super().__init__()
        self.maxsize = maxsize

    def __setitem__(self, key, value):
        if key in self:
            self.move_to_end(key)
        super().__setitem__(key, value)
        if len(self) > self.maxsize:
            self.popitem(last=False)  # Remove oldest


class OptimizedVPNOptimizer:
    """
    Optimized VPN routing optimizer combining:
    - Multi-Agent Reinforcement Learning (MARL) for adaptive decision-making
    - XGBoost for predictive server performance modeling
    - Memory-efficient data structures
    - Optional ML dependencies (graceful degradation)
    """

    def __init__(self, model_path: Optional[str] = None, use_ml: bool = ML_AVAILABLE):
        self.servers: Dict[str, ServerMetrics] = {}
        self.connection_states: Dict[int, ConnectionState] = {}

        # Optimized: Limited history with circular buffer
        self.metrics_history = deque(maxlen=5000)  # Reduced from 10000

        # Optimized: LRU cache for Q-table (prevents unbounded growth)
        self.q_table = LRUCache(maxsize=10000)

        # MARL parameters (optimized)
        self.learning_rate = 0.01  # Increased for faster learning
        self.discount_factor = 0.9  # Slightly reduced for more immediate rewards
        self.exploration_rate = 0.05  # Reduced exploration (more exploitation)

        # Performance tracking
        self.reward_history = deque(maxlen=500)  # Reduced from 1000

        # ML initialization (lazy)
        self.use_ml = use_ml and ML_AVAILABLE
        self.xgb_model = None
        self.scaler = None

        if self.use_ml:
            self._initialize_ml_components(model_path)

    def _initialize_ml_components(self, model_path: Optional[str] = None):
        """Initialize ML components only if dependencies available"""
        if not ML_AVAILABLE:
            return

        try:
            self.scaler = StandardScaler()

            if model_path:
                try:
                    self.xgb_model = xgb.XGBRegressor()
                    self.xgb_model.load_model(model_path)
                    return
                except Exception:
                    pass

            # Optimized XGBoost parameters for production
            self.xgb_model = xgb.XGBRegressor(
                n_estimators=100,  # Reduced from 200
                max_depth=6,  # Reduced from 8
                learning_rate=0.1,  # Increased from 0.05
                subsample=0.8,
                colsample_bytree=0.8,
                objective='reg:squarederror',
                tree_method='hist',  # Fast histogram-based algorithm
                max_bin=128,  # Reduced bins for faster training
                n_jobs=1,  # Single thread for cloud deployment
                random_state=42
            )
        except Exception as e:
            self.use_ml = False

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

        # Store in history (automatic limit via deque)
        self.metrics_history.append({
            'server_id': server_id,
            'timestamp': server.timestamp,
            **metrics
        })

    def _extract_features_simple(self, server: ServerMetrics, user_state: ConnectionState) -> List[float]:
        """Extract features without numpy (fallback)"""
        time_of_day = (time.time() % 86400) / 86400
        return [
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
            1.0 if user_state.preferred_location == server.location else 0.0,
            time_of_day
        ]

    def _extract_features(self, server: ServerMetrics, user_state: ConnectionState) -> Any:
        """Extract feature vector for ML model (optimized)"""
        features = self._extract_features_simple(server, user_state)

        if self.use_ml and NUMPY_AVAILABLE:
            return np.array(features, dtype=np.float32).reshape(1, -1)
        return features

    def _calculate_reward(self, server: ServerMetrics, user_state: ConnectionState) -> float:
        """
        Calculate reward for MARL agent (optimized formula)
        """
        # Optimized: Pre-compute constants
        latency_reward = max(0.0, min(1.0, (200 - server.latency_ms) / 200))
        bandwidth_reward = min(1.0, server.bandwidth_mbps / 1000)
        load_reward = max(0.0, 1.0 - server.cpu_load)
        stability_reward = max(0.0, (1.0 - server.packet_loss) * (1.0 - min(1.0, server.jitter_ms / 100)))
        security_reward = server.security_score

        # Optimized: Fast path for common case
        if user_state.priority_level == 0:  # Free tier
            reward = (
                0.4 * latency_reward +
                0.2 * bandwidth_reward +
                0.2 * load_reward +
                0.2 * stability_reward
            )
        else:  # Premium tier
            reward = (
                0.25 * latency_reward +
                0.25 * bandwidth_reward +
                0.15 * load_reward +
                0.20 * stability_reward +
                0.15 * security_reward
            )

        # Location bonus (optimized check)
        if user_state.preferred_location and user_state.preferred_location in server.location:
            reward *= 1.1

        # Overload penalty
        if server.active_connections > 100:
            reward *= 0.8

        return reward

    def _select_server_marl(self, user_id: int) -> str:
        """
        Select optimal server using MARL (optimized)
        """
        if user_id not in self.connection_states:
            self.connection_states[user_id] = ConnectionState(
                user_id=user_id,
                current_server=None,
                avg_throughput=0.0,
                connection_stability=1.0,
                preferred_location=None,
                priority_level=0
            )

        user_state = self.connection_states[user_id]

        # Optimized: Random choice with list comprehension
        if self.use_ml and NUMPY_AVAILABLE:
            if np.random.random() < self.exploration_rate:
                return list(self.servers.keys())[int(np.random.random() * len(self.servers))]
        else:
            import random
            if random.random() < self.exploration_rate:
                return random.choice(list(self.servers.keys()))

        # Exploit: choose best server
        best_server = None
        best_value = float('-inf')

        for server_id, server in self.servers.items():
            # Simplified state representation for Q-table
            state_hash = (
                user_id % 1000,  # Reduce state space
                hash(server.location) % 100,
                int(server.cpu_load * 10)
            )

            # Get Q-value (LRU cache handles memory)
            q_value = self.q_table.get((state_hash, server_id), 0.0)

            # ML enhancement (if available)
            if self.use_ml and self.xgb_model and len(self.metrics_history) > 100:
                try:
                    features = self._extract_features(server, user_state)
                    predicted_performance = float(self.xgb_model.predict(features)[0])
                    combined_value = 0.7 * q_value + 0.3 * predicted_performance
                except Exception:
                    combined_value = q_value
            else:
                # Fallback: Use reward function directly
                combined_value = q_value + 0.3 * self._calculate_reward(server, user_state)

            if combined_value > best_value:
                best_value = combined_value
                best_server = server_id

        return best_server or list(self.servers.keys())[0]

    def update_q_table(self, user_id: int, server_id: str, reward: float):
        """Update Q-table (optimized with simplified state)"""
        if user_id not in self.connection_states or server_id not in self.servers:
            return

        server = self.servers[server_id]

        # Simplified state (reduces memory)
        state_hash = (
            user_id % 1000,
            hash(server.location) % 100,
            int(server.cpu_load * 10)
        )

        # Current Q-value
        current_q = self.q_table.get((state_hash, server_id), 0.0)

        # Max next Q-value
        max_next_q = max(
            (self.q_table.get((state_hash, sid), 0.0) for sid in self.servers.keys()),
            default=0.0
        )

        # Q-learning update (optimized)
        new_q = current_q + self.learning_rate * (
            reward + self.discount_factor * max_next_q - current_q
        )

        self.q_table[(state_hash, server_id)] = new_q
        self.reward_history.append(reward)

    def select_optimal_server(self, user_id: int, user_location: Optional[str] = None,
                             is_premium: bool = False) -> Dict:
        """
        Main entry point: Select optimal VPN server for user
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

        # Calculate confidence
        user_state = self.connection_states[user_id]
        reward = self._calculate_reward(server, user_state)
        confidence = min(1.0, reward * 1.2)

        return {
            "server_id": server.server_id,
            "location": server.location,
            "estimated_latency_ms": round(server.latency_ms, 2),
            "estimated_bandwidth_mbps": round(server.bandwidth_mbps, 2),
            "confidence_score": round(confidence, 3),
            "server_load": round(server.cpu_load, 2),
            "active_connections": server.active_connections,
            "security_score": round(server.security_score, 2),
            "optimization_method": "MARL+XGBoost" if self.use_ml else "MARL-only"
        }

    def report_connection_quality(self, user_id: int, server_id: str,
                                  actual_latency: float, actual_throughput: float):
        """Report actual connection quality (optimized incremental learning)"""
        if user_id not in self.connection_states or server_id not in self.servers:
            return

        server = self.servers[server_id]
        user_state = self.connection_states[user_id]

        # Update user state (exponential moving average)
        user_state.avg_throughput = 0.9 * user_state.avg_throughput + 0.1 * actual_throughput
        user_state.current_server = server_id

        # Calculate reward
        performance_score = min(1.0, actual_throughput / 100)
        latency_score = max(0.0, (200 - actual_latency) / 200)
        actual_reward = (performance_score + latency_score) / 2

        # Update Q-table
        self.update_q_table(user_id, server_id, actual_reward)

        # Incremental ML training (every 100 samples, not 50)
        if self.use_ml and len(self.metrics_history) > 100 and len(self.metrics_history) % 100 == 0:
            self._train_xgboost_incremental()

    def _train_xgboost_incremental(self):
        """Incremental XGBoost training (optimized)"""
        if not self.use_ml or len(self.metrics_history) < 100:
            return

        try:
            # Use only recent data (last 300 samples)
            recent_data = list(self.metrics_history)[-300:]

            X_data = []
            y_data = []

            for record in recent_data:
                features = [
                    record.get('latency_ms', 50),
                    record.get('bandwidth_mbps', 1000),
                    record.get('cpu_load', 0.5),
                    record.get('active_connections', 0),
                    record.get('packet_loss', 0),
                    record.get('jitter_ms', 2),
                    record.get('security_score', 0.95),
                ]

                # Normalized target
                latency_score = max(0.0, (200 - record.get('latency_ms', 50)) / 200)
                bandwidth_score = min(1.0, record.get('bandwidth_mbps', 1000) / 1000)
                target = (latency_score + bandwidth_score) / 2

                X_data.append(features)
                y_data.append(target)

            # Train with numpy if available
            if NUMPY_AVAILABLE:
                X = np.array(X_data, dtype=np.float32)
                y = np.array(y_data, dtype=np.float32)
                self.xgb_model.fit(X, y, verbose=False)
        except Exception:
            pass  # Fail silently, continue without ML

    def get_stats(self) -> Dict:
        """Get optimizer performance statistics"""
        avg_reward = 0.0
        if self.reward_history:
            if NUMPY_AVAILABLE:
                avg_reward = float(np.mean(list(self.reward_history)))
            else:
                avg_reward = sum(self.reward_history) / len(self.reward_history)

        return {
            "total_servers": len(self.servers),
            "active_users": len(self.connection_states),
            "q_table_size": len(self.q_table),
            "metrics_history_size": len(self.metrics_history),
            "avg_reward": round(avg_reward, 3),
            "ml_enabled": self.use_ml,
            "exploration_rate": self.exploration_rate,
            "model_type": "Optimized MARL + XGBoost" if self.use_ml else "Optimized MARL-only"
        }


# Global optimizer instance
_optimizer_instance: Optional[OptimizedVPNOptimizer] = None


def get_vpn_optimizer() -> OptimizedVPNOptimizer:
    """Get or create global VPN optimizer instance"""
    global _optimizer_instance
    if _optimizer_instance is None:
        _optimizer_instance = OptimizedVPNOptimizer()
        # Initialize with demo servers
        _initialize_demo_servers(_optimizer_instance)
    return _optimizer_instance


def load_servers_from_database(optimizer: OptimizedVPNOptimizer, db):
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
                "security_score": 0.95,
            }
        )
        loaded_count += 1

    return loaded_count


def _initialize_demo_servers(optimizer: OptimizedVPNOptimizer):
    """Initialize demo servers for testing"""
    import random

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
                "cpu_load": random.uniform(0.2, 0.6),
                "active_connections": random.randint(10, 50),
                "packet_loss": random.uniform(0, 0.01),
                "jitter_ms": random.uniform(1, 5),
                "security_score": random.uniform(0.9, 0.99),
            }
        )
