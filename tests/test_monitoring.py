"""
Monitoring and logging tests
"""

import pytest
from datetime import datetime, timedelta


class TestSecurityAudit:
    """Test security audit logging"""

    def test_log_login_event(self, db):
        """Test logging login event"""
        from services.security_audit import get_security_audit, EventType, EventCategory, Severity

        audit = get_security_audit()

        log_id = audit.log_login(
            user_id=1,
            email="test@example.com",
            ip_address="203.0.113.1",
            user_agent="Mozilla/5.0",
            success=True,
            method="password"
        )

        assert log_id is not None

        # Verify log was created
        from models.audit_log import AuditLog
        log = db.query(AuditLog).filter(AuditLog.id == log_id).first()
        assert log is not None
        assert log.event_type == EventType.LOGIN.value
        assert log.success is True

    def test_log_data_access(self, db):
        """Test logging data access"""
        from services.security_audit import get_security_audit

        audit = get_security_audit()

        log_id = audit.log_data_access(
            user_id=1,
            email="test@example.com",
            resource_type="user",
            resource_id="1",
            action="accessed",
            ip_address="203.0.113.1"
        )

        assert log_id is not None

    def test_get_suspicious_events(self, db):
        """Test getting suspicious events"""
        from services.security_audit import get_security_audit, Severity

        audit = get_security_audit()

        # Log suspicious event
        audit.log_suspicious_activity(
            user_id=1,
            email="test@example.com",
            activity_type="rapid_reconnects",
            description="50 connections in 1 hour",
            ip_address="203.0.113.1",
            severity=Severity.WARNING
        )

        # Get suspicious events
        events = audit.get_suspicious_events(hours=24)
        assert len(events) > 0
        assert events[0]["is_suspicious"] is True


class TestPerformanceMonitoring:
    """Test performance monitoring"""

    def test_track_api_metric(self, db):
        """Test tracking API performance metric"""
        from services.performance_monitor import get_performance_monitor

        perf = get_performance_monitor()

        perf.track_metric(
            metric_type="api_response_time",
            endpoint="/api/users",
            total_time_ms=150,
            status_code=200
        )

        # Verify metric was saved
        from models.audit_log import PerformanceMetric
        metric = db.query(PerformanceMetric).filter(
            PerformanceMetric.endpoint == "/api/users"
        ).first()
        assert metric is not None
        assert metric.total_time_ms == 150

    def test_get_performance_stats(self, db):
        """Test getting performance statistics"""
        from services.performance_monitor import get_performance_monitor

        perf = get_performance_monitor()

        # Add some metrics
        for i in range(10):
            perf.track_metric(
                metric_type="api_response_time",
                endpoint="/api/test",
                total_time_ms=100 + i * 10,
                status_code=200
            )

        # Get stats
        stats = perf.get_api_performance_stats(endpoint="/api/test", hours=1)
        assert stats["total_requests"] == 10
        assert stats["average_response_time_ms"] > 0


class TestUptimeMonitoring:
    """Test uptime monitoring"""

    def test_check_http_endpoint(self):
        """Test HTTP endpoint check"""
        from services.uptime_monitor import get_uptime_monitor

        monitor = get_uptime_monitor()

        # This will fail in test environment but tests the function
        is_up, response_time, error = monitor.check_http_endpoint(
            "http://localhost:8000/api/health",
            timeout=5
        )
        # Just verify it returns the expected tuple
        assert isinstance(is_up, bool)
        assert isinstance(response_time, int)

    def test_check_database(self, db):
        """Test database connectivity check"""
        from services.uptime_monitor import get_uptime_monitor

        monitor = get_uptime_monitor()

        result = monitor.check_database()
        assert result["check_name"] == "database"
        # In test environment with SQLite, this should pass
        assert result["is_up"] is True

    def test_save_check_results(self, db):
        """Test saving uptime check results"""
        from services.uptime_monitor import get_uptime_monitor

        monitor = get_uptime_monitor()

        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {
                "test": {
                    "check_name": "test",
                    "check_type": "http",
                    "target": "http://test.com",
                    "is_up": True,
                    "response_time_ms": 100,
                    "status_code": 200,
                    "error_message": None,
                    "checked_at": datetime.utcnow()
                }
            },
            "total_checks": 1
        }

        monitor.save_check_results(results)

        # Verify saved
        from models.audit_log import UptimeCheck
        check = db.query(UptimeCheck).filter(
            UptimeCheck.check_name == "test"
        ).first()
        assert check is not None
        assert check.is_up is True


class TestGDPRCompliance:
    """Test GDPR compliance"""

    def test_create_access_request(self, db, test_user):
        """Test creating GDPR access request"""
        from services.gdpr_service import get_gdpr_service

        gdpr = get_gdpr_service()

        request = gdpr.create_access_request(
            user_id=test_user.id,
            description="User requested all data"
        )

        assert request["user_id"] == test_user.id
        assert request["request_type"] == "access"
        assert request["status"] == "pending"
        assert "request_number" in request

    def test_export_user_data(self, db, test_user):
        """Test exporting user data"""
        from services.gdpr_service import get_gdpr_service

        gdpr = get_gdpr_service()

        data = gdpr.export_user_data(test_user.id)

        assert data["user_id"] == test_user.id
        assert "personal_information" in data
        assert data["personal_information"]["email"] == test_user.email

    def test_record_consent(self, db, test_user):
        """Test recording user consent"""
        from services.gdpr_service import get_gdpr_service

        gdpr = get_gdpr_service()

        consent = gdpr.record_consent(
            user_id=test_user.id,
            consent_type="TERMS_OF_SERVICE",
            is_granted=True,
            consent_version="1.0",
            ip_address="203.0.113.1"
        )

        assert consent["user_id"] == test_user.id
        assert consent["consent_type"] == "terms_of_service"
        assert consent["is_granted"] is True

    def test_check_sla_breaches(self, db, test_user):
        """Test checking SLA breaches"""
        from services.gdpr_service import get_gdpr_service
        from models.gdpr import GDPRRequest, GDPRRequestType, GDPRRequestStatus

        # Create an overdue request
        overdue_date = datetime.utcnow() - timedelta(days=1)
        request = GDPRRequest(
            request_number="GDPR-TEST-00001",
            user_id=test_user.id,
            request_type=GDPRRequestType.ACCESS,
            status=GDPRRequestStatus.PENDING,
            due_date=overdue_date,
            sla_breached=False
        )
        db.add(request)
        db.commit()

        gdpr = get_gdpr_service()
        breaches = gdpr.check_sla_breaches()

        assert len(breaches) > 0
        assert breaches[0]["request_number"] == "GDPR-TEST-00001"
