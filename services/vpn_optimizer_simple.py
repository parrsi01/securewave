"""
SecureWave VPN Simple Optimizer
Lightweight server selection without ML dependencies
Optimizes for latency, load balancing, and location preference
"""
import random
import time
from collections import deque
from dataclasses import dataclass
from typing import Dict, List, Optional


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
    """User connection state"""
    user_id: int
    current_server: Optional[str]
    avg_throughput: float
    connection_stability: float
    preferred_location: Optional[str]
    priority_level: int  # 0=free, 1=premium


class SimpleVPNOptimizer:
    """
    Lightweight VPN routing optimizer using rule-based selection
    No ML dependencies required - perfect for cloud deployments
    """

    def __init__(self):
        self.servers: Dict[str, ServerMetrics] = {}
        self.connection_states: Dict[int, ConnectionState] = {}
        self.metrics_history = deque(maxlen=1000)

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

        # Store in history
        self.metrics_history.append({
            'server_id': server_id,
            'timestamp': server.timestamp,
            **metrics
        })

    def _calculate_score(self, server: ServerMetrics, user_state: ConnectionState) -> float:
        """
        Calculate server score using simple weighted formula
        """
        # Latency score (0-1, lower is better)
        latency_score = max(0, min(1, (200 - server.latency_ms) / 200))

        # Bandwidth score (0-1, higher is better)
        bandwidth_score = min(1, server.bandwidth_mbps / 1000)

        # Load score (0-1, lower load is better)
        load_score = max(0, 1 - server.cpu_load)

        # Stability score
        stability_score = max(0, (1 - server.packet_loss) * (1 - min(1, server.jitter_ms / 100)))

        # Security score (already 0-1)
        security_score = server.security_score

        # Weighted combination
        if user_state.priority_level == 0:  # Free tier
            # Free users: prioritize latency and basic stability
            score = (
                0.4 * latency_score +
                0.2 * bandwidth_score +
                0.2 * load_score +
                0.2 * stability_score
            )
        else:  # Premium tier
            # Premium users: balanced optimization with security
            score = (
                0.25 * latency_score +
                0.25 * bandwidth_score +
                0.15 * load_score +
                0.20 * stability_score +
                0.15 * security_score
            )

        # Bonus for location preference
        if user_state.preferred_location and user_state.preferred_location.lower() in server.location.lower():
            score *= 1.15

        # Penalty for overloaded servers
        if server.active_connections > 100:
            score *= 0.8

        return score

    def select_optimal_server(self, user_id: int, user_location: Optional[str] = None,
                             is_premium: bool = False) -> Dict:
        """
        Main entry point: Select optimal VPN server for user
        Returns server details and confidence score
        """
        if not self.servers:
            return {"error": "No servers available"}

        # Update or create user state
        if user_id not in self.connection_states:
            self.connection_states[user_id] = ConnectionState(
                user_id=user_id,
                current_server=None,
                avg_throughput=0.0,
                connection_stability=1.0,
                preferred_location=user_location,
                priority_level=1 if is_premium else 0
            )
        else:
            self.connection_states[user_id].priority_level = 1 if is_premium else 0
            if user_location:
                self.connection_states[user_id].preferred_location = user_location

        user_state = self.connection_states[user_id]

        # Score all servers
        best_server = None
        best_score = -1.0

        for server_id, server in self.servers.items():
            score = self._calculate_score(server, user_state)
            if score > best_score:
                best_score = score
                best_server = server

        if not best_server:
            # Fallback to first available server
            best_server = list(self.servers.values())[0]
            best_score = 0.5

        return {
            "server_id": best_server.server_id,
            "location": best_server.location,
            "estimated_latency_ms": round(best_server.latency_ms, 2),
            "estimated_bandwidth_mbps": round(best_server.bandwidth_mbps, 2),
            "confidence_score": round(min(1.0, best_score), 3),
            "server_load": round(best_server.cpu_load, 2),
            "active_connections": best_server.active_connections,
            "security_score": round(best_server.security_score, 2),
            "optimization_method": "Rule-based"
        }

    def report_connection_quality(self, user_id: int, server_id: str,
                                  actual_latency: float, actual_throughput: float):
        """
        Report actual connection quality for tracking
        """
        if user_id not in self.connection_states or server_id not in self.servers:
            return

        user_state = self.connection_states[user_id]

        # Update user state with exponential moving average
        user_state.avg_throughput = 0.9 * user_state.avg_throughput + 0.1 * actual_throughput
        user_state.current_server = server_id

    def get_stats(self) -> Dict:
        """Get optimizer performance statistics"""
        return {
            "total_servers": len(self.servers),
            "active_users": len(self.connection_states),
            "metrics_history_size": len(self.metrics_history),
            "model_type": "Simple Rule-based"
        }


# Global optimizer instance (singleton pattern)
_optimizer_instance: Optional[SimpleVPNOptimizer] = None


def get_vpn_optimizer() -> SimpleVPNOptimizer:
    """Get or create global VPN optimizer instance"""
    global _optimizer_instance
    if _optimizer_instance is None:
        _optimizer_instance = SimpleVPNOptimizer()
        # Initialize with demo servers
        _initialize_demo_servers(_optimizer_instance)
    return _optimizer_instance


def load_servers_from_database(optimizer: SimpleVPNOptimizer, db):
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


def _initialize_demo_servers(optimizer: SimpleVPNOptimizer):
    """Initialize demo servers for testing"""
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
