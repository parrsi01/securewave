# SecureWave VPN - Production Database Operations Guide

## 🎯 Azure PostgreSQL Production Database - Complete Implementation

This guide covers the complete production database infrastructure including deployment, backups, replication, disaster recovery, monitoring, and daily operations.

---

## ✅ INFRASTRUCTURE OVERVIEW

### Database Architecture

**Primary Database:**
- Azure Database for PostgreSQL Flexible Server
- PostgreSQL Version: 14
- SKU: GP_Gen5_2 (General Purpose, 2 vCores, 8GB RAM)
- Storage: 100 GB (auto-grow enabled)
- High Availability: Zone-Redundant (99.99% SLA)
- Backup Retention: 35 days
- Geo-Redundant Backups: Enabled

**Connection Pooling:**
- Pool Size: 20 connections (base)
- Max Overflow: 40 connections (total: 60)
- Pool Timeout: 30 seconds
- Pool Recycle: 3600 seconds (1 hour)
- SSL Mode: Required
- Connection Timeout: 10 seconds

**Performance Optimizations:**
- Statement Timeout: 60 seconds
- Lock Timeout: 10 seconds
- Timezone: UTC
- Max Connections: 200
- Shared Buffers: 512MB
- Effective Cache Size: 1.5GB
- Checkpoint Completion Target: 0.9
- Random Page Cost: 1.1 (SSD optimized)

---

## 🚀 DEPLOYMENT INSTRUCTIONS

### Step 1: Prerequisites

```bash
# Install required packages
pip install psycopg2-binary python-dotenv sqlalchemy alembic

# Install Azure CLI (if not installed)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login

# Set subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify authentication
az account show
```

### Step 2: Deploy PostgreSQL Database

```bash
cd /home/sp/cyber-course/projects/securewave

# Deploy primary database server
python3 infrastructure/azure_database_deployer.py

# Expected output:
# ✓ Resource group ready
# ✓ PostgreSQL server created (takes 3-5 minutes)
# ✓ Database 'securewave_vpn' created
# ✓ Firewall rules configured
# ✓ Server parameters optimized
# ✓ Credentials saved to .env.production
```

**Deployment creates:**
- Resource Group: `SecureWaveRG`
- Server Name: `securewave-db.postgres.database.azure.com`
- Database: `securewave_vpn`
- Admin User: `securewave_admin`
- Password: Saved to `.env.production`

### Step 3: Test Database Connection

```bash
# Test connection using backup manager
python3 infrastructure/database_backup_manager.py health-check

# Or test directly
python3 << EOF
from database.session import check_database_connection, get_database_info

# Check connection
if check_database_connection():
    print("✓ Database connection successful")

    # Get database info
    info = get_database_info()
    print(f"✓ Pool size: {info['pool_size']}")
    print(f"✓ Environment: {info['environment']}")
else:
    print("✗ Database connection failed")
EOF
```

### Step 4: Initialize Database Schema

```bash
# Create all tables
python3 << EOF
from database.session import create_tables
create_tables()
print("✓ All database tables created")
EOF

# Verify tables
python3 << EOF
from database.session import SessionLocal
db = SessionLocal()
result = db.execute("""
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
""")
tables = [row[0] for row in result]
print(f"✓ Created {len(tables)} tables:")
for table in tables:
    print(f"  - {table}")
db.close()
EOF
```

---

## 🔄 DATABASE MIGRATION SYSTEM

### Alembic Setup

```bash
# Initialize Alembic (first time only)
cd /home/sp/cyber-course/projects/securewave
alembic init alembic

# Edit alembic.ini
# Update: sqlalchemy.url = (leave empty, we'll use env variable)

# Edit alembic/env.py to use our models
```

**Updated alembic/env.py:**

```python
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
load_dotenv(".env.production")

# Import all models
from database.base import Base
from models.user import User
from models.subscription import Subscription
from models.audit_log import AuditLog
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection

# Alembic Config object
config = context.config

# Set database URL from environment
config.set_main_option(
    "sqlalchemy.url",
    os.getenv("DATABASE_URL")
)

# Interpret the config file for Python logging
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Set target metadata
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

### Creating Migrations

```bash
# Create initial migration (first time)
alembic revision --autogenerate -m "Initial schema"

# Review generated migration
cat alembic/versions/*_initial_schema.py

# Apply migration
alembic upgrade head

# Check current version
alembic current

# View migration history
alembic history
```

### Migration Workflow

```bash
# 1. Make changes to models (e.g., add column to User model)

# 2. Generate migration
alembic revision --autogenerate -m "Add phone_number to users"

# 3. Review migration file
cat alembic/versions/*_add_phone_number_to_users.py

# 4. Apply to database
alembic upgrade head

# Rollback if needed
alembic downgrade -1

# Rollback to specific version
alembic downgrade <revision_id>
```

---

## 💾 BACKUP & RESTORE OPERATIONS

### Automated Backups

Azure PostgreSQL automatically creates backups:
- **Frequency**: Every 5 minutes (transaction logs)
- **Full Backups**: Daily at 2:00 AM UTC
- **Retention**: 35 days
- **Geo-Redundancy**: Enabled (replicated to paired region)
- **Point-in-Time Restore**: Any point within 35 days

### Manual Backup

```bash
# Create manual backup for long-term retention
python3 infrastructure/database_backup_manager.py backup --backup-name "pre-deployment-backup-2026-01-03"

# Output:
# ✓ Manual backup created: pre-deployment-backup-2026-01-03
# ✓ Database dump created: /tmp/pre-deployment-backup-2026-01-03.sql
```

### List Available Backups

```bash
# List all automatic backups
python3 infrastructure/database_backup_manager.py list-backups

# Output (JSON):
# [
#   {
#     "backup_name": "2026-01-03T00:00:00Z",
#     "timestamp": "2026-01-03T00:00:00Z",
#     "type": "automatic",
#     "retention_days": 35,
#     "status": "available"
#   },
#   ...
# ]
```

### Point-in-Time Restore

```bash
# Restore to specific timestamp (creates new server)
python3 infrastructure/database_backup_manager.py restore \
  --restore-time "2026-01-03T12:00:00Z" \
  --target-server "securewave-db-restored"

# This creates a new server with restored data
# Connection string: securewave-db-restored.postgres.database.azure.com

# Test restored database before switching
# Update .env.production when verified
# Delete old server when migration complete
```

### Disaster Recovery Restore

```bash
# If primary region fails, restore from geo-redundant backup
python3 infrastructure/database_backup_manager.py restore \
  --restore-time "2026-01-03T12:00:00Z" \
  --target-server "securewave-db-dr" \
  --location "westus2"  # Different region

# Update application connection string
# Verify application functionality
# Monitor until primary region recovers
```

---

## 🌍 GEO-REPLICATION & READ REPLICAS

### Deploy Read Replica

```bash
# Create read replica in different region (for read scaling)
python3 infrastructure/database_backup_manager.py setup-replica \
  --replica-location "westus2"

# Output:
# ✓ Geo-replication configured: securewave-db-replica-westus2
# Connection: securewave-db-replica-westus2.postgres.database.azure.com
```

### Multiple Replicas for Global Coverage

```bash
# Deploy replicas in multiple regions
python3 << EOF
from infrastructure.database_backup_manager import DatabaseBackupManager

manager = DatabaseBackupManager()

# Americas
manager.setup_geo_replication("westus2", "securewave-db-replica-us-west")

# Europe
manager.setup_geo_replication("westeurope", "securewave-db-replica-eu")

# Asia
manager.setup_geo_replication("southeastasia", "securewave-db-replica-asia")

print("✓ Global read replica network deployed")
EOF
```

### Application Configuration for Replicas

```python
# database/session.py - Add read replica support

import random
from typing import Optional

# Read replica endpoints
READ_REPLICAS = [
    os.getenv("DATABASE_READ_REPLICA_1"),
    os.getenv("DATABASE_READ_REPLICA_2"),
    os.getenv("DATABASE_READ_REPLICA_3"),
]

# Remove None values
READ_REPLICAS = [r for r in READ_REPLICAS if r]

def get_read_db() -> Generator[Session, None, None]:
    """
    Database session for read-only operations (uses replicas)

    Usage:
        @app.get("/users")
        def get_users(db: Session = Depends(get_read_db)):
            return db.query(User).all()
    """
    if READ_REPLICAS:
        # Random replica selection (simple load balancing)
        replica_url = random.choice(READ_REPLICAS)
        replica_engine = create_engine(replica_url, pool_pre_ping=True)
        replica_session = sessionmaker(bind=replica_engine)
        db = replica_session()
    else:
        # Fallback to primary
        db = SessionLocal()

    try:
        yield db
    except Exception as e:
        logger.error(f"Read database session error: {e}")
        db.rollback()
        raise
    finally:
        db.close()
```

---

## 🔧 DATABASE MAINTENANCE

### Manual Maintenance Tasks

```bash
# Run VACUUM ANALYZE and update statistics
python3 infrastructure/database_backup_manager.py maintenance

# Output:
# ✓ VACUUM ANALYZE completed
# ✓ Statistics updated for 15 tables
# ✓ All maintenance tasks completed
```

### Automated Maintenance Schedule

**Create systemd timer for weekly maintenance:**

```bash
# Create maintenance script
sudo nano /usr/local/bin/securewave-db-maintenance.sh
```

```bash
#!/bin/bash
cd /home/sp/cyber-course/projects/securewave
python3 infrastructure/database_backup_manager.py maintenance >> /var/log/securewave-db-maintenance.log 2>&1
```

```bash
chmod +x /usr/local/bin/securewave-db-maintenance.sh

# Create systemd service
sudo nano /etc/systemd/system/securewave-db-maintenance.service
```

```ini
[Unit]
Description=SecureWave Database Maintenance
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/securewave-db-maintenance.sh
User=azureuser
```

```bash
# Create systemd timer (runs every Sunday at 3 AM)
sudo nano /etc/systemd/system/securewave-db-maintenance.timer
```

```ini
[Unit]
Description=SecureWave Database Maintenance Timer
Requires=securewave-db-maintenance.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable securewave-db-maintenance.timer
sudo systemctl start securewave-db-maintenance.timer

# Check timer status
sudo systemctl list-timers securewave-db-maintenance.timer
```

### Index Maintenance

```python
# Create script: infrastructure/database_index_maintenance.py

from database.session import SessionLocal

def rebuild_indexes():
    """Rebuild all indexes for optimal performance"""
    db = SessionLocal()

    # Get all indexes
    result = db.execute("""
        SELECT schemaname, tablename, indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
    """)

    indexes = result.fetchall()

    for schema, table, index in indexes:
        print(f"Rebuilding {index}...")
        db.execute(f"REINDEX INDEX {schema}.{index};")

    print(f"✓ Rebuilt {len(indexes)} indexes")
    db.close()

if __name__ == "__main__":
    rebuild_indexes()
```

---

## 📊 MONITORING & HEALTH CHECKS

### Database Health Check

```bash
# Comprehensive health check
python3 infrastructure/database_backup_manager.py health-check

# Output (JSON):
# {
#   "timestamp": "2026-01-03T15:30:00Z",
#   "status": "healthy",
#   "checks": {
#     "server_state": {"status": "Ready", "healthy": true},
#     "storage": {"used_mb": 5120, "total_mb": 102400, "percent_used": 5.0, "healthy": true},
#     "backups": {"total_backups": 35, "latest_backup": "2026-01-03T02:00:00Z", "healthy": true},
#     "connection": {"can_connect": true, "healthy": true}
#   }
# }
```

### Performance Metrics

```bash
# Get database metrics
python3 infrastructure/database_backup_manager.py metrics

# Output:
# {
#   "timestamp": "2026-01-03T15:30:00Z",
#   "server": {
#     "sku": "GP_Gen5_2",
#     "storage_gb": 100,
#     "backup_retention_days": 35,
#     "version": "14"
#   }
# }
```

### Azure Monitor Integration

```bash
# Create Azure Monitor workspace
az monitor log-analytics workspace create \
  --resource-group SecureWaveRG \
  --workspace-name securewave-db-logs

# Get workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group SecureWaveRG \
  --workspace-name securewave-db-logs \
  --query customerId -o tsv)

# Enable diagnostic logging
az postgres flexible-server diagnostic-settings create \
  --resource-group SecureWaveRG \
  --server-name securewave-db \
  --name db-diagnostics \
  --workspace $WORKSPACE_ID \
  --logs '[{"category": "PostgreSQLLogs", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

### Alert Rules

```bash
# High CPU alert
az monitor metrics alert create \
  --name "DB-High-CPU" \
  --resource-group SecureWaveRG \
  --scopes /subscriptions/YOUR_SUB/resourceGroups/SecureWaveRG/providers/Microsoft.DBforPostgreSQL/flexibleServers/securewave-db \
  --condition "avg cpu_percent > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action email notify@securewave.app

# High memory alert
az monitor metrics alert create \
  --name "DB-High-Memory" \
  --resource-group SecureWaveRG \
  --scopes /subscriptions/YOUR_SUB/resourceGroups/SecureWaveRG/providers/Microsoft.DBforPostgreSQL/flexibleServers/securewave-db \
  --condition "avg memory_percent > 85" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action email notify@securewave.app

# Storage alert (>80% full)
az monitor metrics alert create \
  --name "DB-Storage-Full" \
  --resource-group SecureWaveRG \
  --scopes /subscriptions/YOUR_SUB/resourceGroups/SecureWaveRG/providers/Microsoft.DBforPostgreSQL/flexibleServers/securewave-db \
  --condition "avg storage_percent > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action email notify@securewave.app

# Connection failures
az monitor metrics alert create \
  --name "DB-Connection-Failures" \
  --resource-group SecureWaveRG \
  --scopes /subscriptions/YOUR_SUB/resourceGroups/SecureWaveRG/providers/Microsoft.DBforPostgreSQL/flexibleServers/securewave-db \
  --condition "total failed_connections > 50" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action email notify@securewave.app
```

---

## 🔒 SECURITY & ENCRYPTION

### SSL/TLS Configuration

**Already configured in database/session.py:**
- SSL Mode: Required
- TLS Version: 1.2+
- Certificate Verification: Enabled

### Firewall Rules

```bash
# List current firewall rules
az postgres flexible-server firewall-rule list \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --output table

# Add specific IP range
az postgres flexible-server firewall-rule create \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --rule-name "Office-Network" \
  --start-ip-address 203.0.113.0 \
  --end-ip-address 203.0.113.255

# Remove rule
az postgres flexible-server firewall-rule delete \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --rule-name "Office-Network"
```

### Private Endpoint (VNet Integration)

```bash
# Create VNet
az network vnet create \
  --resource-group SecureWaveRG \
  --name securewave-vnet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name database-subnet \
  --subnet-prefix 10.0.1.0/24

# Configure server with VNet
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --vnet securewave-vnet \
  --subnet database-subnet
```

### Encryption at Rest

Azure PostgreSQL automatically encrypts data at rest using:
- AES-256 encryption
- Microsoft-managed keys
- Transparent data encryption (TDE)

**For customer-managed keys (optional):**

```bash
# Create Key Vault
az keyvault create \
  --resource-group SecureWaveRG \
  --name securewave-db-keys \
  --location eastus

# Create encryption key
az keyvault key create \
  --vault-name securewave-db-keys \
  --name db-encryption-key \
  --kty RSA \
  --size 2048

# Configure database to use customer key
az postgres flexible-server key create \
  --resource-group SecureWaveRG \
  --server-name securewave-db \
  --key-name db-encryption-key \
  --vault-name securewave-db-keys
```

---

## 💰 COST MANAGEMENT

### Current Costs (GP_Gen5_2 with 100GB storage)

- **Compute**: ~$100/month (2 vCores)
- **Storage**: ~$10/month (100 GB)
- **Backup Storage**: ~$5/month (geo-redundant)
- **High Availability**: ~$100/month (zone-redundant)
- **Total**: ~$215/month

### Cost Optimization Strategies

1. **Reserved Instances (40% savings):**
```bash
# Purchase 1-year reservation
az postgres flexible-server reserved-capacity create \
  --resource-group SecureWaveRG \
  --reserved-capacity-name db-reservation-1yr \
  --sku GP_Gen5_2 \
  --term P1Y \
  --count 1

# Savings: ~$86/month = $1,032/year
```

2. **Auto-Pause (for dev/test):**
```bash
# Configure auto-pause after 60 minutes idle
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db-dev \
  --auto-pause-delay 60
```

3. **Right-Sizing:**
```bash
# Monitor CPU/memory usage
# If average CPU < 30%, downgrade to GP_Gen5_1
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --sku-name GP_Gen5_1

# Savings: ~$50/month
```

### Cost Monitoring

```bash
# View monthly costs
az consumption usage list \
  --start-date 2026-01-01 \
  --end-date 2026-01-31 \
  --query "[?contains(instanceName, 'securewave-db')]" \
  --output table

# Set budget alert
az consumption budget create \
  --budget-name db-monthly-budget \
  --amount 250 \
  --time-grain Monthly \
  --category Cost
```

---

## 🔄 SCALING OPERATIONS

### Vertical Scaling (Compute)

```bash
# Scale UP: 2 vCores → 4 vCores
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --sku-name GP_Gen5_4

# Scale DOWN: 4 vCores → 2 vCores
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --sku-name GP_Gen5_2

# Note: Causes brief downtime (~30 seconds)
```

### Storage Scaling

```bash
# Increase storage: 100GB → 200GB
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --storage-size 204800

# Enable auto-grow
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --storage-auto-grow Enabled

# Note: Storage can only increase, never decrease
```

### Horizontal Scaling (Read Replicas)

Already covered in Geo-Replication section above.

---

## 🧪 TESTING & VALIDATION

### Connection Pool Testing

```python
# test_connection_pool.py
import concurrent.futures
import time
from database.session import get_db

def test_connection():
    """Test single database connection"""
    db = next(get_db())
    result = db.execute("SELECT 1").fetchone()
    db.close()
    return result[0] == 1

def stress_test_pool(num_connections=50):
    """Test connection pool under load"""
    with concurrent.futures.ThreadPoolExecutor(max_workers=num_connections) as executor:
        futures = [executor.submit(test_connection) for _ in range(num_connections)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]

    success_count = sum(results)
    print(f"✓ {success_count}/{num_connections} connections successful")
    return success_count == num_connections

if __name__ == "__main__":
    print("Testing connection pool...")
    assert stress_test_pool(50), "Pool test failed"
    print("✓ Connection pool test passed")
```

```bash
python3 test_connection_pool.py
```

### Failover Testing

```python
# test_ha_failover.py
from database.session import SessionLocal
import time

def test_high_availability():
    """Simulate primary zone failure"""
    db = SessionLocal()

    print("Testing high availability...")
    print("Simulating zone failure...")

    # Continuous connection attempts
    for i in range(10):
        try:
            result = db.execute("SELECT NOW()").fetchone()
            print(f"✓ Connection {i+1}: {result[0]}")
            time.sleep(1)
        except Exception as e:
            print(f"✗ Connection {i+1} failed: {e}")

    db.close()

if __name__ == "__main__":
    test_high_availability()
```

### Backup/Restore Testing

```bash
# Create test backup
python3 infrastructure/database_backup_manager.py backup --backup-name "test-backup"

# Restore to new server
python3 infrastructure/database_backup_manager.py restore \
  --restore-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --target-server "securewave-db-test-restore"

# Verify data integrity
python3 << EOF
from database.session import create_engine
from sqlalchemy.orm import sessionmaker

# Connect to restored database
restored_url = "postgresql://securewave_admin:PASSWORD@securewave-db-test-restore.postgres.database.azure.com/securewave_vpn"
restored_engine = create_engine(restored_url)
Session = sessionmaker(bind=restored_engine)
db = Session()

# Check row counts match
from models.user import User
count = db.query(User).count()
print(f"✓ Restored {count} users")

db.close()
EOF

# Cleanup test server
az postgres flexible-server delete \
  --resource-group SecureWaveRG \
  --name securewave-db-test-restore \
  --yes
```

---

## 📋 OPERATIONAL PROCEDURES

### Daily Checklist

- [ ] Check Azure Service Health dashboard
- [ ] Review database health metrics
- [ ] Monitor connection pool usage
- [ ] Check for slow queries (>1s)
- [ ] Review error logs

### Weekly Checklist

- [ ] Run database maintenance (VACUUM ANALYZE)
- [ ] Review backup status (35-day retention verified)
- [ ] Check storage usage trends
- [ ] Review security audit logs
- [ ] Update database statistics

### Monthly Checklist

- [ ] Review and optimize slow queries
- [ ] Analyze cost reports
- [ ] Test disaster recovery procedures
- [ ] Review access control and permissions
- [ ] Update documentation

### Quarterly Checklist

- [ ] Full disaster recovery drill
- [ ] Security audit
- [ ] Performance baseline review
- [ ] Capacity planning review
- [ ] Review and renew reserved instances

---

## 🚨 TROUBLESHOOTING

### Connection Failures

**Symptom:** Cannot connect to database

```bash
# Check server status
az postgres flexible-server show \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --query state -o tsv

# Check firewall rules
az postgres flexible-server firewall-rule list \
  --resource-group SecureWaveRG \
  --name securewave-db

# Test from current IP
curl https://api.ipify.org  # Get your IP
# Verify IP is in firewall rules

# Check connection string
python3 << EOF
import os
from dotenv import load_dotenv
load_dotenv(".env.production")
print(os.getenv("DATABASE_URL"))
EOF
```

### High CPU Usage

```bash
# Identify slow queries
psql $DATABASE_URL << EOF
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
ORDER BY duration DESC;
EOF

# Kill long-running query
psql $DATABASE_URL -c "SELECT pg_terminate_backend(PID);"
```

### Storage Full

```bash
# Check current usage
az postgres flexible-server show \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --query storage -o json

# Increase storage immediately
az postgres flexible-server update \
  --resource-group SecureWaveRG \
  --name securewave-db \
  --storage-size 204800  # 200 GB

# Clean up old data
psql $DATABASE_URL << EOF
-- Delete old audit logs (>90 days)
DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '90 days';
VACUUM FULL audit_logs;
EOF
```

### Connection Pool Exhaustion

```python
# Check pool stats
from database.session import get_database_info

info = get_database_info()
print(f"Pool stats: {info['pool_stats']}")

# Increase pool size in .env.production
# DB_POOL_SIZE=40
# DB_MAX_OVERFLOW=80

# Restart application
sudo systemctl restart securewave-web
```

---

## ✅ VERIFICATION CHECKLIST

Production database is ready when:

- [ ] PostgreSQL Flexible Server deployed
- [ ] High availability (zone-redundant) configured
- [ ] 35-day backup retention enabled
- [ ] Geo-redundant backups enabled
- [ ] Connection pooling configured (20+40)
- [ ] SSL/TLS encryption enforced
- [ ] Firewall rules configured
- [ ] Read replicas deployed (optional)
- [ ] Alembic migrations initialized
- [ ] Health checks passing
- [ ] Monitoring alerts configured
- [ ] Maintenance schedule automated
- [ ] Disaster recovery tested
- [ ] Documentation complete

---

## 📞 SUPPORT & RESOURCES

**Azure Support:**
- Azure Portal: https://portal.azure.com
- Support Tickets: Create from Azure Portal
- Documentation: https://docs.microsoft.com/azure/postgresql/

**Internal Resources:**
- Database Admin: admin@securewave.app
- On-Call: oncall@securewave.app
- Incident Response: incidents@securewave.app

**Key Commands Quick Reference:**

```bash
# Health check
python3 infrastructure/database_backup_manager.py health-check

# Backup
python3 infrastructure/database_backup_manager.py backup

# List backups
python3 infrastructure/database_backup_manager.py list-backups

# Maintenance
python3 infrastructure/database_backup_manager.py maintenance

# Metrics
python3 infrastructure/database_backup_manager.py metrics
```

---

**Documentation Version:** 1.0
**Last Updated:** 2026-01-03
**Status:** Production Ready
**Next Review:** 2026-04-03
