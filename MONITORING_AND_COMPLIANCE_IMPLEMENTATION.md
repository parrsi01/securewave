## SecureWave VPN - Monitoring & Legal Compliance Implementation

## Document Overview

This document summarizes the implementation of **Section 9 (Monitoring & Logging)** and **Section 10 (Legal & Compliance)** from the SecureWave VPN development checklist.

**Implementation Date**: January 7, 2024
**Status**: ✅ COMPLETE

---

## Table of Contents

1. [Implementation Summary](#implementation-summary)
2. [Section 9: Monitoring & Logging](#section-9-monitoring--logging)
3. [Section 10: Legal & Compliance](#section-10-legal--compliance)
4. [Database Changes](#database-changes)
5. [Configuration Requirements](#configuration-requirements)
6. [Deployment Checklist](#deployment-checklist)
7. [Testing Guide](#testing-guide)
8. [Operational Procedures](#operational-procedures)

---

## Implementation Summary

### What Was Implemented

**Section 9: Monitoring & Logging**
✅ Application Insights integration for Azure Monitor
✅ Sentry error tracking with auto-capture
✅ Uptime monitoring for all services
✅ Performance metrics tracking
✅ Security audit logging system

**Section 10: Legal & Compliance**
✅ GDPR compliance framework (data subject rights)
✅ Data retention policies
✅ Warrant canary system
✅ Transparency report generator
✅ User consent management

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                        │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌────────────┐│
│  │ FastAPI  │  │ Background│  │  Admin   │  │   Public   ││
│  │   API    │  │   Jobs    │  │ Dashboard│  │  Website   ││
│  └─────┬────┘  └─────┬─────┘  └────┬─────┘  └──────┬─────┘│
└────────┼──────────────┼─────────────┼────────────────┼──────┘
         │              │             │                │
┌────────┼──────────────┼─────────────┼────────────────┼──────┐
│        │  MONITORING & LOGGING LAYER│                │      │
│  ┌─────▼──────┐ ┌────▼─────┐ ┌─────▼────┐  ┌────────▼───┐ │
│  │Application │ │  Sentry  │ │Performance│  │   Security │ │
│  │  Insights  │ │  Error   │ │  Monitor  │  │    Audit   │ │
│  │(Azure Mon.)│ │ Tracking │ │           │  │   Logging  │ │
│  └─────┬──────┘ └────┬─────┘ └─────┬────┘  └────────┬───┘ │
└────────┼──────────────┼─────────────┼────────────────┼──────┘
         │              │             │                │
┌────────┼──────────────┼─────────────┼────────────────┼──────┐
│        │       DATA STORAGE LAYER   │                │      │
│  ┌─────▼──────────────▼─────────────▼────────────────▼───┐ │
│  │           PostgreSQL Database                          │ │
│  │  - audit_logs        - error_logs                      │ │
│  │  - performance_metrics  - uptime_checks                │ │
│  │  - gdpr_requests     - user_consents                   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Section 9: Monitoring & Logging

### 9.1 Application Insights Integration

**File**: `services/app_insights.py`

#### Features

- **Automatic Request Tracking**: Every API request automatically logged
- **Exception Tracking**: Unhandled exceptions sent to Azure Monitor
- **Custom Events**: Business metrics (logins, payments, VPN connections)
- **Performance Monitoring**: Response times, database queries
- **User Context**: Track events per user for analysis

#### Configuration

```bash
# Environment Variables
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=...;IngestionEndpoint=...
# OR
APPINSIGHTS_INSTRUMENTATIONKEY=your-instrumentation-key
ENABLE_APP_INSIGHTS=true
```

#### Usage Examples

```python
from services.app_insights import get_app_insights_service

app_insights = get_app_insights_service()

# Track custom event
app_insights.track_event(
    "UserLogin",
    properties={"user_id": "123", "method": "password"},
    measurements={"login_count": 1}
)

# Track exception
try:
    risky_operation()
except Exception as e:
    app_insights.track_exception(
        exception=e,
        properties={"operation": "payment_processing"}
    )

# Track metric
app_insights.track_metric("active_connections", 1250)

# Measure performance
@app_insights.measure_performance("process_payment")
def process_payment(amount):
    # Implementation
    pass
```

#### Business Metrics Tracked

- User logins (success/failure rates)
- User registrations
- Subscription creations
- VPN connections (per server, success rate)
- Payment transactions

#### FastAPI Integration

```python
# main.py
from services.app_insights import get_app_insights_service, FastAPIMiddleware

app_insights = get_app_insights_service()

# Add middleware for automatic request tracking
app.middleware("http")(FastAPIMiddleware(app_insights))
```

---

### 9.2 Sentry Error Tracking

**File**: `services/sentry_service.py`

#### Features

- **Automatic Error Capture**: Unhandled exceptions automatically sent
- **Breadcrumbs**: Context trail leading to errors
- **Performance Monitoring**: Transaction tracking (10% sample rate)
- **PII Filtering**: Automatically removes sensitive data
- **Error Deduplication**: Groups similar errors
- **Release Tracking**: Track errors by deployment version

#### Configuration

```bash
# Environment Variables
SENTRY_DSN=https://...@sentry.io/...
SENTRY_ENVIRONMENT=production  # or staging, development
SENTRY_RELEASE=1.0.0
ENABLE_SENTRY=true
SENTRY_TRACES_SAMPLE_RATE=0.1  # 10% of transactions
```

#### Usage Examples

```python
from services.sentry_service import get_sentry_service, capture_exceptions

sentry = get_sentry_service()

# Manual exception capture
try:
    dangerous_operation()
except Exception as e:
    sentry.capture_exception(
        exception=e,
        level="error",
        tags={"module": "payment"},
        extras={"transaction_id": "12345"}
    )

# Capture message
sentry.capture_message(
    "Critical threshold exceeded",
    level="warning",
    tags={"metric": "bandwidth"}
)

# Add breadcrumb for context
sentry.add_breadcrumb(
    message="User initiated payment",
    category="payment",
    level="info",
    data={"amount": 29.99}
)

# Set user context
sentry.set_user(
    user_id="123",
    email="user@example.com",
    username="john_doe"
)

# Decorator for automatic capture
@capture_exceptions(reraise=True)
def process_critical_operation():
    # If this fails, automatically sent to Sentry
    pass
```

#### Security Features

- **PII Scrubbing**: Passwords, tokens, API keys automatically filtered
- **Query Filtering**: Sensitive SQL queries redacted
- **Header Filtering**: Authorization headers removed

---

### 9.3 Uptime Monitoring

**File**: `services/uptime_monitor.py`

#### Monitored Services

1. **API Endpoint**: `/api/health`
2. **Frontend**: Main website
3. **Database**: PostgreSQL connectivity
4. **Redis**: Cache server (if configured)
5. **VPN Servers**: All active WireGuard servers

#### Features

- HTTP/HTTPS endpoint checks
- TCP port availability
- Database query execution
- Response time measurement
- Automatic service discovery

#### Usage

```python
from services.uptime_monitor import get_uptime_monitor

monitor = get_uptime_monitor()

# Run all health checks
results = monitor.run_all_checks()
print(f"Overall status: {results['overall_status']}")  # healthy, degraded, unhealthy
print(f"Passed: {results['passed_checks']}/{results['total_checks']}")

# Check specific service
api_check = monitor.check_api_endpoint("/api/health")
if not api_check["is_up"]:
    alert_team(api_check["error_message"])

# Get uptime statistics
stats = monitor.get_uptime_stats("api", days=7)
print(f"API uptime: {stats['uptime_percentage']}%")
print(f"Average response time: {stats['average_response_time_ms']}ms")

# Save results to database
monitor.save_check_results(results)
```

#### Uptime Calculation

```
Uptime % = (Successful Checks / Total Checks) × 100

Target SLAs:
- API: 99.9% uptime (43 minutes downtime/month)
- Database: 99.95% uptime
- VPN Servers: 99.5% uptime per server
```

---

### 9.4 Performance Metrics

**File**: `services/performance_monitor.py`

#### Tracked Metrics

**API Performance**:
- Response time (total, database, external API)
- Status codes distribution
- Slow endpoints (>500ms)
- P50, P95, P99 percentiles

**Database Performance**:
- Query execution time
- Slow queries (>1000ms)
- Queries per endpoint

**System Resources**:
- Memory usage (MB)
- CPU percentage
- Process statistics

#### Configuration

```bash
# Environment Variables
ENABLE_PERFORMANCE_MONITORING=true
SLOW_QUERY_THRESHOLD_MS=1000  # Log queries slower than 1s
SLOW_API_THRESHOLD_MS=500      # Log API calls slower than 500ms
```

#### Usage

```python
from services.performance_monitor import get_performance_monitor

perf = get_performance_monitor()

# Decorate API endpoints
@app.get("/api/users")
@perf.measure_api_request()
async def get_users():
    # Automatically tracked
    pass

# Measure database queries
@perf.measure_database_query("get_user_by_email")
def get_user(email: str):
    return db.query(User).filter(User.email == email).first()

# Get performance statistics
api_stats = perf.get_api_performance_stats(endpoint="/api/users", hours=24)
print(f"Average response time: {api_stats['average_response_time_ms']}ms")
print(f"P95 response time: {api_stats['p95_response_time_ms']}ms")
print(f"Slow requests: {api_stats['slow_request_percentage']}%")

# Database statistics
db_stats = perf.get_database_performance_stats(hours=24)
print(f"Average query time: {db_stats['average_query_time_ms']}ms")
print(f"Slowest queries:", db_stats['slowest_queries'][:5])

# Check for performance alerts
alerts = perf.check_performance_thresholds()
for alert in alerts:
    print(f"{alert['severity']}: {alert['message']}")
```

#### Performance Targets

- API response time P95: < 500ms
- Database query time average: < 100ms
- Memory usage: < 80% of available
- CPU usage: < 70% average

---

### 9.5 Security Audit Logging

**File**: `services/security_audit.py`

#### Event Categories

1. **Authentication**: Login, logout, password changes, 2FA
2. **Authorization**: Permission denials, role changes
3. **Data**: Access, export, modification, deletion
4. **Security**: Suspicious activity, rate limits, abuse
5. **Payment**: Transactions, refunds
6. **Admin**: Admin actions, configuration changes
7. **VPN**: Connections, configurations, key rotations

#### Features

- **Immutable logs**: Security events cannot be modified
- **Comprehensive context**: IP, user agent, request ID
- **Severity levels**: Info, warning, error, critical
- **Suspicious activity flagging**: Auto-detection
- **Compliance tracking**: GDPR-relevant events marked
- **Fast queries**: Optimized indexes for investigation

#### Usage

```python
from services.security_audit import get_security_audit, EventType, EventCategory, Severity

audit = get_security_audit()

# Log authentication events
audit.log_login(
    user_id=123,
    email="user@example.com",
    ip_address="203.0.113.1",
    user_agent="Mozilla/5.0...",
    success=True,
    method="password"
)

# Log data access (GDPR compliance)
audit.log_data_access(
    user_id=123,
    email="user@example.com",
    resource_type="subscription",
    resource_id="SUB-123",
    action="accessed",
    ip_address="203.0.113.1"
)

# Log suspicious activity
audit.log_suspicious_activity(
    user_id=123,
    email="user@example.com",
    activity_type="rapid_reconnects",
    description="User connected 50 times in 1 hour",
    ip_address="203.0.113.1",
    severity=Severity.WARNING
)

# Query audit logs
user_logs = audit.get_user_audit_log(
    user_id=123,
    days=30,
    event_types=["login", "data_access"]
)

suspicious_events = audit.get_suspicious_events(hours=24)
```

#### Compliance Benefits

- **GDPR Article 30**: Records of processing activities
- **SOC 2 Compliance**: Comprehensive security logging
- **PCI DSS**: Payment transaction auditing
- **Forensic Investigation**: Complete event timeline

---

## Section 10: Legal & Compliance

### 10.1 GDPR Compliance Framework

**Files**:
- `models/gdpr.py` - GDPR data models
- `services/gdpr_service.py` - GDPR operations

#### Data Subject Rights Implemented

1. **Right to Access (Article 15)**
   - Export all user data in JSON format
   - 30-day response deadline
   - Automatic SLA tracking

2. **Right to Erasure / Right to be Forgotten (Article 17)**
   - Complete data deletion
   - Anonymization for legal retention
   - Cascade deletion of related records

3. **Right to Rectification (Article 16)**
   - User profile updates
   - Audit trail of changes

4. **Right to Data Portability (Article 20)**
   - Export in machine-readable format
   - Includes all personal data

#### Request Management

```python
from services.gdpr_service import get_gdpr_service

gdpr = get_gdpr_service()

# Create access request
request = gdpr.create_access_request(
    user_id=123,
    description="User requested all personal data"
)
# Returns: {"request_number": "GDPR-202401-12345", "due_date": "2024-02-07", ...}

# Export user data
data = gdpr.export_user_data(user_id=123, format="json")
# Returns comprehensive JSON with:
# - Personal information
# - Subscriptions
# - VPN connections
# - Support tickets
# - Usage statistics
# - Audit logs

# Create deletion request
deletion_request = gdpr.create_deletion_request(
    user_id=123,
    description="User requested account deletion"
)

# Delete user data
summary = gdpr.delete_user_data(
    user_id=123,
    retention_required=True  # Anonymize instead of delete for legal retention
)

# Check pending requests
pending = gdpr.get_pending_requests()

# Check SLA breaches
breaches = gdpr.check_sla_breaches()
```

#### Data Categories Exported

| Category | Data Included |
|----------|---------------|
| Personal Information | Email, name, created date, 2FA status |
| Subscriptions | Plans, status, dates, prices |
| VPN Connections | Server IDs, timestamps, data transfer (no IPs) |
| WireGuard Peers | Device names, IP allocations, active status |
| Support Tickets | Ticket numbers, subjects, categories |
| Usage Statistics | Total connections, data usage, account age |
| Audit Logs | Last 100 security events |

---

### 10.2 Consent Management

**Model**: `models/gdpr.py` - UserConsent

#### Consent Types

1. **Terms of Service**: Mandatory for account creation
2. **Privacy Policy**: Mandatory for account creation
3. **Marketing Emails**: Optional, can be withdrawn
4. **Analytics**: Optional tracking consent
5. **Third-Party Sharing**: Data sharing consent

#### Features

- Version tracking (T&C/Privacy Policy versions)
- Withdrawal timestamps
- IP address and user agent logging
- Consent method tracking (checkbox, signature, email)

#### Usage

```python
from services.gdpr_service import get_gdpr_service

gdpr = get_gdpr_service()

# Record consent
consent = gdpr.record_consent(
    user_id=123,
    consent_type="TERMS_OF_SERVICE",
    is_granted=True,
    consent_version="2.0",
    ip_address="203.0.113.1",
    user_agent="Mozilla/5.0..."
)

# Get user consents
consents = gdpr.get_user_consents(user_id=123)
for consent in consents:
    print(f"{consent['consent_type']}: {consent['is_granted']}")
```

---

### 10.3 Data Retention Policy

**File**: `services/transparency_service.py`

#### Retention Periods

| Data Type | Retention Period | Reason |
|-----------|------------------|--------|
| Active user accounts | While active + 30 days | Service provision |
| Deleted accounts (personal data) | Immediate deletion | GDPR compliance |
| Deleted accounts (transactions) | 7 years | Tax law |
| VPN connection logs | **NOT STORED** | No-log policy |
| Bandwidth usage | 30 days | Billing only |
| Payment records | 7 years | Legal requirement |
| Support tickets | 2 years after resolution | Customer service |
| Security audit logs | 2 years | Security investigation |
| Compliance audit logs | 7 years | Legal compliance |
| Email communications | 2 years | Record keeping |

#### Automated Cleanup

```python
from services.transparency_service import get_transparency_service

transparency = get_transparency_service()

# Execute data retention cleanup
summary = transparency.execute_data_retention_cleanup()
# Automatically deletes:
# - Audit logs > 2 years (non-compliance)
# - Performance metrics > 90 days
# - Error logs > 90 days (resolved only)
# - Uptime checks > 30 days
# - Email logs > 2 years

# Run monthly as cron job
```

---

### 10.4 Warrant Canary

**File**: `services/transparency_service.py`
**Model**: `models/gdpr.py` - WarrantCanary

#### Purpose

A warrant canary is a published statement indicating the absence of government requests for user data. If the canary is not updated within 95 days, users should assume the service has been compromised.

#### Features

- **Quarterly Updates**: Published every 3 months
- **Cryptographic Hash**: Statement verification
- **Freshness Check**: Auto-alert if canary expires
- **Public Transparency**: Accessible to all users

#### Usage

```python
from services.transparency_service import get_transparency_service

transparency = get_transparency_service()

# Create new warrant canary (quarterly)
canary = transparency.create_warrant_canary(
    published_by_id=admin_id,
    period_months=3
)

# Get latest canary
latest = transparency.get_latest_canary()
print(latest["statement"])
print(f"Published: {latest['published_at']}")
print(f"Valid: {latest['is_valid']}")

# Check freshness
freshness = transparency.check_canary_freshness()
if not freshness["is_fresh"]:
    alert_users("Warrant canary expired - service may be compromised")
```

#### Statement Example

```
WARRANT CANARY STATEMENT
SecureWave VPN Transparency Report

Period: October 1, 2024 to January 1, 2025
Published: January 7, 2025

As of the date of this statement, SecureWave VPN confirms that:

1. We have NOT received any National Security Letters or FISA court orders.
2. We have NOT been subject to any gag orders prohibiting disclosure.
3. We have NOT been compelled to modify software or infrastructure.
4. We have NOT been forced to implement backdoors.
5. Our privacy policy remains unchanged and uncompromised.

This statement is issued quarterly. If not updated within 95 days,
assume one or more statements is no longer true.

Hash: 8f7d3e2a1b9c4f6e... (for verification)
```

---

### 10.5 Transparency Reports

**File**: `services/transparency_service.py`

#### Report Contents

1. **User Statistics**
   - Total users
   - New users in period
   - Active subscriptions

2. **Service Requests**
   - Support tickets created/resolved
   - Average resolution time

3. **Legal Requests**
   - Government requests (if any)
   - National security letters
   - Search warrants
   - Subpoenas
   - Data disclosed
   - Requests challenged in court

4. **GDPR Data Requests**
   - Access requests
   - Deletion requests
   - Rectification requests
   - Average response time

5. **Security Incidents**
   - Suspicious activities
   - Data breaches (if any)
   - Service disruptions

#### Usage

```python
from services.transparency_service import get_transparency_service
from datetime import datetime

transparency = get_transparency_service()

# Generate quarterly report
report = transparency.generate_quarterly_report(year=2024, quarter=4)

# Or custom period
start_date = datetime(2024, 10, 1)
end_date = datetime(2024, 12, 31)
report = transparency.generate_transparency_report(start_date, end_date)

# Example output:
{
    "period_start": "2024-10-01",
    "period_end": "2024-12-31",
    "quarter": "Q4 2024",
    "user_statistics": {
        "total_users": 15000,
        "new_users_period": 2500,
        "active_subscriptions": 12000
    },
    "legal_requests": {
        "total_requests": 0,
        "note": "No government requests received during this period."
    },
    "data_requests": {
        "total_gdpr_requests": 45,
        "access_requests": 30,
        "deletion_requests": 15
    },
    "security_incidents": {
        "suspicious_activities_detected": 127,
        "data_breaches": 0,
        "note": "No data breaches occurred during this period."
    }
}
```

---

## Database Changes

### Migration: `0005_add_monitoring_and_gdpr.py`

**Tables Created/Modified**:

1. **audit_logs** (Enhanced)
   - Added 14 new columns for detailed security tracking
   - Added 5 composite indexes for faster queries

2. **performance_metrics** (New)
   - Tracks API and database performance
   - 2 indexes for time-series queries

3. **uptime_checks** (New)
   - Records service availability checks
   - 2 indexes for uptime analysis

4. **error_logs** (New)
   - Tracks application errors with deduplication
   - 3 indexes for error analysis

5. **gdpr_requests** (New)
   - Manages data subject access requests
   - SLA tracking built-in

6. **user_consents** (New)
   - Tracks all user consents with versions

7. **data_processing_activities** (New)
   - GDPR Article 30 compliance (record of processing)

8. **warrant_canaries** (New)
   - Transparency canary statements

**Total**: 7 new tables, 1 enhanced table, 12 new indexes

---

## Configuration Requirements

### Environment Variables

```bash
# ===========================
# MONITORING (Section 9)
# ===========================

# Application Insights
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=...;IngestionEndpoint=...
# OR
APPINSIGHTS_INSTRUMENTATIONKEY=your-key-here
ENABLE_APP_INSIGHTS=true

# Sentry
SENTRY_DSN=https://...@sentry.io/...
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE=1.0.0
ENABLE_SENTRY=true
SENTRY_TRACES_SAMPLE_RATE=0.1

# Performance Monitoring
ENABLE_PERFORMANCE_MONITORING=true
SLOW_QUERY_THRESHOLD_MS=1000
SLOW_API_THRESHOLD_MS=500

# Uptime Monitoring
UPTIME_CHECK_INTERVAL=300  # 5 minutes

# ===========================
# COMPLIANCE (Section 10)
# ===========================

# GDPR
GDPR_RESPONSE_DEADLINE_DAYS=30

# Data Retention
# (Configured in code - see transparency_service.py)
```

### Dependencies Added

```
# requirements.txt additions
sentry-sdk==1.40.0
opencensus-ext-azure==1.1.9
applicationinsights==0.11.10
psutil==5.9.8
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Set all environment variables in Azure App Service
- [ ] Configure Sentry project and obtain DSN
- [ ] Create Application Insights resource in Azure
- [ ] Run database migration `0005_add_monitoring_and_gdpr.py`
- [ ] Review GDPR data retention policy
- [ ] Appoint Data Protection Officer (if required)
- [ ] Create initial warrant canary

### Monitoring Setup

- [ ] Test Application Insights connection
- [ ] Test Sentry error capture
- [ ] Configure uptime check endpoints
- [ ] Set up performance alert thresholds
- [ ] Create monitoring dashboard in Azure

### Legal Compliance

- [ ] Review and approve warrant canary statement
- [ ] Set up quarterly warrant canary publication schedule
- [ ] Configure GDPR request notification emails
- [ ] Train support team on GDPR request handling
- [ ] Establish data deletion procedures
- [ ] Schedule quarterly transparency reports

### Post-Deployment

- [ ] Verify all monitoring systems are capturing data
- [ ] Test GDPR data export functionality
- [ ] Test data deletion workflow
- [ ] Review initial audit logs
- [ ] Check performance metrics dashboard
- [ ] Publish first warrant canary
- [ ] Set up automated data retention cleanup (monthly cron)

---

## Testing Guide

### 9.1 Test Application Insights

```python
# Test script: test_app_insights.py
from services.app_insights import get_app_insights_service

app_insights = get_app_insights_service()

# Test event tracking
app_insights.track_event("TestEvent", properties={"test": "value"})

# Test exception tracking
try:
    raise ValueError("Test exception")
except Exception as e:
    app_insights.track_exception(e)

# Test metric
app_insights.track_metric("test_metric", 42.0)

print("Check Azure Portal > Application Insights for test data")
```

### 9.2 Test Sentry

```python
# Test script: test_sentry.py
from services.sentry_service import get_sentry_service

sentry = get_sentry_service()

# Test exception capture
try:
    1 / 0
except Exception as e:
    event_id = sentry.capture_exception(e, level="error")
    print(f"Sentry event ID: {event_id}")

# Test message capture
sentry.capture_message("Test message from SecureWave", level="info")

print("Check Sentry dashboard for test events")
```

### 9.3 Test Uptime Monitoring

```bash
# Run health checks
python3 -c "
from services.uptime_monitor import get_uptime_monitor
monitor = get_uptime_monitor()
results = monitor.run_all_checks()
print(f'Overall status: {results[\"overall_status\"]}')
print(f'Checks passed: {results[\"passed_checks\"]}/{results[\"total_checks\"]}')
"
```

### 9.4 Test GDPR Compliance

```python
# Test script: test_gdpr.py
from services.gdpr_service import get_gdpr_service

gdpr = get_gdpr_service()

# Test data export
user_id = 1  # Use test user
data = gdpr.export_user_data(user_id)
print(f"Exported {len(data)} data categories")

# Test access request
request = gdpr.create_access_request(user_id)
print(f"Created request: {request['request_number']}")

# Test consent recording
consent = gdpr.record_consent(
    user_id=user_id,
    consent_type="TERMS_OF_SERVICE",
    is_granted=True,
    consent_version="1.0"
)
print(f"Recorded consent: {consent}")
```

### 9.5 Test Warrant Canary

```python
# Test script: test_canary.py
from services.transparency_service import get_transparency_service

transparency = get_transparency_service()

# Create test canary
canary = transparency.create_warrant_canary(published_by_id=1)
print(canary["statement"])

# Check freshness
freshness = transparency.check_canary_freshness()
print(f"Canary is fresh: {freshness['is_fresh']}")
```

---

## Operational Procedures

### Daily Operations

1. **Monitor Error Rates**: Check Sentry for new errors
2. **Review Security Audit Logs**: Check for suspicious activity
3. **Verify Service Uptime**: Ensure all services are operational

### Weekly Operations

1. **Performance Review**: Analyze slow endpoints
2. **Review GDPR Requests**: Process any pending requests
3. **Check SLA Compliance**: Ensure requests processed on time

### Monthly Operations

1. **Data Retention Cleanup**: Run automated cleanup job
2. **Generate Monthly Report**: Review metrics and trends
3. **Security Audit Review**: Review security events

### Quarterly Operations

1. **Publish Warrant Canary**: Update and publish new canary
2. **Generate Transparency Report**: Publish quarterly report
3. **Review Data Processing Activities**: Update GDPR documentation
4. **Performance Optimization**: Address slow queries and endpoints

### Incident Response

**Security Incident**:
1. Check security audit logs for event timeline
2. Review related error logs and performance metrics
3. Analyze user activity patterns
4. Document findings in incident report
5. Update security measures

**Service Outage**:
1. Check uptime monitoring logs
2. Review error logs for root cause
3. Check performance metrics for degradation
4. Restore service
5. Post-mortem analysis

**GDPR Request**:
1. Verify user identity
2. Export/delete data within 30 days
3. Send confirmation to user
4. Log completion in audit log
5. Update SLA metrics

---

## Summary

### Files Created

**Monitoring Services**:
1. `services/app_insights.py` - Azure Application Insights integration
2. `services/sentry_service.py` - Sentry error tracking
3. `services/uptime_monitor.py` - Service availability monitoring
4. `services/performance_monitor.py` - Performance metrics tracking
5. `services/security_audit.py` - Security event logging

**Compliance Services**:
6. `models/gdpr.py` - GDPR compliance models
7. `services/gdpr_service.py` - GDPR operations
8. `services/transparency_service.py` - Warrant canary & transparency reports

**Database**:
9. `models/audit_log.py` - Enhanced audit logging models
10. `alembic/versions/0005_add_monitoring_and_gdpr.py` - Database migration

**Documentation**:
11. `MONITORING_AND_COMPLIANCE_IMPLEMENTATION.md` - This document

### Key Achievements

✅ **Enterprise-Grade Monitoring**
- Application Insights for comprehensive telemetry
- Sentry for error tracking and alerting
- Uptime monitoring for all critical services
- Performance metrics with percentile tracking
- Complete security audit trail

✅ **GDPR Compliance**
- All data subject rights implemented
- 30-day SLA tracking for requests
- Comprehensive data export in JSON
- Consent management with versioning
- Data retention policies with automated cleanup

✅ **Transparency & Trust**
- Quarterly warrant canary system
- Automatic freshness checks
- Transparency report generator
- Public accountability measures

✅ **Production Ready**
- Database migration ready
- Environment variables documented
- Testing procedures provided
- Operational procedures defined

---

**Implementation Status**: ✅ **SECTIONS 9 & 10 COMPLETE**

**Ready for Deployment**: All monitoring and compliance features are production-ready.

---

**Document Version**: 1.0
**Last Updated**: January 7, 2024
**Prepared By**: SecureWave Development Team
