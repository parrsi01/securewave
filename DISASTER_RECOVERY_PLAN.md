# Disaster Recovery Plan - SecureWave VPN

## Document Control

**Version**: 1.0
**Last Updated**: January 7, 2024
**Review Frequency**: Quarterly
**Document Owner**: DevOps Team
**Classification**: Confidential

---

## Table of Contents

1. [Overview](#overview)
2. [Recovery Objectives](#recovery-objectives)
3. [Backup Strategy](#backup-strategy)
4. [Disaster Scenarios](#disaster-scenarios)
5. [Recovery Procedures](#recovery-procedures)
6. [Testing](#testing)
7. [Contact Information](#contact-information)

---

## Overview

### Purpose

This Disaster Recovery Plan (DRP) outlines the procedures to recover SecureWave VPN services in the event of a catastrophic failure, data loss, or security breach.

### Scope

This plan covers:
- Database recovery
- Application recovery
- VPN infrastructure recovery
- User data restoration
- Service continuity

### Disaster Recovery Team

| Role | Responsibility | Contact |
|------|---------------|---------|
| DR Coordinator | Overall DR coordination | devops@securewave.com |
| Database Admin | Database recovery | dba@securewave.com |
| Network Admin | Infrastructure recovery | netadmin@securewave.com |
| Security Lead | Security incident response | security@securewave.com |

---

## Recovery Objectives

### Recovery Time Objective (RTO)

| Service | RTO Target | Priority |
|---------|-----------|----------|
| Website | 4 hours | P1 |
| API | 2 hours | P0 |
| Database | 1 hour | P0 |
| VPN Servers | 4 hours | P1 |
| Email Service | 24 hours | P2 |

### Recovery Point Objective (RPO)

| Data Type | RPO Target | Backup Frequency |
|-----------|-----------|------------------|
| User Database | 1 hour | Continuous (Point-in-time) |
| VPN Configurations | 24 hours | Daily |
| Application Code | 0 (Git) | Continuous |
| System Logs | 24 hours | Daily |
| Audit Logs | 1 hour | Continuous |

### Maximum Tolerable Downtime (MTD)

- **Critical Services** (API, Database): 8 hours
- **Important Services** (Website, VPN): 24 hours
- **Normal Services** (Email, Reports): 72 hours

---

## Backup Strategy

### Database Backups

#### Automated Backups (Azure PostgreSQL)

```bash
# Automated backups (Azure managed)
- Automatic daily backups (retained for 35 days)
- Point-in-time restore (within retention period)
- Geo-redundant backup storage
- Backup location: Paired Azure region

# Backup verification script
az postgres flexible-server backup list \
  --resource-group securewave-rg \
  --server-name securewave-db
```

#### Manual Backups (On-Demand)

```bash
# Create manual backup before major changes
az postgres flexible-server backup create \
  --resource-group securewave-rg \
  --server-name securewave-db \
  --backup-name "manual-$(date +%Y%m%d-%H%M%S)"

# Export database to file
pg_dump -h securewave-db.postgres.database.azure.com \
  -U securewave_admin \
  -d securewave_prod \
  -F custom \
  -f backup_$(date +%Y%m%d).dump
```

### Application Backups

```bash
# Code backups (Git repository)
- Hosted on GitHub with branch protection
- Daily automated backups to Azure DevOps (mirror)
- Tagged releases for version control

# Configuration backups
az webapp config backup create \
  --resource-group securewave-rg \
  --webapp-name securewave \
  --backup-name "config-$(date +%Y%m%d)"
```

### File Storage Backups

```bash
# Azure Blob Storage (if used for file storage)
az storage blob copy start-batch \
  --source-container production-data \
  --destination-container backup-data \
  --account-name securewave
```

### VPN Configuration Backups

```bash
# WireGuard configurations
# Backup script: backup_vpn_configs.sh

#!/bin/bash
BACKUP_DIR="/backups/vpn/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup WireGuard configs
cp -r /etc/wireguard/*.conf $BACKUP_DIR/

# Backup to Azure Storage
az storage blob upload-batch \
  --destination vpn-configs \
  --source $BACKUP_DIR \
  --account-name securewave
```

---

## Disaster Scenarios

### Scenario 1: Database Corruption

**Impact**: Complete data loss, service unavailable

**Recovery Steps**:
1. Identify corruption extent
2. Stop application to prevent further writes
3. Restore from latest point-in-time backup
4. Verify data integrity
5. Resume application
6. Verify service functionality

**Estimated Recovery Time**: 1-2 hours

### Scenario 2: Azure Region Outage

**Impact**: Primary region unavailable

**Recovery Steps**:
1. Activate DR site in secondary region
2. Update DNS to point to secondary region
3. Restore database from geo-redundant backup
4. Deploy application to secondary region
5. Update VPN server configurations
6. Verify and monitor

**Estimated Recovery Time**: 4-6 hours

### Scenario 3: Security Breach / Ransomware

**Impact**: Data encryption, system compromise

**Recovery Steps**:
1. Isolate affected systems immediately
2. Assess breach extent
3. Restore from clean backup (before breach)
4. Patch vulnerabilities
5. Reset all credentials
6. Notify affected users
7. File security incident report

**Estimated Recovery Time**: 8-24 hours

### Scenario 4: Accidental Data Deletion

**Impact**: User data or configuration lost

**Recovery Steps**:
1. Identify deletion time window
2. Stop related services
3. Restore from point-in-time backup
4. Verify restored data
5. Resume services
6. Review audit logs

**Estimated Recovery Time**: 1-2 hours

### Scenario 5: Application Deployment Failure

**Impact**: Service degradation or outage

**Recovery Steps**:
1. Trigger automatic rollback
2. If rollback fails, deploy previous version manually
3. Verify service restoration
4. Review deployment logs
5. Fix issues in staging
6. Redeploy when ready

**Estimated Recovery Time**: 30 minutes - 1 hour

---

## Recovery Procedures

### Database Recovery

#### Point-in-Time Restore

```bash
# Restore to specific time
az postgres flexible-server restore \
  --resource-group securewave-rg \
  --name securewave-db-restored \
  --source-server securewave-db \
  --restore-point-in-time "2024-01-07T10:00:00Z"

# Update application connection string
az webapp config appsettings set \
  --resource-group securewave-rg \
  --name securewave \
  --settings DATABASE_URL="postgresql://..."
```

#### Restore from Backup File

```bash
# Restore from pg_dump file
pg_restore -h securewave-db.postgres.database.azure.com \
  -U securewave_admin \
  -d securewave_prod \
  -c \
  backup_20240107.dump

# Verify restore
psql -h securewave-db.postgres.database.azure.com \
  -U securewave_admin \
  -d securewave_prod \
  -c "SELECT COUNT(*) FROM users;"
```

### Application Recovery

#### Redeploy from Git

```bash
# Deploy specific version/tag
git checkout v1.2.3

# Deploy to Azure
az webapp deployment source config \
  --resource-group securewave-rg \
  --name securewave \
  --repo-url https://github.com/securewave/vpn \
  --branch main \
  --manual-integration

# Or use GitHub Actions for automated deployment
```

#### Restore from Backup

```bash
# List available backups
az webapp config backup list \
  --resource-group securewave-rg \
  --webapp-name securewave

# Restore from backup
az webapp config backup restore \
  --resource-group securewave-rg \
  --webapp-name securewave \
  --backup-name backup-20240107
```

### VPN Infrastructure Recovery

#### Recreate VPN Servers

```bash
# Deploy new VPN server from template
az deployment group create \
  --resource-group securewave-rg \
  --template-file infrastructure/vpn_server_template.json \
  --parameters location=eastus serverName=vpn-server-1

# Restore configurations
az vm extension set \
  --resource-group securewave-rg \
  --vm-name vpn-server-1 \
  --name CustomScriptExtension \
  --publisher Microsoft.Compute \
  --settings '{"fileUris": ["https://storage.blob.core.windows.net/scripts/setup_wireguard.sh"]}'
```

#### Restore WireGuard Configurations

```bash
# Download configs from backup
az storage blob download-batch \
  --destination /etc/wireguard \
  --source vpn-configs \
  --account-name securewave

# Restart WireGuard
systemctl restart wg-quick@wg0
```

### DNS Recovery

```bash
# Failover DNS to secondary region
az network dns record-set a update \
  --resource-group securewave-rg \
  --zone-name securewave.com \
  --name @ \
  --set aRecords[0].ipv4Address="<secondary-ip>"

# Update Traffic Manager (if configured)
az network traffic-manager endpoint update \
  --resource-group securewave-rg \
  --profile-name securewave-tm \
  --name primary \
  --type azureEndpoints \
  --endpoint-status Disabled
```

---

## Testing

### DR Testing Schedule

| Test Type | Frequency | Last Performed | Next Scheduled |
|-----------|-----------|----------------|----------------|
| Backup Restore Test | Monthly | | |
| Failover Test | Quarterly | | |
| Full DR Exercise | Annually | | |
| Tabletop Exercise | Bi-annually | | |

### Test Procedures

#### Monthly Backup Restore Test

1. Select random backup from previous month
2. Restore to test environment
3. Verify data integrity
4. Run application tests
5. Document results
6. Update RTO/RPO metrics

#### Quarterly Failover Test

1. Schedule maintenance window
2. Simulate primary region failure
3. Execute failover to secondary region
4. Verify all services operational
5. Measure recovery time
6. Failback to primary region
7. Document lessons learned

### Test Checklist

- [ ] Database restore successful
- [ ] Application deployed and running
- [ ] User authentication working
- [ ] VPN connections functional
- [ ] Payment processing operational
- [ ] Email notifications sent
- [ ] Monitoring and logging active
- [ ] RTO/RPO targets met
- [ ] Documentation updated

---

## Contact Information

### Emergency Contacts

**24/7 On-Call Rotation**:
- Primary: +1-XXX-XXX-XXXX
- Secondary: +1-XXX-XXX-XXXX

**Escalation**:
- Level 1: DevOps Engineer (15 min response)
- Level 2: Senior Engineer (30 min response)
- Level 3: Engineering Manager (1 hour response)
- Level 4: CTO (2 hour response)

### Vendor Support

| Vendor | Service | Support Contact | SLA |
|--------|---------|----------------|-----|
| Microsoft Azure | Infrastructure | Azure Portal | 24/7 |
| Sentry | Error Tracking | support@sentry.io | Business hours |
| SendGrid | Email Service | support@sendgrid.com | 24/7 |

### Communication Channels

**During Incident**:
- Primary: Microsoft Teams #disaster-recovery
- Secondary: Slack #incidents
- Status Page: status.securewave.com

**Post-Incident**:
- Email: incident-reports@securewave.com
- Documentation: Confluence DR Space

---

## Appendices

### Appendix A: Recovery Scripts

Located in: `/infrastructure/disaster-recovery/`

- `restore_database.sh` - Database restoration
- `deploy_app.sh` - Application deployment
- `failover_dns.sh` - DNS failover
- `restore_vpn.sh` - VPN infrastructure recovery

### Appendix B: Configuration Files

- Database connection strings
- API keys and secrets (stored in Azure Key Vault)
- VPN server configurations
- DNS zone files

### Appendix C: Post-Incident Review Template

```markdown
# Incident Post-Mortem

**Date**:
**Incident ID**:
**Duration**:
**Impact**:

## Timeline
- [HH:MM] Event description

## Root Cause

## Actions Taken

## What Went Well

## What Needs Improvement

## Action Items
- [ ] Item 1
- [ ] Item 2

## Follow-up
```

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-01-07 | DevOps Team | Initial version |

---

**Next Review Date**: April 7, 2024
**Approved By**: CTO
**Distribution**: Engineering Team, Management
