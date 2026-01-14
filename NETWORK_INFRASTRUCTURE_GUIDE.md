# Network Infrastructure Guide - SecureWave VPN

## Document Overview

This document provides comprehensive guidance for implementing SecureWave VPN's network infrastructure, including DDoS protection, load balancing, zero-log VPN architecture, and bandwidth management.

**Version**: 1.0
**Last Updated**: January 7, 2024
**Classification**: Technical Documentation

---

## Table of Contents

1. [DDoS Protection](#ddos-protection)
2. [Load Balancing & Traffic Routing](#load-balancing--traffic-routing)
3. [Zero-Log VPN Architecture](#zero-log-vpn-architecture)
4. [Bandwidth Management](#bandwidth-management)
5. [Network Security](#network-security)
6. [Monitoring & Alerts](#monitoring--alerts)

---

## DDoS Protection

### Overview

SecureWave VPN implements multi-layer DDoS protection using Azure DDoS Protection Standard and application-level rate limiting.

### Azure DDoS Protection Setup

#### Enable DDoS Protection Standard

```bash
# Create DDoS protection plan
az network ddos-protection create \
  --resource-group securewave-rg \
  --name securewave-ddos-plan \
  --location eastus

# Enable on Virtual Network
az network vnet update \
  --resource-group securewave-rg \
  --name securewave-vnet \
  --ddos-protection true \
  --ddos-protection-plan securewave-ddos-plan
```

#### DDoS Protection Features

**Layer 3/4 Protection**:
- SYN flood protection
- UDP flood protection
- ICMP flood protection
- Protocol attacks (TCP SYN-ACK, TCP RST)

**Automatic Mitigation**:
- Real-time traffic monitoring
- Adaptive tuning based on traffic patterns
- Automatic attack mitigation (no manual intervention)
- Attack metrics and diagnostics

**Protection Levels**:
```
Application Gateway: Protected
Load Balancer: Protected
Public IPs: Protected
VPN Servers: Protected via VNet
```

### Application-Level Protection

#### Rate Limiting (Already Implemented)

```python
# services/rate_limiter.py
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

# API endpoints
@app.get("/api/users")
@limiter.limit("100/minute")  # 100 requests per minute per IP
async def get_users():
    pass

# Authentication endpoints (stricter)
@app.post("/api/auth/login")
@limiter.limit("10/minute")  # Prevent brute force
async def login():
    pass
```

#### IP Reputation Filtering

```python
# services/ip_reputation.py
"""
IP Reputation Service - Block known malicious IPs
"""

import requests
from functools import lru_cache

BLOCKED_RANGES = [
    "10.0.0.0/8",      # Private
    "172.16.0.0/12",   # Private
    "192.168.0.0/16",  # Private
]

class IPReputationService:
    def is_ip_blocked(self, ip_address: str) -> bool:
        """Check if IP is in blocklist"""
        # Check against known bad IP databases
        # Integrate with services like AbuseIPDB, Project Honey Pot
        pass

    def check_rate_limit_violations(self, ip_address: str) -> bool:
        """Check if IP has violated rate limits"""
        from database.session import get_db
        from models.audit_log import AuditLog
        from datetime import datetime, timedelta

        db = next(get_db())

        # Count failed attempts in last hour
        one_hour_ago = datetime.utcnow() - timedelta(hours=1)
        violations = db.query(AuditLog).filter(
            AuditLog.ip_address == ip_address,
            AuditLog.event_type == "rate_limit_exceeded",
            AuditLog.created_at >= one_hour_ago
        ).count()

        return violations > 10  # Block if >10 violations in 1 hour
```

### WAF (Web Application Firewall)

#### Azure Application Gateway with WAF

```bash
# Create Application Gateway with WAF
az network application-gateway create \
  --resource-group securewave-rg \
  --name securewave-appgw \
  --location eastus \
  --sku WAF_v2 \
  --capacity 2 \
  --vnet-name securewave-vnet \
  --subnet appgw-subnet \
  --public-ip-address securewave-appgw-pip \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 443 \
  --http-settings-port 80 \
  --http-settings-protocol Http

# Configure WAF policy
az network application-gateway waf-policy create \
  --resource-group securewave-rg \
  --name securewave-waf-policy \
  --location eastus

# Enable OWASP ruleset
az network application-gateway waf-policy managed-rule rule-set add \
  --resource-group securewave-rg \
  --policy-name securewave-waf-policy \
  --type OWASP \
  --version 3.2
```

### DDoS Response Procedures

**Automated Response**:
1. Azure DDoS Protection detects attack
2. Automatic mitigation engaged within seconds
3. Traffic scrubbed at Microsoft edge
4. Legitimate traffic forwarded to application
5. Attack metrics logged

**Manual Response** (if needed):
1. Monitor Azure DDoS Protection metrics
2. Review attack vector and patterns
3. Adjust rate limits if necessary
4. Block specific IPs/ranges via NSG
5. Coordinate with Azure Support for large attacks

---

## Load Balancing & Traffic Routing

### Multi-Region Architecture

```
                    ┌─────────────────┐
                    │   Azure Front   │
                    │      Door       │ (Global Load Balancer)
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼────────┐ ┌──▼──────────┐ ┌▼─────────────┐
     │  East US Region │ │ West Europe │ │ Asia Pacific │
     │   (Primary)     │ │  (Secondary)│ │  (Tertiary)  │
     └────────┬────────┘ └──┬──────────┘ └┬─────────────┘
              │              │              │
         App Gateway    App Gateway    App Gateway
              │              │              │
         Load Balancer  Load Balancer  Load Balancer
              │              │              │
         Web Apps       Web Apps       Web Apps
         VPN Servers    VPN Servers    VPN Servers
```

### Azure Front Door Setup

```bash
# Create Front Door
az network front-door create \
  --resource-group securewave-rg \
  --name securewave-fd \
  --backend-address securewave-web.azurewebsites.net \
  --backend-address securewave-web.azurewebsites.net \
  --backend-address securewave-web.azurewebsites.net \
  --accepted-protocols Http Https \
  --forwarding-protocol HttpsOnly

# Configure backend pools
az network front-door backend-pool create \
  --resource-group securewave-rg \
  --front-door-name securewave-fd \
  --name WebAppBackend \
  --address securewave-web.azurewebsites.net \
  --address securewave-web.azurewebsites.net \
  --http-port 80 \
  --https-port 443

# Health probe configuration
az network front-door probe create \
  --resource-group securewave-rg \
  --front-door-name securewave-fd \
  --name HealthProbe \
  --path /api/health \
  --protocol Https \
  --interval 30
```

### Traffic Manager (DNS-Based Load Balancing)

```bash
# Create Traffic Manager profile
az network traffic-manager profile create \
  --resource-group securewave-rg \
  --name securewave-tm \
  --routing-method Performance \
  --unique-dns-name securewave-vpn \
  --ttl 30 \
  --protocol HTTPS \
  --port 443 \
  --path /api/health

# Add endpoints
az network traffic-manager endpoint create \
  --resource-group securewave-rg \
  --profile-name securewave-tm \
  --name eastus-endpoint \
  --type azureEndpoints \
  --target-resource-id "/subscriptions/{subscription-id}/resourceGroups/securewave-rg/providers/Microsoft.Web/sites/securewave-eastus" \
  --endpoint-status Enabled \
  --priority 1

az network traffic-manager endpoint create \
  --resource-group securewave-rg \
  --profile-name securewave-tm \
  --name westeu-endpoint \
  --type azureEndpoints \
  --target-resource-id "/subscriptions/{subscription-id}/resourceGroups/securewave-rg/providers/Microsoft.Web/sites/securewave-westeu" \
  --endpoint-status Enabled \
  --priority 2
```

### Routing Methods

**Performance Routing** (Default):
- Routes users to nearest region
- Based on DNS resolution latency
- Automatic failover to next-best region
- Best for global users

**Geographic Routing**:
- Route by user location
- Compliance requirements (GDPR, data residency)
- Regional content/pricing

**Priority Routing**:
- Primary/secondary failover
- Disaster recovery scenarios

**Weighted Routing**:
- Traffic distribution for A/B testing
- Gradual rollout of new versions

### VPN Server Load Balancing

```python
# services/vpn_load_balancer.py
"""
VPN Server Load Balancer - Intelligent server selection
"""

from typing import List, Optional
from models.vpn_server import VPNServer
from database.session import get_db

class VPNLoadBalancer:
    def select_optimal_server(
        self,
        user_id: int,
        preferred_region: Optional[str] = None
    ) -> Optional[VPNServer]:
        """
        Select optimal VPN server based on:
        - Server load
        - Geographic proximity
        - Server health
        - User preferences
        """
        db = next(get_db())

        # Get active servers
        query = db.query(VPNServer).filter(
            VPNServer.is_active == True,
            VPNServer.health_status == "healthy"
        )

        # Filter by region if specified
        if preferred_region:
            query = query.filter(VPNServer.region == preferred_region)

        servers = query.all()

        if not servers:
            return None

        # Calculate load scores
        server_scores = []
        for server in servers:
            score = self._calculate_server_score(server)
            server_scores.append((server, score))

        # Sort by score (lower is better)
        server_scores.sort(key=lambda x: x[1])

        # Return best server
        return server_scores[0][0]

    def _calculate_server_score(self, server: VPNServer) -> float:
        """Calculate server score (lower is better)"""
        score = 0.0

        # Load factor (0-100)
        score += server.current_load * 2

        # Active connections
        score += server.active_connections * 0.5

        # Latency (if available)
        if server.average_latency_ms:
            score += server.average_latency_ms * 0.1

        return score
```

---

## Zero-Log VPN Architecture

### Core Principle

**SecureWave VPN operates a strict no-log policy**: We do NOT log user IP addresses, browsing activity, connection timestamps, or any traffic data that could identify individual users.

### What We DON'T Log

❌ **User IP Addresses**: Never stored or logged
❌ **DNS Queries**: No DNS query logging
❌ **Browsing History**: No traffic inspection or logging
❌ **Connection Timestamps**: Only aggregate statistics, no per-user timestamps
❌ **Bandwidth Usage Per Session**: Only monthly aggregates for billing
❌ **Connection Duration**: Not tracked per session

### What We DO Log (Minimally)

✅ **Account Information**: Email, subscription status (for service provision)
✅ **Aggregate Statistics**: Total monthly bandwidth per user (billing only)
✅ **Technical Events**: Server health, errors (no user identification)
✅ **Payment Records**: Required by law (7 years retention)
✅ **Support Tickets**: Customer service interactions

### Implementation

#### 1. RAM-Only VPN Servers

```bash
# WireGuard configuration - No persistent logging
[Interface]
PrivateKey = SERVER_PRIVATE_KEY
Address = 10.8.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Disable logging
PostUp = echo 0 > /proc/sys/net/netfilter/nf_log/2
PostUp = echo 0 > /proc/sys/net/netfilter/nf_log/10

# NO SaveConfig - prevents writing connection data to disk
```

#### 2. Disable System Logging

```bash
# /etc/rsyslog.d/99-disable-vpn-logging.conf
# Disable logging for VPN-related services

:programname, isequal, "wg-quick" stop
:programname, isequal, "wireguard" stop

# Disable kernel connection tracking logs
:msg, contains, "TRACK:" stop
:msg, contains, "IPTables:" stop
```

#### 3. Disable Connection Tracking in Code

```python
# services/vpn_connection_service.py
"""
VPN Connection Service - ZERO LOG Implementation
"""

class VPNConnectionService:
    def record_connection(
        self,
        user_id: int,
        server_id: int
    ) -> None:
        """
        Record connection for active management ONLY
        NO IP addresses, NO timestamps stored
        Data deleted immediately upon disconnection
        """
        from database.session import get_db
        from models.vpn_connection import VPNConnection

        db = next(get_db())

        # Create temporary connection record (in-memory tracking)
        # Used ONLY for:
        # 1. Concurrent connection limiting
        # 2. Server capacity management
        # 3. Real-time status display

        connection = VPNConnection(
            user_id=user_id,
            server_id=server_id,
            # NO ip_address field
            # NO connected_at timestamp
            # NO traffic data
            is_active=True  # Only active status
        )

        db.add(connection)
        db.commit()

    def disconnect(self, connection_id: int) -> None:
        """
        Remove connection record immediately
        NO historical data retained
        """
        from database.session import get_db
        from models.vpn_connection import VPNConnection

        db = next(get_db())

        # DELETE immediately - no archival
        connection = db.query(VPNConnection).filter(
            VPNConnection.id == connection_id
        ).first()

        if connection:
            db.delete(connection)  # Permanent deletion
            db.commit()

    def get_monthly_bandwidth(self, user_id: int) -> int:
        """
        Get aggregate monthly bandwidth for billing
        NO session-level data, only monthly total
        """
        from database.session import get_db
        from models.usage_analytics import UserUsageStats

        db = next(get_db())

        stats = db.query(UserUsageStats).filter(
            UserUsageStats.user_id == user_id
        ).first()

        # Returns ONLY monthly aggregate
        return stats.current_month_data_gb if stats else 0
```

#### 4. Database Schema - Zero Log Compliant

```python
# models/vpn_connection.py
"""
VPN Connection Model - ZERO LOG Design
"""

class VPNConnection(Base):
    """
    Minimal connection tracking for active connections ONLY
    Deleted immediately upon disconnection
    """
    __tablename__ = "vpn_connections"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    server_id = Column(Integer, ForeignKey("vpn_servers.id"))

    # ONLY active status - no history
    is_active = Column(Boolean, default=True)

    # NO ip_address field
    # NO connected_at timestamp
    # NO disconnected_at timestamp
    # NO data_sent field
    # NO data_received field
    # NO session_duration field
```

#### 5. Bandwidth Aggregation (Billing Only)

```python
# services/bandwidth_aggregator.py
"""
Bandwidth Aggregation - Privacy-Preserving
"""

class BandwidthAggregator:
    def update_monthly_usage(
        self,
        user_id: int,
        data_delta_gb: float
    ) -> None:
        """
        Update ONLY monthly aggregate
        NO per-session tracking
        """
        from database.session import get_db
        from models.usage_analytics import UserUsageStats

        db = next(get_db())

        stats = db.query(UserUsageStats).filter(
            UserUsageStats.user_id == user_id
        ).first()

        if stats:
            # Increment monthly total ONLY
            stats.current_month_data_gb += data_delta_gb
            # NO timestamp of when data was used
            # NO server identification
            # NO session details
            db.commit()
```

### Zero-Log Verification

**Independent Audit**:
- Annual third-party security audit
- Verification of no-log claims
- Server configuration review
- Database schema audit

**User Verification**:
- Data export shows minimal information
- Transparency reports published quarterly
- Warrant canary maintained

---

## Bandwidth Management

### Traffic Shaping

#### Per-User Bandwidth Limits

```python
# services/bandwidth_manager.py
"""
Bandwidth Management Service
"""

class BandwidthManager:
    # Tier-based limits (Mbps)
    TIER_LIMITS = {
        "free": 10,      # 10 Mbps
        "basic": 50,     # 50 Mbps
        "premium": 100,  # 100 Mbps
        "unlimited": 0   # No limit
    }

    def get_user_bandwidth_limit(self, user_id: int) -> int:
        """Get user's bandwidth limit based on subscription"""
        from database.session import get_db
        from models.subscription import Subscription

        db = next(get_db())

        subscription = db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active"
        ).first()

        if not subscription:
            return self.TIER_LIMITS["free"]

        return self.TIER_LIMITS.get(subscription.plan, self.TIER_LIMITS["basic"])

    def check_monthly_quota(self, user_id: int) -> Dict:
        """Check if user has exceeded monthly quota"""
        from database.session import get_db
        from models.usage_analytics import UserUsageStats
        from models.subscription import Subscription

        db = next(get_db())

        stats = db.query(UserUsageStats).filter(
            UserUsageStats.user_id == user_id
        ).first()

        subscription = db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active"
        ).first()

        # Monthly quotas by tier
        quotas = {
            "free": 10,      # 10 GB
            "basic": 100,    # 100 GB
            "premium": 500,  # 500 GB
            "unlimited": -1  # Unlimited
        }

        quota = quotas.get(subscription.plan if subscription else "free", 10)
        used = stats.current_month_data_gb if stats else 0

        return {
            "quota_gb": quota,
            "used_gb": used,
            "remaining_gb": max(0, quota - used) if quota > 0 else -1,
            "is_exceeded": used >= quota if quota > 0 else False
        }
```

#### Server-Level Traffic Shaping

```bash
# WireGuard QoS configuration
# /etc/wireguard/wg0-qos.sh

#!/bin/bash

# Apply traffic shaping per client
# This limits bandwidth without logging individual usage

tc qdisc add dev wg0 root handle 1: htb default 10
tc class add dev wg0 parent 1: classid 1:1 htb rate 1gbit

# Per-peer limits applied via API calls
# No persistent configuration = no logs
```

### Congestion Management

```python
# services/congestion_manager.py
"""
Congestion Management - Prevent server overload
"""

class CongestionManager:
    def should_accept_connection(
        self,
        server_id: int
    ) -> Tuple[bool, Optional[str]]:
        """
        Determine if server can accept new connection
        Based on current load and capacity
        """
        from database.session import get_db
        from models.vpn_server import VPNServer

        db = next(get_db())

        server = db.query(VPNServer).filter(
            VPNServer.id == server_id
        ).first()

        if not server:
            return False, "Server not found"

        if not server.is_active:
            return False, "Server is inactive"

        # Check capacity
        max_connections = server.max_connections or 1000
        current = server.active_connections or 0

        if current >= max_connections:
            return False, "Server at capacity"

        # Check load
        if server.current_load and server.current_load > 90:
            return False, "Server overloaded"

        return True, None
```

---

## Network Security

### Firewall Rules (NSG)

```bash
# Create Network Security Group
az network nsg create \
  --resource-group securewave-rg \
  --name securewave-nsg

# Allow HTTPS (443)
az network nsg rule create \
  --resource-group securewave-rg \
  --nsg-name securewave-nsg \
  --name AllowHTTPS \
  --priority 100 \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-port-ranges 443 \
  --protocol Tcp \
  --access Allow

# Allow WireGuard (51820/UDP)
az network nsg rule create \
  --resource-group securewave-rg \
  --nsg-name securewave-nsg \
  --name AllowWireGuard \
  --priority 110 \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-port-ranges 51820 \
  --protocol Udp \
  --access Allow

# Deny all other inbound
az network nsg rule create \
  --resource-group securewave-rg \
  --nsg-name securewave-nsg \
  --name DenyAllInbound \
  --priority 4096 \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-port-ranges '*' \
  --protocol '*' \
  --access Deny
```

### DNS Security

```bash
# Use Azure Private DNS for internal resolution
az network private-dns zone create \
  --resource-group securewave-rg \
  --name securewave.internal

# Link to VNet
az network private-dns link vnet create \
  --resource-group securewave-rg \
  --zone-name securewave.internal \
  --name securewave-vnet-link \
  --virtual-network securewave-vnet \
  --registration-enabled false
```

---

## Monitoring & Alerts

### Network Monitoring

```bash
# Enable Network Watcher
az network watcher configure \
  --resource-group securewave-rg \
  --locations eastus westeurope \
  --enabled true

# Configure flow logs (aggregate only, no user data)
az network watcher flow-log create \
  --resource-group securewave-rg \
  --name securewave-flowlog \
  --nsg securewave-nsg \
  --storage-account securewave \
  --enabled true \
  --retention 7 \
  --format JSON \
  --traffic-analytics false  # Disabled for privacy
```

### DDoS Alerts

```bash
# Configure DDoS alert
az monitor metrics alert create \
  --resource-group securewave-rg \
  --name ddos-attack-alert \
  --resource securewave-vnet \
  --resource-type Microsoft.Network/virtualNetworks \
  --condition "avg UnderDDoSAttack > 0" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action email admin@securewave.com
```

### Performance Alerts

```bash
# High server load alert
az monitor metrics alert create \
  --resource-group securewave-rg \
  --name high-server-load \
  --resource securewave \
  --resource-type Microsoft.Web/sites \
  --condition "avg CpuPercentage > 80" \
  --window-size 15m \
  --evaluation-frequency 5m
```

---

## Summary

### Architecture Benefits

✅ **DDoS Protection**: Multi-layer defense (L3/L4 + L7)
✅ **Global Load Balancing**: Traffic Manager + Front Door
✅ **Zero-Log VPN**: True no-log implementation
✅ **Bandwidth Management**: Fair usage, tier-based limits
✅ **High Availability**: Multi-region with automatic failover
✅ **Security**: WAF, NSG, rate limiting, IP reputation

### Compliance

- **GDPR**: Minimal data collection, no user tracking
- **Privacy**: Zero-log architecture verified
- **Security**: Enterprise-grade DDoS protection
- **Transparency**: Quarterly reports, warrant canary

---

**Document Version**: 1.0
**Next Review**: April 7, 2024
**Maintained By**: Network Infrastructure Team
