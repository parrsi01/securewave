from datetime import datetime

from sqlalchemy import Column, Integer, String, Float, DateTime, Boolean, JSON
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class VPNServer(Base):
    """VPN server model for tracking server fleet and metrics"""
    __tablename__ = "vpn_servers"

    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(String, unique=True, nullable=False, index=True)  # us-east-1-001, eu-west-1-002, etc.
    location = Column(String, nullable=False)  # New York, London, etc.
    country = Column(String, nullable=False)  # United States, United Kingdom, etc.
    country_code = Column(String(2), nullable=False)  # US, GB, JP, etc.
    city = Column(String, nullable=False)  # New York, London, Tokyo, etc.
    region = Column(String, nullable=True)  # Americas, Europe, Asia
    latitude = Column(Float, nullable=True)  # For map display
    longitude = Column(Float, nullable=True)  # For map display

    # Azure Infrastructure Details
    azure_resource_group = Column(String, nullable=True)  # Azure resource group name
    azure_vm_name = Column(String, nullable=True)  # Azure VM name
    azure_region = Column(String, nullable=False)  # eastus, westeurope, japaneast, etc.
    azure_vm_size = Column(String, default="Standard_B2s")  # VM size/tier
    azure_vm_state = Column(String, nullable=True)  # running, stopped, deallocated, etc.

    # Network Configuration
    public_ip = Column(String, nullable=False)
    private_ip = Column(String, nullable=True)
    endpoint = Column(String, nullable=False)  # IP:port for WireGuard
    wg_listen_port = Column(Integer, default=51820)
    wg_public_key = Column(String, nullable=False)  # Server's WireGuard public key
    wg_private_key_encrypted = Column(String, nullable=False)  # Encrypted private key
    dns_servers = Column(String, default="1.1.1.1,1.0.0.1")  # Cloudflare DNS

    # Capacity and limits
    max_connections = Column(Integer, default=1000)
    tier_restriction = Column(String, nullable=True)  # NULL=all users, 'premium'=premium only
    priority = Column(Integer, default=100)  # Higher = preferred for load balancing

    # Status
    status = Column(String, default="provisioning")  # provisioning, active, maintenance, offline, decommissioned
    health_status = Column(String, default="unknown")  # healthy, degraded, unhealthy, unreachable
    last_health_check = Column(DateTime, nullable=True)
    consecutive_health_failures = Column(Integer, default=0)

    # Auto-scaling metadata
    auto_scale_enabled = Column(Boolean, default=True)
    auto_scale_min_connections = Column(Integer, default=50)  # Scale down threshold
    auto_scale_max_connections = Column(Integer, default=900)  # Scale up threshold
    is_auto_scaled = Column(Boolean, default=False)  # Was this server auto-created?

    # Real-time metrics (updated by monitoring service)
    current_connections = Column(Integer, default=0)
    cpu_load = Column(Float, default=0.0)  # 0.0 to 1.0
    memory_usage = Column(Float, default=0.0)  # 0.0 to 1.0
    disk_usage = Column(Float, default=0.0)  # 0.0 to 1.0
    bandwidth_in_mbps = Column(Float, default=0.0)
    bandwidth_out_mbps = Column(Float, default=0.0)
    total_bandwidth_gb = Column(Float, default=0.0)  # Total bandwidth used (billing)
    latency_ms = Column(Float, default=0.0)
    packet_loss = Column(Float, default=0.0)  # 0.0 to 1.0
    jitter_ms = Column(Float, default=0.0)
    uptime_percentage = Column(Float, default=100.0)  # 99.9%, 100.0%, etc.

    # Failover and redundancy
    failover_server_id = Column(String, nullable=True)  # Backup server if this fails
    is_failover_active = Column(Boolean, default=False)  # Is this currently acting as failover?
    last_failover_at = Column(DateTime, nullable=True)

    # Performance scoring (for intelligent selection)
    performance_score = Column(Float, default=100.0)  # 0-100, calculated from all metrics
    user_rating = Column(Float, default=5.0)  # 1-5 stars from user feedback
    total_user_ratings = Column(Integer, default=0)

    # Metadata
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)
    last_reboot_at = Column(DateTime, nullable=True)
    provisioned_at = Column(DateTime, nullable=True)  # When VM was fully provisioned
    decommissioned_at = Column(DateTime, nullable=True)

    # Relationships
    connections = relationship("VPNConnection", back_populates="server")

    def __repr__(self):
        return f"<VPNServer(id='{self.server_id}', location='{self.location}', country='{self.country}', status='{self.status}')>"

    @property
    def is_available(self) -> bool:
        """Check if server is available for new connections"""
        return (
            self.status == "active" and
            self.health_status in ["healthy", "degraded"] and
            self.current_connections < self.max_connections and
            self.azure_vm_state == "running"
        )

    @property
    def capacity_percentage(self) -> float:
        """Get current capacity usage as percentage"""
        if self.max_connections == 0:
            return 0.0
        return (self.current_connections / self.max_connections) * 100.0

    @property
    def needs_scaling(self) -> bool:
        """Check if this server needs auto-scaling assistance"""
        if not self.auto_scale_enabled:
            return False
        return self.current_connections > self.auto_scale_max_connections

    @property
    def can_scale_down(self) -> bool:
        """Check if this server can be scaled down/removed"""
        if not self.auto_scale_enabled or not self.is_auto_scaled:
            return False
        return self.current_connections < self.auto_scale_min_connections

    def to_dict(self, include_sensitive=False):
        """Convert server to dictionary for API responses"""
        data = {
            "server_id": self.server_id,
            "location": self.location,
            "country": self.country,
            "country_code": self.country_code,
            "city": self.city,
            "region": self.region,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "endpoint": self.endpoint,
            "status": self.status,
            "health_status": self.health_status,
            "current_connections": self.current_connections,
            "max_connections": self.max_connections,
            "capacity_percentage": self.capacity_percentage,
            "cpu_load": round(self.cpu_load * 100, 1),
            "memory_usage": round(self.memory_usage * 100, 1),
            "latency_ms": round(self.latency_ms, 1),
            "packet_loss": round(self.packet_loss * 100, 2),
            "performance_score": round(self.performance_score, 1),
            "user_rating": round(self.user_rating, 1),
            "uptime_percentage": round(self.uptime_percentage, 2),
            "tier_restriction": self.tier_restriction,
            "last_health_check": self.last_health_check.isoformat() if self.last_health_check else None,
        }

        if include_sensitive:
            data.update({
                "public_ip": self.public_ip,
                "private_ip": self.private_ip,
                "wg_public_key": self.wg_public_key,
                "azure_vm_name": self.azure_vm_name,
                "azure_region": self.azure_region,
                "azure_vm_state": self.azure_vm_state,
            })

        return data

    def to_admin_dict(self):
        """Full details for admin dashboard"""
        return {
            **self.to_dict(include_sensitive=True),
            "wg_listen_port": self.wg_listen_port,
            "dns_servers": self.dns_servers,
            "azure_resource_group": self.azure_resource_group,
            "azure_vm_size": self.azure_vm_size,
            "priority": self.priority,
            "auto_scale_enabled": self.auto_scale_enabled,
            "is_auto_scaled": self.is_auto_scaled,
            "consecutive_health_failures": self.consecutive_health_failures,
            "failover_server_id": self.failover_server_id,
            "is_failover_active": self.is_failover_active,
            "bandwidth_in_mbps": round(self.bandwidth_in_mbps, 2),
            "bandwidth_out_mbps": round(self.bandwidth_out_mbps, 2),
            "total_bandwidth_gb": round(self.total_bandwidth_gb, 2),
            "disk_usage": round(self.disk_usage * 100, 1),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "provisioned_at": self.provisioned_at.isoformat() if self.provisioned_at else None,
            "last_reboot_at": self.last_reboot_at.isoformat() if self.last_reboot_at else None,
        }
